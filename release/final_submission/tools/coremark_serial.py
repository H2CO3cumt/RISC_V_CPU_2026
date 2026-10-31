"""Start and validate the MES50HP CoreMark image over its CP2102 UART."""
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path

REQUIRED = (
    "[0]crclist       : 0xe714",
    "[0]crcmatrix     : 0x1fd7",
    "[0]crcstate      : 0x8e3a",
    "Correct operation validated.",
    "COREMARK_DONE",
)


def parse_coremark(text: str, clock_hz: int = 50_000_000) -> dict[str, int | str]:
    for marker in REQUIRED:
        if marker not in text:
            raise ValueError(f"missing CoreMark marker: {marker}")
    fields: dict[str, int | str] = {"validation": "PASS"}
    decimal = {
        "ticks": r"Total ticks\s*:\s*(\d+)",
        "iterations": r"Iterations\s*:\s*(\d+)",
        "score_x1000": r"CoreMark score x1000\s*:\s*(\d+)",
        "coremark_per_mhz_x1000": r"CoreMark/MHz x1000\s*:\s*(\d+)",
    }
    for key, pattern in decimal.items():
        match = re.search(pattern, text)
        if not match:
            raise ValueError(f"missing CoreMark field: {key}")
        fields[key] = int(match.group(1))
    perf = re.search(
        r"PERF cycle=([0-9a-fA-F]+) instret=([0-9a-fA-F]+) "
        r"stall=([0-9a-fA-F]+) load=([0-9a-fA-F]+) "
        r"branch=([0-9a-fA-F]+) taken=([0-9a-fA-F]+) flush=([0-9a-fA-F]+)",
        text,
    )
    if not perf:
        raise ValueError("missing PERF counters")
    for key, value in zip(
        ("cycles", "instret", "stalls", "load_stalls", "branches", "taken", "flushes"),
        perf.groups(),
    ):
        fields[key] = int(value, 16)
    ticks = int(fields["ticks"])
    # clock_hz 由 --clock-hz 给出；50 MHz 基线与 80 MHz 高频配置共用同一解析器。
    # 保留 seconds_at_50mhz_x1000 字段以兼容已有消费者。
    fields["clock_hz"] = clock_hz
    fields["seconds_x1000"] = ticks * 1000 // clock_hz
    fields["seconds_at_50mhz_x1000"] = ticks * 1000 // 50_000_000
    fields["cpi_x1000"] = int(fields["cycles"]) * 1000 // int(fields["instret"])
    return fields


def run_board(port: str, output: Path, summary: Path, timeout: float, baud: int,
              clock_hz: int = 50_000_000) -> dict[str, int | str]:
    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required for MES50HP UART validation") from exc
    data = bytearray()
    print("串口 %s @ %d 8N1：每秒发一个 R 启动，最多等 %.0f 秒…" % (port, baud, timeout))
    t0 = time.monotonic()
    deadline = t0 + timeout
    next_start = 0.0
    next_report = t0 + 10.0
    with serial.Serial(port, baudrate=baud, bytesize=8, parity="N", stopbits=1, timeout=0.1) as ser:
        ser.reset_input_buffer()
        while time.monotonic() < deadline:
            now = time.monotonic()
            if now >= next_start:
                ser.write(b"R")
                next_start = now + 1.0
            data.extend(ser.read(4096))
            if b"COREMARK_DONE" in data:
                break
            if now >= next_report:
                print("   已等 %3.0f 秒，收到 %d 字节%s"
                      % (now - t0, len(data),
                         "" if data else "（板子还没反应：位流下了吗？按过复位吗？）"))
                next_report += 10.0
    text = data.decode("ascii", errors="replace")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    if not data:
        # 一字节都没回来：这不是"解析失败"，是板子根本没在跑计分固件
        raise ValueError("板子一个字节都没回（%.0f 秒内）" % timeout)
    try:
        result = parse_coremark(text, clock_hz=clock_hz)
    except ValueError as exc:
        raise ValueError("收到了 %d 字节但不完整（%s）——多半是中途中止或串口被打断"
                         % (len(data), exc)) from exc
    if int(result["seconds_x1000"]) < 10_000:
        raise ValueError("formal CoreMark interval is shorter than 10 seconds")
    summary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print()
    print("=================== CoreMark 跑分结果 ===================")
    print("  串口            : %s" % port)
    print("  时钟            : %d Hz" % clock_hz)
    print("  迭代次数        : %d" % result["iterations"])
    print("  Total ticks     : %d" % result["ticks"])
    print("  真实耗时        : %.3f s" % (int(result["seconds_x1000"]) / 1000.0))
    print("  CoreMark 分数   : %.3f" % (int(result["score_x1000"]) / 1000.0))
    print("  CoreMark/MHz    : %.3f" % (int(result["coremark_per_mhz_x1000"]) / 1000.0))
    print("  官方 CRC        : %s" % result["validation"])
    print("=========================================================")
    print("COREMARK BOARD PASS port=%s clock_hz=%d ticks=%d "
          "seconds=%.3f score_x1000=%d"
          % (port, clock_hz, result["ticks"], int(result["seconds_x1000"]) / 1000.0,
             result["score_x1000"]))
    return result


