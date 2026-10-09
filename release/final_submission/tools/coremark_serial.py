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
    deadline = time.monotonic() + timeout
    next_start = 0.0
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
    text = data.decode("ascii", errors="replace")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    result = parse_coremark(text, clock_hz=clock_hz)
    if int(result["seconds_x1000"]) < 10_000:
        raise ValueError("formal CoreMark interval is shorter than 10 seconds")
    summary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"COREMARK BOARD PASS port={port} clock_hz={clock_hz} ticks={result['ticks']} "
          f"seconds={int(result['seconds_x1000'])/1000:.3f} score_x1000={result['score_x1000']}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("--output", type=Path, default=Path("release/evidence/coremark_uart.log"))
    parser.add_argument("--summary", type=Path, default=Path("release/evidence/coremark_board.json"))
    parser.add_argument("--timeout", type=float, default=140.0)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--clock-hz", type=int, default=50_000_000,
                        help="CPU 时钟频率，用于把 ticks 换算成秒（80 MHz 配置传 80000000）")
    args = parser.parse_args()
    run_board(args.port, args.output, args.summary, args.timeout, args.baud, args.clock_hz)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
