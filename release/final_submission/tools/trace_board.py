"""板级「提交级 trace」抓取与可视化（COM11 → 单页 HTML）。

分工（与既有的逻辑分析仪上位机完全一致）：
  · 串口分帧只用一个实现：``build_trace_packet`` 生成 4 字节命令；
  · 回包解析与判据只用一个实现：``trace_view.parse_capture`` / ``trace_view.judge``；
  · 本模块只负责"跟板子说话 + 落盘"，不另写一份解析或判据。

时序纪律（和镜像模式同一条）：
  固件 Arm 生效后会先打印 ``TRACE_ARMED``，**必须等到这一行**才发字符串。
  提前发的话，字符串会在 arm 之前到达，窗口从报文中间开始，而页面依旧
  "看起来有一堆指令"——这正是最难查的一类假通过。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import trace_view as tv  # noqa: E402
from logic_analyzer_serial import read_until, synchronize_ready  # noqa: E402

# 0xAB 回包里波形块的头：window/div 是 2026-10-24 新加的两个字段，
# 老固件（没有这两项）也能解析，所以它们是可选的捕获组。
_LA_HEAD_RE = re.compile(
    r"LA RAW count=([0-9A-Fa-f]+)\s+trigger=([0-9A-Fa-f]+)"
    r"(?:\s+window=([0-9A-Fa-f]+)\s+div=([0-9A-Fa-f]+))?")
_HEX_RE = re.compile(r"[0-9A-Fa-f]{1,8}")

TRACE_CMD = 0xAA
WAVE_CMD = 0xAB
TRACE_MAX_CHARS = 32
TRACE_PHASES = (0, 1)
# 0xAB 的波形窗口档 → 后触发样本数。必须与固件 trace_and_wave() 的 post 计算一致：
# 0/1/2 → 256/512/1024，3 → 2047（+1 个触发样本 = 2048，即整块缓冲）。
WAVE_WINDOWS = {0: 256, 1: 512, 2: 1024, 3: 2048}
DEFAULT_PORT = "COM11"
DEFAULT_BAUD = 115200


def build_trace_packet(n_chars: int, phase: int) -> bytes:
    """0xAA 4 字节命令：[0]=cmd [1]=字符数 [2]=阶段 [3]=XOR([1..2])。

    阶段：0 = 只记处理过程（大写化）、1 = 连串口轮询一起记。
    """
    if not 1 <= n_chars <= TRACE_MAX_CHARS:
        raise ValueError("字符数必须在 1..%d，收到 %r" % (TRACE_MAX_CHARS, n_chars))
    if phase not in TRACE_PHASES:
        raise ValueError("阶段只能是 %r，收到 %r" % (list(TRACE_PHASES), phase))
    return bytes([TRACE_CMD, n_chars & 0xFF, phase & 0xFF,
                  (TRACE_CMD ^ (n_chars & 0xFF) ^ (phase & 0xFF)) & 0xFF])


def run_trace(port: str = DEFAULT_PORT, baud: int = DEFAULT_BAUD, text: str = "hello,rv",
              phase: int = 0, timeout: float = 180.0, ser=None):
    """在板上跑一次 trace 抓取，返回 (回包字节, 解析结果)。

    ``ser`` 允许测试注入一个假串口；不给就按 port/baud 真开一个。
    """
    payload = text.encode("ascii")
    if not payload:
        raise ValueError("字符串不能为空")
    packet = build_trace_packet(len(payload), phase)

    own = ser is None
    if own:
        try:
            import serial
        except ImportError as exc:  # pragma: no cover - 只在缺依赖时触发
            raise SystemExit("需要 pyserial 才能连板子") from exc
        ser = serial.Serial(port, baud, timeout=0.05)
    try:
        # 先吃掉上电/上一轮残留的 LA_READY，避免把旧回包当成这一枪
        synchronize_ready(ser, min(timeout, 5.0))
        ser.write(packet)
        ser.flush()
        armed = read_until(ser, b"TRACE_ARMED", timeout)
        if b"TRACE_ARMED" not in armed:
            raise TimeoutError("固件没有回 TRACE_ARMED：%r" % armed[-160:])
        # 只有确认 Arm 生效之后才发字符串
        ser.write(payload)
        ser.flush()
        body = read_until(ser, b"TRACE_DONE", timeout)
    finally:
        if own:
            ser.close()
    raw = armed + body
    text_out = raw.decode("utf-8", errors="replace")
    return raw, tv.parse_capture(text_out)


def build_wave_packet(n_chars: int, window: int = 1) -> bytes:
    """0xAB 4 字节命令：[0]=cmd [1]=字符数 [2]=波形窗口档 [3]=XOR([1..2])。

    窗口档见 ``WAVE_WINDOWS``；档 1（512 个后触发样本）默认够覆盖一次处理循环。
    """
    if not 1 <= n_chars <= TRACE_MAX_CHARS:
        raise ValueError("字符数必须在 1..%d，收到 %r" % (TRACE_MAX_CHARS, n_chars))
    if window not in WAVE_WINDOWS:
        raise ValueError("窗口档只能是 %r，收到 %r" % (sorted(WAVE_WINDOWS), window))
    return bytes([WAVE_CMD, n_chars & 0xFF, window & 0xFF,
                  (WAVE_CMD ^ (n_chars & 0xFF) ^ (window & 0xFF)) & 0xFF])


def run_wave(port: str = DEFAULT_PORT, baud: int = DEFAULT_BAUD, text: str = "hello,rv",
             window: int = 1, timeout: float = 240.0, ser=None):
    """在板上跑一次"波形 + 指令流"组合抓取（0xAB），返回 (回包字节, 解析结果)。

    与 0xAA 的时序差别：**这条命令没有 ARMED 握手**——固件收完 4 字节命令后立刻
    阻塞等那 n 个字符（收字符发生在两个窗口打开之前），所以命令与字符要一次发出去。
    """
    payload = text.encode("ascii")
    if not payload:
        raise ValueError("字符串不能为空")
    packet = build_wave_packet(len(payload), window)

    own = ser is None
    if own:
        try:
            import serial
        except ImportError as exc:  # pragma: no cover
            raise SystemExit("需要 pyserial 才能连板子") from exc
        ser = serial.Serial(port, baud, timeout=0.05)
    try:
        synchronize_ready(ser, min(timeout, 5.0))
        ser.write(packet + payload)
        ser.flush()
        body = read_until(ser, b"TRACE_DONE", timeout)
    finally:
        if own:
            ser.close()
    text_out = body.decode("utf-8", errors="replace")
    return body, parse_wave_response(text_out)


def parse_wave_response(text: str) -> dict:
    """把 0xAB 的回包切成两块：``wave``（每拍波形）+ ``capture``（提交级 trace）。

    波形块头部：``LA RAW count=<n> trigger=<idx> window=<n> div=<d>``，
    随后每样本 8 位十六进制。指令流块交给 ``trace_view.parse_capture``——
    它的字段与 0xAA 的回包逐字段相同，所以只有一份解析实现。
    """
    head = text.find("LA RAW")
    trace_at = text.find("TRACE RAW")
    if head < 0 or trace_at < 0 or trace_at <= head:
        raise ValueError("回包里没有 LA RAW / TRACE RAW 两块：%r" % text[:160])
    la_text = text[head:trace_at]
    m = _LA_HEAD_RE.search(la_text)
    if not m:
        raise ValueError("LA RAW 头格式不对：%r" % la_text.splitlines()[0][:120])
    samples = [int(tok, 16) & 0xFF
               for tok in la_text[m.end():].split()
               if _HEX_RE.fullmatch(tok)]
    capture = tv.parse_capture(text[trace_at:])
    return {"wave": {"count": int(m.group(1), 16), "trigger": int(m.group(2), 16),
                     "window": int(m.group(3), 16) if m.group(3) else len(samples),
                     "div": int(m.group(4), 16) if m.group(4) else 1,
                     "samples": samples},
            "capture": capture}


def capture_wave(out_dir, text: str, window: int, res: dict, mem_hint: str, raw: bytes) -> dict:
    """0xAB 组合采集落盘：原始回包 + 判据/对齐 JSON + 单页 HTML + 摘要。

    与 ``capture_and_page`` 的分工一致：**解析与判据只有一份实现**
    （``trace_view.parse_capture`` / ``judge`` / ``judge_wave`` / ``align_wave``），
    这里只负责把同一份数据写成三个产物。
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    log_path = out_dir / "trace_wave.log"
    html_path = out_dir / "trace_wave.html"
    json_path = out_dir / "trace_wave.json"
    log_path.write_bytes(raw)

    capture = res["capture"]
    wave = res["wave"]
    imem = None
    mem_path = Path(mem_hint)
    if mem_path.exists():
        imem = tv.load_program_mem(mem_path)
    base = tv.judge(capture, text, 0, imem, depth=4096)
    flow = tv.build_flow(capture, imem)
    align = tv.align_wave(capture, wave, flow["nodes"])
    results = base + tv.judge_wave(capture, wave, flow["nodes"])
    summary = summarise(capture, flow, text)
    payload = tv.page_payload(capture, flow, text, 0,
                              {"log": str(log_path), "mem": mem_hint, "summary": summary,
                               "judgements": [{"name": n, "ok": ok, "detail": d}
                                              for n, ok, d in results],
                               "wave": {"cycles": align["cycles"], "div": align["div"],
                                        "offset": align["offset"],
                                        "retire_pulses": align["retire_pulses"],
                                        "data_pulses": align["data_pulses"],
                                        "data_records": align["data_records"],
                                        "mismatch": align["mismatch"]}})
    tv.write_trace_page(html_path, payload)
    json_path.write_text(json.dumps({
        "judgements": payload["meta"]["judgements"],
        "count": capture["count"], "marks": capture["mark_count"],
        "status": capture["status"], "text": capture["text"],
        "wave": {"count": wave["count"], "trigger": wave["trigger"],
                 "window": wave["window"], "div": wave["div"],
                 "retire_pulses": align["retire_pulses"],
                 "data_pulses": align["data_pulses"]},
        "align": {k: align[k] for k in ("offset", "anchor", "delta", "tied", "ambiguous",
                                        "trace_arm", "cycles", "retire_pulses",
                                        "data_pulses", "data_records", "mismatch")},
        "summary": summary,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"log": log_path, "html": html_path, "json": json_path, "summary": summary,
            "judgements": results, "pass": tv.judgements_pass(results), "align": align}


def summarise(capture, flow, text) -> dict:
    """把一窗 trace 压成可以写进报告的几个数字。

    只用节点里已经算好的 pc / 助记符，不另做统计口径——
    页面上的热点和这里的热点必然一致。

    · ``hotspots``：按 (pc, 助记符) 聚合，回答"这窗里 CPU 到底在重复什么"；
    · ``chars``：阶段 0 时每个字符对应多少条提交（拿 marks 的间隔算）；
    · ``polling_share``：前 4 个热点占整窗的比例，用来量化"空转占了窗口多少"。
    """
    nodes = flow["nodes"]
    counter = {}
    for n in nodes:
        key = (n["pc"], n["asm"])
        counter[key] = counter.get(key, 0) + 1
    ordered = sorted(counter.items(), key=lambda kv: -kv[1])
    hotspots = [{"pc": pc, "asm": asm, "count": c,
                 "share": (c / len(nodes)) if nodes else 0.0} for (pc, asm), c in ordered[:8]]
    top4 = sum(item["count"] for item in hotspots[:4])
    spans = []
    marks = capture["marks"]
    for i in range(1, len(marks)):
        spans.append(marks[i]["index"] - marks[i - 1]["index"])
    return {
        "records": len(nodes),
        "distinct_pc": len(counter),
        "hotspots": hotspots,
        "top4_share": (top4 / len(nodes)) if nodes else 0.0,
        "chars": len(marks),
        "marks": [m["index"] for m in marks],
        "instructions_per_char": spans,
        "sent": text,
    }


def capture_and_page(out_dir: Path, text: str, phase: int, capture, mem_hint: str) -> dict:
    """落盘：原始回包 + 解析后的 JSON + 单页 HTML + 摘要。四个产物同源。"""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    tag = "phase%d" % phase
    log_path = out_dir / ("trace_%s.log" % tag)
    html_path = out_dir / ("trace_%s.html" % tag)
    json_path = out_dir / ("trace_%s.json" % tag)

    imem = None
    mem_path = Path(mem_hint)
    if mem_path.exists():
        imem = tv.load_program_mem(mem_path)
    results = tv.judge(capture, text, phase, imem, depth=4096)
    flow = tv.build_flow(capture, imem)
    summary = summarise(capture, flow, text)
    payload = tv.page_payload(capture, flow, text, phase,
                              {"log": str(log_path), "mem": mem_hint, "summary": summary,
                               "judgements": [{"name": n, "ok": ok, "detail": d} for n, ok, d in results]})
    tv.write_trace_page(html_path, payload)
    json_path.write_text(json.dumps({"judgements": payload["meta"]["judgements"],
                                     "count": capture["count"], "marks": capture["mark_count"],
                                     "status": capture["status"], "text": capture["text"],
                                     "summary": summary},
                                    ensure_ascii=False, indent=2), encoding="utf-8")
    return {"log": log_path, "html": html_path, "json": json_path, "summary": summary,
            "judgements": results, "pass": tv.judgements_pass(results)}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="从 MES50HP 抓取提交级 trace 并生成单页可视化")
    ap.add_argument("--port", default=DEFAULT_PORT)
    ap.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    ap.add_argument("--text", default="hello,rv", help="要 CPU 处理的字符串（<=32 字符）")
    ap.add_argument("--phase", type=int, default=0, choices=list(TRACE_PHASES),
                    help="0=只记处理过程 1=连串口轮询一起记")
    ap.add_argument("--outdir", default="results/trace85_board")
    ap.add_argument("--mem", default="fpga/trace85/rtl/logic_analyzer_program.mem")
    ap.add_argument("--timeout", type=float, default=180.0)
    args = ap.parse_args(argv)

    raw, capture = run_trace(args.port, args.baud, args.text, args.phase, args.timeout)
    out = capture_and_page(Path(args.outdir), args.text, args.phase, capture, args.mem)
    out["log"].write_bytes(raw)
    print(tv.judge_text(out["judgements"]))
    print("TRACE BOARD count=%d marks=%d status=0x%X" % (capture["count"], capture["mark_count"], capture["status"]))
    s = out["summary"]
    print("TRACE BOARD SUMMARY records=%d distinct_pc=%d top4_share=%.2f%% per_char=%r"
          % (s["records"], s["distinct_pc"], 100.0 * s["top4_share"], s["instructions_per_char"]))
    for h in s["hotspots"][:4]:
        print("TRACE BOARD HOT   pc=0x%03X n=%4d %5.1f%%  %s"
              % (h["pc"], h["count"], 100.0 * h["share"], h["asm"]))
    print("TRACE BOARD LOG  %s" % out["log"])
    print("TRACE BOARD PAGE %s" % out["html"])
    print("TRACE BOARD %s" % ("PASS" if out["pass"] else "FAIL"))
    return 0 if out["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