def _candidate_ports():
    """所有串口，板载 CP210x 排最前（这台机器上有 9 个口，只有一个是板子）。"""
    try:
        from serial.tools import list_ports
    except Exception:
        return []
    rows = []
    for p in list_ports.comports():
        desc = p.description or ""
        u = desc.upper()
        rank = 2 if ("CP210" in u or "SILICON LABS" in u) else (
            1 if ("USB-SERIAL" in u or "CH340" in u or "FTDI" in u) else 0)
        rows.append((-rank, p.device, desc))
    rows.sort()
    return [(dev, desc) for _r, dev, desc in rows]


def _can_open(port, baud):
    """只判断"这个口能不能打开"，不发任何字节。

    为什么不发 `R` 去探测：计分固件**只响应一次启动**，探一下就把机会用掉了，
    真正的跑分反而收不到完整输出。
    """
    try:
        import serial
    except ImportError:
        raise SystemExit("需要 pyserial：py -3 -m pip install pyserial")
    try:
        with serial.Serial(port, baudrate=baud, timeout=0.1):
            return True
    except Exception:
        return False


def pick_port(baud: int) -> str:
    """不指定端口时自动选：CP210x 优先，且必须打得开（被别的程序占着的口直接跳过）。"""
    cands = _candidate_ports()
    if not cands:
        raise SystemExit("一个串口都没找到：插好板载 CP210x 的 USB 数据线（只有充电功能的线不行）")
    print("可用串口：")
    for dev, desc in cands:
        print("   %-6s %s" % (dev, desc))
    for dev, desc in cands:
        if _can_open(dev, baud):
            print("→ 自动选用 %s （%s）" % (dev, desc))
            return dev
        print("   %s 打不开（被别的程序占着？），跳过" % dev)
    raise SystemExit("所有串口都打不开：关掉上位机 / 串口助手 / PDS 串口窗口后再试")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="MES50HP CoreMark 跑分：开串口 → 每秒发 R → 读输出 → 算分并校验官方 CRC。"
                    "不下载位流（位流请自己下好，下载后不要按复位）。")
    parser.add_argument("port", nargs="?", default=None,
                        help="板载 CP210x 串口，例如 COM11；不填则自动寻找")
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--summary", type=Path, default=None)
    parser.add_argument("--timeout", type=float, default=140.0)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--clock-hz", type=int, default=85_000_000,
                        help="CPU 时钟，用来把 ticks 换算成秒；交付配置是 85000000，50 MHz 配置传 50000000")
    args = parser.parse_args()

    port = args.port or pick_port(args.baud)

    # 结果默认另存带时间戳的文件：release/evidence 下那两个是**登记在 claims_map 的规范证据**，
    # 随手跑一次 85 MHz 就把它们覆盖掉，会让材料与证据对不上。
    stamp = time.strftime("%Y%m%d-%H%M%S")
    default_dir = Path("results") / "coremark"
    output = args.output or (default_dir / ("coremark_uart_%s.log" % stamp))
    summary = args.summary or (default_dir / ("coremark_%s.json" % stamp))

    try:
        run_board(port, output, summary, args.timeout, args.baud, args.clock_hz)
    except KeyboardInterrupt:
        print("\n已中止")
        return 130
    except Exception as exc:                    # noqa: BLE001 —— 失败也要讲清楚为什么
        print("\n跑分失败：%s" % exc)
        print("按顺序查这四条：")
        print("  1) 位流是你自己下的那一颗计分位流吗？（不是逻辑分析仪那颗）")
        print("  2) 下载后按过复位吗？按过就重下——计分固件只在刚下载后响应一次 R。")
        print("  3) 串口是不是被别的程序占着？（上位机 / 串口助手 / PDS 串口窗口）")
        print("  4) 上一轮已经跑完的话，也要重新下载位流才能再跑一次。")
        print("原始串口日志：%s" % output)
        return 1

    print("\n跑分成功。结果文件：")
    print("  串口原始日志 : %s" % output)
    print("  结果 JSON    : %s" % summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
