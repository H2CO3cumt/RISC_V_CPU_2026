#!/usr/bin/env python3
"""M-21 独立 golden 事件判定器。

输入：`tmp/trap_golden/trace.log`，由 `tb/tb_trap_golden.v` 产生。
那份日志**只包含 Core 的公开端口**：
  T    <cycle> <pc> <inst> <rd_we> <rd_addr> <rd_data> <mem_we> <mem_addr> <mem_data> <wstrb>
  TRAP <cycle>       ← event_trap 脉冲
  MRET <cycle>       ← event_trap_return 脉冲

本脚本不读 Core 内部信号、不使用单周期 Reference Model（它不支持 Trap），
而是**从提交级 trace 与 Trap 事件自己重建"发生了什么"**，再和下面声明的期望序列比对：

  * 提交序列必须等于 golden 列表（顺序、条数、跳过的 PC 都要对）；
  * 三条异常指令（0x08 ECALL / 0x0C 非法指令 / 0x10 未对齐 Store）都**不得**出现提交记录；
  * event_trap 恰好 3 次、event_trap_return 恰好 3 次，且每次 Trap 之后
    恰好 4 条 handler 指令被提交（handler 固定 4 条）；
  * 出错路径上不得出现任何内存写事务（未对齐 Store 不能产生总线写）。

判定结果输出 `TRAP GOLDEN JUDGE PASS/FAIL`，失败退出码为 1。
"""

from __future__ import annotations

import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
LOG = REPO / "tmp" / "trap_golden" / "trace.log"

# ---------------------------------------------------------------------------
# 期望序列（golden）
# ---------------------------------------------------------------------------
HANDLER = [0x1C, 0x20, 0x24, 0x28]     # csrrs mepc / addi +4 / csrrw mepc / mret
FAULT_PCS = [0x08, 0x0C, 0x10]         # ECALL / 非法指令 / 未对齐 Store
GOLDEN_PREFIX = (
    [0x00, 0x04]                       # mtvec 建立
    + HANDLER                          # 第 1 次 Trap（0x08 ECALL 自己不提交）
    + HANDLER                          # 第 2 次 Trap（0x0C 非法指令自己不提交）
    + HANDLER                          # 第 3 次 Trap（0x10 未对齐 Store 自己不提交）
    + [0x14, 0x18]                     # 恢复路径 + halt（之后是自跳转循环）
)
EXPECTED_TRAPS = 3
EXPECTED_MRETS = 3


def fail(msg: str, failures: list[str]) -> None:
    failures.append(msg)


def main() -> int:
    if not LOG.exists():
        print(f"TRAP GOLDEN JUDGE FAIL 日志不存在：{LOG}")
        return 1

    commits: list[tuple[int, int, int, int]] = []   # cycle, pc, inst, mem_we
    traps: list[int] = []
    mrets: list[int] = []

    for raw in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = raw.split()
        if not parts:
            continue
        if parts[0] == "T":
            cycle = int(parts[1])
            pc = int(parts[2], 16)
            inst = int(parts[3], 16)
            mem_we = int(parts[7])
            commits.append((cycle, pc, inst, mem_we))
        elif parts[0] == "TRAP":
            traps.append(int(parts[1]))
        elif parts[0] == "MRET":
            mrets.append(int(parts[1]))

    failures: list[str] = []

    # 1) 提交序列前缀必须与 golden 一致
    pcs = [c[1] for c in commits]
    if len(pcs) < len(GOLDEN_PREFIX):
        fail(f"too few commit records: got {len(pcs)}, want at least {len(GOLDEN_PREFIX)}", failures)
    else:
        for i, (got, want) in enumerate(zip(pcs, GOLDEN_PREFIX)):
            if got != want:
                fail(f"commit #{i} PC mismatch: got={got:#04x} want={want:#04x}", failures)
                break

    # 2) 三条异常指令都不得提交
    for pc in FAULT_PCS:
        if pc in pcs:
            fail(f"faulting instruction {pc:#04x} produced a commit record", failures)

    # 3) Trap / mret 次数
    if len(traps) != EXPECTED_TRAPS:
        fail(f"event_trap count mismatch: got={len(traps)} want={EXPECTED_TRAPS}", failures)
    if len(mrets) != EXPECTED_MRETS:
        fail(f"event_trap_return count mismatch: got={len(mrets)} want={EXPECTED_MRETS}", failures)

    # 4) 每次 Trap 之后恰好 4 条 handler 指令提交
    #    序列结构：0x00 0x04 [H×4 0x0C] [H×4 0x10] [H×4 0x14] 0x18 ...
    if len(pcs) >= len(GOLDEN_PREFIX):
        for k in range(EXPECTED_TRAPS):
            base = 2 + k * 4
            seg = pcs[base:base + 4]
            if seg != HANDLER:
                fail(f"handler segment {k + 1} mismatch: got={[hex(x) for x in seg]}", failures)

    # 5) 出错路径不得有任何内存写事务
    bad_writes = [c for c in commits if c[3] == 1]
    if bad_writes:
        fail(f"trace stream contains {len(bad_writes)} memory-write records (misaligned store must not issue one)", failures)

    # 6) Trap 与 mret 的时间顺序必须是 TRAP 在前
    if traps and mrets and not (traps[0] < mrets[0]):
        fail("first event_trap_return happened before the first event_trap", failures)

    if failures:
        print(f"TRAP GOLDEN JUDGE FAIL commits={len(commits)} traps={len(traps)} mrets={len(mrets)}")
        for f in failures:
            print(f"  - {f}")
        return 1

    print(f"TRAP GOLDEN JUDGE PASS commits={len(commits)} traps={len(traps)} mrets={len(mrets)}")
    print("  golden prefix = " + " ".join(f"{p:#04x}" for p in GOLDEN_PREFIX))
    return 0


if __name__ == "__main__":
    sys.exit(main())
