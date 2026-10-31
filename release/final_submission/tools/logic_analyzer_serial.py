"""Configure, repeat, validate and archive Task 30 captures over CP2102 UART."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from logic_analyzer import decode_spi, decode_uart, parse_raw, write_vcd, write_waveform_page

MODES = {"static": 0, "counter": 1, "uart": 2, "spi": 3, "mirror": 4, "core": 0}
# 采集源（板级逻辑分析仪的"双源可选"，MMIO 寄存器 18 / 0xA8 命令的 [12] 字节）：
#   SOURCE_J8   = 0：J8 外部 8 路物理输入（默认，与历史全部证据同源）
#   SOURCE_CORE = 1：Core 内部观测点（ch0..ch7 = i_req_valid / i_req_ready /
#                   i_rsp_valid / d_req_valid / d_req_ready / event_stall /
#                   event_flush / trace_valid，见板级顶层注释）
SOURCE_J8 = 0
SOURCE_CORE = 1
SOURCE_PREFIX = 0xA8
# 「这一窗数据是什么」——**与 mode 不是一回事**（2026-10-14 新增）。
# 采集源改变了 8 根线的物理含义，于是"用什么图形采"和"采到的是什么"必须分开：
#   源 = Core             -> VIEW_CORE：ch0..ch7 是流水线内部观测点（CORE_PROBE_NAMES）
#   源 = J8 且 mode=core  -> VIEW_RAW ：core 只剩"全速 + 2048 点 + ch6 上升沿"这组预设，
#                                       8 根线仍是 J8 引脚，没有 CPU trace 可判
#   其余                  -> mode 本身（uart/spi/… 的协议解码才成立）
# 不分开就会出现"用 uart 模式 + Core 源采一窗流水线信号，主机却按 UART 帧去解码并报 FAIL"
# 这种把正确采集判成失败的假警报。
VIEW_CORE = "core"
VIEW_RAW = "raw"


def capture_view(mode: str, source: int) -> str:
    """采集源 + 模式 -> 这一窗数据的解释方式（见上方 VIEW_* 注释）。"""
    if int(source) == SOURCE_CORE:
        return VIEW_CORE
    if mode == VIEW_CORE:
        return VIEW_RAW
    return mode
# Core 内部观测点的通道名（与板级顶层 mes50hp_logic_analyzer_top.v 的 core_probe 逐位对应）。
# 出处：docs/interfaces.md §293~299 的对外观测输出 + 统一取指/数据事务端口。
CORE_PROBE_NAMES = {
    "0": "i_req_valid", "1": "i_req_ready", "2": "i_rsp_valid",
    "3": "d_req_valid", "4": "d_req_ready",
    "5": "event_stall", "6": "event_flush", "7": "trace_valid",
}
TRIGGERS = {"level": 0, "rise": 1, "fall": 2}

# 镜像模式（0xA7）：字符串由上位机经 CP2102 直接发到 uart0_rx，板级顶层把它镜像到
# J8-31/32 那一对回环脚（ch7），采集器只负责"抓"和"报"。采样点数固定 8 点/比特：
# 一整句 12 字符 = 120 bit，8 点/bit 需要 960 点，而深度 2048 点给出的窗口是
# 2.2 ms（报文本身 1.04 ms），留了一倍余量吸收 USB 串口的字节间间隙。
MIRROR_BIT_SAMPLES = 8
MIRROR_CHANNEL = 7
MIRROR_PREFIX = 0xA7
DEFAULT_MIRROR_TEXT = "HELLO,RISC-V"


def build_packet(mode: int, data: int, pattern_div: int, sample_div: int,
                 trigger_type: int, trigger_mask: int, trigger_value: int,
                 pre: int, post: int, prefix: int = 0xA5,
                 post16: bool = False, source: int | None = None) -> bytes:
    """命令报文。

    post16=False（0xA5，四模式）：[10]=pre、[11]=post，各 1 字节，与历史报文逐字节一致。
    post16=True （0xA7，镜像）  ：[10]|[11] 是**16 位 post**（小端），pre 由固件固定为 0
                                  —— 镜像抓取必须"窗口从起始位开始"，所以 pre 没有意义。
    source 不为 None 时改用 **0xA8**：16 字节，
    [1]～[9] 与 0xA5 完全一致，[10]|[11]=pre、[12]|[13]=post（各 16 位小端），
    [14]=采集源、[15]=XOR 校验。为什么另开一个命令而不是往 0xA5 里挤：
    13 字节布局已被上位机、解析器与板级 100/100 证据锁死，改长度会波及全部既有证据；
    新命令只在用新功能时出现，老路径逐字节不变。

    每个字段都做宽度校验、不做位截断：越界配置必须报错，不能被悄悄改成另一个配置。
    """
    for name, value, limit in (("prefix", prefix, 0xFF), ("mode", mode, 0xFF), ("data", data, 0xFF),
                               ("pattern_div", pattern_div, 0xFFFF), ("sample_div", sample_div, 0xFFFF),
                               ("trigger_type", trigger_type, 0xFF), ("trigger_mask", trigger_mask, 0xFF),
                               ("trigger_value", trigger_value, 0xFF)):
        if not 0 <= value <= limit:
            raise ValueError(f"packet field {name} is outside its encoded width")
    if source is not None:
        # 0xA8：16 字节。比 0xA5 长是因为 pre/post 要各占 2 字节——Core 内部观测点
        # 要的是"全速采样 + 以一次冲刷为中心的 2048 点窗口"，1 字节根本装不下。
        # 这一段必须在下面的 8 位 pre/post 校验**之前**，否则合法的 16 位窗口
        # 会先被老格式的宽度检查拦掉（实测：core 模式 post=1983 直接报错）。
        if source not in (SOURCE_J8, SOURCE_CORE):
            raise ValueError(f"未知采集源 {source!r}；只能是 SOURCE_J8(0) 或 SOURCE_CORE(1)")
        if not 0 <= pre <= 0xFFFF or not 0 <= post <= 0xFFFF:
            raise ValueError("0xA8 的 pre/post 是 16 位，超出即报错")
        values = [SOURCE_PREFIX, mode, data, pattern_div & 0xFF, pattern_div >> 8,
                  sample_div & 0xFF, sample_div >> 8, trigger_type,
                  trigger_mask, trigger_value,
                  pre & 0xFF, pre >> 8, post & 0xFF, post >> 8, source]
        checksum = 0
        for value in values:
            checksum ^= value
        return bytes(values + [checksum])
    if post16:
        if not 0 <= post <= 0xFFFF:
            raise ValueError("post does not fit in 16 bits")
        slots = [post & 0xFF, post >> 8]
    else:
        if not 0 <= pre <= 0xFF or not 0 <= post <= 0xFF:
            raise ValueError("pre/post do not fit in one byte each")
        slots = [pre, post]
    values = [prefix, mode, data, pattern_div & 0xFF, pattern_div >> 8,
              sample_div & 0xFF, sample_div >> 8, trigger_type,
              trigger_mask, trigger_value] + slots
    checksum = 0
    for value in values:
        checksum ^= value
    return bytes(values + [checksum])


def default_config(mode: str, data: int, clock_hz: int = 85_000_000,
                   baud: int = 115200, depth: int = 2048) -> dict[str, int]:
    if mode == "mirror":
        # 采样间隔由"比特时间 / 每比特采样点数"反算，不能照抄 pattern_div 那套：
        # 这里的比特率是**上位机真实串口波特率**，不是 pattern_gen 的分频。
        bit_cycles = clock_hz / baud
        sample_div = max(0, int(round(bit_cycles / MIRROR_BIT_SAMPLES)) - 1)
        bit_samples = int(round(bit_cycles / (sample_div + 1)))
        return dict(mode=4, data=bit_samples, pattern_div=0, sample_div=sample_div,
                    trigger_type=2, trigger_mask=1 << MIRROR_CHANNEL, trigger_value=0,
                    pre=0, post=depth - 1, prefix=MIRROR_PREFIX, post16=True,
                    channel=MIRROR_CHANNEL, bit_samples=bit_samples)
    if mode == "core":
        # 采集源 = Core 内部观测点（板级逻辑分析仪"双源可选"的另一半）。
        # 全速采样（sample_div=0，每拍一个点）：2048 点 ≈ 24 µs @85 MHz，
        # 够看几十条指令；触发选 ch6 = event_flush 的**上升沿**，窗口因此天然
        # "以一次控制流冲刷为中心"，正好回答"这次冲刷是怎么来的"。
        # 激励发生器与本次采集无关（源已经切到 Core），保持最小干扰的 mode=0。
        return dict(mode=0, data=0, pattern_div=0, sample_div=0,
                    trigger_type=1, trigger_mask=1 << 6, trigger_value=0,
                    pre=64, post=2047 - 64, prefix=0xA5, post16=False,
                    channel=6, bit_samples=1, source=SOURCE_CORE)
    if mode == "uart":
        # [2026-09-30 修] pre 16 -> 64、post 220 -> 191（窗口仍 240 个采样点，没超 Raw 上限）。
        # 原因：pattern_div=433 / sample_div=26 => 每比特 16.65 个采样点，一帧 10 bit = 166.5 点。
        # 旧窗口（pre=16/post=220）只给"帧起始位"留 237-166.5 = 70.5 点的余量，一旦触发沿落在
        # 数据位内部，整帧就装不进窗口 => 解码失败，**而波形本身完全正确**。
        # 这个隐患在 50/80 MHz 上碰巧不发作，在 85 MHz PLL 变体上暴露了。
        # 现在把窗口前移，帧起始位必被框住，各频率都能稳定解码。
        return dict(mode=2, data=data, pattern_div=433, sample_div=26,
                    trigger_type=2, trigger_mask=1, trigger_value=0, pre=64, post=191,
                    prefix=0xA5, post16=False, channel=0, bit_samples=16)
    if mode == "spi":
        # [2026-10-10 修] 触发从"SCLK 上升沿"改成"CS 下降沿"。
        # 原因：pattern_gen 是自由运行的，触发在 SCLK 上升沿时，窗口会落在字节的**任意一个 bit**
        # 上——落在 b7 就能凑满 8 个脉冲、PASS；落在 b6 就只剩 7 个脉冲，而 CS 会在第 8 个脉冲
        # 之前拉高，解码器（正确地）丢弃这个被截断的字节，判据变成空。
        # 老固件恰好落在字节边界上，所以这条 PASS 一直是**相位运气**；固件指令数一变就暴露了。
        # 触发 CS 下降沿 = 教科书用法，窗口确定从字节边界开始，与 arm 时刻无关。
        return dict(mode=3, data=data, pattern_div=3, sample_div=0,
                    trigger_type=2, trigger_mask=0x04, trigger_value=0, pre=4, post=80,
                    prefix=0xA5, post16=False, channel=0, bit_samples=16)
    return dict(mode=MODES[mode], data=data, pattern_div=3, sample_div=0,
                trigger_type=0, trigger_mask=1, trigger_value=data & 1, pre=4, post=4,
                prefix=0xA5, post16=False, channel=0, bit_samples=16)


# --------------------------------------------------------------- 仪器面板旋钮
# 只列固件**真的会读**的字段：就是 13 字节报文里存在的那些
# （software/logic_analyzer/logic_analyzer.c 第 213～229 行收包，第 153～166 行写寄存器）。
#
# `channel_mask` 故意不在其中：固件把 LA_CH_MASK 写死成 0xFF（同文件第 154 行），
# 报文里根本没有这个字节。界面上给它一个控件就是"能点、硬件不认"——
# 这正是现场最容易把人卡住的一类坑，所以宁可不给。
KNOB_FIELDS = ("sample_div", "trigger_type", "trigger_mask", "trigger_value",
               "pre", "post", "pattern_div", "data", "source")
# 每个旋钮在报文里的编码宽度（越界必须报错，不许静默截断成另一个配置）
KNOB_MAX = {"sample_div": 0xFFFF, "trigger_type": 2, "trigger_mask": 0xFF,
            "trigger_value": 0xFF, "pre": 0xFF, "post": 0xFF,
            "pattern_div": 0xFFFF, "data": 0xFF, "source": SOURCE_CORE}
# 面板上"采集源"下拉的显示名与数值。两份界面（pyUI 与单文件版）共用这一处定义，
# 避免"界面能选、报文不认"——与 channel_mask 不进面板是同一条纪律。
SOURCE_CHOICES = (("J8 外部 8 路", SOURCE_J8), ("Core 内部观测点", SOURCE_CORE))
# 镜像模式（0xA7）只接受 post：其余字段在固件里被重新定义或写死。
MIRROR_KNOBS = ("post",)
MIRROR_REJECT = {
    "sample_div": "镜像模式的时基必须与上位机波特率匹配（每比特固定 8 个采样点），改了必然解出乱码",
    "pattern_div": "镜像模式的被测信号来自上位机串口线，板上的发生器不参与",
    "data": "0xA7 命令里这个字段表示「每比特采样点数」，不是激励字节",
    "pre": "镜像模式固定 pre=0：窗口必须从起始位开始",
    "trigger_type": "镜像模式的触发固定为 ch7 起始位下降沿（docs/application_logic_analyzer.md §6.7.3）",
    "trigger_mask": "镜像模式的触发固定为 ch7 起始位下降沿（docs/application_logic_analyzer.md §6.7.3）",
    "trigger_value": "镜像模式的触发固定为 ch7 起始位下降沿（docs/application_logic_analyzer.md §6.7.3）",
    "source": "镜像模式抓的是上位机串口线（ch7），与采集源无关；0xA7 的 13 字节报文也装不下源字节",
}


def mirror_required_samples(text: str, bit_samples: int) -> int:
    """镜像抓取至少需要多少个采样点：字符数 × 10 位（8N1）× 每比特采样点数。

    界面的事前校验和 run_captures 的事后判据都用这一个函数，
    避免"界面按一个公式拦、判据按另一个公式判"。
    """
    return len(text.encode("ascii")) * 10 * bit_samples


def _knob_int(name: str, raw) -> int:
    """界面传进来的是字符串，这里统一转整数；转不了就报错，不做静默取整。"""
    if isinstance(raw, bool):
        raise ValueError(f"旋钮 {name} 收到布尔值 {raw!r}，应填一个整数")
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            raise ValueError(f"旋钮 {name} 是空的：要么取消勾选「使用面板参数」，要么填一个整数")
        try:
            # 十进制优先，`0x` 前缀按十六进制：不要用 int(text, 0)——
            # 它会把操作员习惯写的 "010" 直接判成非法（Python 3 的 base=0 不许前导零）。
            return int(text, 16) if text.lower().startswith("0x") else int(text, 10)
        except ValueError:
            raise ValueError(f"旋钮 {name}={raw!r} 不是整数") from None
    raise ValueError(f"旋钮 {name} 类型不支持：{type(raw).__name__}")


def apply_knobs(mode: str, cfg: dict[str, int], knobs: dict | None = None,
                depth: int = 2048) -> dict[str, int]:
    """把「仪器面板」的旋钮套到模式默认配置上，返回**新字典**（不改调用方的 cfg）。

    knobs 为空（None 或 {}）时逐字段原样返回：这是板级 100/100 验收和历史证据
    走的那条路，一个字节都不许变。

    为什么必须有这一处：旋钮之间是耦合的。固件里的「每比特采样点数」是它自己算的
    ——`(pattern_div+1)/(sample_div+1)` 的整数除法（logic_analyzer.c 第 177 行）。
    上位机若沿用写死的 16，操作员一改时基或激励速率，页面上标的字节就和判据用的
    字节不是同一个，属于「判据与标注必须同源」（docs/application_logic_analyzer.md §6.6）。

    越界、未知字段、镜像模式不支持的字段一律抛 ValueError：
    采集器内部会**静默截断** pre/post（capture_engine.v 第 21～24 行），
    悄悄改掉操作员输入的窗口比报错更坏。
    """
    merged = dict(cfg)
    if not knobs:
        return merged
    allowed = MIRROR_KNOBS if mode == "mirror" else KNOB_FIELDS
    for name in knobs:
        if name not in KNOB_FIELDS:
            raise ValueError(f"未知旋钮 {name!r}；可用：{'、'.join(KNOB_FIELDS)}")
        if name not in allowed:
            raise ValueError(f"{mode} 模式不支持旋钮 {name}：{MIRROR_REJECT[name]}")
    # 采集源必须先定：它决定 pre/post 的编码宽度——走 0xA8（Core 内部观测点）时
    # 这两个字段各占 2 字节，走 0xA5 时各 1 字节。上限按"将要发出的那条命令"判，
    # 否则会出现"界面填得进去、报文装不下"的假配置。
    if "source" in knobs:
        source = _knob_int("source", knobs["source"])
    else:
        source = int(merged.get("source", SOURCE_J8))
    if source not in (SOURCE_J8, SOURCE_CORE):
        raise ValueError(f"旋钮 source={source} 越界（0 = J8 外部，1 = Core 内部观测点）")
    wide_window = (source == SOURCE_CORE)
    for name, raw in knobs.items():
        if name == "source":
            continue
        value = _knob_int(name, raw)
        # 16 位窗口只存在于两条命令：0xA8（采集源=Core）的 pre/post，0xA7（镜像）的 post
        if name in ("pre", "post") and (mode == "mirror" or wide_window):
            limit = 0xFFFF
        else:
            limit = KNOB_MAX[name]
        if not 0 <= value <= limit:
            raise ValueError(f"旋钮 {name}={value} 越界（允许 0..{limit}）")
        merged[name] = value
    if wide_window:
        merged["source"] = SOURCE_CORE
    else:
        # 明确回到 J8：命令仍是 0xA5/0xA7，报文逐字节与历史一致
        merged.pop("source", None)
    if merged["pre"] + 1 + merged["post"] > depth:
        raise ValueError(
            f"窗口装不下：pre={merged['pre']} + 触发样本 1 + post={merged['post']} "
            f"= {merged['pre'] + 1 + merged['post']} 点，超过 Raw 深度 {depth}；"
            f"采集器会静默截断 pre，拿到的窗口和输入的不是一回事")
    if mode == "mirror":
        if merged["pre"] != 0:
            raise ValueError("镜像模式固定 pre=0，不接受其他值")
    else:
        # 与固件同一个公式、同一种整数除法（不是四舍五入）
        merged["bit_samples"] = (merged["pattern_div"] + 1) // (merged["sample_div"] + 1)
        if mode == "uart" and merged["bit_samples"] < 1:
            raise ValueError(
                "时基比激励速率还慢：每比特不足 1 个采样点，UART 解码不成立；"
                "把时基 sample_div 调小，或把激励速率 pattern_div 调大")
    return merged


def packet_for(mode: str, value: int, clock_hz: int = 85_000_000,
               baud: int = 115200, depth: int = 2048,
               knobs: dict | None = None) -> tuple[bytes, dict[str, int]]:
    """按模式推导配置并打包成 13 字节命令，返回 (packet, cfg)。

    cfg 里既有报文用到的字段，也有**解码/判据**要用的字段（channel / bit_samples / post），
    这样各处只用一处推导，不会出现"报文用一套参数、页面标注用另一套"。

    knobs 给"仪器面板"的旋钮值（可为字符串）；为空时逐字段沿用模式默认。
    """
    cfg = apply_knobs(mode, default_config(mode, value, clock_hz, baud, depth), knobs, depth)
    packet = build_packet(cfg["mode"], cfg["data"], cfg["pattern_div"], cfg["sample_div"],
                          cfg["trigger_type"], cfg["trigger_mask"], cfg["trigger_value"],
                          cfg["pre"], cfg["post"], cfg["prefix"], cfg["post16"],
                          cfg.get("source"))
    return packet, cfg


def read_until(ser, marker: bytes, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    data = bytearray()
    while time.monotonic() < deadline:
        data.extend(ser.read(4096))
        if marker in data:
            return bytes(data)
    raise TimeoutError(f"UART timeout waiting for {marker!r}; bytes={len(data)}")


def synchronize_ready(ser, timeout: float) -> bytes:
    """Wait for a prompt in flight; silence means the target was already waiting."""
    deadline = time.monotonic() + timeout
    quiet_deadline = time.monotonic() + min(0.5, timeout)
    data = bytearray()
    while time.monotonic() < deadline:
        chunk = ser.read(4096)
        if chunk:
            data.extend(chunk)
            quiet_deadline = time.monotonic() + min(0.5, timeout)
            if b"LA_READY" in data:
                return bytes(data)
        elif not data and time.monotonic() >= quiet_deadline:
            return b""
    raise TimeoutError(f"UART produced data but no LA_READY prompt; bytes={len(data)}")


def run_captures(port: str, output: Path, mode: str, value: int, runs: int,
                 baud: int, timeout: float,
                 pre: int | None = None, post: int | None = None,
                 on_run=None, mirror_text: str = DEFAULT_MIRROR_TEXT,
                 clock_hz: int = 85_000_000,
                 knobs: dict | None = None) -> list[dict[str, int | str]]:
    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required for live MES50HP capture") from exc
    cfg = default_config(mode, value, clock_hz, baud)
    # 镜像模式的 pre/post 由固件语义决定（pre=0、post=深度-1），不接受命令行覆盖 pre。
    if pre is not None and mode != "mirror":
        cfg["pre"] = pre
    if post is not None:
        cfg["post"] = post
    # 面板旋钮最后套用：面板上的值优先于命令行的 -Pre/-Post，并在这里完成越界校验。
    cfg = apply_knobs(mode, cfg, knobs)
    # 这一窗数据该怎么解释：由"采集源"决定，不由 mode 决定（见 capture_view 注释）。
    view = capture_view(mode, cfg.get("source", SOURCE_J8))
    if view != mode:
        print(f"提示：采集源={'Core 内部观测点' if view == VIEW_CORE else 'J8 外部 8 路'}，"
              f"本窗按 {view} 解释（{mode} 模式只提供窗口与触发预设）")
    # 镜像模式先算窗口够不够：不够就当场报错，别采完一轮才发现整句装不下。
    if mode == "mirror":
        need = mirror_required_samples(mirror_text, cfg["bit_samples"])
        if cfg["post"] + 1 < need:
            raise ValueError(f"镜像窗口 {cfg['post'] + 1} 点装不下 {len(mirror_text)} 个字符"
                             f"（需要 {need} 点）：把 post 调到 ≥ {need - 1}")
    packet = build_packet(cfg["mode"], cfg["data"], cfg["pattern_div"], cfg["sample_div"],
                          cfg["trigger_type"], cfg["trigger_mask"], cfg["trigger_value"],
                          cfg["pre"], cfg["post"], cfg["prefix"], cfg["post16"],
                          cfg.get("source"))
    # 镜像模式要发出去的那句话：判据就是"解出来的必须逐字节等于它"。
    text_bytes = mirror_text.encode("ascii") if mode == "mirror" else b""
    output.mkdir(parents=True, exist_ok=True)
    summaries: list[dict[str, int | str]] = []
    with serial.Serial(port, baudrate=baud, bytesize=8, parity="N", stopbits=1, timeout=0.1) as ser:
        ser.reset_input_buffer()
        synchronize_ready(ser, min(timeout, 3.0))
        for run in range(runs):
            ser.write(packet)
            if mode == "mirror":
                # 固件 Arm 生效后才会打印 LA_ARMED。**必须等到它再发字符串**：
                # 字符串比 Arm 早到的话，第一个起始位下降沿会落在 Arm 之前，
                # 采集窗口就从报文中间开始了（这条顺序是硬约束，不是保险）。
                read_until(ser, b"LA_ARMED", timeout)
                ser.write(text_bytes)
            # 固件在 LA_DONE 之后输出 LA_READY；等到 READY 才允许发送下一包，
            # 防止 UART 回传期间新配置字节覆盖硬件的一字节 RX 邮箱。
            try:
                raw_text = read_until(ser, b"LA_READY", timeout)
            except TimeoutError as exc:
                # 最常见的原因不是板子坏了，而是"触发条件根本没出现"。把这一条直接
                # 写在报错里：否则现场只能看到一个 20 秒超时，猜不出要改触发通道。
                # 原句照旧保留在最前面，历史日志的检索方式不受影响。
                if len(exc.args) and "bytes=0" in str(exc.args[0]):
                    # 一个字节都没有 = 固件不在命令循环里（不是"在等触发"而是"已经等在
                    # 采集完成上"）。固件该处是无超时轮询（logic_analyzer.c 第 189 行），
                    # 所以上一枪若发了永不出现的触发，板子会停在采样里、串口不再响应，
                    # **只有按 REST 或重新下载同一位流才能恢复**。这里必须说清，否则
                    # 现场会以为是接线或串口坏了，一直重试到演示结束。
                    raise TimeoutError(
                        f"{exc}；板子完全没有输出：上一枪的触发条件很可能从未出现，"
                        f"固件正停在等待采集完成（该处无超时），只能按板上 REST 或重新下载"
                        f"同一位流恢复（release/materials/field_recovery_card.md）。"
                        f"恢复后请确认触发通道上真的有信号：当前 采集源={cfg.get('source', SOURCE_J8)} "
                        f"触发={('level', 'rise', 'fall')[cfg['trigger_type']]} "
                        f"mask=0x{cfg['trigger_mask']:02X} value=0x{cfg['trigger_value']:02X}") from None
                raise TimeoutError(
                    f"{exc}；触发条件在 {timeout:g} 秒内没有出现：请确认触发通道上真的有信号。"
                    f"当前 采集源={cfg.get('source', SOURCE_J8)} 触发={('level', 'rise', 'fall')[cfg['trigger_type']]} "
                    f"mask=0x{cfg['trigger_mask']:02X} value=0x{cfg['trigger_value']:02X}"
                    f"（J8 源下这些是 J8 引脚；Core 源下才是流水线观测点）") from None
            if b"LA_DONE" not in raw_text:
                raise ValueError(f"capture {run} ended without LA_DONE")
            samples, trigger = parse_raw(raw_text)
            if not samples or trigger is None or trigger >= len(samples):
                raise ValueError(f"capture {run} invalid: samples={len(samples)} trigger={trigger}")
            # Always preserve the board response and VCD before protocol
            # validation.  A failed physical capture must remain inspectable.
            stem = f"{mode}_{run:02d}"
            (output / f"{stem}.log").write_bytes(raw_text)
            write_vcd(samples, output / f"{stem}.vcd", 8, trigger)
            # [2026-10-03 新增] 同步生成自包含波形页：pyUI 采完不必再手动拖 .vcd，
            # 直接双击这个 .html 就能用浏览器看（与零依赖采集器产物一致）。
            page_note = f"mode={mode} samples={len(samples)} trigger={trigger}"
            page_extra: dict[str, object] = {}
            if view == VIEW_CORE:
                # 波形页必须把 8 根线标成真名，否则现场没人认得出哪根是 flush。
                page_note = ("采集源 = Core 内部观测点（MMIO 寄存器 18 切换，不重新综合）· "
                             "ch0 i_req_valid · ch1 i_req_ready · ch2 i_rsp_valid · "
                             "ch3 d_req_valid · ch4 d_req_ready · ch5 event_stall · "
                             "ch6 event_flush（触发沿）· ch7 trace_valid")
                page_extra = {
                    "sample_ns": 1e9 * (cfg["sample_div"] + 1) / clock_hz,
                    "tag_names": dict(CORE_PROBE_NAMES),
                }
            elif view == VIEW_RAW:
                # core 预设 + J8 源：8 根线就是 J8 引脚，不能再挂流水线的通道名，
                # 否则页面上"ch7 = trace_valid"会把一根普通外部线说成 CPU 提交信号。
                page_note = (f"采集源 = J8 外部 8 路（core 只是窗口/触发预设："
                             f"每比特 {cfg['sample_div'] + 1} 拍 · 2048 点 · ch6 上升沿）· "
                             f"samples={len(samples)} trigger={trigger}")
                page_extra = {"sample_ns": 1e9 * (cfg["sample_div"] + 1) / clock_hz}
            if mode == "mirror":
                page_note = (f"上位机发送 {mirror_text}（{len(text_bytes)} 字符 / "
                             f"{len(text_bytes) * 10} bit / {baud} 8N1）· "
                             f"ch{MIRROR_CHANNEL}=J8-31/32 回环 · 触发=起始位下降沿 · "
                             f"每比特 {cfg['bit_samples']} 个采样点")
                # 采样点周期 = (sample_div+1)/时钟；给了页面才把横轴标成真实时间。
                page_extra = {
                    "sample_ns": 1e9 * (cfg["sample_div"] + 1) / clock_hz,
                    "decode": {"protocol": "uart", "channel": MIRROR_CHANNEL,
                               "bit_samples": cfg["bit_samples"], "which": 1},
                    "tag_names": {str(MIRROR_CHANNEL): "PC_TX"},
                }
            write_waveform_page(
                [{"name": f"{mode} 模式 第{run + 1}次", "samples": samples, "trigger": trigger,
                  "note": page_note, **page_extra}],
                output / f"{stem}.html",
            )
            # [2026-10-03 新增] 把这一轮立刻交给调用方（pyUI 的实时波形面板）。
            # 放在协议校验**之前**：校验失败时更需要对着一张真实波形排错，
            # 而不是等抛异常后什么都看不到。
            if on_run is not None:
                on_run(samples, trigger, {"mode": mode, "view": view, "run": run, "runs": runs,
                                          "source": int(cfg.get("source", SOURCE_J8)),
                                          "log": str(output / f"{stem}.log"),
                                          "vcd": str(output / f"{stem}.vcd")})
            uart_data, uart_errors = decode_uart(samples, cfg["channel"], cfg["bit_samples"])
            spi_data = decode_spi(samples, 0, 1, 2)
            if view == VIEW_CORE:
                # 判据：Core 必须**真的在跑**。只看"采到 2048 个点"是不够的——
                # 采到一整窗 0 也满足点数的形式条件，而那正是"源没切过去"或
                # "Core 卡死"时的样子。这里要求窗口里既有提交脉冲（ch7 trace_valid），
                # 又有取指请求在场（ch0 i_req_valid）。
                commits = sum(1 for sample in samples if sample & 0x80)
                fetch_valid = sum(1 for sample in samples if sample & 0x01)
                if commits < 8 or fetch_valid < 8:
                    raise ValueError(f"capture {run} core probe shows no CPU activity: "
                                     f"commits={commits} fetch_valid={fetch_valid}")
            # 协议判据只在"这一窗确实是该协议的引脚波形"时才成立：源切到 Core 以后
            # 8 根线是流水线内部信号，拿 UART/SPI 帧去套必然报假失败；
            # core 预设 + J8 源则只是 8 路外部信号，没有任何协议可判。
            if view == mode and mode == "static" and any(sample != value for sample in samples):
                raise ValueError(f"capture {run} static loopback mismatch: "
                                 f"expected={value:02x} samples={bytes(samples).hex()}")
            if view == mode and mode == "counter" and len(set(samples)) < 2:
                raise ValueError(f"capture {run} counter did not change: samples={bytes(samples).hex()}")
            if view == mode and mode == "uart" and (bytes([value]) not in uart_data or uart_errors):
                raise ValueError(f"capture {run} UART decode mismatch: {uart_data.hex()} errors={uart_errors}")
            if view == mode and mode == "spi" and bytes([value]) not in spi_data:
                raise ValueError(f"capture {run} SPI decode mismatch: {spi_data.hex()}")
            if view == mode and mode == "mirror":
                # 判据：从波形里解出来的字节必须**逐字节等于上位机发出去的那句话**。
                # 只判"解出了东西"是不够的——那正是本次要修掉的半比特错位能混过去的原因。
                if uart_errors or uart_data != text_bytes:
                    raise ValueError(
                        f"capture {run} mirror decode mismatch: got={uart_data!r} "
                        f"want={text_bytes!r} errors={uart_errors} samples={len(samples)}")
                head = mirror_required_samples(mirror_text, cfg["bit_samples"])
                if len(samples) < head:
                    raise ValueError(f"capture {run} mirror window too short: "
                                     f"samples={len(samples)} need>={head}")
            summaries.append({"run": run, "mode": mode, "view": view, "value": value,
                              "samples": len(samples), "trigger": trigger,
                              "uart": uart_data.hex(), "uart_errors": uart_errors,
                              "spi": spi_data.hex(),
                              "core_commits": sum(1 for s in samples if s & 0x80) if view == VIEW_CORE else 0,
                              "core_stalls": sum(1 for s in samples if s & 0x20) if view == VIEW_CORE else 0,
                              "core_flushes": sum(1 for s in samples if s & 0x40) if view == VIEW_CORE else 0,
                              "text": mirror_text if mode == "mirror" else ""})
            print(f"LOGIC ANALYZER BOARD RUN {run + 1}/{runs} PASS mode={mode} view={view} "
                  f"samples={len(samples)} trigger={trigger}")
    (output / "summary.json").write_text(json.dumps(summaries, indent=2) + "\n", encoding="utf-8")
    print(f"ALL {runs} LOGIC ANALYZER BOARD CAPTURES PASS output={output}")
    return summaries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("--output", type=Path, default=Path("release/evidence/logic_analyzer"))
    parser.add_argument("--mode", choices=MODES, default="static")
    parser.add_argument("--value", type=lambda x: int(x, 0), default=0xA5)
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=5.0)
    # [2026-09-30] 可选覆盖采集窗口；不传即沿用各模式既有值。
    parser.add_argument("--pre", type=int, default=None,
                        help="trigger 之前的采样点数（默认取模式配置）")
    parser.add_argument("--post", type=int, default=None,
                        help="trigger 之后的采样点数（默认取模式配置）")
    # [2026-10-10] 镜像模式（--mode mirror）：上位机把 --text 这句话原样发到板子串口，
    # 逻辑分析仪抓的就是这根线本身。--clock-hz 只用来把"比特时间"换算成采样分频，
    # 必须与实际位流的时钟一致（la85 = 85 MHz，la50 = 50 MHz）。
    parser.add_argument("--text", default=DEFAULT_MIRROR_TEXT,
                        help="mirror 模式要发送并抓取的字符串（ASCII）")
    parser.add_argument("--clock-hz", type=int, default=85_000_000,
                        help="位流时钟，用于 mirror 模式的采样分频换算")
    args = parser.parse_args()
    run_captures(args.port, args.output, args.mode, args.value & 0xFF,
                 args.runs, args.baud, args.timeout, args.pre, args.post,
                 mirror_text=args.text, clock_hz=args.clock_hz)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
