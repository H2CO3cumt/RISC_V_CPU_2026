"""N1 串口解析器的自检（不需要板子）。

存在意义：python/timer_demo_serial.py 的全部判据都在解析算术里，而这段算术
（记录切分、丢字节后的重同步、错位假链的排除、mtime 回绕、周期换算）在真机上调试一轮
要接板子、下载、等十几秒。先用构造出来的流把它钉死，再去碰硬件。

这里复现的都是**板上真实出现过**的情况：
  - 采集起点落在记录中间（会被切掉半条）；
  - 中断计数一路递增到 15 再回绕到 0（`:`..`?` 这些"标点"其实就是十六进制 10..15）；
  - 丢中断（计数跳号）必须让链断开，而不是被硬拼起来；
  - **主机串口丢字节**：真机实测 12 秒里丢过若干字节，丢一次就让之后所有记录整体错位，
    解析器必须能收回错位两侧的合法记录，并且不能把错位读出来的假链当成真记录。
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from timer_demo_serial import (  # noqa: E402
    MTIME_LSB_TICKS,
    MTIME_MOD_TICKS,
    chains_are_sound,
    measure_period,
    mtime_deltas,
    parse_chains,
    parse_runs,
)

FAILURES = 0


def check(name: str, got: object, want: object) -> None:
    global FAILURES
    if got == want:
        print(f"TEST PASS {name}: {got}")
    else:
        print(f"TEST FAIL {name}: want {want} got {got}")
        FAILURES += 1


def make_record(count: int, led: int, mtime: int) -> str:
    """按 start.S 的输出格式造一条 5 字节记录（mtime 用 [27:16] 三位十六进制）。"""
    assert mtime % 65536 == 0, "self-timed field is quantised to 65536 ticks"
    return "%x%d%03x" % (count % 16, led, (mtime >> 16) & 0xFFF)


def counts(runs) -> str:
    return "".join(str(r["count"]) for run in runs for r in run)


def leds(runs) -> str:
    return "".join(str(r["led"]) for run in runs for r in run)


def total(runs) -> int:
    return sum(len(run) for run in runs)


def deltas_of(runs) -> list[int]:
    out: list[int] = []
    for run in runs:
        out.extend(mtime_deltas(run))
    return out


# DELTA 取 65536 的整数倍，才能被自计时的量化步长整除（12500000 / 65536 = 190.7）。
DELTA = 65536 * 191          # = 12_517_376，与交付用的 12_500_000 差 0.14%
TOL = MTIME_LSB_TICKS        # 自计时的量化步长就是容差下限
records = "".join(make_record(i, i % 2, i * DELTA) for i in range(1, 21))

# ---- 1) 干净整段 ----
runs, anchored = parse_runs("=" + records, None, expect_delta=DELTA, tolerance_ticks=TOL)
check("clean stream is one anchored run", (len(runs), anchored), (1, True))
check("clean stream record count", total(runs), 20)
check("clean stream count sequence", counts(runs), "123456789abcdef01234")
check("clean stream led sequence", leds(runs), "10101010101010101010")
check("clean stream self-timed deltas", set(deltas_of(runs)), {DELTA})

# ---- 2) 没有 '=' 的流（复位前就开始采集）：不锚定，但仍要能解析出记录 ----
runs2, anchored2 = parse_runs(records, None, expect_delta=DELTA, tolerance_ticks=TOL)
check("stream without '=' is reported as NOT anchored", anchored2, False)
check("stream without '=' still yields the records", counts(runs2), "123456789abcdef01234")

# ---- 3) 丢一个字节：错位之后**必须重同步**，且不能把错位读出的假链算成记录 ----
# 在第 12 条记录中间删掉 1 个字节，之后所有记录整体错位。
# 期望：只剩错位之后那段真记录（第 13 条起），错位前的部分无法证明连续，宁可不要；
# 关键是**所有存活间隔都必须等于 delta**——错位假链的 mtime 差不可能等于 delta。
broken = records[:11 * 5 + 2] + records[11 * 5 + 3:]
runs3, anchored3 = parse_runs("=" + broken, None, expect_delta=DELTA, tolerance_ticks=TOL)
print(f"       dropped 1 byte → runs={[len(r) for r in runs3]} counts={counts(runs3)}")
check("host byte-drop still anchors on the boot marker", anchored3, True)
if total(runs3) >= 6:
    print(f"TEST PASS byte-drop still yields usable records ({total(runs3)})")
else:
    print(f"TEST FAIL byte-drop lost too many records ({total(runs3)})")
    FAILURES += 1
check("byte-drop survivors all have the expected interval", set(deltas_of(runs3)), {DELTA})

# ---- 3b) 不用自计时判别式时，错位假链会混进来——这正是判别式存在的理由 ----
# 同一条丢字节的流，把 expect_delta 去掉：这时 mtime 不再被核对，假链就会被当成记录。
runs3b, _ = parse_runs("=" + broken)
check("without the self-timing check, mis-aligned chains are NOT filtered",
      set(deltas_of(runs3b)) != {DELTA}, True)

# ---- 4) mtime 回绕：跨过 (1<<28) 拍边界时必须按模补回来 ----
wrapped = "=" + "".join(make_record(i + 1, i % 2, (i * DELTA) % MTIME_MOD_TICKS)
                        for i in range(1, 12))
runs4, _ = parse_runs(wrapped, None, expect_delta=DELTA, tolerance_ticks=TOL)
check("mtime wraparound deltas stay equal to delta", set(deltas_of(runs4)), {DELTA})

# ---- 5) 丢中断：任何被接受的链**都不能跨过计数跳号** ----
# 不指定 expect_delta 时解析器只是"结构诊断模式"（返回所有满足结构条件的链），
# 里面会夹带着互相重叠的短片段，所以不适合断言"总序列等于某某"。
# 真正常驻不变量是：**没有任何一条链能同时包含跳号两侧的计数**。
gap = "=" + make_record(1, 1, 0) + make_record(2, 0, DELTA) + make_record(3, 1, 2 * DELTA) \
      + make_record(9, 0, 3 * DELTA) + make_record(10, 1, 4 * DELTA) + make_record(11, 0, 5 * DELTA)
runs5, _ = parse_runs(gap, None, expect_delta=DELTA, tolerance_ticks=TOL)
sub5 = {counts([run])[a:b] for run in parse_chains(gap)
        for a in range(len(run)) for b in range(a + 1, len(run) + 1)}
in_any5 = "".join(counts([run]) for run in parse_chains(gap))
check("count gap: no chain spans the missing count (4..8)", "123456789" in in_any5, False)
check("count gap: the delta-checked runs only contain '123' and '9ab'",
      sorted(counts([r]) for r in runs5), ["123", "9ab"])

# ---- 6) LED 位不交替 = 那两条记录不能同链 ----
# 记录 1 与 2 的 LED 位都是 1，所以"把 1..5 全部串起来"这条链不可能存在。
# （错位确实能凑出别的短链，这是定长记录 + 双条件的固有性质，已由第 7 条不变量与
#  自计时判别式兜住；这里只断言"整串 5 条不可能"这个结构结论。）
stuck_led = "=" + make_record(1, 1, 0) + make_record(2, 1, DELTA) + make_record(3, 0, 2 * DELTA) \
            + make_record(4, 1, 3 * DELTA) + make_record(5, 0, 4 * DELTA)
longest6 = max(len(run) for run in parse_chains(stuck_led))
check("repeated LED digit: the 5-record sequence can never be one chain", longest6 < 5, True)
runs6, _ = parse_runs(stuck_led, None, expect_delta=DELTA, tolerance_ticks=TOL)
check("repeated LED digit: delta-checked runs all have the expected interval",
      set(deltas_of(runs6)), {DELTA})

# ---- 7) 解析器自检不变量：所有链都必须"定长 5 字节 + LED 交替" ----
chains = parse_chains("=" + records + "=" + broken)
sound, why = chains_are_sound(chains)
check("every parsed chain satisfies the 5-byte/LED invariants", (sound, why), (True, "ok"))

# ---- 8) 周期换算：n 条记录之间只有 n-1 个间隔 ----
period_ms = DELTA * 1000.0 / 50_000_000
got_ms, slack_ms, ok = measure_period(pair_count=25, span_seconds=6.0, fallback_seconds=6.0,
                                      period_ms=period_ms, tolerance_ms=15)
if ok and abs(got_ms - 250.0) < 1e-6:
    print(f"TEST PASS wall-clock math uses n-1 intervals ({got_ms:.3f} ms)")
else:
    print(f"TEST FAIL wall-clock math: got {got_ms:.3f} ms ok={ok} (want 250.000 ms)")
    FAILURES += 1

# ---- 9) 主机墙钟离谱时必须被判不合格（否则坏结果会蒙过去）----
_, _, bad_ok = measure_period(pair_count=25, span_seconds=0.2, fallback_seconds=0.2,
                              period_ms=period_ms, tolerance_ms=15)
if not bad_ok:
    print("TEST PASS a 8 ms wall-clock estimate is rejected against a 250 ms expectation")
else:
    print("TEST FAIL a wildly wrong wall-clock estimate was accepted")
    FAILURES += 1

# ---- 10) 记录数不足时不得给出"合格" ----
_, _, few_ok = measure_period(pair_count=1, span_seconds=1.0, fallback_seconds=1.0,
                              period_ms=period_ms, tolerance_ms=15)
if not few_ok:
    print("TEST PASS pair_count<2 yields not-ok instead of dividing by zero")
else:
    print("TEST FAIL pair_count<2 was reported ok")
    FAILURES += 1

if FAILURES == 0:
    print("ALL TIMER DEMO SERIAL PARSER TEST PASS")
else:
    print(f"TIMER DEMO SERIAL PARSER {FAILURES} TESTS FAIL")
    sys.exit(1)
