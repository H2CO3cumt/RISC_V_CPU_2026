# -*- coding: utf-8 -*-
"""按本板参数改写 HMIC_S 的 IP 实例数据文件（`.ipc`，就是一个 XML）。

## 背景：IP 生成本来只能在界面上点，现在可以由脚本完成

PDS 的 IP Compiler 是图形工具，官方文档明确写着"不能用命令行输入"。
但实测找到了两个可脚本化的入口，配上本脚本**就能全程无 GUI 产出本板配置的 IP**：

1. `ip_compiler.exe -c -n <名> -i <实例>.ipc -m <IP模型目录> -family Logos -device PGL50H
    -pack FBG484 -speed -6` —— 创建实例数据文件 `.ipc`（XML，264 个参数）。
    结构为 `<ip_inst><header>…</header><param><name>X</name><item>…</item><value>V</value></param>…`，
    `<item>` 是合法取值列表、`<value>` 是当前选中值。
2. 本脚本把 `<value>` 改成本板取值，**并校验新值确实在该参数的 `<item>` 合法列表里**。
3. `ip_generate.exe -i <实例>.ipc -family … -device …` —— 生成 IP RTL。

**最终验证（2026-09-29 实测通过）**：用这条链路生成的顶层 `ddr3_mes50hp.v` 里
`MEM_DQ_WIDTH = 32`、`MEM_DQS_WIDTH = 4`、`MEM_ROW/COLUMN/BANK = 15/10/3`，
`Done: 0 error(s)`，产出 `rtl/` 64 个文件。整条命令见
`scripts/run_ddr3_ip_generate.ps1`。

## 最容易踩的坑（实测教训）

**位宽类参数必须成组改。** 只把 `MEM_DQ_WIDTH` 从 16 改成 32、却留着 `MEM_DQS_WIDTH=2`，
生成出的顶层**仍然是 16 位**——工具发现这组值自相矛盾后回退了，而且**不报错**。
必须同时给 `MEM_DQS_WIDTH=4` 与 `MEM_DM_WIDTH=4`（都等于 DQ 位宽 / 8）。
`BOARD_VALUES` 里已经成组设好。

## 用法

  python scripts/ddr3_ipc_patch.py --src <默认.ipc> --dst <目标.ipc> [--list]
  --list 只打印实例里所有参数名与当前值，便于核对。
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

# 本板取值（依据见 docs/ddr3_s1_survey.md；管脚来自 MES50HP 手册表 2-4）
#
# ⚠️ 这三个位宽参数**必须配套**，否则生成的 IP 会不一致：
#     MEM_DQ_WIDTH  = 32   总数据位宽
#     MEM_DQS_WIDTH = 4    数据选通对数 = DQ/8（每条 lane 一对）
#     MEM_DM_WIDTH  = 4    数据掩码数   = DQ/8
# 实测教训：第一次只把 MEM_DQ_WIDTH 改成 32、留下 MEM_DQS_WIDTH=2，
# 生成出的顶层**仍然是 16 位**（工具发现矛盾后回退了）。
# 把 DQS 也改成 4 之后才真正生效（顶层变成 MEM_DQ_WIDTH = 32）。
BOARD_VALUES = {
    'MEM_DQ_WIDTH': '32',
    'MEM_DQS_WIDTH': '4',
    'MEM_DM_WIDTH': '4',
    'CLKIN_FREQ': '50',
    'DDR_MEM_PART': 'MT41K256M16xx-15E',
    'BANK_CA': 'B3',
    # ---- 以下两项以官方例程 `07_ddr3_test`（本板跑通的工程）为基准补齐（2026-09-29）----
    #
    # `DQ2_EN`/`DQ3_EN`：**必须为 true**。这不是可选项——`ui.tcl` 的
    #   proc `get_dq_group_number` 只在 `if {[ui::getValue -name $dq_group_en]}` 成立时才
    #   给 `GROUP_DQG_<k>_NUM` 赋值，否则它一直是 proc 开头写下的**占位值 9**。
    #   我们这份实例原本是 false，于是 lane2/lane3 的时钟索引恒为 9
    #   （对 9 位 `ddrphy_ioclk` 越界），实测表现为 lane3 的时钟脚接不到时钟、
    #   布线报 `Route-2014: _$$_GND_$$_ ... -> DQSL_6_276:CLK_IO`。
    #   32 位 = 4 条 lane，四条都必须使能。
    'DQ2_EN': 'true',
    'DQ3_EN': 'true',
    # `CUSTOMIZE_CA`：官方例程为 true。置 true 后 IP 才会使用下面 `CA_GROUP*` 的分组表；
    #   为 false 时（我们原来的值）分组表不生效，改它也没意义。
    'CUSTOMIZE_CA': 'true',
}


def parse_params(xml: str) -> dict[str, dict]:
    """抽出每个 `<param>` 的 name / items / value。"""
    out: dict[str, dict] = {}
    for m in re.finditer(r'<param>\s*<name>([^<]+)</name>(.*?)</param>', xml, re.S):
        name, body = m.group(1).strip(), m.group(2)
        items = re.findall(r'<item>([^<]*)</item>', body)
        val = re.search(r'<value>([^<]*)</value>', body)
        out[name] = {'items': items, 'value': val.group(1) if val else None,
                     'span': (m.start(), m.end())}
    return out


def patch(xml: str, values: dict[str, str]) -> tuple[str, list[str]]:
    """替换指定参数的 `<value>`；返回 (新 XML, 变更说明)。"""
    params = parse_params(xml)
    log: list[str] = []
    # 从后往前替换，避免位置偏移
    edits: list[tuple[int, int, str]] = []
    for name, want in values.items():
        p = params.get(name)
        if p is None:
            log.append(f'!! 实例里没有参数 {name}（跳过）')
            continue
        if p['value'] == want:
            log.append(f'== {name} 已经是 {want}（不变）')
            continue
        if p['items'] and want not in p['items']:
            log.append(f'!! {name} 的合法取值里没有 {want}；合法值={p["items"]}（跳过）')
            continue
        s, e = p['span']
        seg = xml[s:e]
        # 只替换该 param 段内最后一个 <value>（就在 </param> 之前）
        idx = seg.rfind('<value>')
        assert idx >= 0, name
        end = seg.index('</value>', idx) + len('</value>')
        new_seg = seg[:idx] + f'<value>{want}</value>' + seg[end:]
        edits.append((s, e, new_seg))
        log.append(f'-> {name}: {p["value"]} => {want}')
    edits.sort(key=lambda t: -t[0])
    for s, e, new_seg in edits:
        xml = xml[:s] + new_seg + xml[e:]
    return xml, log


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--dst')
    ap.add_argument('--list', action='store_true')
    args = ap.parse_args()

    src = Path(args.src)
    xml = src.read_text(encoding='utf-8')
    params = parse_params(xml)

    if args.list:
        print(f'{src} 里共 {len(params)} 个参数：')
        for n, p in params.items():
            print(f'  {n:<26} = {str(p["value"]):<22} 合法值: {",".join(p["items"][:8])}'
                  f'{" …" if len(p["items"]) > 8 else ""}')
        return

    if not args.dst:
        raise SystemExit('需要 --dst（除 --list 外）')
    dst = Path(args.dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    new_xml, log = patch(xml, BOARD_VALUES)
    dst.write_text(new_xml, encoding='utf-8')
    for line in log:
        print(line)
    print(f'写入 {dst}')


if __name__ == '__main__':
    main()
