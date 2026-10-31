#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""逻辑分析仪 · 单文件全功能演示（自包含，不依赖仓库里任何模块）

双击本文件即可运行（或在命令行里 python 逻辑分析仪演示.py）。五种模式一个窗口全看完：

    static   固定电平回环      —— 先确认接线和八通道映射
    counter  8 位计数器        —— 确认八路都在动
    uart     芯片自己发的 UART —— 波形 + 解出的字节
    spi      芯片自己发的 SPI  —— SCLK/MOSI/CS 三根线 + 解出的字节
    mirror   上位机发字符串    —— 你自己在下面输入框里打的字，抓的就是这根串口线

只需要 pyserial（pip install pyserial）。板子里要有交付位流，J8 八对脚接好：
3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。

命令行附加用法（不看界面，只跑一遍自检）：
    python 逻辑分析仪演示.py --selftest            # 五种模式各抓一次，打印 PASS/FAIL
    python 逻辑分析仪演示.py --selftest --text "HI"
"""
from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

try:
    import serial
    import serial.tools.list_ports as list_ports
except ImportError:                                   # pragma: no cover
    sys.exit("缺 pyserial：先执行  py -3 -m pip install pyserial")

# 控制台中文：Windows 下 Python 默认按 GBK 写 stdout，而把输出重定向/被别的进程抓走时
# 对方常按 UTF-8 解码，于是满屏乱码。这里统一成"控制台代码页 65001 + stdout 写 UTF-8"，
# 直接双击、在 cmd 里、在 PowerShell 里、被脚本抓取，四种情况都不会乱码。
if sys.platform == "win32":
    try:
        import ctypes
        ctypes.windll.kernel32.SetConsoleOutputCP(65001)
    except Exception:
        pass
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")     # Python 3.7+
        except Exception:
            pass

BAUD = 115200
TIMEOUT = 12.0
DEPTH = 2048                     # 交付固件的采集深度（logic_analyzer_mmio 的 DEPTH 参数）
OUT = Path(__file__).resolve().parent / "results" / "demo"
MODES = ("static", "counter", "uart", "spi", "mirror", "core")
MODE_VALUES = {"static": 0xA5, "counter": 0x00, "uart": 0xA5, "spi": 0x3C, "core": 0x00}
DEFAULT_TEXT = "HELLO,RISC-V"
# 采集源（双源可选，MMIO 寄存器 18）：0 = J8 外部 8 路，1 = Core 内部观测点。
# 选 1 时命令变成 0xA8（16 字节：pre/post 各 2 字节 + [14] 源字节）。
SOURCE_J8, SOURCE_CORE = 0, 1
SOURCES = (("J8 外部 8 路", SOURCE_J8), ("Core 内部观测点", SOURCE_CORE))
# Core 内部观测点的通道名（与板级顶层 core_probe 逐位对应）
CORE_CHANNELS = {0: "i_req_valid", 1: "i_req_ready", 2: "i_rsp_valid", 3: "d_req_valid",
                 4: "d_req_ready", 5: "event_stall", 6: "event_flush", 7: "trace_valid"}
# 「这一窗数据是什么」——与 mode 不是一回事（与 python/logic_analyzer_serial.py 的
# capture_view 必须保持一致）：采集源改变 8 根线的物理含义，所以判据不能只按模式走。
#   源 = Core             -> "core"：ch0..ch7 是流水线观测点
#   源 = J8 且 mode=core  -> "raw" ：core 只剩窗口/触发预设，8 根线仍是 J8 引脚
#   其余                  -> mode 本身（协议解码才成立）
VIEW_CORE, VIEW_RAW = "core", "raw"


def capture_view(mode: str, source: int) -> str:
    if int(source) == SOURCE_CORE:
        return VIEW_CORE
    if mode == VIEW_CORE:
        return VIEW_RAW
    return mode

# ============================================================ 协议与参数
def build_packet(mode, data, pattern_div, sample_div, trig_type, trig_mask,
                 trig_value, pre, post, prefix=0xA5, post16=False,
                 source=None) -> bytes:
    """命令报文。

    默认 13 字节：A5/A7 mode data pd_lo pd_hi sd_lo sd_hi trig mask value pre post XOR
    source 不为 None 时改用 **0xA8**，16 字节：
      [1]~[9] 同 0xA5，[10]|[11]=pre、[12]|[13]=post（各 16 位小端），
      [14]=采集源，[15]=XOR 校验。
    为什么另开一条命令：0xA5/0xA7 的 13 字节布局已被上位机、解析器与板级 100/100
    证据锁死，改长度会波及全部既有证据；新命令只在用双源功能时出现。
    """
    if source is not None:
        v = [0xA8, mode, data, pattern_div & 0xFF, pattern_div >> 8,
             sample_div & 0xFF, sample_div >> 8, trig_type, trig_mask, trig_value,
             pre & 0xFF, pre >> 8, post & 0xFF, post >> 8, source]
        cs = 0
        for x in v:
            cs ^= x
        return bytes(v + [cs])
    slots = [post & 0xFF, post >> 8] if post16 else [pre, post]
    v = [prefix, mode, data, pattern_div & 0xFF, pattern_div >> 8,
         sample_div & 0xFF, sample_div >> 8, trig_type, trig_mask, trig_value] + slots
    cs = 0
    for x in v:
        cs ^= x
    return bytes(v + [cs])


def packet_for_cfg(cfg: dict) -> bytes:
    """按一份**最终 cfg** 打报文。界面里所有"要发出去"和"要记进日志"的地方都必须走这里。

    [2026-10-14 修] 原来这个拼装被抄了两份：`capture()` 传了 `source`、而 `log_packet()`
    漏传 —— 于是 **core 模式的报文在写日志时抛 ValueError**（pre=64/post=1983 被当成
    单字节）异常从 Tk 的 after 回调里窜出去，把整个轮询循环打断，界面表现为"点 core
    完全没反应"。一份实现就不可能出现两处漏字段。
    """
    return build_packet(cfg["mode"], cfg["data"], cfg["pattern_div"], cfg["sample_div"],
                        cfg["trig_type"], cfg["trig_mask"], cfg["trig_value"],
                        cfg["pre"], cfg["post"], cfg["prefix"], cfg["post16"],
                        cfg.get("source"))


def mode_config(mode: str, text: str = DEFAULT_TEXT, clock_hz: int = 85_000_000) -> dict:
    """每个模式的采样/触发参数。mirror 的分频要按板级时钟和波特率算，不能照抄别的模式。"""
    if mode == "core":
        # 采集源切到 Core 内部观测点：全速采样（sample_div=0，每拍一个点），
        # 2048 点窗口 ≈ 24 µs @85 MHz；触发 ch6 = event_flush 上升沿，
        # 窗口因此天然"以一次控制流冲刷为中心"。
        return dict(mode=0, data=0, pattern_div=0, sample_div=0,
                    trig_type=1, trig_mask=1 << 6, trig_value=0,
                    pre=64, post=DEPTH - 1 - 64,
                    prefix=0xA5, post16=False, channel=6, bit_samples=1,
                    source=SOURCE_CORE, text="",
                    note="采集源 = Core 内部观测点 · 触发 ch6 event_flush 上升沿")
    if mode == "mirror":
        bit_cycles = clock_hz / BAUD
        sample_div = max(0, round(bit_cycles / 8) - 1)
        bit_samples = round(bit_cycles / (sample_div + 1))
        return dict(mode=4, data=bit_samples, pattern_div=0, sample_div=sample_div,
                    trig_type=2, trig_mask=1 << 7, trig_value=0, pre=0, post=DEPTH - 1,
                    prefix=0xA7, post16=True, channel=7, bit_samples=bit_samples,
                    text=text, note=f"上位机发送 {text}")
    if mode == "uart":
        return dict(mode=2, data=MODE_VALUES["uart"], pattern_div=433, sample_div=26,
                    trig_type=2, trig_mask=1, trig_value=0, pre=64, post=191,
                    prefix=0xA5, post16=False, channel=0, bit_samples=16,
                    text="", note="芯片发 UART 8N1，字节 0xA5")
    if mode == "spi":
        return dict(mode=3, data=MODE_VALUES["spi"], pattern_div=3, sample_div=0,
                    trig_type=2, trig_mask=1 << 2, trig_value=0, pre=4, post=80,
                    prefix=0xA5, post16=False, channel=0, bit_samples=16,
                    text="", note="芯片发 SPI mode0，字节 0x3C；触发 CS 下降沿")
    m = 1 if mode == "counter" else 0
    data = MODE_VALUES[mode]
    return dict(mode=m, data=data, pattern_div=3, sample_div=0,
                trig_type=0, trig_mask=1, trig_value=data & 1, pre=4, post=4,
                prefix=0xA5, post16=False, channel=0, bit_samples=16,
                text="", note=f"{mode} 回环，激励 0x{data:02X}")


# ============================================================ 仪器面板旋钮
# 只列固件**真的会读**的字段（13 字节报文里存在的那些）。固件把 LA_CH_MASK
# 写死成 0xFF，报文里没有这个字节，所以不做成旋钮——点得动、硬件不认最坑人。
KNOB_FIELDS = ("sample_div", "trigger_type", "trigger_mask", "trigger_value",
               "pre", "post", "pattern_div", "data", "source")
KNOB_MAX = {"sample_div": 0xFFFF, "trigger_type": 2, "trigger_mask": 0xFF,
            "trigger_value": 0xFF, "pre": 0xFF, "post": 0xFF,
            "pattern_div": 0xFFFF, "data": 0xFF, "source": SOURCE_CORE}
MIRROR_REJECT = {
    "sample_div": "镜像模式的时基必须与上位机波特率匹配（每比特固定 8 个采样点），改了必然解出乱码",
    "pattern_div": "镜像模式的被测信号来自上位机串口线，板上的发生器不参与",
    "data": "0xA7 命令里这个字段表示「每比特采样点数」，不是激励字节",
    "pre": "镜像模式固定 pre=0：窗口必须从起始位开始",
    "trigger_type": "镜像模式的触发固定为 ch7 起始位下降沿",
    "trigger_mask": "镜像模式的触发固定为 ch7 起始位下降沿",
    "trigger_value": "镜像模式的触发固定为 ch7 起始位下降沿",
    "source": "镜像模式抓的是上位机串口线（ch7），与采集源无关；0xA7 的 13 字节报文也装不下源字节",
}
# 本文件的 cfg 用的是 trig_* 这套短名字，而面板/报文字段名是 trigger_*。
# 必须在这里显式翻译：写错的话旋钮会被静默加成一个新键，报文照发但**参数没生效**
# ——这正是本轮对拍抓到的 bug（触发旋钮一度完全无效）。
_KNOB_TO_CFG = {"trigger_type": "trig_type", "trigger_mask": "trig_mask",
                "trigger_value": "trig_value"}


def mask_to_channel(mask: int) -> int:
    for ch in range(8):
        if mask & (1 << ch):
            return ch
    return 0


def mirror_required_samples(text: str, bit_samples: int) -> int:
    """镜像抓取至少需要多少采样点：字符数 × 10 位（8N1）× 每比特点数。"""
    return len(text.encode("ascii")) * 10 * bit_samples


def _knob_int(name, raw) -> int:
    if isinstance(raw, bool):
        raise ValueError(f"旋钮 {name} 收到布尔值 {raw!r}，应填一个整数")
    if isinstance(raw, int):
        return raw
    text = str(raw).strip()
    if not text:
        raise ValueError(f"旋钮 {name} 是空的：要么取消勾选「使用面板参数」，要么填一个整数")
    try:
        # 十进制优先，0x 前缀按十六进制。不要用 int(text, 0)：它会把 "010" 判成非法
        return int(text, 16) if text.lower().startswith("0x") else int(text, 10)
    except ValueError:
        raise ValueError(f"旋钮 {name}={raw!r} 不是整数") from None


def apply_knobs(mode: str, cfg: dict, knobs=None) -> dict:
    """把面板旋钮套到模式默认参数上，返回**新字典**。

    旋钮为空时逐字段原样返回：不勾面板就走这条路，与以前的采集**完全一致**。
    越界一律报错——采集器内部会静默截断 pre/post，把操作员输的窗口悄悄改掉比报错更坏。
    """
    merged = dict(cfg)
    if not knobs:
        return merged
    for name in knobs:
        if name not in KNOB_FIELDS:
            raise ValueError(f"未知旋钮 {name!r}")
        if mode == "mirror" and name != "post":
            raise ValueError(f"镜像模式不支持旋钮 {name}：{MIRROR_REJECT[name]}")
    # 采集源先定：它决定 pre/post 的编码宽度（0xA8 各 2 字节，0xA5 各 1 字节），
    # 上限必须按**将要发出的那条命令**判，否则界面能填、报文却装不下。
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
        # 16 位窗口只存在于两条命令：0xA8 的 pre/post 与 0xA7（镜像）的 post
        if name in ("pre", "post") and (mode == "mirror" or wide_window):
            limit = 0xFFFF
        else:
            limit = KNOB_MAX[name]
        if not 0 <= value <= limit:
            raise ValueError(f"旋钮 {name}={value} 越界（允许 0..{limit}）")
        merged[_KNOB_TO_CFG.get(name, name)] = value
    if wide_window:
        merged["source"] = SOURCE_CORE
    else:
        # 明确回到 J8：命令仍是 0xA5/0xA7，报文逐字节与历史一致
        merged.pop("source", None)
    if merged["pre"] + 1 + merged["post"] > DEPTH:
        raise ValueError(f"窗口装不下：pre={merged['pre']} + 触发样本 1 + post={merged['post']} "
                         f"= {merged['pre'] + 1 + merged['post']} 点，超过深度 {DEPTH}")
    if mode == "mirror":
        if merged["pre"] != 0:
            raise ValueError("镜像模式固定 pre=0，不接受其他值")
    else:
        # 每比特采样点数与固件用**同一个公式、同一种整数除法**（logic_analyzer.c 第 177 行）。
        # 不重算的话，一改时基或激励速率，波形页标的字节就和判据用的字节不是同一个。
        merged["bit_samples"] = (merged["pattern_div"] + 1) // (merged["sample_div"] + 1)
        if mode == "uart" and merged["bit_samples"] < 1:
            raise ValueError("时基比激励速率还慢：每比特不足 1 个采样点，UART 解码不成立；"
                             "把时基调小或把激励速率调大")
    return merged


# ============================================================ 解析与解码
def parse_raw(raw: bytes):
    """从板子回包里取样本与触发点。只认 LA RAW 那一行，避免把日志里的十六进制当成样本。"""
    text = raw.decode("ascii", "replace")
    m = re.search(r"LA RAW count=([0-9a-fA-F]+) trigger=([0-9a-fA-F]+)", text)
    if not m:
        raise ValueError("回包里没有 LA RAW 行（固件不是交付版？）")
    count, trigger = int(m.group(1), 16), int(m.group(2), 16)
    rest = text[m.end():]
    eol = re.search(r"\r?\n", rest)
    line = ""
    if eol:
        rest2 = rest[eol.end():]
        nxt = re.search(r"\r?\n", rest2)
        line = rest2[:nxt.start()] if nxt else rest2
    samples = [int(t, 16) & 0xFF for t in re.findall(r"\b[0-9a-fA-F]{1,8}\b", line)][:count]
    return samples, trigger


def decode_uart(samples, channel=0, bit_samples=16, want_bytes=None):
    """8N1 解码：在**比特中点**取样；每帧用自己的起始位重新对齐（实板边沿有 ±1 点抖动，
    固定跳 10 个比特会让误差逐帧累积）。返回 (字节, 帧列表, 错误数)。"""
    if bit_samples < 1:
        bit_samples = 1
    half = max(1, bit_samples // 2)
    level = [(s >> channel) & 1 for s in samples]
    out, frames, errors, i = bytearray(), [], 0, 0
    n = len(level)
    while i + bit_samples * 9 + half < n:
        prev = level[i - 1] if i > 0 else 1
        if prev == 1 and level[i] == 0:
            val = 0
            for b in range(8):
                val |= level[i + bit_samples * (b + 1) + half] << b
            stop = level[i + bit_samples * 9 + half]
            if stop == 1:
                if want_bytes is None or len(out) < want_bytes:
                    frames.append((i, i + bit_samples * 10, val))
                out.append(val)
                i += bit_samples * 9 + half + 1
            else:
                errors += 1
                i += 1
        else:
            i += 1
    return bytes(out), frames, errors


def decode_spi(samples, clock=0, mosi=1, cs=2):
    """SPI mode0：CS 低有效，SCLK 上升沿采 MOSI（MSB 先）。返回 (字节, 帧列表)。"""
    cm, mm, csm = 1 << clock, 1 << mosi, 1 << cs
    out, frames = bytearray(), []
    val = bits = prev = 0
    start = None
    for i, s in enumerate(samples):
        active = not (s & csm)
        rising = prev == 0 and (s & cm)
        prev = 1 if s & cm else 0
        if active and rising:
            if start is None:
                start = i
            val = ((val << 1) | (1 if s & mm else 0)) & 0xFF
            bits += 1
            if bits == 8:
                out.append(val)
                frames.append((start, i, val))
                val = bits = 0
                start = None
        elif not active:
            val = bits = 0
            start = None
    return bytes(out), frames


# ============================================================ 仪器读数
def fmt_si(v: float, unit: str) -> str:
    """按量级加前缀：1234.5 Hz → 1.234 kHz。仪表读数就该这么写，不该让人自己数零。"""
    if v is None:
        return "—"
    if v == 0:
        return f"0 {unit}"
    for div, pre in ((1e9, "G"), (1e6, "M"), (1e3, "k")):
        if abs(v) >= div:
            return f"{v / div:.4g} {pre}{unit}"
    if abs(v) < 1:
        for div, pre in ((1e-3, "m"), (1e-6, "µ"), (1e-9, "n")):
            if abs(v) >= div:
                return f"{v / div:.4g} {pre}{unit}"
    return f"{v:.4g} {unit}"


def fmt_time(ns: float | None) -> str:
    """时间读数：输入**纳秒**，输出带正确单位。

    别把纳秒值丢给通用 SI 格式化 —— 那会把 8658 ns 印成 "8.659 ks"（本轮实测踩到）。
    """
    if ns is None:
        return "—"
    if ns < 1000:
        return f"{ns:.1f} ns"
    if ns < 1e6:
        return f"{ns / 1000:.3f} µs"
    if ns < 1e9:
        return f"{ns / 1e6:.3f} ms"
    return f"{ns / 1e9:.3f} s"


def fmt_freq(period_ns: float | None) -> str:
    return "—" if not period_ns else fmt_si(1e9 / period_ns, "Hz")


def measure_channel(samples, ch: int, sample_ns: float):
    """一条通道的仪器读数：边沿、频率、周期（中位数）、占空比、最小/最大脉宽。

    周期用**中位数**而不是平均值：只要信号里有字节间隙、停顿这类偶发长间隔，
    平均值就会被带偏（实测 SPI 的 SCLK 因此读成 10.07 MHz，真值 10.62 MHz）。
    同时给出最小/最大周期，抖动是读数的一部分，不能藏。不足两个边沿返回 None——
    一条直线测不出频率，硬报 0 Hz 是假读数。
    """
    if len(samples) < 2 or not sample_ns:
        return None
    lvl = [(s >> ch) & 1 for s in samples]
    edges = [i for i in range(1, len(lvl)) if lvl[i] != lvl[i - 1]]
    rises = [i for i in edges if lvl[i] == 1]
    falls = [i for i in edges if lvl[i] == 0]
    duty = sum(lvl) / len(lvl) * 100.0
    gaps = sorted((rises[k + 1] - rises[k]) * sample_ns for k in range(len(rises) - 1))
    period = gaps[len(gaps) // 2] if gaps else None
    widths = []
    run = 1
    for i in range(1, len(lvl)):
        if lvl[i] == lvl[i - 1]:
            run += 1
        else:
            widths.append(run * sample_ns)
            run = 1
    widths.append(run * sample_ns)
    return dict(ch=ch, rises=len(rises), falls=len(falls), edges=len(edges), duty=duty,
                period=period, freq=(1e9 / period) if period else None,
                pmin=gaps[0] if gaps else None, pmax=gaps[-1] if gaps else None,
                wmin=min(widths), wmax=max(widths), n=len(samples))


def measure_all(samples, sample_ns):
    return [measure_channel(samples, ch, sample_ns) for ch in range(8)]


def protocol_readings(mode, cfg, sample_ns, frames, errors, samples):
    """协议层读数：帧/字节数、帧错误、位宽、推算波特率。数值全部由实测位宽反推。"""
    out = []
    bit_ns = cfg.get("bit_samples", 0) * sample_ns
    if mode in ("uart", "mirror"):
        out += [("协议", "UART 8N1"),
                ("帧数（字符数）", str(len(frames))),
                ("帧错误", str(errors)),
                ("每位采样点", str(cfg.get("bit_samples", "—"))),
                ("位宽", fmt_time(bit_ns) if bit_ns else "—"),
                ("推算波特率", fmt_si(1e9 / bit_ns, "Bd") if bit_ns else "—"),
                ("解码内容", "".join(chr(v) if 32 <= v < 127 else "·" for _, _, v in frames)
                 or "（未解出）")]
    elif mode == VIEW_CORE:
        # 采到的是流水线内部信号：有意义的读数不是"哪根线多少 Hz"，而是这几个计数。
        commits = sum(1 for s in samples if s & 0x80)      # ch7 trace_valid
        fetch = sum(1 for s in samples if s & 0x01)        # ch0 i_req_valid
        stalls = sum(1 for s in samples if s & 0x20)       # ch5 event_stall
        flushes = sum(1 for s in samples if s & 0x40)      # ch6 event_flush
        ipc = commits / len(samples) if samples else 0.0
        out += [("采集源", "Core 内部观测点"),
                ("提交拍数 ch7", str(commits)),
                ("取指请求在场 ch0", str(fetch)),
                ("停顿拍数 ch5", str(stalls)),
                ("冲刷次数 ch6", str(flushes)),
                ("窗口 IPC", f"{ipc:.3f}")]
    elif mode == VIEW_RAW:
        edges = sum(1 for a, b in zip(samples, samples[1:]) if a != b)
        out += [("采集源", "J8 外部 8 路（core 预设）"),
                ("采样点数", str(len(samples))),
                ("窗口内跳变", str(edges))]
    elif mode == "spi":
        sclk = measure_channel(samples, 0, sample_ns)
        out += [("协议", "SPI mode0"),
                ("字节数", str(len(frames))),
                ("SCLK 频率", fmt_freq(sclk["period"]) if sclk else "—"),
                ("SCLK 周期抖动", f"{fmt_time(sclk['pmin'])} … {fmt_time(sclk['pmax'])}"
                 if sclk and sclk["pmin"] else "—"),
                ("解码字节", " ".join(f"0x{v:02X}" for _, _, v in frames) or "（未解出）")]
    else:
        out += [("协议", "无（只看电平）"), ("采样点数", str(len(samples)))]
    return out


def report_markdown(title, mode, note, cfg, sample_ns, samples, frames, errors, clock) -> str:
    """一张能直接交出去的测量报告：结论 + 读数 + 测量条件。"""
    rows = measure_all(samples, sample_ns)
    L = ["# 逻辑分析仪测量报告", "", f"**{title}**", "",
         f"- 模式：`{mode}`", f"- 说明：{note}",
         f"- 板级时钟：{clock / 1e6:.0f} MHz · 采样点周期 {sample_ns:.2f} ns",
         f"- 采样深度：{len(samples)} 点 · 时间窗 {fmt_time(sample_ns * len(samples))}", "",
         "## 通道读数", "",
         "| 通道 | 上升沿 | 下降沿 | 频率 | 周期(中位) | 周期抖动 | 占空比 | 最小脉宽 | 最大脉宽 |",
         "|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if r is None or r["edges"] == 0:
            ch = r["ch"] if r else "?"
            duty = f"{r['duty']:.1f} %" if r else "—"
            L.append(f"| ch{ch} | 0 | 0 | — | — | — | {duty} | — | — |")
            continue
        L.append(f"| ch{r['ch']} | {r['rises']} | {r['falls']} | {fmt_freq(r['period'])} | "
                 f"{fmt_time(r['period'])} | {fmt_time(r['pmin'])}…{fmt_time(r['pmax'])} | "
                 f"{r['duty']:.2f} % | {fmt_time(r['wmin'])} | {fmt_time(r['wmax'])} |")
    L += ["", "## 协议读数", "", "| 项 | 值 |", "|---|---|"]
    for k, v in protocol_readings(mode, cfg, sample_ns, frames, errors, samples):
        L.append(f"| {k} | {v} |")
    L += ["", "> 读数口径：位宽 = 每比特采样点数 × 采样点周期；周期取上升沿间隔的**中位数**",
          "> （平均值会被字节间隙带偏），并同时给出抖动范围；帧错误为 0 表示起始位/停止位全部合法。", ""]
    return "\n".join(L)



def find_port(explicit=None) -> str:
    if explicit:
        return explicit
    ports = list(list_ports.comports())
    for p in ports:
        name = f"{p.description or ''} {p.manufacturer or ''}"
        if "CP210" in name or "Silicon Labs" in name:
            return p.device
    if ports:
        return ports[0].device
    raise RuntimeError("找不到串口：插好板载 CP210x USB 线再刷新")


# ============================================================ 串口
def _read_until(ser, marker: bytes, timeout: float) -> bytes:
    end = time.monotonic() + timeout
    data = bytearray()
    while time.monotonic() < end:
        data.extend(ser.read(4096))
        if marker in data:
            return bytes(data)
    raise TimeoutError(f"等不到 {marker!r}（收到 {len(data)} 字节）")


def _sync(ser, timeout=3.0):
    end = time.monotonic() + timeout
    quiet = time.monotonic() + 0.5
    data = bytearray()
    while time.monotonic() < end:
        chunk = ser.read(4096)
        if chunk:
            data.extend(chunk)
            quiet = time.monotonic() + 0.5
            if b"LA_READY" in data:
                return
        elif not data and time.monotonic() >= quiet:
            return


def capture(port: str, mode: str, text: str = DEFAULT_TEXT, clock_hz: int = 85_000_000,
            knobs=None):
    """一次采集。返回 (原始回包, 样本, 触发点, 参数, 解出的字节, 帧, 帧错误数)。

    knobs 是仪器面板的旋钮（可为字符串）；为空则完全走模式默认参数。
    """
    cfg = apply_knobs(mode, mode_config(mode, text, clock_hz), knobs)
    if mode == "mirror":
        # 窗口够不够要在**打开串口之前**算：别采完一轮才发现整句装不下
        need = mirror_required_samples(text, cfg["bit_samples"])
        if cfg["post"] + 1 < need:
            raise ValueError(f"镜像窗口 {cfg['post'] + 1} 点装不下 {len(text)} 个字符"
                             f"（需要 {need} 点）：把 post 调到 ≥ {need - 1}")
    packet = packet_for_cfg(cfg)
    with serial.Serial(port, BAUD, bytesize=8, parity="N", stopbits=1, timeout=0.1) as ser:
        ser.reset_input_buffer()
        _sync(ser)
        ser.write(packet)
        if mode == "mirror":
            # 固件 Arm 生效后才打印 LA_ARMED；必须等到它再发字符串，
            # 否则字符串比 Arm 早到，采集窗口会从报文中间开始
            _read_until(ser, b"LA_ARMED", TIMEOUT)
            ser.write(text.encode("ascii"))
        raw = _read_until(ser, b"LA_READY", TIMEOUT)
    samples, trigger = parse_raw(raw)
    if mode in ("uart", "mirror"):
        decoded, frames, errors = decode_uart(samples, cfg["channel"], cfg["bit_samples"])
    else:
        decoded, frames = decode_spi(samples)
        errors = 0
    return raw, samples, trigger, cfg, decoded, frames, errors


# ============================================================ 判定（每个模式的 PASS 条件）
def judge(view, samples, decoded, errors, cfg, text) -> tuple[bool, str]:
    """view 是 capture_view() 的结果，不是 mode：采集源决定这 8 根线是什么。

    例如 uart 模式 + Core 源：波形是流水线内部信号，按 UART 帧去解必然报假失败，
    所以这里只认 view。view == "raw"（core 预设 + J8 源）没有任何判据，只报统计。
    """
    if view == VIEW_RAW:
        edges = sum(1 for a, b in zip(samples, samples[1:]) if a != b)
        return True, (f"J8 外部 8 路 {len(samples)} 点（core 只提供窗口/触发预设）· "
                      f"窗口内跳变 {edges} 次 · 无协议判据")
    if view == "static":
        bad = sum(1 for s in samples if s != MODE_VALUES["static"])
        return bad == 0, f"八路全等 0x{MODE_VALUES['static']:02X}" if bad == 0 else f"{bad} 个点不等于 0xA5"
    if view == "counter":
        return len(set(samples)) >= 2, f"采样值有 {len(set(samples))} 种（说明在计数）"
    if view == "uart":
        ok = bytes([MODE_VALUES["uart"]]) in decoded and errors == 0
        return ok, f"解出 {decoded.hex() or '空'}，帧错误 {errors}"
    if view == "spi":
        ok = bytes([MODE_VALUES["spi"]]) in decoded
        return ok, f"解出 {decoded.hex() or '空'}"
    if view == "core":
        # 判据：Core 必须**真的在跑**。只看"采到 2048 个点"不够——一整窗 0 也满足点数的
        # 形式条件，而那正是"源没切过去"或"Core 卡死"时的样子。
        commits = sum(1 for s in samples if s & 0x80)      # ch7 trace_valid
        fetch = sum(1 for s in samples if s & 0x01)        # ch0 i_req_valid
        stalls = sum(1 for s in samples if s & 0x20)       # ch5 event_stall
        flushes = sum(1 for s in samples if s & 0x40)      # ch6 event_flush
        ok = commits >= 8 and fetch >= 8
        ipc = commits / len(samples) if samples else 0.0
        return ok, (f"提交 {commits} 拍 / 取指在场 {fetch} 拍 / 停顿 {stalls} 拍 / "
                    f"冲刷 {flushes} 次 · 窗口 IPC ≈{ipc:.3f}")
    # 走到底只剩 mirror：解出来的字节必须逐字节等于上位机发出去的那句话
    want = text.encode("ascii")
    ok = decoded == want and errors == 0
    return ok, f"解出 {decoded.decode('ascii', 'replace')!r}，期望 {text!r}，帧错误 {errors}"


# ============================================================ 导出
def write_vcd(samples, path: Path, trigger: int):
    ids = [chr(33 + i) for i in range(8)]
    with path.open("w", encoding="ascii", newline="\n") as f:
        f.write("$timescale 1ns $end\n$scope module capture $end\n")
        for i, t in enumerate(ids):
            f.write(f"$var wire 1 {t} ch{i} $end\n")
        f.write("$upscope $end\n$enddefinitions $end\n#0\n")
        for i, t in enumerate(ids):
            f.write(f"{(samples[0] >> i) & 1 if samples else 0}{t}\n")
        for n, s in enumerate(samples[1:], 1):
            f.write(f"#{n}\n")
            for i, t in enumerate(ids):
                f.write(f"{(s >> i) & 1}{t}\n")
        if 0 <= trigger < len(samples):
            f.write(f"$comment trigger_index={trigger} $end\n")


HTML = """<!doctype html><meta charset="utf-8"><title>%(title)s</title>
<style>body{background:#101722;color:#dbe6f6;font:14px/1.5 "Microsoft YaHei",sans-serif;margin:0}
header{padding:10px 16px;background:#182233;border-bottom:1px solid #2b3a55}
details{padding:6px 16px;background:#141d2c;border-bottom:1px solid #2b3a55;font-size:13px}
table{border-collapse:collapse;margin:6px 0}td,th{border:1px solid #2b3a55;padding:2px 8px;font-size:12px}
canvas{display:block;width:100%%;height:calc(100vh - 150px)}</style>
<header><b>逻辑分析仪波形</b> — %(note)s</header>
<details open><summary>仪器读数</summary>%(readings)s</details>
<canvas id="c"></canvas><script>
var D=%(data)s,S=D.samples,W=0,H=0,cv=document.getElementById('c'),ctx=cv.getContext('2d');
var COL=['#39c0ff','#7ef0a1','#ffd479','#ff9c6e','#c792ea','#8ab4ff','#4ee0d0','#ff7ba8'];
function draw(){var dpr=devicePixelRatio||1;W=cv.clientWidth;H=cv.clientHeight;
cv.width=W*dpr;cv.height=H*dpr;ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,W,H);
var padL=86,padT=28,padB=26,x0=padL,x1=W-12,y0=padT,y1=H-padB;
var chs=D.channels&&D.channels.length?D.channels:[0,1,2,3,4,5,6,7];
var rh=(y1-y0)/chs.length,span=Math.max(1,S.length-1);
function X(i){return x0+i/span*(x1-x0);}
ctx.font='13px "Microsoft YaHei",sans-serif';
chs.forEach(function(ch,k){var top=y0+k*rh,hi=top+rh*0.26,lo=top+rh*0.76;
ctx.fillStyle=k%%2?'rgba(255,255,255,.02)':'rgba(255,255,255,.045)';ctx.fillRect(0,top,W,rh);
ctx.fillStyle='#93a4c4';ctx.fillText('ch'+ch+(D.tags&&D.tags[ch]?' · '+D.tags[ch]:''),10,top+rh/2);
ctx.strokeStyle=COL[ch%%8];ctx.lineWidth=1.6;ctx.beginPath();
for(var i=0;i<S.length;i++){var y=((S[i]>>ch)&1)?hi:lo;if(i===0)ctx.moveTo(X(i),y);else ctx.lineTo(X(i),y);}
ctx.stroke();});
if(D.trigger!=null&&D.trigger>=0){var tx=X(D.trigger);ctx.strokeStyle='#ff4d6d';ctx.setLineDash([6,4]);
ctx.beginPath();ctx.moveTo(tx,y0);ctx.lineTo(tx,y1);ctx.stroke();ctx.setLineDash([]);
ctx.fillStyle='#ff8fa3';ctx.fillText('触发 @'+D.trigger,Math.min(tx+4,W-80),16);}
(D.frames||[]).forEach(function(f){var xa=X(f[0]),xb=X(f[1]);if(xb-xa<2)return;
ctx.strokeStyle='rgba(126,240,161,.8)';ctx.beginPath();ctx.moveTo(xa,y0);ctx.lineTo(xa,y1);
ctx.moveTo(xb,y0);ctx.lineTo(xb,y1);ctx.stroke();var v=f[2];
var s=(v>=32&&v<127)?("'"+String.fromCharCode(v)+"' "):"";
ctx.fillStyle='#ffd479';ctx.font='12px Consolas,monospace';
ctx.fillText(s+'0x'+('0'+v.toString(16).toUpperCase()).slice(-2),xa+3,16);});
ctx.fillStyle='#7e91b3';ctx.fillText('0',x0-4,y1+16);ctx.fillText(String(S.length),x1-30,y1+16);
ctx.fillText('采样点',(x0+x1)/2-18,y1+16);}
addEventListener('resize',draw);draw();
</script>"""


def readings_html(mode, cfg, sample_ns, samples, frames, errors) -> str:
    """网页里那张"仪器读数"表：和界面右栏用的是同一套测量函数，不另写一份。"""
    head = ("<tr><th>通道</th><th>边沿</th><th>频率</th><th>周期(中位)</th>"
            "<th>占空比</th><th>最小脉宽</th><th>最大脉宽</th></tr>")
    body = []
    for r in measure_all(samples, sample_ns):
        if r is None or r["edges"] == 0:
            ch = r["ch"] if r else 0
            body.append(f"<tr><td>ch{ch}</td><td>0</td><td>—</td><td>—</td><td>—</td>"
                        f"<td>—</td><td>—</td></tr>")
            continue
        body.append(f"<tr><td>ch{r['ch']}</td><td>{r['edges']}</td><td>{fmt_freq(r['period'])}</td>"
                    f"<td>{fmt_time(r['period'])}</td><td>{r['duty']:.1f}%</td>"
                    f"<td>{fmt_time(r['wmin'])}</td><td>{fmt_time(r['wmax'])}</td></tr>")
    proto = "".join(f"<tr><td>{k}</td><td>{v}</td></tr>"
                    for k, v in protocol_readings(mode, cfg, sample_ns, frames, errors, samples))
    return (f"<table>{head}{''.join(body)}</table>"
            f"<table><tr><th>协议项</th><th>值</th></tr>{proto}</table>")


def write_html(path: Path, samples, trigger, frames, cfg, note, channels, tags,
               readings: str = ""):
    data = {"samples": samples, "trigger": trigger,
            "frames": [list(f) for f in frames[:64]],
            "channels": channels, "tags": tags}
    path.write_text(HTML % {"title": note, "note": note, "readings": readings,
                            "data": json.dumps(data, separators=(",", ":"))},
                    encoding="utf-8")


# ============================================================ 界面
def draw_wave(cv, ds):
    """把一路采集画到 canvas。

    怎么让人一眼看懂（第一版就是没做到这点，被用户当场打回）：
      · **只画参与协议的通道**：mirror 只画 ch7，uart 只画 ch0，spi 画 ch0/1/2。
        2048 个点画满一屏时，八条线里七条是直线，那条有用的线被压成一条缝 —— 等于没画。
      · 每个字符在**自己的框里用大字标出来**（'H' + 0x48），框和波形同一行，不用去顶上找。
      · 画**位网格**：每 bit_samples 个采样点一条淡竖线，一眼看出"一个字符 = 10 位"。
      · 顶上写清楚"这句话是什么"，底下横轴给真实时间（µs），不给"采样点"这种要换算的东西。

    放在模块级是为了能用 --selftest 在真实采集数据上跑一遍——画图这段是最容易写错的地方。
    """
    cv.delete("all")
    W = max(cv.winfo_width(), 480)
    H = max(cv.winfo_height(), 320)
    samples = ds.get("samples") or []
    frames = ds.get("frames") or []
    tags = ds.get("tags") or {}
    cfg = ds.get("cfg") or {}
    note = ds.get("note") or ""
    rows = sorted(tags) if tags else list(range(8))
    padL, padR, axis_h = 120, 14, 24
    head_h = 30 if note else 8
    x0, x1 = padL, W - padR
    y0, y1 = head_h + 6, H - axis_h
    rh = (y1 - y0) / len(rows)
    band = min(46, rh * 0.34) if frames else 0        # 字符标签带占行高的一部分
    span = max(1, len(samples) - 1)
    X = lambda i: x0 + i / span * (x1 - x0)
    # 通道配色取 GitHub Dark 的 scale 色板：八条线在同一张深底上互相不撞色，
    # 也和外层浅色外壳（Printer 风格）不打架。
    colors = ["#58a6ff", "#3fb950", "#d29922", "#db6d28",
              "#bc8cff", "#79c0ff", "#39c5cf", "#f778ba"]

    if note:
        cv.create_text(10, head_h / 2, anchor="w", text=note,
                       fill="#e6edf3", font=("Microsoft YaHei", 11, "bold"))

    # 位网格：以第一个字符的起始位为锚点，每 bit_samples 个采样点一条淡线
    bit_samples = cfg.get("bit_samples") or 0
    anchor = frames[0][0] if frames else 0
    if bit_samples and samples:
        k = 0
        while anchor + k * bit_samples <= len(samples):
            x = X(anchor + k * bit_samples)
            if x0 - 1 <= x <= x1 + 1:
                cv.create_line(x, y0, x, y1, fill="#21262d")
            k += 1

    for idx, ch in enumerate(rows):
        top = y0 + idx * rh
        wtop = top + band
        hi = wtop + (rh - band) * 0.26
        lo = wtop + (rh - band) * 0.76
        cv.create_rectangle(0, top, W, top + rh, outline="",
                            fill="#161b22" if idx % 2 else "#0d1117")
        cv.create_text(10, (hi + lo) / 2, anchor="w", fill="#8b949e",
                       text=f"ch{ch}" + (f"\n{tags[ch]}" if ch in tags else ""),
                       font=("Microsoft YaHei", 10), justify="left")
        if not samples:
            continue
        pts = []
        for i, s in enumerate(samples):
            pts += [X(i), hi if (s >> ch) & 1 else lo]
        if len(samples) == 1:
            cv.create_line(x0, pts[1], x1, pts[1], fill=colors[ch % 8], width=2)
        else:
            cv.create_line(*pts, fill=colors[ch % 8], width=2)

    # 字符框 + 大字标签（和波形同一行，不用抬头找）
    # 注意：帧属于 cfg["channel"] 这一条通道，别写成从 tags 里取标签名（那是字符串，不是通道号）。
    frame_ch = cfg.get("channel", rows[0])
    row_top = y0 + (rows.index(frame_ch) if frame_ch in rows else 0) * rh
    for frame in frames:
        a, b, v = frame[0], frame[1], frame[2]
        xa, xb = X(a), X(b)
        if xb - xa < 2:
            continue
        cv.create_rectangle(xa, row_top + 2, xb, row_top + band - 4,
                            outline="#1f6feb", fill="#12233b")
        cv.create_line(xa, row_top + band - 4, xa, y1, fill="#1f6feb")
        cv.create_line(xb, row_top + band - 4, xb, y1, fill="#1f6feb")
        txt = f"'{chr(v)}'" if 32 <= v < 127 else "??"
        if xb - xa >= 36:                              # 够宽：字符 + 十六进制两行
            cv.create_text((xa + xb) / 2, row_top + band * 0.38, text=txt,
                           fill="#e3b341", font=("Consolas", 15, "bold"))
            cv.create_text((xa + xb) / 2, row_top + band * 0.76, text=f"0x{v:02X}",
                           fill="#79c0ff", font=("Consolas", 9))
        elif xb - xa >= 15:                            # 窄：至少把字符本身写出来
            cv.create_text((xa + xb) / 2, row_top + band * 0.5, text=txt,
                           fill="#e3b341", font=("Consolas", 11, "bold"))
        # 再窄就只留框和分隔线：硬塞字反而糊成一团

    trg = ds.get("trigger")
    if trg is not None and 0 <= trg < len(samples):
        tx = X(trg)
        cv.create_line(tx, y0, tx, y1, fill="#f85149", dash=(6, 4), width=1)
        cv.create_text(min(tx + 6, W - 90), y0 - 10, text="触发点（起始位）",
                       fill="#ff7b72", anchor="w", font=("Microsoft YaHei", 9))

    # 横轴：给真实时间，单位按量级自适应（5 个点的窗口用 µs 会显示成 0，得退到 ns）
    ns = ds.get("sample_ns") or 0
    total_ns = ns * len(samples) if ns else 0

    def fmt(v_ns: float) -> str:
        if v_ns < 1000:
            return f"{v_ns:.0f} ns"
        if v_ns < 1_000_000:
            return f"{v_ns / 1000:.1f} µs"
        return f"{v_ns / 1e6:.2f} ms"

    if total_ns:
        cv.create_text(x0 - 6, y1 + 14, text="0", fill="#8b949e", anchor="e")
        cv.create_text((x0 + x1) / 2, y1 + 14, text=fmt(total_ns / 2), fill="#8b949e")
        cv.create_text(x1, y1 + 14, text=fmt(total_ns), fill="#8b949e", anchor="e")
        cv.create_text(x0 - 40, y1 + 14, text="时间", fill="#6e7681", anchor="e")
    else:
        cv.create_text(x0 - 6, y1 + 14, text="0", fill="#8b949e", anchor="e")
        cv.create_text(x1, y1 + 14, text=f"{len(samples)} 点", fill="#8b949e", anchor="e")


# ============================================================ 提交级 trace：寄存器写回热力图
# 板子上除了八通道波形，还有第二条通道：Core 把每条退休指令打成一条 132 位记录
# （pc / 指令码 / 写回 / 访存 / error），经 Trace MMIO 一窗一窗送出来。
# 波形回答"信号在第几拍变了"，trace 回答"CPU 到底执行了哪条指令、写回了哪个寄存器"。
# 热力图把后者摊平：横轴 = 记录序号，纵轴 = x0…x31，有方格 = 那条记录写回了这个寄存器。
# 因此它最直接的用途是回答"这一窗里哪几个寄存器在被反复搬数据"。
TRACE_CMD = 0xAA
TRACE_MAX_CHARS = 32
TRACE_PHASES = (0, 1)          # 0 = 只记处理过程，1 = 连串口轮询一起记
TRACE_WORDS = 5                # 一条 132 位记录要 5 个 32 位字
TRACE_REC_FIELDS = (
    # 字段名, 起始位, 位宽（与 rtl/trace_buffer.v、rtl/pipeline_cpu.v 的 trace_* 一一对应）
    ("pc", 0, 12), ("instr", 12, 32), ("rd_we", 44, 1), ("rd", 45, 5),
    ("rd_data", 50, 32), ("mem_we", 82, 1), ("mem_addr", 83, 12),
    ("mem_wstrb", 95, 4), ("mem_data", 99, 32), ("error", 131, 1),
)

_TRACE_RAW_RE = re.compile(
    r"TRACE RAW count=([0-9A-Fa-f]{1,8}) marks=([0-9A-Fa-f]{1,8}) status=([0-9A-Fa-f]{1,8})")
_TRACE_MARK_RE = re.compile(r"TRACE MARK n=([0-9A-Fa-f]{1,8})")
_TRACE_TEXT_RE = re.compile(
    r"TRACE TEXT hex=([0-9A-Fa-f]*) ascii=(.*?) xor=([0-9A-Fa-f]{1,8})"
    r" up=([0-9A-Fa-f]{1,8}) chars=([0-9A-Fa-f]{1,8})")


def build_trace_packet(n_chars: int, phase: int = 0) -> bytes:
    """0xAA 的 4 字节命令：[0]=cmd [1]=字符数 [2]=阶段 [3]=XOR([1..2])。"""
    if not 1 <= n_chars <= TRACE_MAX_CHARS:
        raise ValueError(f"字符数必须在 1..{TRACE_MAX_CHARS}，收到 {n_chars}")
    if phase not in TRACE_PHASES:
        raise ValueError(f"阶段只能是 {list(TRACE_PHASES)}，收到 {phase}")
    return bytes([TRACE_CMD, n_chars & 0xFF, phase & 0xFF,
                  (TRACE_CMD ^ (n_chars & 0xFF) ^ (phase & 0xFF)) & 0xFF])


def run_trace(port: str, text: str, phase: int = 0, timeout: float = 180.0, ser=None):
    """抓一枪提交级 trace，返回 (原始回包字节, 解析结果)。

    时序上和镜像模式同一条纪律：固件 Arm 生效后会先回 TRACE_ARMED，**必须等到它**
    再发字符串；提前发的话字符串比 arm 早到，窗口会从报文中间开始，
    而页面上照样"有一堆指令"——这类假通过最难查。
    """
    payload = text.encode("ascii")
    if not payload:
        raise ValueError("字符串不能为空")
    packet = build_trace_packet(len(payload), phase)
    own = ser is None
    if own:
        ser = serial.Serial(port, BAUD, bytesize=8, parity="N", stopbits=1, timeout=0.05)
    try:
        ser.reset_input_buffer()
        _sync(ser, min(timeout, 5.0))
        ser.write(packet)
        ser.flush()
        # Arm 应答只该等几秒：**交付位流 la85 里根本没有 0xAA 命令**，
        # 发过去它什么也不回。以前这里用 180 s 超时，用户看到的是"点了没反应、
        # 三分钟后报一句等不到 TRACE_ARMED"，既不知道该干什么也看不出原因。
        try:
            armed = _read_until(ser, b"TRACE_ARMED", 6.0)
        except TimeoutError as exc:
            raise RuntimeError(
                "板子没回 TRACE_ARMED —— 当前固件不是 trace 版（交付位流 la85 只有八通道采集，"
                "没有 0xAA 命令）。要采 CPU 数据流请先下载演示位流："
                "scripts\\program_board.ps1 -Config tr85 ；不接板子想看热力图，"
                "直接点『示例数据（不用板子）』。（%s）" % exc) from exc
        ser.write(payload)
        ser.flush()
        body = _read_until(ser, b"TRACE_DONE", timeout)
    finally:
        if own:
            ser.close()
    raw = armed + body
    return raw, parse_trace_capture(raw.decode("utf-8", errors="replace"))


def unpack_trace_record(words):
    """5 个 32 位字 -> 一条记录的字段字典（words[0] 是最低 32 位）。"""
    if len(words) != TRACE_WORDS:
        raise ValueError(f"一条记录必须正好 {TRACE_WORDS} 个字，收到 {len(words)} 个")
    raw = 0
    for i, w in enumerate(words):
        if not 0 <= w <= 0xFFFFFFFF:
            raise ValueError(f"第 {i} 个字超出 32 位: {w!r}")
        raw |= (w & 0xFFFFFFFF) << (32 * i)
    rec = {name: (raw >> low) & ((1 << width) - 1) for name, low, width in TRACE_REC_FIELDS}
    rec["raw"] = raw
    return rec


def pack_trace_record(rec) -> int:
    """字段字典 -> 132 位整数（自检造样本用，和 unpack 互为反操作）。"""
    raw = 0
    for name, low, width in TRACE_REC_FIELDS:
        raw |= (int(rec.get(name, 0)) & ((1 << width) - 1)) << low
    return raw


def record_line(rec) -> str:
    """一条记录写成回包里那一行 5 个十六进制字。"""
    raw = pack_trace_record(rec)
    return " ".join("%08X" % ((raw >> (32 * i)) & 0xFFFFFFFF) for i in range(TRACE_WORDS))


def parse_trace_capture(text: str) -> dict:
    """从串口回包里解析一枪 trace（头部 / 记录 / 打点 / 文本四块）。"""
    start = text.find("TRACE RAW count=")
    if start < 0:
        raise ValueError(f"回包里没有 TRACE RAW 头：{text[:120]!r}")
    body = text[start:]
    head = _TRACE_RAW_RE.search(body)
    if not head:
        raise ValueError(f"TRACE RAW 头格式不对：{body.splitlines()[0][:120]!r}")
    count, mark_count, status = (int(head.group(i), 16) for i in (1, 2, 3))

    lines = body.splitlines()
    records, pos = [], 1
    while len(records) < count:
        if pos >= len(lines):
            raise ValueError(f"记录不足：头部说 {count} 条，实际只解出 {len(records)} 条")
        line = lines[pos].strip()
        pos += 1
        if not line:
            continue
        words = line.split()
        if len(words) != TRACE_WORDS:
            raise ValueError(f"第 {len(records)} 条记录不是 {TRACE_WORDS} 个字：{line!r}")
        records.append(unpack_trace_record([int(w, 16) for w in words]))

    marks, mark_head = [], None
    for i in range(pos, len(lines)):
        m = _TRACE_MARK_RE.search(lines[i])
        if m:
            mark_head = int(m.group(1), 16)
            pos = i + 1
            break
    if mark_head is None:
        raise ValueError("找不到 TRACE MARK 头")
    if mark_head != mark_count:
        raise ValueError(f"MARK 头 {mark_head} 与 RAW 头的 marks={mark_count} 不一致")
    if mark_count:
        for token in lines[pos].split():
            v = int(token, 16)
            marks.append({"index": (v >> 8) & 0xFFFF, "value": v & 0xFF})

    m = _TRACE_TEXT_RE.search(body)
    if not m:
        raise ValueError("找不到 TRACE TEXT 行")
    blob = m.group(1)
    text_bytes = [int(blob[i:i + 8], 16) & 0xFF for i in range(0, len(blob), 8)]
    return {"count": count, "mark_count": mark_count, "status": status,
            "records": records, "marks": marks, "text": text_bytes,
            "ascii": m.group(2), "xor": int(m.group(3), 16),
            "up": int(m.group(4), 16), "chars": int(m.group(5), 16)}


def expected_phase0(text: str) -> dict:
    """阶段 0 固件对字节做的处理：小写转大写 + 逐字节 XOR + 小写个数。

    这是"固件到底做了什么"的**唯一**实现：界面预览、判据、网页标注都调它。
    """
    raw = [ord(ch) & 0xFF for ch in text]
    want = [c - 0x20 if 0x61 <= c <= 0x7A else c for c in raw]
    xor = 0
    for c in want:
        xor ^= c
    return {"raw": raw, "want": want, "xor": xor & 0xFFFFFFFF,
            "up": sum(1 for c in raw if 0x61 <= c <= 0x7A)}


def sent_text_from_marks(capture: dict) -> str:
    """「发送的字符串」= 打点值。

    **不能**用回包里的 `TRACE TEXT`：那是固件处理**之后**的结果（阶段 0 已把小写转成大写），
    拿它去比打点值会稳定判出 2 条假 FAIL（打点值对不上、大写字符计数期望 0）。
    固件是"先记打点、再大写化"，所以打点值才是当时真正送进 CPU 的原始字节。
    """
    return "".join(chr(m["value"]) for m in capture["marks"])


def judge_trace(capture: dict, sent: str = "", phase: int = 0, depth: int = DEPTH) -> list:
    """一枪 trace 的判据 -> [(名称, 是否通过, 说明)]；任何一条 FAIL 就说明这一枪不可信。

    与仓库里 `python/trace_view.py` 的判据同口径（少一条"pc 与固件镜像同源"：
    本文件的指令助记符直接由记录里的指令字反汇编，不依赖任何外部镜像，
    所以不存在"样本与镜像不同源"这类问题）。
    """
    out = []
    recs = capture["records"]
    sent = sent or sent_text_from_marks(capture)
    out.append(("记录条数自洽", capture["count"] == len(recs),
                "头部 count=%d，实际解出 %d 条" % (capture["count"], len(recs))))
    sent_bytes = [ord(ch) & 0xFF for ch in sent]
    out.append(("打点数等于字符数", capture["mark_count"] == len(sent_bytes),
                "marks=%d，发送字符数=%d" % (capture["mark_count"], len(sent_bytes))))
    mark_vals = [m["value"] for m in capture["marks"]]
    out.append(("打点值等于发送的字符", mark_vals == sent_bytes,
                "打点=%r 发送=%r" % (bytes(mark_vals), bytes(sent_bytes))))
    idxs = [m["index"] for m in capture["marks"]]
    out.append(("打点索引单调且不越界",
                idxs == sorted(idxs) and all(0 <= i <= capture["count"] for i in idxs),
                "索引=%r，count=%d" % (idxs, capture["count"])))
    exp = expected_phase0(sent)
    if phase == 0:
        out.append(("大写化结果", capture["text"] == exp["want"],
                    "得到 %r，期望 %r" % (bytes(capture["text"]), bytes(exp["want"]))))
        out.append(("大写字符计数", capture["up"] == exp["up"],
                    "up=%d，期望 %d" % (capture["up"], exp["up"])))
        out.append(("XOR 校验", capture["xor"] == exp["xor"],
                    "xor=0x%08X，期望 0x%08X" % (capture["xor"], exp["xor"])))
    else:
        out.append(("原样回读", capture["text"] == sent_bytes,
                    "得到 %r，期望 %r" % (bytes(capture["text"]), bytes(sent_bytes))))
        out.append(("大写字符计数应为 0", capture["up"] == 0, "up=%d" % capture["up"]))
    out.append(("字符数字段", capture["chars"] == len(sent_bytes),
                "chars=%d，期望 %d" % (capture["chars"], len(sent_bytes))))
    armed, recording = capture["status"] & 1, (capture["status"] >> 1) & 1
    done, overflow = (capture["status"] >> 2) & 1, (capture["status"] >> 3) & 1
    out.append(("收尾状态位", armed == 0 and recording == 0 and done == 1,
                "status=0x%X（armed=%d recording=%d done=%d overflow=%d）"
                % (capture["status"], armed, recording, done, overflow)))
    out.append(("未溢出", (overflow == 0) or (capture["count"] >= depth),
                "overflow=%d，count=%d，窗口容量=%d" % (overflow, capture["count"], depth)))
    bad_rd = [r["pc"] for r in recs if r["rd_we"] and r["rd"] == 0]
    out.append(("rd_we 不得指向 x0", not bad_rd, "越界样本 %d 条" % len(bad_rd)))
    bad_st = [r["pc"] for r in recs if r["mem_we"] and r["mem_wstrb"] == 0]
    out.append(("store 必须有字节使能", not bad_st, "越界样本 %d 条" % len(bad_st)))
    bad_pc = [r["pc"] for r in recs if r["pc"] & 3]
    out.append(("记录 pc 必须 4 字节对齐", not bad_pc, "越界样本 %d 条" % len(bad_pc)))
    return out


def judgements_pass(results) -> bool:
    return all(ok for _n, ok, _d in results)


# ---- RV32I 反汇编：只为了表格里显示指令助记符，以及"这条指令读了哪几个寄存器" ----
def _sext(v, bits):
    sign = 1 << (bits - 1)
    return (v & (sign - 1)) - (sign if v & sign else 0)


_BRANCH = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
_LOAD = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
_STORE = {0: "sb", 1: "sh", 2: "sw"}
_OPIMM = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}
_OP = {0: "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor", 5: "srl", 6: "or", 7: "and"}
_MULDIV = {0: "mul", 1: "mulh", 2: "mulhsu", 3: "mulhu", 4: "div", 5: "divu", 6: "rem", 7: "remu"}
_CSR = {1: "csrrw", 2: "csrrs", 3: "csrrc", 5: "csrrwi", 6: "csrrsi", 7: "csrrci"}


def decode_rv32i(word: int) -> dict:
    """把一条 32 位指令拆成 {mnemonic, text, reads, writes, rd, rs1, rs2, imm}。"""
    word &= 0xFFFFFFFF
    opcode, rd = word & 0x7F, (word >> 7) & 0x1F
    funct3, rs1, rs2, funct7 = (word >> 12) & 0x7, (word >> 15) & 0x1F, \
        (word >> 20) & 0x1F, (word >> 25) & 0x7F
    out = {"word": word, "rd": rd, "rs1": rs1, "rs2": rs2,
           "reads": [], "writes": [], "imm": 0}

    def done(mnem, text, reads=(), writes=()):
        out["mnemonic"], out["text"] = mnem, text
        out["reads"] = [r for r in reads if r]
        out["writes"] = [w for w in writes if w]
        return out

    if opcode == 0x37:
        out["imm"] = word & 0xFFFFF000
        return done("lui", f"lui x{rd},0x{word >> 12:x}", (), (rd,))
    if opcode == 0x17:
        out["imm"] = word & 0xFFFFF000
        return done("auipc", f"auipc x{rd},0x{word >> 12:x}", (), (rd,))
    if opcode == 0x6F:
        v = (((word >> 31) & 1) << 20) | (((word >> 12) & 0xFF) << 12) | \
            (((word >> 20) & 1) << 11) | (((word >> 21) & 0x3FF) << 1)
        out["imm"] = _sext(v, 21)
        return done("jal", f"jal x{rd},{out['imm']}", (), (rd,))
    if opcode == 0x67:
        if funct3 != 0:
            return done("illegal", f".word 0x{word:08x}")
        out["imm"] = _sext(word >> 20, 12)
        return done("jalr", f"jalr x{rd},{out['imm']}(x{rs1})", (rs1,), (rd,))
    if opcode == 0x63:
        m = _BRANCH.get(funct3)
        if m is None:
            return done("illegal", f".word 0x{word:08x}")
        v = (((word >> 31) & 1) << 12) | (((word >> 7) & 1) << 11) | \
            (((word >> 25) & 0x3F) << 5) | (((word >> 8) & 0xF) << 1)
        out["imm"] = _sext(v, 13)
        return done(m, f"{m} x{rs1},x{rs2},{out['imm']}", (rs1, rs2), ())
    if opcode == 0x03:
        m = _LOAD.get(funct3)
        if m is None:
            return done("illegal", f".word 0x{word:08x}")
        out["imm"] = _sext(word >> 20, 12)
        return done(m, f"{m} x{rd},{out['imm']}(x{rs1})", (rs1,), (rd,))
    if opcode == 0x23:
        m = _STORE.get(funct3)
        if m is None:
            return done("illegal", f".word 0x{word:08x}")
        out["imm"] = _sext(((word >> 25) << 5) | ((word >> 7) & 0x1F), 12)
        return done(m, f"{m} x{rs2},{out['imm']}(x{rs1})", (rs1, rs2), ())
    if opcode == 0x13:
        if funct3 in (1, 5):
            shamt = (word >> 20) & 0x1F
            out["imm"] = shamt
            m = "slli" if funct3 == 1 else ("srai" if funct7 == 0x20 else "srli")
            return done(m, f"{m} x{rd},x{rs1},{shamt}", (rs1,), (rd,))
        m = _OPIMM.get(funct3)
        if m is None:
            return done("illegal", f".word 0x{word:08x}")
        out["imm"] = _sext(word >> 20, 12)
        return done(m, f"{m} x{rd},x{rs1},{out['imm']}", (rs1,), (rd,))
    if opcode == 0x33:
        if funct7 == 0x01:
            m = _MULDIV.get(funct3)
            if m is None:
                return done("illegal", f".word 0x{word:08x}")
            return done(m, f"{m} x{rd},x{rs1},x{rs2}", (rs1, rs2), (rd,))
        if funct7 == 0x20 and funct3 in (0, 5):
            m = "sub" if funct3 == 0 else "sra"
            return done(m, f"{m} x{rd},x{rs1},x{rs2}", (rs1, rs2), (rd,))
        if funct7 == 0x00:
            m = _OP.get(funct3)
            if m is None:
                return done("illegal", f".word 0x{word:08x}")
            return done(m, f"{m} x{rd},x{rs1},x{rs2}", (rs1, rs2), (rd,))
        return done("illegal", f".word 0x{word:08x}")
    if opcode == 0x0F:
        return done("fence", "fence")
    if opcode == 0x73:
        if word == 0x00000073:
            return done("ecall", "ecall")
        if word == 0x00100073:
            return done("ebreak", "ebreak")
        if word == 0x30200073:
            return done("mret", "mret")
        if word == 0x10500073:
            return done("wfi", "wfi")
        m = _CSR.get(funct3)
        if m is not None:
            csr = word >> 20
            if funct3 >= 5:
                return done(m, f"{m} x{rd},0x{csr:03x},{rs1}", (), (rd,))
            return done(m, f"{m} x{rd},0x{csr:03x},x{rs1}", (rs1,), (rd,))
        return done("illegal", f".word 0x{word:08x}")
    return done("illegal", f".word 0x{word:08x}")


def build_trace_nodes(capture: dict) -> list:
    """给每条记录补上反汇编文本与"读到谁写的"依赖边（热力图与表格共用这份）。"""
    last_writer, nodes = {}, []
    for idx, rec in enumerate(capture["records"]):
        dec = decode_rv32i(rec["instr"])
        node = {"i": idx, "pc": rec["pc"] & ~3, "raw_pc": rec["pc"],
                "instr": rec["instr"], "asm": dec["text"], "mnemonic": dec["mnemonic"],
                "reads": list(dec["reads"]), "writes": list(dec["writes"]),
                "rd": rec["rd"], "rd_we": rec["rd_we"], "rd_data": rec["rd_data"],
                "mem_we": rec["mem_we"], "mem_addr": rec["mem_addr"],
                "mem_data": rec["mem_data"], "mem_wstrb": rec["mem_wstrb"],
                "error": rec["error"], "srcs": []}
        for r in dec["reads"]:
            if r == 0:
                continue
            edge = {"reg": r, "from": last_writer.get(r)}
            if edge not in node["srcs"]:
                node["srcs"].append(edge)
        if rec["rd_we"] and rec["rd"]:
            last_writer[rec["rd"]] = idx
        nodes.append(node)
    # 打点（每个字符到达时记下的记录序号）挂在它锚定的那条记录上
    by_index = {}
    for mk in capture["marks"]:
        by_index.setdefault(mk["index"], []).append(
            chr(mk["value"]) if 32 <= mk["value"] < 127 else ".")
    for node in nodes:
        node["marks"] = by_index.get(node["i"], [])
    return nodes


def heatmap_cells(nodes) -> list:
    """热力图的方格列表：[(记录序号, 寄存器号), …]。x0 永不写回，不产生方格。"""
    return [(n["i"], n["rd"]) for n in nodes if n["rd_we"] and n["rd"]]


def _hsl_hex(h: float, s: float, l: float) -> str:
    """HSL -> #rrggbb。和网页版用同一套 (序号*47)%360 色相，两端看起来是同一张图。"""
    h = (h % 360) / 360.0

    def f(p, q, t):
        t = t + 1 if t < 0 else (t - 1 if t > 1 else t)
        if t < 1 / 6:
            return p + (q - p) * 6 * t
        if t < 0.5:
            return q
        if t < 2 / 3:
            return p + (q - p) * (2 / 3 - t) * 6
        return p

    if s == 0:
        r = g = b = l
    else:
        q = l * (1 + s) if l < 0.5 else l + s - l * s
        p = 2 * l - q
        r, g, b = f(p, q, h + 1 / 3), f(p, q, h), f(p, q, h - 1 / 3)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def reg_color(reg: int) -> str:
    return _hsl_hex((reg * 47) % 360, 0.72, 0.62)


HEAT_BG, HEAT_GRID, HEAT_LABEL = "#0b111d", "#141d2c", "#6d80a0"
HEAT_WATCH, HEAT_CURSOR, HEAT_TEXT = "#242b3a", "#ffd479", "#c9d1d9"


def heatmap_layout(width: int, height: int, n_records: int,
                   left: int = 44, top: int = 18, bottom: int = 10) -> dict:
    """热力图的坐标换算。界面与网页版共用同一组比例，两边格子位置一致。"""
    rows = 32
    n = max(1, n_records)
    return {"left": left, "top": top, "bottom": bottom, "rows": rows,
            "row_h": (height - top - bottom) / rows,
            "bw": (width - left) / n, "n": n, "width": width, "height": height}


def draw_reg_heatmap(cv, nodes, sel=None, width=None, height=None) -> dict:
    """在 Canvas 上画寄存器写回热力图，返回画了多少个方格等统计。

    sel 是当前选中的记录序号：它的读寄存器行会被高亮，并画一条竖游标。
    """
    cv.delete("all")
    w = width or max(cv.winfo_width(), 400)
    h = height or max(cv.winfo_height(), 260)
    lay = heatmap_layout(w, h, len(nodes))
    left, top, row_h, bw = lay["left"], lay["top"], lay["row_h"], lay["bw"]
    cv.create_rectangle(0, 0, w, h, fill=HEAT_BG, outline="")
    if not nodes:
        cv.create_text(w / 2, h / 2, text="还没有数据：点『采集』或『示例数据』",
                       fill=HEAT_LABEL)
        return {"cells": 0, "records": 0, "layout": lay}

    # 行标签每 4 行一个，32 个标签会糊成一片
    for r in range(0, 32, 4):
        y = top + r * row_h
        cv.create_text(left - 6, y + row_h * 0.8, text=f"x{r}", fill=HEAT_LABEL, anchor="e")
        cv.create_line(left, y, w, y, fill=HEAT_GRID)
    # 选中指令读的寄存器：整行淡黄，回答"这条指令的数据是从哪几个寄存器来的"
    if sel is not None and 0 <= sel < len(nodes):
        for r in nodes[sel]["reads"]:
            y = top + r * row_h
            cv.create_rectangle(left, y, w, y + row_h, fill=HEAT_WATCH, outline="")
    # 写回方格
    cells = heatmap_cells(nodes)
    for i, reg in cells:
        x = left + i * bw
        y = top + reg * row_h
        cv.create_rectangle(x, y + 0.5, x + max(1.0, bw), y + max(1.0, row_h - 1),
                            fill=reg_color(reg), outline="")
    if sel is not None and 0 <= sel < len(nodes):
        x = left + (sel + 0.5) * bw
        cv.create_line(x, top, x, h - lay["bottom"], fill=HEAT_CURSOR)
    return {"cells": len(cells), "records": len(nodes), "layout": lay}


TRACE_HTML = """<!doctype html><meta charset="utf-8"><title>%(title)s</title>
<style>
 body{margin:0;background:#0d1117;color:#c9d1d9;font:13px/1.6 "Segoe UI",sans-serif}
 .wrap{padding:14px 18px}.h{font-size:15px;font-weight:600;color:#e6edf3}
 .sub{color:#8b949e;margin:6px 0 12px}
 #heat{width:100%%;height:420px;display:block;background:#0b111d;border:1px solid #30363d;
       border-radius:6px}
 table{border-collapse:collapse;width:100%%;font:12px Consolas,monospace}
 th,td{border-bottom:1px solid #21262d;padding:2px 6px;text-align:left}
 th{color:#8b949e;font-weight:600;position:sticky;top:0;background:#0d1117}
 tr.sel{background:rgba(255,212,121,.12)}
 .num{color:#8b949e}#tbl{max-height:40vh;overflow:auto;margin-top:12px}
</style>
<div class="wrap">
<div class="h">CPU 数据流 · 寄存器写回热力图</div>
<div class="sub">%(sub)s</div>
<canvas id="heat"></canvas>
<div id="tbl"><table><thead><tr><th>#</th><th>pc</th><th>指令</th><th>写回</th><th>访存</th></tr></thead>
<tbody>%(rows)s</tbody></table></div>
</div>
<script>
const N = %(nodes)s;
const CV = document.getElementById('heat'), CTX = CV.getContext('2d');
function hue(r){ return 'hsl(' + ((r * 47) %% 360) + ', 72%%, 62%%)'; }
let sel = %(sel)d;
function draw(){
  const w = CV.width = CV.clientWidth, h = CV.height = CV.clientHeight;
  CTX.clearRect(0,0,w,h); CTX.fillStyle='#0b111d'; CTX.fillRect(0,0,w,h);
  const left=44, top=18, bottom=10, rows=32, rowH=(h-top-bottom)/rows;
  const n = Math.max(1, N.length), bw = (w-left)/n;
  CTX.font='9px Consolas, monospace'; CTX.textAlign='right'; CTX.fillStyle='#6d80a0';
  for (let r=0; r<rows; r+=4){
    CTX.fillText('x'+r, left-6, top+r*rowH+rowH*0.8);
    CTX.strokeStyle='#141d2c'; CTX.beginPath();
    CTX.moveTo(left, top+r*rowH); CTX.lineTo(w, top+r*rowH); CTX.stroke();
  }
  if (sel >= 0 && N[sel]){
    for (const r of N[sel].reads){
      CTX.fillStyle='#242b3a';
      CTX.fillRect(left, top+r*rowH, w-left, rowH);
    }
  }
  for (const nd of N){
    if (!nd.rd_we || !nd.rd) continue;
    CTX.fillStyle = hue(nd.rd);
    CTX.fillRect(left+nd.i*bw, top+nd.rd*rowH+0.5, Math.max(1,bw), Math.max(1,rowH-1));
  }
  if (sel >= 0){
    const sx = left+(sel+0.5)*bw;
    CTX.strokeStyle='#ffd479'; CTX.beginPath();
    CTX.moveTo(sx, top); CTX.lineTo(sx, h-bottom); CTX.stroke();
  }
}
function pick(i){
  sel = i;
  document.querySelectorAll('tr.sel').forEach(e => e.classList.remove('sel'));
  const row = document.getElementById('r'+i); if (row) row.classList.add('sel');
  draw();
}
draw();
window.addEventListener('resize', draw);
</script>
"""


def trace_html(nodes, capture, sent: str, sel: int = -1, title: str = "寄存器写回热力图") -> str:
    """把一枪 trace 写成自包含的 HTML 页（不需要 Python、不需要板子就能看）。"""
    rows = []
    for n in nodes:
        cls = ' class="sel"' if n["i"] == sel else ""
        wr = "x%d ← 0x%08X" % (n["rd"], n["rd_data"]) if (n["rd_we"] and n["rd"]) else "—"
        mem = "0x%03X ← 0x%08X" % (n["mem_addr"], n["mem_data"]) if n["mem_we"] else "—"
        rows.append('<tr id="r%d"%s><td class="num">%d</td><td class="num">0x%03X</td>'
                    '<td>%s</td><td>%s</td><td>%s</td></tr>'
                    % (n["i"], cls, n["i"], n["pc"], n["asm"], wr, mem))
    sub = ("发送 %r · 记录 %d 条 · 打点 %d 个 · 写回方格 %d 个 · 状态 0x%X"
           % (sent, capture["count"], capture["mark_count"],
              len(heatmap_cells(nodes)), capture["status"]))
    return TRACE_HTML % {"title": title, "sub": sub, "rows": "\n".join(rows),
                         "nodes": json.dumps(nodes, ensure_ascii=False), "sel": sel}


def write_trace_html(path: Path, nodes, capture, sent: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(trace_html(nodes, capture, sent), encoding="utf-8")
    return path


# 一枪真实记录的样本（2026-10-24 板上 tr85 位流跑 "HELLO,RV" 的前 32 条），
# 用途是让界面在没有板子时也能把热力图显示出来，不是编造的数据。
SAMPLE_TRACE = """TRACE_ARMED
TRACE RAW count=00000064 marks=00000008 status=00000004
7A023DCC 0000020E 90040000 0000000F 00000000
90D93DD0 00037000 00000000 00000000 00000000
78613DD4 88B1922C 00004000 00000000 00000000
00593DD8 00657019 00000000 00000000 00000000
0006FDDC 00000014 00000000 00000000 00000000
40713DF0 4CE1D000 00000000 00000000 00000000
44783DF4 01A1F000 00000000 00000000 00000000
62023DF8 0000000F 91640000 00000347 00000000
78693DFC 001DBF9F 00000000 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
78793E04 0121FFE0 00000000 00000000 00000000
90913E08 00065001 00000000 00000000 00000000
FF06FE0C 00000FD5 00000000 00000000 00000000
70023DE0 0000000F 99C40000 00000240 00000000
DCDB3DE4 0123700F 00000000 00000000 00000000
40413DE8 4CE51001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
40713DF0 4CE5D000 00000000 00000000 00000000
44783DF4 0195F000 00000000 00000000 00000000
62023DF8 0000000F 91640000 0000032F 00000000
78693DFC 0011BF9F 00000000 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
78793E04 0115FFE0 00000000 00000000 00000000
90913E08 000A5001 00000000 00000000 00000000
FF06FE0C 00000FD5 00000000 00000000 00000000
70023DE0 0000000F 19CC0000 00022801 00000000
DCDB3DE4 0037700F 00000000 00000000 00000000
40413DE8 4CE91001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
40713DF0 4CE9D000 00000000 00000000 00000000
44783DF4 01B1F000 00000000 00000000 00000000
62023DF8 0000000F 91640000 00000367 00000000
78693DFC 002DBF9F 00000000 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
78793E04 0131FFE0 00000000 00000000 00000000
90913E08 000E5001 00000000 00000000 00000000
FF06FE0C 00000FD5 00000000 00000000 00000000
70023DE0 0000000F 19D40000 02600002 00000000
DCDB3DE4 0107700F 00000000 00000000 00000000
40413DE8 4CED1001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
40713DF0 4CEDD000 00000000 00000000 00000000
44783DF4 01B1F000 00000000 00000000 00000000
62023DF8 0000000F 91640000 00000367 00000000
78693DFC 002DBF9F 00000000 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
78793E04 0131FFE0 00000000 00000000 00000000
90913E08 00125001 00000000 00000000 00000000
FF06FE0C 00000FD5 00000000 00000000 00000000
70023DE0 0000000F 19DC0000 60000004 00000002
DCDB3DE4 0037700F 00000000 00000000 00000000
40413DE8 4CF11001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
40713DF0 4CF1D000 00000000 00000000 00000000
44783DF4 01BDF000 00000000 00000000 00000000
62023DF8 0000000F 91640000 0000037F 00000000
78693DFC 0039BF9F 00000000 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
78793E04 013DFFE0 00000000 00000000 00000000
90913E08 00165001 00000000 00000000 00000000
FF06FE0C 00000FD5 00000000 00000000 00000000
70023DE0 0000000F 99E40000 00000278 00000000
DCDB3DE4 010B700F 00000000 00000000 00000000
40413DE8 4CF51001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
40713DF0 4CF5D000 00000000 00000000 00000000
44783DF4 00B1F000 00000000 00000000 00000000
62023DF8 0000000F 91640000 00000167 00000000
78693DFC FF2DBF9F 0003FFFF 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
70023DE0 0000000F 19EC0000 00016001 00000000
DCDB3DE4 01BB700F 00000000 00000000 00000000
40413DE8 4CF91001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
40713DF0 4CF9D000 00000000 00000000 00000000
44783DF4 01C9F000 00000000 00000000 00000000
62023DF8 0000000F 91640000 00000397 00000000
78693DFC 0045BF9F 00000000 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
78793E04 0149FFE0 00000000 00000000 00000000
90913E08 001A5001 00000000 00000000 00000000
FF06FE0C 00000FD5 00000000 00000000 00000000
70023DE0 0000000F 19F40000 02900002 00000000
DCDB3DE4 00F3700F 00000000 00000000 00000000
40413DE8 4CFD1001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
40713DF0 4CFDD000 00000000 00000000 00000000
44783DF4 01D9F000 00000000 00000000 00000000
62023DF8 0000000F 91640000 000003B7 00000000
78693DFC 0055BF9F 00000000 00000000 00000000
5E0E3E00 00000FED 00000000 00000000 00000000
78793E04 0159FFE0 00000000 00000000 00000000
90913E08 001E5001 00000000 00000000 00000000
FF06FE0C 00000FD5 00000000 00000000 00000000
70023DE0 0000000F 19FC0000 B0000004 00000002
DCDB3DE4 01AB700F 00000000 00000000 00000000
40413DE8 4D011001 00000000 00000000 00000000
40263DEC 00000033 00000000 00000000 00000000
027B7E10 8001F100 00004000 00000000 00000000
00713E14 0009D002 00000000 00000000 00000000
TRACE MARK n=00000008
00000768 00001365 00001F6C 00002B6C 0000376F 0000432C 00004C72 00005876
TRACE TEXT hex=00000048000000450000004C0000004C0000004F0000002C0000005200000056 ascii=HELLO,RV xor=0000006A up=00000007 chars=00000008
TRACE_DONE
LA_READY
"""


def sample_capture() -> dict:
    """解析内置样本，返回 capture（界面『示例数据』与自检都用它）。"""
    return parse_trace_capture(SAMPLE_TRACE)


# ============================================================ 界面外观（只改长相，不改行为）
# 为什么单独做一层：原来用 ttk 默认外观（Windows 灰按钮）+ 深色画布，投影时层次全糊，
# 深色面板和浅灰控件互相打架。这里借 GitHub Primer 的浅色令牌做"外壳"、
# GitHub Dark 的令牌做三块深色"代码面"（波形 / 读数 / 日志），语义色沿用 GitHub
# 的绿（主操作）、蓝（选中/焦点）、红（错误）。
#
# 三条纪律：
#   1. 只调用 ttk.Style 与控件构造参数，**不碰**任何一个 command / variable / 状态机；
#   2. 控件类型不许变（TRadiobutton / TCombobox / Treeview 都是测试与脚本依赖的锚点）；
#   3. 必须切到 clam 主题：Windows 原生主题会**忽略** ttk 的 background/bordercolor，
#      不切的话下面这些颜色一个都不生效（这是最容易白改一遍的坑）。
THEME = {
    "bg": "#f6f8fa", "card": "#ffffff", "border": "#d0d7de", "text": "#1f2328",
    "muted": "#656d76", "subtle": "#8c959f", "accent": "#0969da",
    "primary": "#1f883d", "primary_hover": "#1a7f37", "primary_disabled": "#94d3a2",
    "danger": "#cf222e", "hover": "#f3f4f6", "pressed": "#eaeef2",
    "select": "#ddf4ff", "plot_bg": "#0d1117", "plot_text": "#c9d1d9",
    "plot_border": "#30363d", "plot_select": "#264f78",
}
UI_FONT_CANDIDATES = ("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI",
                      "Noto Sans CJK SC", "Arial")
MONO_FONT_CANDIDATES = ("Cascadia Mono", "Consolas", "JetBrains Mono",
                        "DejaVu Sans Mono", "Courier New")


def _pick_family(root, tkfont, candidates) -> str:
    """挑一个本机真有的字体族（不存在的族会被 Tk 静默替换，字号观感会飘）。"""
    try:
        available = set(tkfont.families(root))
    except Exception:                       # 取不到列表就按第一个硬上
        return candidates[0]
    for name in candidates:
        if name in available:
            return name
    return candidates[0]


def _style_set(style, name: str, opts: dict) -> None:
    """逐项塞样式选项：clam 各元素支持的选项不完全一致，不支持的项跳过而不是让窗口起不来。"""
    try:
        style.configure(name, **opts)
        return
    except Exception:
        pass
    for key, value in opts.items():
        try:
            style.configure(name, **{key: value})
        except Exception:
            pass


def _style_map(style, name: str, opts: dict) -> None:
    for key, value in opts.items():
        try:
            style.map(name, **{key: value})
        except Exception:
            pass


def install_theme(root, tk, ttk, tkfont) -> dict:
    """把 ttk 换成 clam 并套上 GitHub 风格，返回字体与色板给调用方复用。"""
    T = THEME
    ui = _pick_family(root, tkfont, UI_FONT_CANDIDATES)
    mono = _pick_family(root, tkfont, MONO_FONT_CANDIDATES)
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except Exception:                       # 理论上 clam 永远在，真没有也不许崩
        pass
    root.configure(background=T["bg"])

    # 默认值＝"卡片内"：白底深字。最外层 1px 边框统一由 Hair.TFrame 画。
    _style_set(style, ".", {"background": T["card"], "foreground": T["text"], "font": (ui, 10)})
    _style_set(style, "TFrame", {"background": T["card"], "borderwidth": 0})
    _style_set(style, "Hair.TFrame", {"background": T["border"], "borderwidth": 0})
    _style_set(style, "TLabel", {"background": T["card"], "foreground": T["text"]})
    _style_set(style, "Muted.TLabel", {"background": T["card"], "foreground": T["muted"],
                                       "font": (ui, 9)})
    _style_set(style, "Status.TLabel", {"background": T["card"], "foreground": T["text"],
                                        "font": (ui, 10)})
    _style_set(style, "Section.TLabel", {"background": T["card"], "foreground": T["text"],
                                         "font": (ui, 10, "bold")})
    _style_set(style, "TLabelframe", {"background": T["card"], "bordercolor": T["border"],
                                      "lightcolor": T["border"], "darkcolor": T["border"],
                                      "relief": "solid", "borderwidth": 1})
    _style_set(style, "TLabelframe.Label", {"background": T["card"], "foreground": T["text"],
                                            "font": (ui, 10, "bold")})

    # 次要按钮：白底 + 1px 边框（GitHub 的 default button）
    _style_set(style, "TButton", {"background": T["bg"], "foreground": T["text"],
                                  "bordercolor": T["border"], "lightcolor": T["bg"],
                                  "darkcolor": T["bg"], "relief": "solid", "borderwidth": 1,
                                  "padding": (12, 5), "font": (ui, 10)})
    _style_map(style, "TButton", {
        "background": [("disabled", T["bg"]), ("pressed", T["pressed"]), ("active", T["hover"])],
        "foreground": [("disabled", T["subtle"])],
        "bordercolor": [("active", "#bcbec4"), ("focus", T["accent"])],
    })
    # 主操作：GitHub 的绿色 primary button
    _style_set(style, "Primary.TButton", {"background": T["primary"], "foreground": "#ffffff",
                                          "bordercolor": T["primary_hover"],
                                          "lightcolor": T["primary"], "darkcolor": T["primary"],
                                          "relief": "solid", "borderwidth": 1,
                                          "padding": (12, 5), "font": (ui, 10, "bold")})
    _style_map(style, "Primary.TButton", {
        "background": [("disabled", T["primary_disabled"]), ("pressed", T["primary_hover"]),
                       ("active", "#1c8139")],
        "foreground": [("disabled", "#ffffff")],
        "bordercolor": [("disabled", T["primary_disabled"])],
    })

    _style_set(style, "TEntry", {"fieldbackground": T["card"], "foreground": T["text"],
                                 "bordercolor": T["border"], "lightcolor": T["border"],
                                 "darkcolor": T["border"], "insertcolor": T["text"],
                                 "padding": (8, 5)})
    _style_map(style, "TEntry", {
        "bordercolor": [("focus", T["accent"])],
        "fieldbackground": [("disabled", T["bg"])],
        "foreground": [("disabled", T["subtle"])],
    })
    _style_set(style, "TCombobox", {"fieldbackground": T["card"], "background": T["bg"],
                                    "foreground": T["text"], "bordercolor": T["border"],
                                    "lightcolor": T["border"], "darkcolor": T["border"],
                                    "arrowcolor": T["muted"], "padding": (8, 5)})
    _style_map(style, "TCombobox", {
        "fieldbackground": [("readonly", T["card"]), ("disabled", T["bg"])],
        "foreground": [("disabled", T["subtle"]), ("readonly", T["text"])],
        "bordercolor": [("focus", T["accent"])],
        "arrowcolor": [("disabled", T["subtle"])],
    })

    _style_set(style, "TRadiobutton", {"background": T["card"], "foreground": T["text"],
                                       "focuscolor": T["accent"], "padding": (1, 2),
                                       "font": (ui, 10)})
    _style_map(style, "TRadiobutton", {
        "background": [("active", T["card"])],
        "indicatorcolor": [("selected", T["accent"]), ("!selected", T["card"])],
        "foreground": [("disabled", T["subtle"])],
    })
    _style_set(style, "TCheckbutton", {"background": T["card"], "foreground": T["text"],
                                       "focuscolor": T["accent"], "padding": (2, 3),
                                       "font": (ui, 10)})
    _style_map(style, "TCheckbutton", {
        "background": [("active", T["card"])],
        "indicatorcolor": [("selected", T["accent"]), ("!selected", T["card"])],
        "foreground": [("disabled", T["subtle"])],
    })

    # 读数表：表头浅灰、行高放宽、选中用 GitHub 的淡蓝高亮
    _style_set(style, "Treeview", {"background": T["card"], "fieldbackground": T["card"],
                                   "foreground": T["text"], "bordercolor": T["border"],
                                   "rowheight": 24, "font": (mono, 10)})
    _style_set(style, "Treeview.Heading", {"background": T["bg"], "foreground": T["muted"],
                                           "relief": "flat", "bordercolor": T["border"],
                                           "font": (ui, 9)})
    _style_map(style, "Treeview", {
        "background": [("selected", T["select"])],
        "foreground": [("selected", T["text"])],
    })
    _style_map(style, "Treeview.Heading", {"background": [("active", T["hover"])]})

    # 下拉列表是 tk Listbox，只能通过 option database 上色
    for pattern, value in (("*TCombobox*Listbox.background", T["card"]),
                           ("*TCombobox*Listbox.foreground", T["text"]),
                           ("*TCombobox*Listbox.selectBackground", T["select"]),
                           ("*TCombobox*Listbox.selectForeground", T["text"])):
        try:
            root.option_add(pattern, value)
        except Exception:
            pass
    return {"ui": ui, "mono": mono, "tok": T, "style": style}


class TraceWindow:
    """提交级数据流窗口：左边逐条指令表，右边寄存器写回热力图。

    单独开一个 Toplevel，而不是往主窗口再塞第三块面板：主窗口横向已经被波形和
    读数占满，热力图挤进去只能剩一窄条；而它的价值恰恰在"横轴放得下几十上百条记录、
    纵轴 32 个寄存器都能点到"。两块放在一个窗口里，点表格行就能在图上定位。
    """

    def __init__(self, parent, port_var, ui_font, mono_font, T, log_line=None,
                 stop_live=None):
        import tkinter as tk
        from tkinter import filedialog, ttk

        self.tk, self.parent, self.port_var = tk, parent, port_var
        self.stop_live = stop_live          # 打开串口前先让主窗口停止连续采集
        self.ui_font, self.mono, self.T, self.log_line = ui_font, mono_font, T, log_line
        self.nodes, self.capture, self.sent, self.sel = [], None, "", -1
        self.source, self.phase = "", 0
        self.results: queue.Queue = queue.Queue()
        self.busy = False
        self._syncing = False      # 正在由代码改选中状态，忽略随之而来的选择事件
        self._resize_job = None

        self.win = tk.Toplevel(parent)
        self.win.title("CPU 数据流 · 寄存器写回热力图")
        self.win.geometry("1260x780")
        self.win.minsize(980, 640)

        # ---- 顶部：和主窗口同一套串口与字符串，不用来回切 ----
        top = ttk.Frame(self.win, padding=(14, 10, 14, 6))
        top.pack(fill="x")
        ttk.Label(top, text="板载串口", style="Muted.TLabel").pack(side="left")
        self.port_label = ttk.Label(top, textvariable=port_var, style="Status.TLabel")
        self.port_label.pack(side="left", padx=(6, 14))
        ttk.Label(top, text="发送给 CPU 的字符串", style="Muted.TLabel").pack(side="left")
        self.text_var = tk.StringVar(value="hello,rv")
        ttk.Entry(top, textvariable=self.text_var, width=18).pack(side="left", padx=(6, 12))
        ttk.Label(top, text="阶段", style="Muted.TLabel").pack(side="left")
        self.phase_var = tk.StringVar(value="0 · 只记处理过程")
        ttk.Combobox(top, textvariable=self.phase_var, width=20, state="readonly",
                     values=("0 · 只记处理过程", "1 · 连串口轮询一起记")).pack(side="left",
                                                                          padx=(6, 12))
        self.export_btn = ttk.Button(top, text="导出 HTML", command=self._export)
        self.export_btn.pack(side="right")
        self.sample_btn = ttk.Button(top, text="示例数据（不用板子）", command=self.load_sample)
        self.sample_btn.pack(side="right", padx=(0, 8))
        self.run_btn = ttk.Button(top, text="▶ 采集", style="Primary.TButton",
                                  command=self._run)
        self.run_btn.pack(side="right", padx=(0, 8))

        ttk.Frame(self.win, style="Hair.TFrame", height=1).pack(fill="x")
        self.status_var = tk.StringVar(
            value="先点『示例数据』看一枪真实记录；接好板子后点『采集』抓当前一枪。")
        ttk.Label(self.win, textvariable=self.status_var, style="Status.TLabel",
                  padding=(14, 5)).pack(fill="x")
        ttk.Frame(self.win, style="Hair.TFrame", height=1).pack(fill="x")

        # ---- 中部：左表格 + 右热力图 ----
        mid = ttk.Frame(self.win, padding=(14, 10, 14, 12))
        mid.pack(fill="both", expand=True)
        mid.columnconfigure(0, weight=0)
        mid.columnconfigure(1, weight=1)
        mid.rowconfigure(0, weight=1)

        left = ttk.Frame(mid)
        left.grid(row=0, column=0, sticky="ns", padx=(0, 12))
        ttk.Label(left, text="逐条指令（点一行，右边定位到它）",
                  style="Muted.TLabel").pack(anchor="w", pady=(0, 4))
        # 表格用 Treeview：主窗口的表格也是它，两者观感一致，脚本也好驱动
        cols = ("i", "pc", "asm", "wr", "mem")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", height=22)
        for c, txt, w in (("i", "#", 46), ("pc", "pc", 58), ("asm", "指令", 190),
                          ("wr", "写回", 118), ("mem", "访存", 118)):
            self.tree.heading(c, text=txt)
            self.tree.column(c, width=w, anchor="w", stretch=False)
        self.tree.tag_configure("sel", background=T["select"])
        sb = ttk.Scrollbar(left, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="y")
        sb.pack(side="left", fill="y")
        self.tree.bind("<<TreeviewSelect>>", lambda _e: self._on_pick())

        right = ttk.Frame(mid)
        right.grid(row=0, column=1, sticky="nsew")
        head = ttk.Frame(right)
        head.pack(fill="x")
        ttk.Label(head, text="寄存器写回热力图",
                  font=(ui_font, 13, "bold")).pack(side="left")
        ttk.Label(head, text="　横轴 = 记录序号　纵轴 = x0…x31　"
                             "方格 = 这条记录写回了该寄存器　黄行 = 选中指令读的寄存器",
                  style="Muted.TLabel").pack(side="left")
        self.canvas = tk.Canvas(right, background=HEAT_BG, height=420,
                                highlightthickness=1, highlightbackground=T["plot_border"])
        self.canvas.pack(fill="both", expand=True, pady=(6, 0))
        self.canvas.bind("<Configure>", self._on_resize)
        self.canvas.bind("<Button-1>", self._on_click)

        # ---- 底部：判据（这一枪到底可不可信）----
        # 没有这块，窗口只会说"记录 32 条"，看的人无从判断数据对不对。
        # 判据必须和画图共用同一份解析结果（都来自 parse_trace_capture），不另写第二套。
        box = ttk.LabelFrame(self.win, text=" 判据（这一枪可不可信） ", padding=(10, 6))
        box.pack(fill="x", padx=14, pady=(0, 10))
        self.verdict_var = tk.StringVar(value="还没有数据：点『示例数据』或『▶ 采集』")
        ttk.Label(box, textvariable=self.verdict_var).pack(anchor="w")
        self.judge_text = tk.Text(box, height=7, wrap="word", font=(mono_font, 9),
                                  background=HEAT_BG, foreground=T["plot_text"],
                                  highlightthickness=0, borderwidth=0)
        self.judge_text.pack(fill="x", pady=(4, 0))
        self.judge_text.configure(state="disabled")

        self.win.bind("<Escape>", lambda _e: self.win.destroy())
        self._draw()

    # ---- 画图 ----
    def _draw(self):
        stat = draw_reg_heatmap(self.canvas, self.nodes, self.sel)
        if self.nodes:
            self.status_var.set(
                f"{self.source or '采集'} · 发送 {self.sent!r} · 记录 {stat['records']} 条 · "
                f"写回方格 {stat['cells']} 个 · 打点 {self.capture['mark_count']} 个 · "
                f"状态 0x{self.capture['status']:X}"
                + (f" · 选中第 {self.sel} 条：{self.nodes[self.sel]['asm']}"
                   if 0 <= self.sel < len(self.nodes) else ""))
        return stat

    def _show_judges(self, results, source):
        """判据面板：把这一枪的每条判据摊开，并通过/失败数写在标题行。"""
        ok = sum(1 for _n, good, _d in results if good)
        self.verdict_var.set(
            "%s · 判据 %d/%d %s" % (source, ok, len(results),
                                    "全部通过" if ok == len(results) else "有失败项（数据不可信）"))
        self.judge_text.configure(state="normal")
        self.judge_text.delete("1.0", "end")
        for name, good, detail in results:
            self.judge_text.insert("end", "%s %s — %s\n"
                                   % ("PASS" if good else "FAIL", name, detail))
        self.judge_text.configure(state="disabled")

    def _on_resize(self, _event=None):
        # 拖动窗口会连续触发 Configure；攒 120ms 再重画一次，避免每次拖帧都重画几百个方格
        if self._resize_job is not None:
            self.win.after_cancel(self._resize_job)
        self._resize_job = self.win.after(120, self._draw)

    def _on_click(self, event):
        if not self.nodes:
            return
        lay = heatmap_layout(max(self.canvas.winfo_width(), 400),
                             max(self.canvas.winfo_height(), 260), len(self.nodes))
        if event.x < lay["left"]:
            return
        col = int((event.x - lay["left"]) / lay["bw"])
        if 0 <= col < len(self.nodes):
            self._select(col)

    def _on_pick(self):
        sel = self.tree.selection()
        if not sel:
            return
        i = int(sel[0])
        if i == self.sel:
            # 关键：已经是这一行了。再 selection_set 会再发一次 <<TreeviewSelect>>，
            # 而 Tk 是排队投递的，"置标志"挡不住（回调跑到时标志早已复位）——只能靠幂等。
            return
        self._select(i)

    def _select(self, i):
        if not 0 <= i < len(self.nodes):
            return
        self.sel = i
        cur = self.tree.selection()
        if not (len(cur) == 1 and cur[0] == str(i)):
            self._syncing = True
            try:
                self.tree.selection_set(str(i))
            finally:
                self._syncing = False
        self.tree.see(str(i))
        self._draw()

    # ---- 数据 ----
    def load(self, raw, capture, sent, note="", phase=0, source="实时采集（本机板子）"):
        """把一枪解析结果装进界面（raw 可为 None，示例数据就没有原始回包）。

        `sent` 一律以**打点值**为准（见 `sent_text_from_marks`）：示例数据也走同一条路，
        否则界面会拿大写化之后的回包文本去判据，白报两条 FAIL。
        """
        self.source, self.phase = source, phase
        self.capture = capture
        self.sent = sent_text_from_marks(capture) or sent
        self.nodes = build_trace_nodes(capture)
        self.sel = 0 if self.nodes else -1
        self.tree.delete(*self.tree.get_children())
        for n in self.nodes:
            wr = "x%d ← 0x%08X" % (n["rd"], n["rd_data"]) if (n["rd_we"] and n["rd"]) else "—"
            mem = "0x%03X ← 0x%08X" % (n["mem_addr"], n["mem_data"]) if n["mem_we"] else "—"
            self.tree.insert("", "end", iid=str(n["i"]),
                             values=(n["i"], "0x%03X" % n["pc"], n["asm"], wr, mem))
        if self.nodes:
            self._syncing = True
            try:
                self.tree.selection_set("0")
            finally:
                self._syncing = False
        self._show_judges(judge_trace(capture, self.sent, phase), source)
        stat = self._draw()
        if note and self.log_line:
            self.log_line(note)
        if raw:
            OUT.mkdir(parents=True, exist_ok=True)
            path = OUT / "trace.log"
            path.write_bytes(raw)
            if self.log_line:
                self.log_line(f"trace 原始回包已存：{path}")
        return stat

    def load_sample(self):
        """内置一枪真实记录：没有板子也能立刻看到热力图。"""
        try:
            cap = sample_capture()
        except Exception as exc:
            self.status_var.set(f"示例数据解析失败：{exc}")
            return
        self.load(None, cap, "", "已载入示例数据（2026-10-24 板上 tr85 的真实记录）",
                  phase=0, source="示例数据（离线，不是本机板子）")

    def _run(self):
        if self.busy:
            return
        port = (self.port_var.get() or "").strip()
        if not port:
            self.status_var.set("还没有选串口：先回主窗口点『刷新』选一个")
            return
        text = (self.text_var.get() or "").strip() or "hello,rv"
        phase = 0 if self.phase_var.get().startswith("0") else 1
        self.phase = phase
        self.busy = True
        self.run_btn.state(["disabled"])
        self.status_var.set(f"正在采集中（{text!r}，阶段 {phase}）……")

        def work():
            # 串口被占（PermissionError 13 拒绝访问）最常见的来源就是**本程序的主窗口**
            # 还在连续采集。先让它停下来，再重试最多 4 秒；仍打不开就把"谁占着"讲清楚。
            last_exc = None
            for attempt in range(9):
                try:
                    raw, cap = run_trace(port, text, phase)
                    self.results.put(("ok", raw, cap, text))
                    return
                except PermissionError as exc:
                    last_exc = exc
                    if attempt == 0 and self.stop_live:
                        self.stop_live()
                    time.sleep(0.5)
                except Exception as exc:                 # 串口/固件问题都从这里回界面
                    self.results.put(("err", exc, None, text))
                    return
            self.results.put(("err", RuntimeError(
                "打不开串口 %s：被别的程序占着（%s）。最常见的原因：主窗口的『▶ 连续采集』"
                "或另一个上位机窗口还开着，或串口助手/终端程序占着这个口。"
                "把它们停掉再点一次『▶ 采集』即可。" % (port, last_exc)), None, text))

        threading.Thread(target=work, daemon=True).start()
        self._poll()

    def _poll(self):
        try:
            kind, payload, cap, text = self.results.get_nowait()
        except queue.Empty:
            if self.busy:
                self.win.after(80, self._poll)
            return
        self.busy = False
        self.run_btn.state(["!disabled"])
        if kind == "err":
            self.status_var.set(f"采集失败：{payload}")
            return
        self.load(payload, cap, text, phase=getattr(self, "phase", 0),
                  source="实时采集（本机板子）")

    def _export(self):
        if not self.nodes:
            self.status_var.set("还没有数据可导出")
            return
        from tkinter import filedialog
        OUT.mkdir(parents=True, exist_ok=True)
        path = filedialog.asksaveasfilename(
            defaultextension=".html", initialdir=str(OUT),
            initialfile="register_heatmap.html")
        if not path:
            return
        write_trace_html(Path(path), self.nodes, self.capture, self.sent)
        self.status_var.set("已导出：" + path)
        if self.log_line:
            self.log_line("已导出寄存器热力图网页：" + path)
        webbrowser.open(Path(path).resolve().as_uri())


# 打开过的热力图窗口都留在这里：Toplevel 一旦没有引用就会被回收成空壳
TRACE_WINDOWS: list = []


def firmware_guide() -> list:
    """「到底该用哪颗位流」的唯一权威答案。

    为什么放在单文件里：仓库里有 15 颗 .sbit（la50/la80/la85/la90、tr85、cm50…cmim85、
    ila、tm50、tmila、ddr3），每颗只服务一个用途，混用必然"采集失败"或"读不出分"。
    这里按**用途**给四行答案，其余一律标注"专项位流，演示不用"。
    """
    return [
        "该用哪颗位流（按用途选，别混；下载命令就是每行的第二句）：",
        "  ① 交付 / 演示主力 = la85（85 MHz）",
        "     scripts\\program_board.ps1 -Config la85",
        "     文件：release\\final_submission\\bitstream\\mes50hp_riscv_logic_analyzer.sbit",
        "     能做：八通道五模式（static/counter/uart/spi/mirror）+ Core 内部观测点 + 仪器读数 + VCD/HTML 报告。",
        "     拍视频绝大多数时间用这颗。它**没有** CPU 数据流（0xAA），也**没有** CoreMark。",
        "  ② 只有 ① 打不开时才用备用 = la50（50 MHz，已验证备用，不是交付口径）",
        "     scripts\\program_board.ps1 -Config la50",
        "  ③ 要拍 CPU 数据流 / 寄存器热力图 = tr85",
        "     scripts\\program_board.ps1 -Config tr85",
        "     文件：fpga\\trace85\\generate_bitstream\\mes50hp_trace_pll_top.sbit（只有 trace，没有八通道采集）",
        "     不接板子也想看热力图：点数据流窗口里的『示例数据（不用板子）』，不用任何位流。",
        "  ④ 要拍 CoreMark 跑分 = cmim85（RV32IM；Score 193.192 / CoreMark-MHz 2.272）",
        "     scripts\\program_board.ps1 -Config cmim85 ；纯 RV32I 口径用 cm85r（Score 79.587）",
        "  拍完一律回到 ①：scripts\\program_board.ps1 -Config la85",
        "  其余 cm50/cm80/cm90/cm95/cmim/cm85/ila/tm50/tmila/ddr3 都是某个证据点的专项位流，演示不用。",
    ]


def run_gui(autorun: str | None = None, probe=None, trace: bool = False,
            trace_text: str = DEFAULT_TEXT, trace_port: str | None = None) -> int:
    """autorun：给自检用——启动后自动按这个模式采集一次再退出（正常双击不走这条路）。
    probe：给无人值守自检用——把面板内部句柄交出去，让脚本能驱动界面（正常双击也不走）。"""
    import tkinter as tk
    from tkinter import filedialog, font as tkfont, messagebox, ttk

    root = tk.Tk()
    root.title("逻辑分析仪 · 单文件全功能演示")
    theme = install_theme(root, tk, ttk, tkfont)     # 只改外观，见 install_theme 的说明
    UI_FONT, MONO_FONT, T = theme["ui"], theme["mono"], theme["tok"]
    # 窗口尺寸跟着屏幕走：这块板子的演示机不一定是 1080p，写死 1240x840 会掉到屏幕外，
    # 掉出去的部分正是日志和导出按钮（现场最容易需要的那两块）。
    _sw, _sh = root.winfo_screenwidth(), root.winfo_screenheight()
    root.geometry("%dx%d" % (min(1400, max(1180, _sw - 260)),
                             min(950, max(720, _sh - 120))))
    root.minsize(1120, 720)
    st = {"port": tk.StringVar(), "mode": tk.StringVar(value="static"),
          "text": tk.StringVar(value=DEFAULT_TEXT), "busy": False, "stop": False,
          "last": None, "clock": 85_000_000,
          # 仪器面板的状态：勾选、板级时钟文本、停止条件、八个旋钮
          "manual": tk.BooleanVar(value=False), "clock_text": tk.StringVar(value="85000000"),
          "stop_after": tk.StringVar(value="0"), "knob_widgets": {},
          "knob": {n: tk.StringVar() for n in
                   ("sample_div", "trigger_type", "trigger_channel", "trigger_level",
                    "pre", "post", "pattern_div", "data", "source")},
          "live": False,
          # running_mode：**正在跑的那个任务用的是哪个模式**。任务在 start() 那一刻就把模式
          # 固定了（jobs.put 只读一次），所以运行中改单选钮不会影响它——不记住这个值，
          # 界面就没法告诉用户"你看到的波形是哪个模式采的"（现场表现：点了 core 没反应）。
          # restart_live：运行中切模式后，等这一轮收尾**自动按新模重开连续采集**。
          "running_mode": None, "restart_live": False}
    q: queue.Queue = queue.Queue()          # 线程 -> 界面（结果）
    jobs: queue.Queue = queue.Queue()       # 界面 -> 线程（任务）

    # 提交级数据流窗口：留着引用，否则窗口关掉前会被 Python 回收成空壳
    trace_windows: list = []

    def open_trace():
        # stop_live：数据流窗口要抢串口时，先让主窗口把「连续采集」停下来。
        # 否则连采状态下主窗口一直握着 COM 口，数据流窗口开会报
        # PermissionError(13, '拒绝访问') —— 2026-10-30 用户实际踩到的就是这一条。
        w = TraceWindow(root, st["port"], UI_FONT, MONO_FONT, T, log_line,
                        stop_live=lambda: stop_for_trace())
        trace_windows.append(w)
        TRACE_WINDOWS.append(w)
        return w

    def stop_for_trace():
        """把主窗口的采集停下来（连续采集 / 正在跑的那一轮都会在收尾后退出）。"""
        if st["busy"]:
            st["stop"] = True
            log_line("已通知主窗口停止采集（串口要让给下面这个操作）")
        return st["busy"]

    # 自检脚本从 st 里取这个入口；probe 的实参个数保持不变（既有测试按老签名回调）
    st["open_trace"] = open_trace

    # ---- 顶部工具条：左边「连接 + 模式 + 字符串」，右边「采集动作」 ----
    # 分组只靠竖分隔线和间距，控件本身与原来一模一样（顺序也没动，动作按钮挪到右边是为了
    # 让主操作落在拇指/鼠标最后停留的位置，与 GitHub 表单的 primary action 一个道理）。
    top = ttk.Frame(root, padding=(14, 11, 14, 11))
    top.pack(fill="x")
    ttk.Label(top, text="板载串口", style="Muted.TLabel").pack(side="left")
    port_box = ttk.Combobox(top, textvariable=st["port"], width=18, state="readonly")
    port_box.pack(side="left", padx=(8, 6))
    ttk.Button(top, text="刷新", command=lambda: refresh_ports()).pack(side="left")
    ttk.Frame(top, style="Hair.TFrame", width=1).pack(side="left", fill="y", padx=10)
    ttk.Label(top, text="模式", style="Muted.TLabel").pack(side="left", padx=(0, 4))
    for m in MODES:
        ttk.Radiobutton(top, text=m, value=m, variable=st["mode"],
                        command=lambda: on_mode_change()).pack(side="left")
    ttk.Frame(top, style="Hair.TFrame", width=1).pack(side="left", fill="y", padx=10)
    ttk.Label(top, text="字符串", style="Muted.TLabel").pack(side="left", padx=(0, 4))
    text_entry = ttk.Entry(top, textvariable=st["text"], width=14)
    text_entry.pack(side="left")
    live_btn = ttk.Button(top, text="▶ 连续采集", command=lambda: toggle_live())
    live_btn.pack(side="right")
    trace_btn = ttk.Button(top, text="▶ 提交级数据流（寄存器热力图）",
                           command=lambda: open_trace())
    trace_btn.pack(side="right", padx=(0, 8))
    ttk.Button(top, text="该用哪颗位流？",
               command=lambda: show_guide()).pack(side="right", padx=(0, 8))
    ttk.Button(top, text="一键自检",
               command=lambda: selfcheck()).pack(side="right", padx=(0, 8))
    ttk.Button(top, text="跑分",
               command=lambda: run_score()).pack(side="right", padx=(0, 8))
    run_btn = ttk.Button(top, text="▶ 采集一次", style="Primary.TButton",
                         command=lambda: once())
    run_btn.pack(side="right", padx=(0, 8))

    ttk.Frame(root, style="Hair.TFrame", height=1).pack(fill="x")
    info_bar = ttk.Frame(root, padding=(14, 5))
    info_bar.pack(fill="x")
    info = ttk.Label(info_bar, text="就绪", style="Status.TLabel")
    info.pack(anchor="w")
    ttk.Frame(root, style="Hair.TFrame", height=1).pack(fill="x")

    # ---- 仪器面板：不改板子、不重新综合就能换时基/触发/窗口/激励 ----
    # 这些字段固件一直都在收（13 字节报文里就有），原来只是被写死在模式默认里。
    pnl = ttk.LabelFrame(root, text=" 仪器面板 ", padding=(12, 8, 12, 8))
    pnl.pack(fill="x", padx=14, pady=(12, 0))
    head = ttk.Frame(pnl)
    head.pack(fill="x")
    ttk.Checkbutton(head, text="使用面板参数（不勾就用模式默认）", variable=st["manual"],
                    command=lambda: on_manual_toggle()).pack(side="left")
    ttk.Button(head, text="载入当前模式默认值",
               command=lambda: load_defaults()).pack(side="left", padx=(10, 0))
    ttk.Frame(head, style="Hair.TFrame", width=1).pack(side="left", fill="y", padx=13)
    # 板级时钟必须与下载的位流一致：镜像模式的时基是按它反算的，填错必然解出乱码
    ttk.Label(head, text="板级时钟", style="Muted.TLabel").pack(side="left", padx=(0, 6))
    ttk.Combobox(head, textvariable=st["clock_text"], width=10, state="readonly",
                 values=("85000000", "50000000")).pack(side="left")
    # 连续采集的停止条件。固件只在"触发过"以后才置 done，所以每次成功回包都是一次命中
    ttk.Label(head, text="采满", style="Muted.TLabel").pack(side="left", padx=(16, 6))
    stop_entry = ttk.Entry(head, textvariable=st["stop_after"], width=5)
    stop_entry.pack(side="left")
    ttk.Label(head, text="次后自动停（0 = 一直采）", style="Muted.TLabel").pack(side="left",
                                                                              padx=(6, 0))

    ttk.Frame(pnl, style="Hair.TFrame", height=1).pack(fill="x", pady=(8, 2))
    kgrid = ttk.Frame(pnl)
    kgrid.pack(fill="x", pady=(4, 0))
    for i, (label, name, width) in enumerate((
            ("时基 sample_div", "sample_div", 8), ("触发方式", "trigger_type", 8),
            ("触发通道", "trigger_channel", 6), ("电平", "trigger_level", 6),
            ("pre", "pre", 6), ("post", "post", 7),
            ("激励速率", "pattern_div", 8), ("激励数据", "data", 6),
            # 采集源（双源可选）：0 = J8 外部 8 路，1 = Core 内部观测点。
            # 选 Core 时命令变成 0xA8（16 位 pre/post + 源字节），pre/post 上限也随之放宽。
            ("采集源", "source", 16))):
        row, col = divmod(i, 4)
        ttk.Label(kgrid, text=label, style="Muted.TLabel").grid(
            row=row, column=col * 2, sticky="e", padx=(0 if col == 0 else 18, 6), pady=2)
        if name == "trigger_type":
            w = ttk.Combobox(kgrid, textvariable=st["knob"][name], width=width,
                             state="readonly", values=("level", "rise", "fall"))
            w.bind("<<ComboboxSelected>>", lambda _e: update_info())
        elif name == "trigger_level":
            w = ttk.Combobox(kgrid, textvariable=st["knob"][name], width=width,
                             state="readonly", values=("1 高", "0 低"))
            w.bind("<<ComboboxSelected>>", lambda _e: update_info())
        elif name == "trigger_channel":
            w = ttk.Combobox(kgrid, textvariable=st["knob"][name], width=width,
                             state="readonly", values=tuple(f"ch{c}" for c in range(8)))
            w.bind("<<ComboboxSelected>>", lambda _e: update_info())
        elif name == "source":
            w = ttk.Combobox(kgrid, textvariable=st["knob"][name], width=width,
                             state="readonly", values=tuple(lbl for lbl, _ in SOURCES))
            w.bind("<<ComboboxSelected>>", lambda _e: on_source_change())
        else:
            w = ttk.Entry(kgrid, textvariable=st["knob"][name], width=width)
            w.bind("<KeyRelease>", lambda _e: update_info())
        st["knob_widgets"][name] = w
        w.grid(row=row, column=col * 2 + 1, sticky="w", pady=2)
    knob_info = ttk.Label(pnl, text="", style="Muted.TLabel")
    knob_info.pack(anchor="w", pady=(6, 0))

    # 中间区：左边波形，右边仪器读数表（真仪器就是"波形 + 读数"两块并排）
    # 三块深色面（波形/读数/日志）用 1px 边框收边，浅色外壳 + 深色内容面是 Grafana、
    # Datadog 那类工具的惯用分法：观片区长时间盯着不刺眼，控件区在投影上又足够清楚。
    mid = ttk.Frame(root)
    mid.pack(fill="both", expand=True, padx=14, pady=(10, 0))
    cv_card = ttk.Frame(mid, style="Hair.TFrame", padding=1)
    cv_card.pack(side="left", fill="both", expand=True)
    cv = tk.Canvas(cv_card, background=T["plot_bg"], highlightthickness=0, borderwidth=0)
    cv.pack(fill="both", expand=True)
    side = ttk.Frame(mid)
    side.pack(side="right", fill="y", padx=(12, 0))
    ttk.Label(side, text="通道读数", style="Section.TLabel").pack(anchor="w")
    cols = ("ch", "edge", "freq", "period", "duty", "wmin", "wmax")
    table = ttk.Treeview(side, columns=cols, show="headings", height=8)
    for c, w, t in (("ch", 50, "通道"), ("edge", 54, "边沿"), ("freq", 76, "频率"),
                    ("period", 76, "周期"), ("duty", 60, "占空比"),
                    ("wmin", 76, "最小脉宽"), ("wmax", 76, "最大脉宽")):
        table.heading(c, text=t)
        table.column(c, width=w, anchor="center")
    table.pack(fill="x", pady=(6, 0))
    ttk.Label(side, text="协议读数", style="Section.TLabel").pack(anchor="w", pady=(14, 0))
    rd_card = ttk.Frame(side, style="Hair.TFrame", padding=1)
    rd_card.pack(fill="both", expand=True, pady=(6, 0))
    readings = tk.Text(rd_card, height=6, width=40, background=T["plot_bg"],
                       foreground=T["plot_text"], font=(MONO_FONT, 10), state="disabled",
                       relief="flat", borderwidth=0, highlightthickness=0,
                       padx=10, pady=8, selectbackground=T["plot_select"],
                       selectforeground=T["plot_text"])
    readings.pack(fill="both", expand=True)

    log_card = ttk.Frame(root, style="Hair.TFrame", padding=1)
    log_card.pack(fill="x", padx=14, pady=(10, 0))
    log = tk.Text(log_card, height=5, background=T["plot_bg"], foreground=T["plot_text"],
                  insertbackground=T["plot_text"], font=(MONO_FONT, 10), relief="flat",
                  borderwidth=0, highlightthickness=0, padx=10, pady=8,
                  selectbackground=T["plot_select"], selectforeground=T["plot_text"])
    log.pack(fill="x")
    ttk.Frame(root, style="Hair.TFrame", height=1).pack(fill="x", pady=(10, 0))
    bottom = ttk.Frame(root, padding=(14, 8, 14, 10))
    bottom.pack(fill="x")
    ttk.Button(bottom, text="打开输出目录",
               command=lambda: webbrowser.open(OUT.resolve().as_uri())).pack(side="right")
    ttk.Button(bottom, text="导出 VCD", command=lambda: export("vcd")).pack(side="left")
    ttk.Button(bottom, text="导出网页波形", command=lambda: export("html")).pack(side="left",
                                                                               padx=8)
    ttk.Button(bottom, text="导出测量报告", command=lambda: export("md")).pack(side="left")

    def log_line(s: str):
        log.insert("end", s + "\n")
        log.see("end")

    def show_guide():
        """「该用哪颗位流？」按钮：把用途对照表打进日志区（不碰串口，任何状态下都能点）。"""
        for s in firmware_guide():
            log_line(s)

    def selfcheck():
        """一键自检：把"到底哪一步不行"打成一份可照抄的检查单。

        为什么要有这个按钮：用户报"采集不行"时，可能的原因分布在四五处
        （串口选错、端口被别的程序占着、板子固件不对、J8 线没接、模式参数不对），
        光看一句"采集失败"根本分不清。这里按"串口清单 → static → counter"的顺序自己跑一遍，
        每步都落一行结论，谁看都知道卡在哪。
        """
        def work():
            try:
                q.put(("log", "=" * 56))
                q.put(("log", "一键自检（不重新下载位流，只发两包采集命令）"))
                ports = list(list_ports.comports())
                if not ports:
                    q.put(("log", "✗ 系统里一个串口都没有：板载 CP210x 的 USB 线没插？"))
                for p in ports:
                    desc = (p.description or "")
                    is_board = ("CP210" in desc.upper()) or ("SILICON LABS" in desc.upper())
                    q.put(("log", "  串口 %-6s %s%s" % (p.device, desc,
                                                       "   ← 板载 CP210x（就是它）" if is_board else "")))
                port = (st["port"].get() or "").strip()
                if not port:
                    q.put(("log", "✗ 还没选中串口：在上面的『板载串口』里选 CP210x 那个（通常 COM11）"))
                    return
                q.put(("log", "  当前选中：%s，开始采集 static / counter …" % port))
                ok_n = 0
                for mode in ("static", "counter"):
                    try:
                        raw, samples, trig, cfg, decoded, frames, errors = capture(port, mode)
                        ok_n += 1
                        head = raw[:44].replace(b"\r", b" ").replace(b"\n", b" ")
                        q.put(("log", "✓ %s：%d 个采样点，触发=%s，回包头 %r"
                                     % (mode, len(samples), trig, head)))
                    except Exception as exc:
                        q.put(("log", "✗ %s：%s" % (mode, exc)))
                if ok_n:
                    q.put(("log", "结论：板子与上位机这一路是通的（%d/2 通过）。"
                                  "接着点『▶ 采集一次』就能出波形；要热力图点右上角那个按钮。" % ok_n))
                else:
                    q.put(("log", "结论：一包都没回来。依次查：① 选的是不是 CP210x 那个口（不是 COM15/16）；"
                                  "② 有没有别的程序占着这个口（PDS、旧窗口）；"
                                  "③ USB 线是不是只有充电功能；④ 板子有没有下载交付位流 la85。"))
            finally:
                q.put(("idle", None))
        threading.Thread(target=work, daemon=True).start()

    def run_score():
        """「跑分」按钮：**只跑分，不下载位流**。

        位流由用户自己下载（他明确要求不要替他自动下载）。这里只做跑分程序本身的事：
        开串口 → 每秒发一个 R → 读 CoreMark 输出 → 算分并校验官方 CRC。
        """
        port = (st["port"].get() or "").strip()
        if not port:
            log_line("✗ 还没选中串口：先在『板载串口』里选 CP210x 那个（通常 COM11）")
            return
        root = Path(__file__).resolve().parent
        scorer = root / "scripts" / "coremark_score.ps1"
        if not scorer.exists():
            scorer = root / "tools" / "coremark_score.ps1"
        if not scorer.exists():
            log_line("✗ 找不到跑分程序 coremark_score.ps1")
            return
        stop_for_trace()                     # 串口要先让出来
        ps = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                          "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
        args = ["-File", str(scorer), "-Port", port, "-ClockHz", "85000000"]
        log_line("=" * 52)
        log_line("开始跑分（只跑分，不下载位流）：发 R → 读串口 → 算分 → 校验官方 CRC")
        log_line("  前提：你已经把计分位流下好了，而且下载后没有按复位。约 30 秒。")

        def work():
            try:
                time.sleep(1.0)              # 等主窗口那一轮采集收尾
                # 输出直接落文件而不是走管道：管道在某些受限环境里会报 EPERM，
                # 落文件还能顺便留一份原始日志给用户自己看。
                OUT.mkdir(parents=True, exist_ok=True)
                tmp = OUT / "coremark_button.log"
                with open(tmp, "w", encoding="utf-8", errors="replace") as fh:
                    subprocess.run([ps, "-NoProfile", "-ExecutionPolicy", "Bypass"] + args,
                                   cwd=str(root), stdout=fh, stderr=subprocess.STDOUT,
                                   timeout=420)
                out = tmp.read_text(encoding="utf-8", errors="replace")
                lines = [ln.rstrip() for ln in out.splitlines() if ln.strip()]
                for ln in lines[-26:]:
                    q.put(("log", "  " + ln))
                if any(("分数" in ln) or ("score_x1000" in ln) for ln in lines):
                    q.put(("log", "跑分完成 ✓ （板子现在是 cmim85，只能跑分；"
                                  "要采波形刷 la85，要看热力图刷 tr85）"))
                else:
                    q.put(("log", "没读到分数 ✗ 常见原因：COM 被别的程序占着、板上不是跑分位流、"
                                  "下载线没插好。上面几行就是原始输出，完整日志在 " + str(tmp)))
            except subprocess.TimeoutExpired:
                q.put(("log", "✗ 跑分超时（超过 7 分钟）：检查板子与串口"))
            except Exception as exc:          # noqa: BLE001
                q.put(("log", "✗ 跑分失败：%r" % (exc,)))
            finally:
                q.put(("idle", None))
        threading.Thread(target=work, daemon=True).start()

    def fill_readings(ds):
        """把仪器读数填进右边的表。

        八行固定（没有活动的通道标 —），这与真仪表一致：面板上的位数不会因为没接信号就少一行。
        """
        for item in table.get_children():
            table.delete(item)
        for r in measure_all(ds["samples"], ds["sample_ns"]):
            if r is None or r["edges"] == 0:
                ch = r["ch"] if r else 0
                table.insert("", "end", values=(f"ch{ch}", "0", "—", "—", "—", "—", "—"))
                continue
            table.insert("", "end", values=(
                f"ch{r['ch']}", str(r["edges"]), fmt_freq(r["period"]), fmt_time(r["period"]),
                f"{r['duty']:.1f} %", fmt_time(r["wmin"]), fmt_time(r["wmax"])))
        readings.configure(state="normal")
        readings.delete("1.0", "end")
        for k, v in protocol_readings(ds.get("view", ds["mode"]), ds["cfg"], ds["sample_ns"], ds["frames"],
                                      ds.get("errors", 0), ds["samples"]):
            readings.insert("end", f"{k}：{v}\n")
        readings.insert("end", "\n注：频率/周期只对周期性信号有意义，数据线上的读数\n"
                               "仅供参考；判据是帧数、帧错误和解码内容。\n")
        readings.configure(state="disabled")

    def refresh_ports():
        """刷新串口清单，并**优先选中板载 CP210x**。

        2026-10-30 修：以前只在"当前没选"时才挑端口，于是用户上次手滑选了
        COM15/COM16（机器上另外两个 USB 串口）之后，再也回不到板子那个口，
        表现就是"点了采集失败"。现在只要发现 CP210x 且当前选中的不是它，就自动切回去并记一行日志。
        """
        infos = list(list_ports.comports())
        ports = [p.device for p in infos]
        port_box["values"] = ports
        board = None
        for p in infos:
            desc = (p.description or "").upper()
            if "CP210" in desc or "SILICON LABS" in desc:
                board = p.device
                break
        cur = st["port"].get()
        if board and cur != board and (not cur or cur not in ports):
            st["port"].set(board)
            log_line(f"已自动选中板载 CP210x 串口：{board}")
        if not ports:
            log_line("没找到串口：插好板载 CP210x 的 USB 数据线（只有充电功能的线不会出现串口）再点刷新")
        elif board:
            log_line("串口清单：" + "、".join(
                f"{p.device}{'(板子)' if p.device == board else ''}" for p in infos)
                + f"　→ 板子是 {board}")
        else:
            log_line("串口清单：" + "、".join(ports)
                     + "　→ 没看到 CP210x，USB 线可能只有充电功能")

    def sync_text_state():
        text_entry.configure(state="normal" if st["mode"].get() == "mirror" else "disabled")

    # ---------------------------------------------------------- 仪器面板
    def current_mode() -> str:
        return st["mode"].get()

    def default_cfg() -> dict:
        return mode_config(current_mode(), st["text"].get() or DEFAULT_TEXT, st["clock"])

    def load_defaults():
        """把当前模式的默认参数填进面板。空输入框会被当成 0，所以先预填，操作员只改要改的。"""
        cfg = default_cfg()
        k = st["knob"]
        k["sample_div"].set(str(cfg["sample_div"]))
        k["trigger_type"].set(("level", "rise", "fall")[cfg["trig_type"]])
        k["trigger_channel"].set(f"ch{mask_to_channel(cfg['trig_mask'])}")
        k["trigger_level"].set("1 高" if (cfg["trig_value"] & cfg["trig_mask"]) else "0 低")
        k["pre"].set(str(cfg["pre"]))
        k["post"].set(str(cfg["post"]))
        k["pattern_div"].set(str(cfg["pattern_div"]))
        k["data"].set(str(cfg["data"]))
        # 采集源：从模式默认读（core 模式默认为 Core 内部观测点）
        k["source"].set(source_to_label(int(cfg.get("source", SOURCE_J8))))
        update_info()

    def source_to_label(value: int) -> str:
        for label, code in SOURCES:
            if code == value:
                return label
        return SOURCES[0][0]

    def label_to_source(label: str) -> int:
        for name, code in SOURCES:
            if name == label:
                return code
        raise ValueError(f"未知采集源 {label!r}")

    def on_source_change():
        """切换采集源后把窗口换成新源下的合法默认值，并重算提示。

        0xA8（Core 源）的 pre/post 各 2 字节，0xA5（J8 源）只有 1 字节：
        从 Core 切回 J8 时 post=1983 会超上限被 apply_knobs 拦下（拦得对，
        但现场看到报错会以为功能坏了）；从 J8 切到 Core 时用户要的通常是
        2048 点全速窗口。两处都在这里顺手换掉。
        """
        if st["manual"].get():
            try:
                if label_to_source(st["knob"]["source"].get()) == SOURCE_CORE:
                    cfg = mode_config("core", st["text"].get() or DEFAULT_TEXT, st["clock"])
                    st["knob"]["sample_div"].set("0")
                    st["knob"]["pre"].set(str(cfg["pre"]))
                    st["knob"]["post"].set(str(cfg["post"]))
                else:
                    cfg = default_cfg()
                    st["knob"]["pre"].set(str(min(int(cfg["pre"]), 0xFF)))
                    st["knob"]["post"].set(str(min(int(cfg["post"]), 0xFF)))
            except (ValueError, KeyError):
                pass
        update_info()

    def collect_knobs() -> dict:
        """面板控件 → 报文字段名。两处换算都在这里：
        ① "触发通道 ch3" → 掩码 1<<3；
        ② 电平触发的值必须**与掩码同位**——固件里是
           `(channels & trig_mask) == (trig_value & trig_mask)`，
           ch3 选"高"要写 0x08；写 1 会被 AND 成 0，触发电平正好反掉。
        """
        k = st["knob"]
        knobs = {n: k[n].get() for n in ("sample_div", "pre", "post", "pattern_div", "data")}
        # 采集源：界面显示名 → 报文数值（0xA8 的 [14] 字节 / 是否走 0xA8）
        knobs["source"] = label_to_source(k["source"].get())
        text = k["trigger_channel"].get().strip().lstrip("ch")
        try:
            ch = int(text)
        except ValueError:
            raise ValueError(f"触发通道 {k['trigger_channel'].get()!r} 不是 ch0…ch7") from None
        if not 0 <= ch <= 7:
            raise ValueError(f"触发通道 {ch} 越界：本板只有 ch0…ch7")
        knobs["trigger_type"] = {"level": 0, "rise": 1, "fall": 2}.get(k["trigger_type"].get(), 0)
        knobs["trigger_mask"] = 1 << ch
        knobs["trigger_value"] = (1 << ch) if k["trigger_level"].get().startswith("1") else 0
        if current_mode() == "mirror":
            # 镜像只认 post：其余字段在固件里被重新定义或写死（控件也已禁用，这里再兜一次）
            knobs = {"post": knobs["post"]}
        return knobs

    def knobs_now():
        return collect_knobs() if st["manual"].get() else None

    def update_info():
        """面板的即时体检：这组参数能不能采、每比特几点、窗口多长。"""
        try:
            cfg = apply_knobs(current_mode(), default_cfg(), knobs_now())
        except (ValueError, KeyError) as exc:
            knob_info.configure(text="✗ " + str(exc), foreground=T["danger"])
            return
        window = cfg["pre"] + 1 + cfg["post"]
        msg = (f"采集源 {source_to_label(int(cfg.get('source', SOURCE_J8)))} · "
               f"每比特 {cfg['bit_samples']} 个采样点 · 窗口 {window} 点"
               f"（pre {cfg['pre']} + 触发 1 + post {cfg['post']}）")
        if current_mode() == "mirror":
            need = mirror_required_samples(st["text"].get() or DEFAULT_TEXT, cfg["bit_samples"])
            msg += f" · 整句至少要 {need} 点"
            if window < need:
                knob_info.configure(text=f"✗ 窗口 {window} 点装不下整句（需要 {need} 点）",
                                    foreground=T["danger"])
                return
        if not st["manual"].get():
            msg += " ·（当前用模式默认，勾上左边才生效）"
        knob_info.configure(text=msg, foreground=T["muted"])

    def sync_knob_state():
        """按 勾选/模式/是否在跑 决定每个控件能不能动。"""
        manual = bool(st["manual"].get())
        mirror = current_mode() == "mirror"
        for name, w in st["knob_widgets"].items():
            if name == "post":
                on = manual and not st["busy"]
            else:
                on = manual and not mirror and not st["busy"]
            if isinstance(w, ttk.Combobox):
                w.configure(state="readonly" if on else "disabled")
            else:
                w.configure(state="normal" if on else "disabled")
        stop_entry.configure(state="disabled" if st["busy"] else "normal")

    def on_manual_toggle():
        if st["manual"].get():
            load_defaults()          # 先填默认值，避免空框被当成 0
        update_info()
        sync_knob_state()

    def on_mode_change():
        sync_text_state()
        if st["manual"].get():
            load_defaults()
        else:
            # 不勾面板时旋钮是灰的，但"采集源"这一格必须显示**真正会用的**那个值：
            # core 模式默认就走 Core 内部观测点，格子还写 J8 会与实际采集不符。
            st["knob"]["source"].set(source_to_label(int(default_cfg().get("source", SOURCE_J8))))
        # 【2026-10-14 修】采集运行中切模式：任务在 start() 那一刻就把模式固定了，
        # 光改单选钮**不会**改变正在跑的那一枪 —— 现场表现是"点了 core 没反应、
        # 画面还是 mirror 的波形"。这里主动停掉当前任务；连续采集还会在收尾后按新模重开。
        new_mode = st["mode"].get()
        if st["busy"] and new_mode != st.get("running_mode"):
            was_live = bool(st["live"])
            st["stop"] = True
            if was_live:
                st["restart_live"] = True
            log_line(f"切换模式 → {new_mode}：正在采的是 {st.get('running_mode')}，已请求停止"
                     + ("，这一轮收尾后自动按新模重开连续采集" if was_live
                        else "，停止后请再点『采集一次』"))
            info.configure(text=(f"正在停止（{st.get('running_mode')}）…"
                                 + (f"随后自动切换到 {new_mode}" if was_live else "")))
        update_info()
        sync_knob_state()

    def read_stop_after() -> int:
        raw = st["stop_after"].get().strip() or "0"
        try:
            n = int(raw, 10)
        except ValueError:
            raise ValueError(f"「采满 N 次后自动停」填的不是整数：{raw!r}") from None
        if n < 0:
            raise ValueError("「采满 N 次后自动停」不能为负数（0 = 一直采）")
        return n

    def log_packet(mode: str, cfg: dict):
        """把这一枪的报文打进日志：现场用的到底是哪组参数，事后能逐字节复现。

        必须和 `capture()` 用**同一个** `packet_for_cfg()`：这里曾经漏传 `source`，
        core 模式写日志时抛 ValueError，把界面的轮询循环打断（"点 core 没反应"）。
        """
        packet = packet_for_cfg(cfg)
        log_line(f"   报文 {packet.hex()} · 时基 {cfg['sample_div']} · 速率 {cfg['pattern_div']}"
                 f" · 触发 {'level rise fall'.split()[cfg['trig_type']]}"
                 f" mask=0x{cfg['trig_mask']:02X} value=0x{cfg['trig_value']:02X}"
                 f" · pre {cfg['pre']} post {cfg['post']} · 每比特 {cfg['bit_samples']} 点")

    # ---- 画波形：8 通道 + 帧框 + 字符标注 ----
    # ---- 画波形：实现见模块级 draw_wave（自检也用它，避免两处实现漂移） ----
    def draw(ds):
        draw_wave(cv, ds)

    # ---- 采集线程：UI 不卡，连续采集也能停 ----
    # 两个队列：jobs 只走"UI→线程"的任务，q 只走"线程→UI"的结果。
    # 共用一个队列会让线程取到自己刚放进去的结果消息，解包直接抛异常（本轮实测踩到）。
    def worker():
        while True:
            job = jobs.get()
            if job is None:
                return
            mode, text, live, knobs, stop_after = job
            rounds = 0
            try:
                while True:
                    clock = st["clock"]
                    cfg = apply_knobs(mode, mode_config(mode, text, clock), knobs)
                    if mode == "mirror":      # 先把"窗口够不够"算清楚，再发报文
                        need = mirror_required_samples(text, cfg["bit_samples"])
                        if cfg["post"] + 1 < need:
                            raise ValueError(f"镜像窗口 {cfg['post'] + 1} 点装不下 {len(text)} "
                                             f"个字符（需要 {need} 点）：post 至少 {need - 1}")
                    q.put(("packet", (mode, cfg)))
                    raw, samples, trigger, cfg, decoded, frames, errors = capture(
                        st["port"].get(), mode, text, clock, knobs)
                    view = capture_view(mode, int(cfg.get("source", SOURCE_J8)))
                    ok, why = judge(view, samples, decoded, errors, cfg, text)
                    if mode == "mirror" and not ok and clock == 85_000_000:
                        # 板上可能是 50 MHz 备用位流：自动换时钟再抓一次
                        clock = 50_000_000
                        st["clock"] = clock
                        root.after(0, lambda c=clock: st["clock_text"].set(str(c)))
                        raw, samples, trigger, cfg, decoded, frames, errors = capture(
                            st["port"].get(), mode, text, clock, knobs)
                        view = capture_view(mode, int(cfg.get("source", SOURCE_J8)))
                        ok, why = judge(view, samples, decoded, errors, cfg, text)
                    q.put(("done", (mode, text, raw, samples, trigger, cfg,
                                    decoded, frames, errors, ok, why, clock, view)))
                    rounds += 1
                    # 单次采集：一轮就收工。连续采集：直到按下停止，或采满 N 次
                    if not live or st["stop"] or (stop_after and rounds >= stop_after):
                        break
            except Exception as exc:
                q.put(("error", str(exc)))
            finally:
                st["stop"] = False
                q.put(("idle", None))

    threading.Thread(target=worker, daemon=True).start()

    def start(live: bool):
        if st["busy"]:
            return
        if not st["port"].get():
            messagebox.showwarning("没有串口", "先插好板载 CP210x USB 线，然后点『刷新』")
            return
        try:
            knobs = knobs_now()
            if knobs is not None:
                # 先在主线程校验一次：用的是与采集同一个 apply_knobs，
                # 所以"界面放行、采集时又报另一个错"不会发生
                apply_knobs(current_mode(), default_cfg(), knobs)
            stop_after = read_stop_after()
        except (ValueError, KeyError) as exc:
            messagebox.showerror("面板参数错误", str(exc))
            return
        st["busy"] = True
        st["live"] = live
        st["clock"] = int(st["clock_text"].get() or 85_000_000)
        # 记住这一轮任务实际用的模式：界面据此显示"正在采 X"，切模式时也比对它。
        st["running_mode"] = current_mode()
        run_btn.configure(state="disabled")
        live_btn.configure(text="■ 停止采集" if live else "▶ 连续采集")
        info.configure(text=(f"连续采集中…（正在采 {st['running_mode']}）再点一次『停止采集』结束" if live
                             else f"采集中…（{st['running_mode']} 模式，mirror 每次约 3 秒）"))
        jobs.put((st["running_mode"], st["text"].get() or DEFAULT_TEXT, live, knobs, stop_after))

    def once():
        start(False)

    def toggle_live():
        if st["busy"]:
            st["stop"] = True
            info.configure(text=f"停止中…（正在采 {st.get('running_mode')}，等这一轮收尾）")
            return
        start(True)

    def poll():
        try:
            while True:
                kind, payload = q.get_nowait()
                if kind == "done":
                    (mode, text, raw, samples, trigger, cfg, decoded,
                     frames, errors, ok, why, clock, view) = payload
                    OUT.mkdir(parents=True, exist_ok=True)
                    (OUT / f"{mode}.log").write_bytes(raw)
                    write_vcd(samples, OUT / f"{mode}.vcd", trigger)
                    # 通道名跟着 view 走：Core 源下 ch0..ch7 是流水线观测点，
                    # J8 源下才是 PC_TX / SCLK 这些引脚名。挂错名字比不挂更糟。
                    if view == VIEW_CORE:
                        tags = dict(CORE_CHANNELS)
                    elif view == VIEW_RAW:
                        tags = {}
                    else:
                        tags = {cfg["channel"]: "PC_TX"} if mode == "mirror" else (
                            {0: "SCLK", 1: "MOSI", 2: "CS"} if mode == "spi" else
                            ({0: "UART_TX"} if mode == "uart" else {}))
                    # 顶部那句话要说人话：这是什么、多少字符、每字符几位、窗口多长。
                    if view == VIEW_CORE:
                        note = (f"采集源 = Core 内部观测点（MMIO 寄存器 18）· "
                                f"{mode} 模式只提供窗口与触发预设 · 采集 {len(samples)} 点 · "
                                f"时基 {cfg['sample_div'] + 1} 拍/点")
                    elif view == VIEW_RAW:
                        note = (f"采集源 = J8 外部 8 路（core 只提供窗口/触发预设）· "
                                f"采集 {len(samples)} 点 · 每比特 {cfg['bit_samples']} 个采样点")
                    elif mode == "mirror":
                        note = (f"上位机发送 \"{text}\" —— {len(text)} 个字符 · "
                                f"每个字符 10 位（起始 1 + 数据 8 + 停止 1）· "
                                f"采集 {len(samples)} 点 / "
                                f"{(cfg['sample_div'] + 1) / clock * len(samples) * 1e3:.2f} ms")
                    else:
                        note = (f"{mode} 模式：{cfg['note']} · 采集 {len(samples)} 点 · "
                                f"每比特 {cfg['bit_samples']} 个采样点")
                    sample_ns = 1e9 * (cfg["sample_div"] + 1) / clock
                    write_html(OUT / f"{mode}.html", samples, trigger, frames, cfg, note,
                               sorted(tags) if tags else list(range(8)), tags,
                               readings_html(view, cfg, sample_ns, samples, frames, errors))
                    st["last"] = dict(samples=samples, trigger=trigger, frames=frames,
                                      cfg=cfg, note=note, tags=tags, mode=mode, text=text,
                                      clock=clock, errors=errors, sample_ns=sample_ns,
                                      view=view)
                    draw(st["last"])
                    fill_readings(st["last"])
                    log_line(f"[{mode}] {'PASS' if ok else 'FAIL'} · {why} · "
                             f"{len(samples)} 点 · 触发 {trigger} · {clock / 1e6:.0f} MHz"
                             + (f" · 采集源={view}" if view != mode else ""))
                    line = next((l for l in raw.decode("ascii", "replace").splitlines()
                                 if l.startswith("LA TEXT")), "")
                    if line:
                        log_line("   " + line)
                    info.configure(text=f"{mode}：{'PASS' if ok else 'FAIL'} — {why}"
                                        f"（已存 {OUT}）")
                    if st["live"]:
                        st["rounds"] = st.get("rounds", 0) + 1
                        live_btn.configure(text=f"■ 停止采集（已 {st['rounds']} 次）")
                elif kind == "packet":
                    # 每一枪的报文都打进日志：现场到底用的哪组参数，事后能逐字节复现
                    log_packet(*payload)
                elif kind == "error":
                    log_line("抓取失败：" + payload)
                    if ("PermissionError" in str(payload)) or ("拒绝访问" in str(payload)):
                        log_line("  串口被别的程序占着：关掉另一个上位机窗口 / 串口助手 / 串口监视工具；"
                                 "本窗口若在『▶ 连续采集』，先停止再点采集。")
                    elif "收到 0 字节" in str(payload):
                        # 一个字节都没收到 = 板子不在逻辑分析仪的命令循环里（不是"波形不好看"）。
                        # 两种可复现的原因，现场按这两条排查（详见 release/materials/field_recovery_card.md）：
                        log_line("  板子一个字节都没回，按这两条排查：")
                        log_line("   ① 板上可能不是逻辑分析仪位流：CoreMark 计分位流开机不打印、"
                                 "只等串口发大写 R 才开跑 → 重下 .\\scripts\\program_board.ps1 -Config la85")
                        log_line("   ② 逻辑分析仪固件被『永不命中的触发』挂住了（例如 mirror 等的是 "
                                 "J8-31↔32 那对回环脚的下降沿，线没接好就永远等不到）→ "
                                 "按板上 REST，或重新下载同一位流")
                        log_line("  恢复后先跑一次 static 确认链路通了，再玩 mirror / core。")
                    info.configure(text="抓取失败——看下面日志")
                elif kind == "log":
                    log_line(payload)
                elif kind == "idle":
                    st["busy"] = False
                    st["live"] = False
                    st["rounds"] = 0
                    run_btn.configure(state="normal")
                    live_btn.configure(text="▶ 连续采集")
                    sync_knob_state()
                    if st["restart_live"]:
                        # 运行中点过模式：这一轮收尾后按新模式自动重开连续采集，
                        # 否则用户点了模式却看不到任何变化（本次修的正是这个）。
                        st["restart_live"] = False
                        st["stop"] = False
                        log_line(f"已按新模式重开连续采集：{current_mode()}")
                        start(True)
                    elif st["stop"]:
                        st["stop"] = False
                        info.configure(text="已停止")
        except queue.Empty:
            pass
        except Exception as exc:      # noqa: BLE001 —— 一条坏消息不能把整个界面弄死
            # [2026-10-14 修] 这里原来只捕 queue.Empty。任何别的异常（例如 log_packet 在
            # core 模式下漏传 source 抛的 ValueError）会从 after 回调里窜出去，**末尾那句
            # root.after(120, poll) 就不再执行** ⇒ 界面从此不再刷新/不再写日志/按钮卡住，
            # 看起来像"点什么都没反应"，而唯一线索被打到看不见的控制台。
            # 现在一律记进日志面板（现场就能看见），并且无论如何都把轮询续上。
            import traceback
            try:
                log_line("内部错误（界面会继续运行）：" + repr(exc))
                for line in traceback.format_exc().splitlines()[-4:]:
                    log_line("   " + line)
            except Exception:
                pass
        finally:
            root.after(120, poll)

    def export(kind):
        if not st["last"]:
            messagebox.showinfo("还没有数据", "先点『采集一次』")
            return
        d = st["last"]
        if kind == "vcd":
            p = filedialog.asksaveasfilename(defaultextension=".vcd",
                                             initialfile=f"{d['mode']}.vcd")
            if p:
                write_vcd(d["samples"], Path(p), d["trigger"])
                log_line("已导出 VCD：" + p)
        elif kind == "md":
            p = filedialog.asksaveasfilename(defaultextension=".md",
                                             initialfile=f"{d['mode']}_测量报告.md")
            if p:
                Path(p).write_text(
                    report_markdown(d["note"], d.get("view", d["mode"]), d["note"], d["cfg"],
                                    d["sample_ns"], d["samples"], d["frames"],
                                    d.get("errors", 0), d.get("clock", 85e6)),
                    encoding="utf-8")
                log_line("已导出测量报告：" + p)
                webbrowser.open(Path(p).resolve().as_uri())
        else:
            p = filedialog.asksaveasfilename(defaultextension=".html",
                                             initialfile=f"{d['mode']}.html")
            if p:
                write_html(Path(p), d["samples"], d["trigger"], d["frames"], d["cfg"],
                           d["note"],
                           sorted(d["tags"]) if d["tags"] else list(range(8)), d["tags"],
                           readings_html(d.get("view", d["mode"]), d["cfg"], d["sample_ns"],
                                         d["samples"], d["frames"], d.get("errors", 0)))
                log_line("已导出网页波形：" + p)
                webbrowser.open(Path(p).resolve().as_uri())

    root.bind("<Return>", lambda e: once())
    refresh_ports()
    on_mode_change()
    load_defaults()          # 面板先填上当前模式的默认值（空框会被当成 0）
    sync_knob_state()
    poll()
    log_line("操作顺序：① 板子里下载交付位流  ② J8 八对脚接好（31↔32 是被测的串口线）"
             "  ③ 选串口  ④ 选模式点『采集一次』")
    log_line("mirror 模式：在『字符串』框里打字，波形上会逐字符标出你发的那句话。")
    log_line("仪器面板：勾上「使用面板参数」就能改时基/触发/窗口/激励，改完下一枪生效；"
             "不勾就走模式默认，和以前一样。")
    log_line("连续采集：点一次开始，再点一次停止；面板里填「采满 N 次」会自动停（0 = 一直采）。")
    log_line("『提交级数据流』按钮打开寄存器写回热力图窗口；没有板子时点里面的"
             "『示例数据』也能看到一枪真实记录。")
    if probe is not None:
        # 无人值守自检：把面板句柄交出去，脚本据此驱动界面并断言状态
        root.after(300, lambda: probe(st, update_info, sync_knob_state, knob_info,
                                      run_btn, live_btn, root))
    if trace:
        def _open_trace():
            w = open_trace()
            w.text_var.set(trace_text)
            if trace_port:
                st["port"].set(trace_port)
                w._run()
            else:
                w.load_sample()
        root.after(400, _open_trace)
    # 双击打开就直接能看到寄存器热力图：自动开窗并载入内置的那一枪真实记录。
    # 有板子时点窗口里的『采集』就换成当前一枪；不想看可以随手关掉这个窗口。
    if autorun is None:
        def _auto_trace():
            try:
                w = open_trace()
                w.load_sample()
            except Exception as exc:                 # 开不出来也不能拖垮主窗口
                log_line(f"热力图窗口没打开：{exc}")
        root.after(600, _auto_trace)
    if autorun:
        st["mode"].set(autorun)
        on_mode_change()
        root.after(700, once)
        root.after(30000, root.destroy)
    root.mainloop()
    return 0


# ============================================================ 自检（不开界面）
def selftest(text: str, port: str | None) -> int:
    p = find_port(port)
    print(f"串口 {p}，逐模式采集自检\n" + "-" * 60)
    OUT.mkdir(parents=True, exist_ok=True)
    cv = None
    try:                                   # 顺便用真实数据把画图代码跑一遍（窗口不显示）
        import tkinter as tk
        holder = tk.Tk()
        holder.withdraw()
        cv = tk.Canvas(holder, width=1000, height=560)
        cv.pack()
    except Exception as exc:               # 无显示环境就只跳过画图这一项
        print(f"（本机开不了 Tk 窗口，跳过画图自检：{exc}）")
    bad = 0
    for mode in MODES:
        try:
            raw, samples, trigger, cfg, decoded, frames, errors = capture(p, mode, text)
            view = capture_view(mode, int(cfg.get("source", SOURCE_J8)))
            ok, why = judge(view, samples, decoded, errors, cfg, text)
        except Exception as exc:
            print(f"{mode:<8} FAIL  {exc}")
            bad += 1
            continue
        (OUT / f"{mode}.log").write_bytes(raw)
        write_vcd(samples, OUT / f"{mode}.vcd", trigger)
        tags = (dict(CORE_CHANNELS) if view == VIEW_CORE else {} if view == VIEW_RAW else
                {cfg["channel"]: "PC_TX"} if mode == "mirror" else
                {0: "SCLK", 1: "MOSI", 2: "CS"} if mode == "spi" else
                {0: "UART_TX"} if mode == "uart" else {})
        drawn = ""
        if cv is not None:
            draw_wave(cv, dict(samples=samples, trigger=trigger, frames=frames, tags=tags,
                               cfg=cfg, note=f"{mode} 模式 {cfg['note']}",
                               sample_ns=1e9 * (cfg["sample_div"] + 1) / 85_000_000))
            drawn = f" · 画图 {len(cv.find_all())} 个图元"
        line = next((l for l in raw.decode("ascii", "replace").splitlines()
                     if l.startswith("LA TEXT")), "")
        print(f"{mode:<8} {'PASS' if ok else 'FAIL'}  {why} · {len(samples)} 点 · "
              f"触发 {trigger}{drawn}")
        if line:
            print(f"         {line}")
        # 仪器读数：和界面右栏那张表同源（同一套 measure_* 函数）
        ns = 1e9 * (cfg["sample_div"] + 1) / 85_000_000
        for r in measure_all(samples, ns):
            if r and r["edges"]:
                print(f"         ch{r['ch']}: 边沿 {r['edges']} · 频率 {fmt_freq(r['period'])}"
                      f" · 周期 {fmt_time(r['period'])} · 占空比 {r['duty']:.1f}%"
                      f" · 脉宽 {fmt_time(r['wmin'])}…{fmt_time(r['wmax'])}")
        for k, v in protocol_readings(view, cfg, ns, frames, errors, samples):
            print(f"           {k}：{v}")
        if not ok:
            bad += 1
    print("-" * 60)
    print(f"{'全部通过' if bad == 0 else str(bad) + ' 个模式失败'}；产物在 {OUT}")
    return 1 if bad else 0


# ============================================================ 寄存器热力图自检（不用板子）
def trace_selftest() -> int:
    """不需要开发板与串口：命令编码、回包解析、反汇编、热力图坐标与画图逐项断言。"""
    bad = 0

    def check(name, ok, detail=""):
        nonlocal bad
        if not ok:
            bad += 1
        print(f"TRACE SELFTEST {'PASS' if ok else 'FAIL'} {name}"
              f"{('  ' + detail) if detail else ''}")
        return ok

    # 1) 0xAA 命令：字符数、阶段要原样落进第 2/3 字节，第 4 字节是 XOR
    p1, p2 = build_trace_packet(8, 0), build_trace_packet(32, 1)
    check("命令 0xAA 编码(8,0)", p1 == bytes([0xAA, 8, 0, 0xAA ^ 8]), p1.hex(" "))
    check("命令 0xAA 编码(32,1)", p2 == bytes([0xAA, 32, 1, 0xAA ^ 32 ^ 1]), p2.hex(" "))

    # 2) 解析内置的那一枪真实回包
    cap = sample_capture()
    check("解析记录数", cap["count"] == 100 and len(cap["records"]) == 100,
          f"count={cap['count']}")
    check("解析打点数", cap["mark_count"] == 8 and len(cap["marks"]) == 8,
          f"marks={cap['mark_count']}")
    check("解析发送文本", cap["text"] == [ord(c) for c in "HELLO,RV"], repr(cap["ascii"]))

    # ---- 判据：发送的字符串必须取打点值 ----
    sent_now = sent_text_from_marks(cap)
    check("发送文本取打点值", sent_now == "hello,rv", repr(sent_now))
    res = judge_trace(cap, sent_now, 0)
    check("判据全部通过（%d 条）" % len(res), judgements_pass(res),
          repr([n for n, ok, _d in res if not ok]))
    res_wrong = judge_trace(cap, "".join(chr(c) for c in cap["text"]), 0)
    check("用回包文本判据必然报错", not judgements_pass(res_wrong),
          repr([n for n, ok, _d in res_wrong if not ok]))

    # 3) 132 位记录装/拆互逆
    rec = {"pc": 0xABC, "instr": 0x005303B3, "rd_we": 1, "rd": 7, "rd_data": 0xDEADBEEF,
           "mem_we": 1, "mem_addr": 0x123, "mem_wstrb": 0b0010, "mem_data": 0x11223344,
           "error": 1}
    words = [(pack_trace_record(rec) >> (32 * i)) & 0xFFFFFFFF for i in range(TRACE_WORDS)]
    back = unpack_trace_record(words)
    check("记录装拆互逆", all(back[k] == v for k, v in rec.items()))

    # 4) 反汇编：助记符、文本、读寄存器、写寄存器四项都要对上
    cases = (
        (0x00000013, "addi x0,x0,0", (), ()),
        (0x000012B7, "lui x5,0x1", (), (5,)),
        (0x01028293, "addi x5,x5,16", (5,), (5,)),
        (0x00502023, "sw x5,0(x0)", (5,), ()),
        (0x00002303, "lw x6,0(x0)", (), (6,)),
        (0x005303B3, "add x7,x6,x5", (6, 5), (7,)),
        (0x00038463, "beq x7,x0,8", (7,), ()),
        (0x008000EF, "jal x1,8", (), (1,)),
        (0x00100073, "ebreak", (), ()),
        (0x30200073, "mret", (), ()),
        (0x00000073, "ecall", (), ()),
        ((0x300 << 20) | (2 << 12) | (1 << 7) | 0x73, "csrrs x1,0x300,x0", (), (1,)),
    )
    ok_all = True
    for word, want_text, want_reads, want_writes in cases:
        d = decode_rv32i(word)
        if (d["text"], tuple(d["reads"]), tuple(d["writes"])) != \
                (want_text, want_reads, want_writes):
            ok_all = False
            print(f"            0x{word:08X} 得到 {d['text']} {d['reads']}/{d['writes']}，"
                  f"期望 {want_text} {list(want_reads)}/{list(want_writes)}")
    check(f"反汇编 {len(cases)} 条", ok_all)

    # 5) 热力图方格：等于"rd_we 且 rd != 0"的记录数，且一定不含 x0
    nodes = build_trace_nodes(cap)
    cells = heatmap_cells(nodes)
    want = sum(1 for n in nodes if n["rd_we"] and n["rd"])
    check("方格数 = 写回记录数", len(cells) == want, f"{len(cells)} 个方格 / {want} 条写回")
    check("方格不含 x0", all(reg != 0 for _i, reg in cells))
    check("表格行数 = 记录数", len(nodes) == cap["count"])

    # 6) 坐标换算：方格必须正好铺满绘图区，不能越界
    lay = heatmap_layout(1000, 420, len(nodes))
    check("坐标换算", abs(lay["left"] + lay["bw"] * lay["n"] - 1000) < 1e-6
          and abs(lay["top"] + lay["row_h"] * 32 + lay["bottom"] - 420) < 1e-6,
          f"bw={lay['bw']:.2f} row_h={lay['row_h']:.2f}")

    # 7) 真在 Canvas 上画一遍（本机开不了窗口就跳过，不算失败）
    try:
        import tkinter as tk
        holder = tk.Tk()
        holder.withdraw()
        cv = tk.Canvas(holder, width=1000, height=420)
        cv.pack()
        stat = draw_reg_heatmap(cv, nodes, sel=3, width=1000, height=420)
        rects = [i for i in cv.find_all() if cv.type(i) == "rectangle"]
        lines = [i for i in cv.find_all() if cv.type(i) == "line"]
        # 矩形 = 1 个底色 + 选中指令读的寄存器行 + 每个写回方格
        check("画图方格数", stat["cells"] == len(cells), f"{stat['cells']} 个")
        check("画图矩形数", len(rects) == 1 + len(nodes[3]["reads"]) + len(cells),
              f"{len(rects)} 个矩形")
        check("画图游标与行线", len(lines) == 1 + 8, f"{len(lines)} 条线")
        draw_reg_heatmap(cv, [], width=1000, height=420)
        check("空数据不崩", len(cv.find_all()) == 2, f"{len(cv.find_all())} 个图元")
        holder.destroy()
    except Exception as exc:
        print(f"TRACE SELFTEST SKIP 画图（本机开不了 Tk 窗口：{exc}）")

    # 8) 导出网页：能落盘、内容里带得到方格与记录
    OUT.mkdir(parents=True, exist_ok=True)
    page = OUT / "register_heatmap_selftest.html"
    write_trace_html(page, nodes, cap, "HELLO,RV")
    html = page.read_text(encoding="utf-8")
    check("导出网页", page.stat().st_size > 2000 and "rd_we" in html and "id=\"heat\"" in html,
          f"{page.stat().st_size} 字节")

    print("-" * 60)
    print("TRACE SELFTEST " + ("PASS" if bad == 0 else f"FAIL（{bad} 项失败）")
          + f"；产物在 {OUT}")
    return 0 if not bad else 1


def main() -> int:
    argv = sys.argv[1:]
    text = DEFAULT_TEXT
    port = None
    if "--text" in argv:
        text = argv[argv.index("--text") + 1]
    flags = ("--selftest", "--trace-selftest", "--trace", "--guide", "--text", text)
    rest = [a for a in argv if a not in flags]
    if rest:
        port = rest[0]
    if "--guide" in argv:
        print("\n".join(firmware_guide()))
        return 0
    if "--trace-selftest" in argv:
        return trace_selftest()
    if "--selftest" in argv:
        return selftest(text, port)
    if "--trace" in argv:
        # 直接开在提交级数据流窗口：不给串口就显示示例数据，给了就当场抓一枪
        return run_gui(trace=True, trace_text=text, trace_port=port)
    return run_gui()


if __name__ == "__main__":
    raise SystemExit(main())
