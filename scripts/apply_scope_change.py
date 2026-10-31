# -*- coding: utf-8 -*-
r"""把"本届不实现 Cache/burst/DDR"的旧表述改成范围变更后的新表述。

## 背景

`docs/handoff_next.md` §3.3 明确要求：S2～S4 必须先由**用户**改写 `AGENTS.md` §1.14，
Agent 不得自行其是。用户已于 2026-09-29 **批准**该范围变更，本脚本据此同步其余文档，
避免"一处改了、八处还写着不做"的自相矛盾。

`AGENTS.md` 的三处正文由手工改写（改动较大、需要保留完整上下文），本脚本只处理
其余文档里那些**一句话式的旧冻结表述**。

## 用法

  python scripts/apply_scope_change.py --check   # 只报告将要改什么
  python scripts/apply_scope_change.py           # 实际改写

每一处替换都是**字面精确匹配**；匹配不到或匹配到多处都会报错退出，不静默跳过。
"""
from __future__ import annotations

import argparse
from pathlib import Path

REPO = Path(r'D:\RISC_V_CPU_2026')

# (文件, 原文字面, 新文字面)
EDITS: list[tuple[str, str, str]] = [
    (
        'AGENTS.local.md',
        '- 严格遵循 `docs/roadmap.md` 的当前 Gate，不提前实现后续 Gate，不恢复本届已冻结的 RLE、BTB、Cache、异常/中断等功能。',
        '- 严格遵循 `docs/roadmap.md` 的当前 Gate，不提前实现后续 Gate，不恢复本届已冻结的 RLE、BTB 等功能。\n'
        '  注：**Cache/burst/外部 DDR3 已于 2026-09-29 经用户批准解冻**并纳入本届路线（`AGENTS.md` §1.14、\n'
        '  `docs/handoff_next.md` §3.3），按 S1→S2→S3→S4 闸门推进；此处"已冻结"不再包含 Cache。',
    ),
    (
        'docs/interfaces.md',
        '- 本届不实现 I/D Cache 或 burst。未来赛后如研究，I-Cache 只能位于取指端口与下级存储之间，D-Cache 只能位于数据端口与 SoC 互连之间，且不得改变 Core 事务语义。',
        '- **I/D Cache 与 burst 已于 2026-09-29 经用户批准纳入本届**（`AGENTS.md` §1.14）。\n'
        '  放置位置**不得改变**：I-Cache 只能位于取指端口与下级存储之间，D-Cache 只能位于数据端口与 SoC 互连之间，\n'
        '  且不得改变 Core 事务语义；具体契约见本文件 §3.4「行/突发适配器与 Cache 契约」。',
    ),
    (
        'docs/architecture.md',
        '- 本届使用可综合片上 RAM/BRAM 完成稳定 Baseline，不实现 I/D Cache 或 burst；MMIO 始终属于 uncacheable 区域。',
        '- 稳定 Baseline 使用可综合片上 RAM/BRAM，**不依赖** Cache 或 burst；MMIO 始终属于 uncacheable 区域。\n'
        '- **2026-09-29 范围变更**：I/D Cache 与行式突发纳入本届（`AGENTS.md` §1.14），\n'
        '  存储层次见本文件「存储层次（行式突发 + 2 路组相联 Cache）」一节；Baseline 路径保持不变、可随时回退。',
    ),
    (
        'docs/roadmap.md',
        '- 本届不得开始 RLE；BTB 仅按 Task 32 冻结规格实现，不能扩展到 Cache 或异常/中断。',
        '- 本届不得开始 RLE；BTB 仅按 Task 32 冻结规格实现。\n'
        '  注：**Cache 已于 2026-09-29 经用户批准解冻**，作为 P3 阶段的 S3/S4 任务按闸门推进（`AGENTS.md` §1.14）。',
    ),
    (
        'docs/roadmap.md',
        '- 不实现 Cache、DDR 或复杂总线。',
        '- 本阶段（基础 SoC）不使用 Cache、DDR 或复杂总线；Cache/DDR 属于 P3 阶段（`AGENTS.md` §1.14）。',
    ),
    (
        'docs/trap_contract.md',
        '4. 不实现 Cache/burst/DDR；Trap 不得引入新的存储层次。',
        '4. Trap 实现本身**不得引入新的存储层次**：Cache/burst 属于 P3（S2～S4）的独立工作，\n'
        '   由 `docs/interfaces.md` §3.4 约定，且不得改变 Trap 的精确性语义。\n'
        '   **2026-09-29 范围变更**：Cache/burst/DDR 已纳入本届（`AGENTS.md` §1.14）；\n'
        '   接入 Cache 后**必须**重跑本契约全部断言，任何一条退化即回退。',
    ),
    (
        'docs/competition_scoring.md',
        '本届目标已经切换为单人 60 天国赛冲刺。RLE 继续冻结；BTB 按最终完善路线纳入，但不得扩展到 Cache 或完整异常/中断。其余时间投入：',
        '本届目标已经切换为单人 60 天国赛冲刺。RLE 继续冻结；BTB 按最终完善路线纳入。\n'
        '**2026-09-29 范围变更**：Cache/burst/外部 DDR3 经用户批准纳入本届，作为官方高阶项①\n'
        '（`AGENTS.md` §1.14、`docs/handoff_next.md` §3.3），因此本句原先"不得扩展到 Cache"已作废；\n'
        '"完整异常/中断"仍按下文既有边界。其余时间投入：',
    ),
    (
        'docs/debug_log.md',
        '并拒绝已冻结功能（RLE/Cache/异常中断/AI/DDR/HDMI/PCIe/千兆网/I2C/16 通道）的实现；',
        '并拒绝已冻结功能（RLE/AI/HDMI/PCIe/千兆网/I2C/16 通道）的实现；\n'
        '（注：Cache、异常/中断、外部 DDR3 已于 2026-09-28～29 先后解冻，见 `AGENTS.md` §1.14；\n'
        ' 本条为 2026-09-17 时的历史记录，保留原文语境不再作为现行范围依据。）',
    ),
    (
        'docs/roadmap.md',
        '- 未达到此条件时不得进入 Task 30；RLE 及已删减的 Cache、异常/中断和 AI 不因 Baseline 通过而恢复。16 项 BTB 只能在 Task 30 与 CoreMark 基线通过后按 Task 32 的冻结规格实现。',
        '- 未达到此条件时不得进入 Task 30；RLE 与 AI 不因 Baseline 通过而恢复；\n'
        '  Cache 与异常/中断已于 2026-09-28～29 解冻，按各自契约与闸门推进（`AGENTS.md` §1.14）。\n'
        '  16 项 BTB 只能在 Task 30 与 CoreMark 基线通过后按 Task 32 的冻结规格实现。',
    ),
]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()

    changed: dict[str, str] = {}
    problems: list[str] = []
    for rel, old, new in EDITS:
        p = REPO / rel
        if not p.exists():
            problems.append(f'文件不存在: {rel}')
            continue
        text = changed.get(rel) or p.read_text(encoding='utf-8')
        n = text.count(old)
        if n == 0:
            problems.append(f'匹配不到（可能已改过或原文已变）: {rel} :: {old[:60]}...')
            continue
        if n > 1:
            problems.append(f'匹配到 {n} 处，不敢自动改: {rel} :: {old[:60]}...')
            continue
        changed[rel] = text.replace(old, new)
        print(f'{"[check] " if args.check else ""}将改写 {rel}: {old[:56]}...')

    if problems:
        print()
        for x in problems:
            print('!! ' + x)
        raise SystemExit(f'有 {len(problems)} 处未能处理，未写任何文件')

    if args.check:
        print(f'\n共 {len(EDITS)} 处，全部可改（--check 模式，未写文件）')
        return
    for rel, text in changed.items():
        (REPO / rel).write_text(text, encoding='utf-8')
    print(f'\n已改写 {len(changed)} 个文件、共 {len(EDITS)} 处')


if __name__ == '__main__':
    main()
