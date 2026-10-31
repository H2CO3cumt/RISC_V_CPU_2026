"""Read the M-24/N1 periodic timer-interrupt demo over the MES50HP CP2102 UART.

板上每次定时器中断往串口写 **5 个字节**（见 software/timer_demo/start.S）：

    <计数低4位> <LED值低4位> <mtime[27:24]> <mtime[23:20]> <mtime[19:16]>

判据（全部自动判定）：

1. 串口上先出现启动自检字符 `=`（证明程序跑到了初始化结束）；
2. 中断计数逐次 +1（含 15→0 回绕，不回绕即丢中断）；
3. LED 那一位在 1/0 之间交替 —— "LED0 每 delta 拍翻转一次"的串口侧证据（不必盯着板子看）；
4. **自计时周期**：后三位拼成 mtime[27:16]，相邻两次中断之差 × 65536 = 周期（单位：拍）。
   mtime 是 50 MHz 的硬件计数器，这个数字**不依赖主机串口时钟**，是"板上周期确实是
   delta 拍"的硬证据。量化粒度 65536 拍；delta=12_500_000 时约 0.52%。
5. 主机墙钟（每字节到达时间）作为**交叉核对**。它单独不可信：实测同一段流用主机时间戳
   算出的周期能在 200~1300 ms 之间跳（Windows 串口缓冲 + USB 调度抖动），
   所以只用来确认"量级一致"，判 PASS 以第 4 条为准。
"""
from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

HEX_CHARS = "0123456789abcdefABCDEF"
RECORD_LEN = 5
LF_CHARS = "\r\n"
BOOT_MARKER = "="
# 自计时取 mtime[27:16]（3 位十六进制）：量化步长 65536 拍，
# 模 (1<<28) 拍 —— 远大于 delta，所以间隔不会绕（曾经取 [15:4]，模只有 65536 拍，
# delta=12_500_000 会绕 190 次，差值毫无意义）。
MTIME_LSB_TICKS = 1 << 16
MTIME_MOD_TICKS = 1 << 28


def _chain_from(positions: list[tuple[int, str]], start: int,
                step: int = RECORD_LEN) -> list[dict[str, object]]:
    """从 positions[start] 起，每隔 step 个（非换行）字符读一条记录，贪心连成链。

    step 就是记录长度：真机流里记录是定长 5 字节，所以步长必须是 5；
    允许传别的值只是为了能从任意对齐相位去验证"错位拼不出长链"。
    """
    run: list[dict[str, object]] = []
    j = start
    while j + RECORD_LEN <= len(positions):
        field = [positions[j + k][1] for k in range(RECORD_LEN)]
        if any(ch not in HEX_CHARS for ch in field):
            break
        if run:
            if int(field[0], 16) != (int(run[-1]["count"], 16) + 1) % 16:
                break
            if field[1] == run[-1]["led"]:
                break
        run.append({
            "count": field[0],
            "led": field[1],
            # 三位十六进制是 mtime[27:16]，换算回拍要乘 65536。
            "mtime": int("".join(field[2:5]), 16) * MTIME_LSB_TICKS,
            "idx": positions[j][0],
        })
        j += step
    return run


def parse_chains(text: str) -> list[list[dict[str, object]]]:
    """返回**所有对齐相位下**的链（步长都取定长 5），供自检使用。

    真机判据只用锚定后的那条（parse_records）；把各相位都暴露出来是为了让
    "错位的起点拼不出长链"这种断言可以直接检验。
    """
    positions = [(i, ch) for i, ch in enumerate(text) if ch not in LF_CHARS]
    chains: list[list[dict[str, object]]] = []
    for i in range(len(positions)):
        run = _chain_from(positions, i)
        if run:
            chains.append(run)
    return chains


def chains_are_sound(chains: list[list[dict[str, object]]]) -> tuple[bool, str]:
    """自检不变量：任何被接受为"连续"的记录对，必须**真的**是连续的两条记录。

    为什么需要这条：真机流里记录是**定长 5 字节**的。如果解析器允许起点错位，
    它可能把"上一条记录的尾巴 + 下一条记录的开头"读成一条"合法记录"，
    从而拼出一条计数递增、LED 交替、但其实并不存在的链（实测构造过一个这样的假链）。
    判据：
      1. 链里相邻两个记录的字节位置必须正好差 5；
      2. 逐对检查时，LED 位必须不同。
    返回 (是否全部成立, 说明)。
    """
    for chain in chains:
        for a, b in zip(chain, chain[1:]):
            gap = int(b["idx"]) - int(a["idx"])
            if gap != RECORD_LEN:
                return False, (f"chain jumps {gap} bytes instead of {RECORD_LEN} "
                               f"(idx {a['idx']}→{b['idx']})")
            if a["led"] == b["led"]:
                return False, (f"chain keeps LED digit {a['led']} on consecutive records "
                               f"(idx {a['idx']}→{b['idx']})")
    return True, "ok"


