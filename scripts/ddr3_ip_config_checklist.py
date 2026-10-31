# -*- coding: utf-8 -*-
"""从 `createFiles.tcl` 抽出 HMIC_S IP 的全部 ui 配置参数，并生成**逐项填好的配置单**。

为什么要做这个：`example_design/rtl/test_ddr.v` **只是 `test_ddr.v.xml` 这个 IP 配置模板**，
真正可综合的源码要由 PDS 的 IP 生成器按 `ui::getValue` 的参数生成。
所以"把例程搬到本板"这件事，本质就是**把这份参数表按本板改对**。
本脚本把参数名全部列出来，并把能从手册推出的项直接填上值，
剩下的（分组号等）标成"按 IP 界面核对"。

输出：`tmp/ddr3/ip_config_checklist.md`
"""
from __future__ import annotations

import json
import re
from pathlib import Path

IP = Path(r'D:\Pango\PDS_2024.2-SP2\ip\system_ip\ipsxb_hmic_s'
          r'\ipsxb_hmic_eval\ipsxb_hmic_s')
REPO = Path(__file__).resolve().parents[1]
PINMAP = REPO / 'tmp/ddr3/pinmap_manual.json'
OUT = REPO / 'tmp/ddr3/ip_config_checklist.md'

# 本板确定的值（来源见 docs/ddr3_s1_survey.md 与 MES50HP 手册）
BOARD = {
    'MEM_TYPE': 'DDR3',
    'DDR_MEM_PART': 'MT41K256M16xx-15E（与板载 QN3B256M16H-16A::P 兼容）',
    'MEM_DQ_WIDTH': '32',
    'MEM_DQS_WIDTH': '4',
    'CLKIN_FREQ': '50',
    'ACTUAL_RATE': '800',
    'OPERATING_MODE': 'Controller + PHY',
    'BANK_CA': 'B3',
    'MEM_ADDR_WIDTH': '15',
    'MEM_BANK_WIDTH': '3',
    'MEM_COLUMN_WIDTH': '10',
}


