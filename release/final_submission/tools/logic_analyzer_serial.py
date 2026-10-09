"""Configure, repeat, validate and archive Task 30 captures over CP2102 UART."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from logic_analyzer import decode_spi, decode_uart, parse_raw, write_vcd, write_waveform_page

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
        # [2026-09-30 修] pre 16 -> 64、post 220 -> 191（窗口仍 240 个采样点，没超 Raw 上限）。
        # 原因：pattern_div=433 / sample_div=26 => 每比特 16.65 个采样点，一帧 10 bit = 166.5 点。
        # 旧窗口（pre=16/post=220）只给"帧起始位"留 237-166.5 = 70.5 点的余量，一旦触发沿落在
        # 数据位内部，整帧就装不进窗口 => 解码失败，**而波形本身完全正确**。
        # 这个隐患在 50/80 MHz 上碰巧不发作，在 85 MHz PLL 变体上暴露了。
        # 现在把窗口前移，帧起始位必被框住，各频率都能稳定解码。
        return dict(mode=2, data=data, pattern_div=433, sample_div=26,
                    trigger_type=2, trigger_mask=1, trigger_value=0, pre=64, post=191)
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
                 baud: int, timeout: float,
                 pre: int | None = None, post: int | None = None,
                 on_run=None) -> list[dict[str, int | str]]:
    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required for live MES50HP capture") from exc
    cfg = default_config(mode, value)
    # [2026-09-30 新增] 允许命令行覆盖 pre/post（不传就是各模式既有值，行为不变）。
    # 为什么需要：UART 模式 pattern_div=433 / sample_div=26 => 每比特 433/26 = 16.65 个
    # 采样点，一帧 10 bit 占 166.5 个采样点，而 Raw 深度上限只有 256。
    # 默认 pre=16/post=220（窗口 237）只给"帧起始位"留了 237-166.5 = 70.5 个采样点的余量；
    # 一旦触发沿落在数据位内部（85 MHz PLL 变体正是如此，窗口比 50 MHz 晚 32 个采样点），
    # 整帧就装不进窗口，解码必然失败——而波形本身完全正确。
    # 把 pre 提到 64 让窗口前移，就能把起始位框进来。
    if pre is not None:
        cfg["pre"] = pre
    if post is not None:
        cfg["post"] = post
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
            # [2026-10-03 新增] 同步生成自包含波形页：pyUI 采完不必再手动拖 .vcd，
            # 直接双击这个 .html 就能用浏览器看（与零依赖采集器产物一致）。
            write_waveform_page(
                [{"name": f"{mode} 模式 第{run + 1}次", "samples": samples, "trigger": trigger,
                  "note": f"mode={mode} samples={len(samples)} trigger={trigger}"}],
                output / f"{stem}.html",
            )
            # [2026-10-03 新增] 把这一轮立刻交给调用方（pyUI 的实时波形面板）。
            # 放在协议校验**之前**：校验失败时更需要对着一张真实波形排错，
            # 而不是等抛异常后什么都看不到。
            if on_run is not None:
                on_run(samples, trigger, {"mode": mode, "run": run, "runs": runs,
                                          "log": str(output / f"{stem}.log"),
                                          "vcd": str(output / f"{stem}.vcd")})
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
    # [2026-09-30] 可选覆盖采集窗口；不传即沿用各模式既有值。
    parser.add_argument("--pre", type=int, default=None,
                        help="trigger 之前的采样点数（默认取模式配置）")
    parser.add_argument("--post", type=int, default=None,
                        help="trigger 之后的采样点数（默认取模式配置）")
    args = parser.parse_args()
    run_captures(args.port, args.output, args.mode, args.value & 0xFF,
                 args.runs, args.baud, args.timeout, args.pre, args.post)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