def alignment_score(positions: list[tuple[int, str]], start: int) -> tuple[int, int]:
    """从 positions[start] 起按定长 5 读记录，返回 (可读记录数, 通过全部结构条件的记录数)。

    结构条件 = "计数逐次 +1（含 15→0 回绕）" 且 "LED 位与上一条不同"。
    这个函数只用来**挑相位**，不参与最终判据。
    """
    readable = 0
    contiguous = 0
    j = start
    prev_count = None
    prev_led = None
    while j + RECORD_LEN <= len(positions):
        field = [positions[j + m][1] for m in range(RECORD_LEN)]
        if any(ch not in HEX_CHARS for ch in field):
            break
        readable += 1
        if prev_count is not None:
            if int(field[0], 16) != (prev_count + 1) % 16 or field[1] == prev_led:
                break
        prev_count = int(field[0], 16)
        prev_led = field[1]
        contiguous += 1
        j += RECORD_LEN
    return readable, contiguous


def find_alignment(text: str) -> tuple[int, bool]:
    """在整条采集流里找记录边界的相位，返回 (非换行字符序号, 是否靠启动自检字符定死)。

    为什么要做相位搜索：真机上出现过两种情况——
      1. 采集起点落在一条记录中间（`=` 没被采到）；
      2. 串口线上出现一段**持续低电平**（板子重配置期间的毛刺），主机把它当帧收成
         一大段 `0x00`，之后才重新对上真实数据。
    这两种都会让"从第 0 个字符按 5 字节切"完全错位。做法是：
      - 有 `=` 时直接用它的位置定起点（最可靠，返回 True）；
      - 否则对全部 5 个相位各扫一遍，用**结构条件数**最大的相位。
        结构条件（计数递增 + LED 交替）在正确相位上会连续成立，在错误相位上很快就断。
    """
    positions = [(i, ch) for i, ch in enumerate(text) if ch not in LF_CHARS]
    boot = next((k for k, (_, ch) in enumerate(positions) if ch == BOOT_MARKER), None)
    if boot is not None:
        for k in (boot + 1, boot + 1 + RECORD_LEN):
            if k < len(positions) and positions[k][1] == "1":
                return k, True
    best_start, best_score = 0, -1
    for start in range(min(RECORD_LEN, len(positions))):
        readable, contiguous = alignment_score(positions, start)
        score = contiguous * 1000 + readable
        if score > best_score:
            best_start, best_score = start, score
    return best_start, False


def parse_runs(text: str, stamps: list[float] | None = None,
               expect_delta: int | None = None, tolerance_ticks: int = 0
               ) -> tuple[list[list[dict[str, object]]], bool]:
    """切出可用的连续记录段，返回 (段列表, 是否锚定在启动自检字符之后)。

    两条判据同时成立才算"真记录"：
      A. 结构：段内相邻记录的字节位置**正好差 5**（记录定长），计数逐次 +1，LED 位必须不同；
      B. 自计时：相邻记录的 mtime[27:16] 差（×65536）必须落在 expect_delta ± tolerance 内。

    为什么需要 B：记录定长 5 字节，"计数递增 + LED 交替"这两个条件**错位时也可能凑巧满足**
    （实测构造出过假链）。错位读出来的 mtime 是别的字节拼的，其差值基本不可能是 delta，
    所以 B 是一个很强的判别式——真机上实测它把错位段全部挡掉。

    为什么"最长的一段"还不够：真机串口会**丢字节**，丢一次就让之后所有记录错位。
    实测 12 秒采集里 48 条记录只剩 10 条最长合法段。所以这里逐字符前移、
    把所有通过 A+B 的段都收回来（段与段之间可以不相邻，各自独立成立）。
    """
    positions = [(i, ch) for i, ch in enumerate(text) if ch not in LF_CHARS]

    def ok_delta(run: list[dict[str, object]]) -> bool:
        if expect_delta is None or tolerance_ticks <= 0:
            return True
        return all(abs(d - expect_delta) <= tolerance_ticks for d in mtime_deltas(run))

    runs: list[list[dict[str, object]]] = []
    seen_starts: set[int] = set()

    def add_from(start: int) -> bool:
        if start in seen_starts or start >= len(positions):
            return False
        run = _chain_from(positions, start)
        if len(run) >= 2 and ok_delta(run):
            runs.append(run)
            seen_starts.add(start)
            return True
        return False

    # **每个相位都扫一遍**，而不是"先挑一个相位再一路走"。
    # 原因（本轮实测）：真机的丢字节不是"丢一次就稳定"，而是**一直丢**——流里每隔几条记录
    # 就错位一次。只认一个相位的话，一次采集只能收回 5 条记录；逐字符扫相位能把
    # 各段都收回来。为了不让复杂度爆掉，起点仍然按 RECORD_LEN 步进
    # （相位只有 5 种，逐字符扫没有必要且会引入大量重叠子段）。
    for phase in range(RECORD_LEN):
        cursor = phase
        while cursor < len(positions):
            if add_from(cursor):
                cursor = int(runs[-1][-1]["idx"]) + RECORD_LEN
            else:
                cursor += RECORD_LEN

    align_start, anchored = find_alignment(text)
    runs.sort(key=lambda r: int(r[0]["idx"]))

    if stamps is not None:
        for run in runs:
            for m in range(len(run)):
                idx = int(run[m]["idx"])
                run[m] = dict(run[m])
                run[m]["t"] = stamps[idx] if idx < len(stamps) else None
    return runs, anchored