def main() -> None:
    tcl = (IP / 'createFiles.tcl').read_text(encoding='utf-8', errors='replace')
    names: list[str] = []
    for n in re.findall(r'ui::getValue -name "([^"]+)"', tcl):
        if n not in names:
            names.append(n)
    pads = [n for n in names if n.startswith('PAD_')]
    others = [n for n in names if not n.startswith('PAD_')]

    pinmap = json.loads(PINMAP.read_text(encoding='utf-8')) if PINMAP.exists() else {}
    # 建立 PAD_<SIG> -> 手册管脚 的映射（名字翻译，不猜管脚）
    def pad_value(pad: str) -> str:
        sig = pad[len('PAD_'):].lower()
        # 注意 1：IP 的复位端口叫 mem_rst_n（厂商模板一致），不是 mem_reset_n。
        # 注意 2：PAD_A15 在 IP 里**存在**，但厂商模板只约束到 mem_a[14]
        #   —— 因为 MEM_ROW_ADDR_WIDTH=15（mem_a[14:0]）。
        #   手册里 ddr3_addr[15]=R7 在本配置下不会被驱动，属于"板上有线但设计不用"，
        #   不能把它当成漏掉的管脚去乱接。
        cands = {
            'reset': 'mem_rst_n', 'cke': 'mem_cke', 'ck': 'mem_ck', 'ckn': 'mem_ck_n',
            'cs': 'mem_cs_n', 'ras': 'mem_ras_n', 'cas': 'mem_cas_n', 'we': 'mem_we_n',
            'odt': 'mem_odt',
        }
        if sig in cands:
            port = cands[sig]
            return pinmap.get(port, {}).get('pin', '?')
        m = re.fullmatch(r'([a-z]+)(\d+)', sig)
        if not m:
            return '?'
        base, idx = m.group(1), int(m.group(2))
        port = {'ba': 'mem_ba[%d]', 'a': 'mem_a[%d]', 'dq': 'mem_dq[%d]',
                'dm': 'mem_dm[%d]'}.get(base)
        if port:
            return pinmap.get(port % idx, {}).get('pin', '?')
        if base == 'dqs':
            return pinmap.get('mem_dqs[%d]' % idx, {}).get('pin', '?')
        if base == 'dqsn':
            return pinmap.get('mem_dqs_n[%d]' % idx, {}).get('pin', '?')
        return '?'

    lines = [
        '# HMIC_S IP 配置单（按 MES50HP 本板填好）',
        '',
        '> 由 `scripts/ddr3_ip_config_checklist.py` 从 `createFiles.tcl` 的参数名 + 手册管脚表生成。',
        '> `example_design/rtl/test_ddr.v` 只是 `test_ddr.v.xml` 这个 **IP 配置模板**，',
        '> 可综合源码必须由 PDS 的 IP 生成器按这份参数表生成。',
        '',
        '## 1. 固定参数（本板确定值）',
        '',
        '| 参数 | 本板取值 | 依据 |',
        '|---|---|---|',
    ]
    basis = {
        'MEM_TYPE': 'IP 当前只支持 DDR3',
        'DDR_MEM_PART': '板载 2×QN3B256M16H-16A::P，手册 §2.2.3',
        'MEM_DQ_WIDTH': '2 颗 x16 并行 = 32 bit，手册 §2.2.3',
        'MEM_DQS_WIDTH': '32 bit / 8 = 4 个 byte lane',
        'CLKIN_FREQ': '板载 50 MHz 接 P20',
        'ACTUAL_RATE': '手册允许到 800 Mbps',
        'OPERATING_MODE': '控制器 + PHY',
        'BANK_CA': 'DDR3 接 Bank 3，手册 §2.2.3',
        'MEM_ADDR_WIDTH': '4 Gb DDR3',
        'MEM_BANK_WIDTH': '4 Gb DDR3',
        'MEM_COLUMN_WIDTH': '4 Gb DDR3',
    }
    for k, v in BOARD.items():
        lines.append(f'| `{k}` | **{v}** | {basis.get(k, "")} |')

    lines += [
        '',
        '## 2. 非管脚参数（需在 IP 界面逐项确认）',
        '',
        '| 参数名 | 建议值 / 说明 |',
        '|---|---|',
    ]
    for n in others:
        if n in BOARD:
            continue
        hint = ''
        if 'GROUP' in n:
            hint = '按手册 byte lane 分组核对（见 §3 的 DQ 分组）'
        elif 'CUSTOMIZE' in n:
            hint = '0（用上面列出的标准器件型号）'
        elif 'REGION' in n:
            hint = '默认'
        elif 'DEVICE' in n:
            hint = '默认（PGL50H）'
        elif n == 'USER_PINS_CON_EN':
            hint = '**1**（Enable：启用手工管脚约束，配合 USER_FDC_PATH 导入下面的 FDC）'
        elif n == 'USER_FDC_PATH':
            hint = ('**指到 `tmp/ddr3/ddr3_pins_from_manual.fdc`**'
                    '（用户指南 Step3：勾选后可导入 FDC，自动读入 Control/Address 与 Data 管脚）')
        elif n == 'CS_n_EN':
            hint = '**1**（厂商模板约束了 `mem_cs_n`，说明该板按"启用 CS_n"配置；本板同理）'
        elif n.startswith('STATIC_RATIO'):
            hint = '默认（PHY 静态比值，由 IP 按频率算出）'
        lines.append(f'| `{n}` | {hint} |')

    lines += [
        '',
        f'## 3. PAD_* 管脚参数（共 {len(pads)} 个，管脚已按手册填好）',
        '',
        '| 参数名 | 手册管脚 | 参数名 | 手册管脚 |',
        '|---|---|---|---|',
    ]
    half = (len(pads) + 1) // 2
    left, right = pads[:half], pads[half:]
    for i in range(half):
        l = left[i]
        lp = pad_value(l)
        if i < len(right):
            r = right[i]
            rp = pad_value(r)
            lines.append(f'| `{l}` | **{lp}** | `{r}` | **{rp}** |')
        else:
            lines.append(f'| `{l}` | **{lp}** | | |')

    unknown = [p for p in pads if pad_value(p) == '?']
    lines += [
        '',
        '## 4. 自检',
        '',
        f'- PAD_* 参数总数：**{len(pads)}**',
        f'- 能从手册表自动填上管脚的：**{len(pads) - len(unknown)}**',
        f'- 需要人工判断的：**{len(unknown)}**' + (f' → {unknown}' if unknown else ''),
        '- 管脚来源：MES50HP 硬件手册表 2-4（**不是**厂商模板，那份模板 65/69 个管脚与本板不符）',
        '',
        '## 5. 两处必须知道、否则会"以为漏了管脚"的地方',
        '',
        '1. **`PAD_A15` 不用接**。IP 的 `MEM_ROW_ADDR_WIDTH` 默认是 **15**',
        '   （`test_ddr.v.xml` 第 31 行，可选 12/13/14/15），于是端口是 `mem_a[14:0]`；',
        '   厂商模板也只约束到 `mem_a[14]`。',
        '   手册里 `ddr3_addr[15] = R7` 是**板上确有走线但本配置不使用**的管脚 ⇒',
        '   **不要**把它接到 `PAD_A15` 上（接了反而与 IP 的端口宽度不符）。',
        '2. **IP 的复位端口是 `mem_rst_n`**，对应参数 `PAD_RESET`，手册管脚 **C1**',
        '   （手册信号名是 `ddr3_reset_n`）。命名不一致，容易看漏。',
        '',
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(lines), encoding='utf-8')
    print(f'ui 参数共 {len(names)} 个（PAD_* {len(pads)} 个，其它 {len(others)} 个）')
    print(f'自动填上管脚 {len(pads) - len(unknown)}/{len(pads)}')
    if unknown:
        print('需人工核对:', unknown)
    print(f'输出: {OUT.relative_to(REPO)}')


if __name__ == '__main__':
    main()
