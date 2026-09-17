"""Configure, repeat, validate and archive Task 30 captures over CP2102 UART."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from logic_analyzer import decode_spi, decode_uart, parse_raw, write_vcd

MODES = {"static": 0, "counter": 1, "uart": 2, "spi": 3}
TRIGGERS = {"level": 0, "rise": 1, "fall": 2}


def build_packet(mode: int, data: int, pattern_div: int, sample_div: int,
                 trigger_type: int, trigger_mask: int, trigger_value: int,
                 pre: int, post: int) -> bytes:
    values = [0xA5, mode, data, pattern_div & 0xFF, pattern_div >> 8,
              sample_div & 0xFF, sample_div >> 8, trigger_type,
              trigger_mask, trigger_value, pre, post]
    if any(not 0 <= value <= 0xFF for value in values):
        raise ValueError("packet field is outside its encoded width")
    checksum = 0
    for value in values:
        checksum ^= value
    return bytes(values + [checksum])


def default_config(mode: str, data: int) -> dict[str, int]:
    if mode == "uart":
        return dict(mode=2, data=data, pattern_div=433, sample_div=26,
                    trigger_type=2, trigger_mask=1, trigger_value=0, pre=16, post=220)
    if mode == "spi":
        return dict(mode=3, data=data, pattern_div=3, sample_div=0,
                    trigger_type=1, trigger_mask=1, trigger_value=1, pre=4, post=80)
    return dict(mode=MODES[mode], data=data, pattern_div=3, sample_div=0,
                trigger_type=0, trigger_mask=1, trigger_value=data & 1, pre=4, post=4)


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
                 baud: int, timeout: float) -> list[dict[str, int | str]]:
    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required for live MES50HP capture") from exc
    cfg = default_config(mode, value)
    packet = build_packet(**cfg)
    output.mkdir(parents=True, exist_ok=True)
    summaries: list[dict[str, int | str]] = []
    with serial.Serial(port, baudrate=baud, bytesize=8, parity="N", stopbits=1, timeout=0.1) as ser:
        ser.reset_input_buffer()
        synchronize_ready(ser, min(timeout, 3.0))
        for run in range(runs):
            ser.write(packet)
            # 固件在 LA_DONE 之后输出 LA_READY；等到 READY 才允许发送下一包，
            # 防止 UART 回传期间新配置字节覆盖硬件的一字节 RX 邮箱。
            raw_text = read_until(ser, b"LA_READY", timeout)
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
            uart_data, uart_errors = decode_uart(samples, 0, 16)
            spi_data = decode_spi(samples, 0, 1, 2)
            if mode == "static" and any(sample != value for sample in samples):
                raise ValueError(f"capture {run} static loopback mismatch: "
                                 f"expected={value:02x} samples={bytes(samples).hex()}")
            if mode == "counter" and len(set(samples)) < 2:
                raise ValueError(f"capture {run} counter did not change: samples={bytes(samples).hex()}")
            if mode == "uart" and (bytes([value]) not in uart_data or uart_errors):
                raise ValueError(f"capture {run} UART decode mismatch: {uart_data.hex()} errors={uart_errors}")
            if mode == "spi" and bytes([value]) not in spi_data:
                raise ValueError(f"capture {run} SPI decode mismatch: {spi_data.hex()}")
            summaries.append({"run": run, "mode": mode, "value": value,
                              "samples": len(samples), "trigger": trigger,
                              "uart": uart_data.hex(), "uart_errors": uart_errors,
                              "spi": spi_data.hex()})
            print(f"LOGIC ANALYZER BOARD RUN {run + 1}/{runs} PASS mode={mode} samples={len(samples)} trigger={trigger}")
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
    args = parser.parse_args()
    run_captures(args.port, args.output, args.mode, args.value & 0xFF,
                 args.runs, args.baud, args.timeout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