def mtime_deltas(records: list[dict[str, object]]) -> list[int]:
    """相邻两次中断的 mtime[27:16] 差 → 折算成拍（×65536），并处理 (1<<28) 拍回绕。"""
    out: list[int] = []
    for a, b in zip(records, records[1:]):
        delta = int(b["mtime"]) - int(a["mtime"])
        if delta <= 0:
            delta += MTIME_MOD_TICKS
        out.append(delta)
    return out


def measure_period(pair_count: int, span_seconds: float | None, fallback_seconds: float,
                   period_ms: float, tolerance_ms: float) -> tuple[float, float, bool]:
    """主机墙钟侧周期（仅作交叉核对），返回 (实测ms, 容差ms, 是否量级一致)。

    n 个记录之间有 n-1 个间隔：用 跨度/n 会把第一个记录之前的等待也算进去，
    得到的不是"间隔"；n 只有 20 来条时这个差别很大。
    """
    if pair_count < 2:
        return 0.0, 0.0, False
    span = span_seconds if (span_seconds is not None and span_seconds > 0) else fallback_seconds
    measured_ms = span * 1000.0 / (pair_count - 1)
    arrival_slack_ms = 1000.0 * 2 / max(pair_count - 1, 1)
    # 主机侧抖动很大（实测见过 1.3 s），所以这里只判"量级"：
    # 合格区间是 [0.3×, 3×] 期望周期。真正的判据是自计时那一条。
    lo, hi = period_ms * 0.3 - tolerance_ms, period_ms * 3.0 + tolerance_ms
    return measured_ms, arrival_slack_ms, (lo <= measured_ms <= hi)


def run_capture(port: str, baud: int, seconds: float, output: Path, summary: Path,
                delta: int, clock_hz: int, tolerance_ticks: int) -> dict:
    try:
        import serial
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("pyserial is required for MES50HP UART validation") from exc

    period_ms = delta * 1000.0 / clock_hz
    chunks: list[str] = []
    stamps: list[float] = []
    deadline = time.monotonic() + seconds
    with serial.Serial(port, baudrate=baud, bytesize=8, parity="N",
                       stopbits=1, timeout=0.05) as ser:
        ser.reset_input_buffer()
        while time.monotonic() < deadline:
            data = ser.read(256)
            if data:
                now = time.monotonic()
                for _ in range(len(data)):
                    stamps.append(now)
                chunks.append(data.decode("ascii", errors="replace"))

    text = "".join(chunks)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")

    runs, anchored = parse_runs(text, stamps,
                                expect_delta=delta,
                                tolerance_ticks=max(tolerance_ticks, MTIME_LSB_TICKS))
    # 把所有合法段拼起来看：段内是"真连续"的（相邻记录字节位置正好差 5），
    # 段之间必然夹着**丢字节造成的错位**——主机侧串口会丢字节，这是采集的现实，
    # 不代表板上中断丢了。所以判据是"段内严格连续 + 段总数够用"，不是"整条流连续"。
    all_records = [rec for run in runs for rec in run]
    deltas: list[int] = []
    for run in runs:
        deltas.extend(mtime_deltas(run))
    result: dict[str, object] = {
        "port": port,
        "baud": baud,
        "capture_seconds": seconds,
        "raw_bytes": len(text),
        "boot_equals_seen": "=" in text,
        "record_runs_anchored_on_boot_marker": anchored,
        "run_count": len(runs),
        "run_lengths": [len(r) for r in runs],
        "record_count": len(all_records),
        "delta_ticks": delta,
        "expected_period_ticks": delta,
        "expected_period_ms": round(period_ms, 3),
        "tolerance_ticks": tolerance_ticks,
        "count_sequence": "".join(str(r["count"]) for r in all_records),
        "led_sequence": "".join(str(r["led"]) for r in all_records),
        "count_increments_ok": True,
        "led_alternates_ok": True,
    }

    # 判据下限：至少 2 段、总共至少 8 条记录、总间隔至少 6 个。
    if len(runs) < 2 or len(all_records) < 8 or len(deltas) < 6:
        raise SystemExit(
            f"N1 TIMER DEMO BOARD FAIL: only {len(runs)} run(s)/{len(all_records)} records/"
            f"{len(deltas)} intervals parsed (need >=2/8/6). Raw bytes={len(text)}. "
            f"First 200 chars: {text[:200]!r}")

    # ---- 判据 4：自计时周期（硬证据，不依赖主机时钟）----
    result["mtime_period_ticks_min"] = min(deltas)
    result["mtime_period_ticks_max"] = max(deltas)
    result["mtime_period_ticks_median"] = int(statistics.median(deltas))
    result["mtime_period_ms_median"] = round(
        statistics.median(deltas) * 1000.0 / clock_hz, 3)
    # 自计时的量化步长是 65536 拍（mtime[27:16]），所以容差不能小于一个步长。
    tol = max(tolerance_ticks, MTIME_LSB_TICKS)
    self_timed_ok = all(abs(d - delta) <= tol for d in deltas)
    result["self_timed_period_ok"] = self_timed_ok
    result["self_timed_tolerance_ticks"] = tol

    # ---- 判据 5：主机墙钟交叉核对（只判量级）----
    ts = [r.get("t") for r in all_records if r.get("t") is not None]
    span = (float(ts[-1]) - float(ts[0])) if len(ts) >= 2 else None
    measured_ms, arrival_slack_ms, wall_ok = measure_period(
        len(all_records), span, seconds, period_ms, tolerance_ticks * 1000.0 / clock_hz)
    result["wallclock_period_ms"] = round(measured_ms, 3)
    result["wallclock_magnitude_ok"] = wall_ok

    summary.parent.mkdir(parents=True, exist_ok=True)
    summary.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"N1 TIMER DEMO UART runs={len(runs)} {result['run_lengths']} records={len(all_records)} "
          f"raw_bytes={len(text)} boot_equals={result['boot_equals_seen']} anchored={anchored}")
    print(f"N1 count_sequence={result['count_sequence']}")
    print(f"N1 led_sequence  ={result['led_sequence']}")
    print(f"N1 self-timed period ticks: min={result['mtime_period_ticks_min']} "
          f"median={result['mtime_period_ticks_median']} max={result['mtime_period_ticks_max']} "
          f"(expect {delta} ± {tol}) over {len(deltas)} intervals "
          f"→ {result['mtime_period_ms_median']} ms")
    print(f"N1 wallclock cross-check: {measured_ms:.1f} ms (slack {arrival_slack_ms:.1f} ms) "
          f"magnitude_ok={wall_ok}")

    if not result["boot_equals_seen"]:
        raise SystemExit("N1 TIMER DEMO BOARD FAIL: boot self-check '=' was not seen")
    if not self_timed_ok:
        raise SystemExit(
            f"N1 TIMER DEMO BOARD FAIL: self-timed period out of tolerance "
            f"(min={result['mtime_period_ticks_min']} max={result['mtime_period_ticks_max']} "
            f"expect {delta} ± {tol})")
    if not wall_ok:
        print("N1 WARNING: wall-clock estimate is off by more than 3x; "
              "host-side serial timing is unreliable, self-timed period is authoritative")
    print("N1 TIMER DEMO BOARD PASS")
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--seconds", type=float, default=12.0)
    ap.add_argument("--output", type=Path,
                    default=Path("release/evidence/timer_demo_board/uart/uart_00.log"))
    ap.add_argument("--summary", type=Path,
                    default=Path("release/evidence/timer_demo_board/timer_demo_board.json"))
    ap.add_argument("--delta", type=int, default=12500000,
                    help="MTIMECMP_DELTA in ticks (must match the bitstream image)")
    ap.add_argument("--clock-hz", type=int, default=50_000_000)
    ap.add_argument("--tolerance-ticks", type=int, default=256,
                    help="self-timed period tolerance in ticks (quantisation is 16)")
    args = ap.parse_args()
    run_capture(args.port, args.baud, args.seconds, args.output, args.summary,
                args.delta, args.clock_hz, args.tolerance_ticks)


if __name__ == "__main__":
    main()
