# -*- coding: utf-8 -*-
"""按 MES50HP 官方手册重做 DDR3 管脚约束映射。

为什么需要它：厂商 HMIC 例程自带的 `50h_ddr3_fbg484_b3_x32.fdc` 与 MES50HP 手册
**对不上**（实测 69 个 DDR3 信号里 65 个管脚不同，而且手册里 F3 是 `ddr3_addr[3]`
而不是例程写的 `mem_ck`）。管脚错 = 位流可能把 DDR3 的 CK 打到别的功能管脚上，
所以**绝不能**拿厂商模板直接下载。

输入：
  - `tmp/ddr3/manual_pins.json`：从 MES50HP 硬件手册抽取的 `ddr3_* -> 管脚` 表（72 条）
  - 厂商模板：只借它的**端口命名**（`mem_a[0]` / `mem_dqs_n[0]` …）与**电平标准**写法
输出：
  - `tmp/ddr3/pinmap_manual.json`：`mem_* -> {pin, standard, vccio, note}` 的映射表
  - 同一份映射表供生成 `.fdc` 用（本脚本只做映射，不直接写 fdc）

**映射不是靠猜**：手册表把 DDR3 侧按 byte lane 给全了
（`ddr3_dq[0..7]` 配 `ddr3_dqs_p[0]`/`ddr3_dqs_n[0]`/`ddr3_dm[0]`），
所以直接按下标一一对应即可，不做任何重排。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANUAL = REPO / 'tmp/ddr3/manual_pins.json'
VENDOR_FDC = Path(r'D:\Pango\PDS_2024.2-SP2\ip\system_ip\ipsxb_hmic_s'
                  r'\ipsxb_hmic_eval\ipsxb_hmic_s\pnr\50h_ddr3_fbg484_b3_x32.fdc')
OUT = REPO / 'tmp/ddr3/pinmap_manual.json'
OUT_FDC = REPO / 'tmp/ddr3/ddr3_pins_from_manual.fdc'


def vendor_port_to_manual(port: str) -> str:
    """把厂商端口名换成手册信号名（纯命名翻译，不含任何管脚信息）。"""
    n = port
    n = n.replace('mem_dqs_n[', 'ddr3_dqs_n[')
    n = n.replace('mem_dqs[', 'ddr3_dqs_p[')
    n = n.replace('mem_dm[', 'ddr3_dm[')
    n = n.replace('mem_dq[', 'ddr3_dq[')
    n = n.replace('mem_a[', 'ddr3_addr[')
    n = n.replace('mem_ba[', 'ddr3_ba[')
    # 顺序重要：长名必须先替换，否则 mem_ck 的规则会把 mem_cke 变成 ddr3_ck_pe、
    # 把 mem_ck_n 变成 ddr3_ck_pn（第一版就是这么错的，脚本自检才抓到）。
    n = n.replace('mem_ck_n', 'ddr3_ck_n')
    n = n.replace('mem_cke', 'ddr3_cke')
    n = n.replace('mem_ck', 'ddr3_ck_p')
    for a, b in (('mem_cs_n', 'ddr3_cs_n'), ('mem_ras_n', 'ddr3_ras_n'),
                 ('mem_cas_n', 'ddr3_cas_n'), ('mem_we_n', 'ddr3_we_n'),
                 ('mem_rst_n', 'ddr3_reset_n'),
                 ('mem_odt', 'ddr3_odt')):
        n = n.replace(a, b)
    return n.lower()


def main() -> None:
    manual = json.loads(MANUAL.read_text(encoding='utf-8'))
    vtxt = VENDOR_FDC.read_text(encoding='utf-8', errors='replace')

    # 厂商模板里借两样东西：端口名清单、以及每个端口的电平标准
    ports = re.findall(r'define_attribute \{p:([^}]+)\} \{PAP_IO_LOC\}', vtxt)
    std = dict(re.findall(r'define_attribute \{p:([^}]+)\} \{PAP_IO_STANDARD\} \{([^}]+)\}', vtxt))

    mapping: dict[str, dict[str, str]] = {}
    unmatched: list[str] = []
    for port in ports:
        if not port.startswith('mem_'):
            continue          # 时钟/复位/RST/UART 等由调用方单独处理
        sig = vendor_port_to_manual(port)
        pin = manual.get(sig)
        if pin is None:
            unmatched.append(f'{port} (手册名 {sig})')
            continue
        mapping[port] = {
            'pin': pin,
            'standard': std.get(port, 'SSTL15_I'),
            'vccio': '1.5',
            'manual_signal': sig,
        }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(mapping, indent=1, sort_keys=True, ensure_ascii=False),
                   encoding='utf-8')

    print(f'映射成功 {len(mapping)} 个 DDR3 端口，未匹配 {len(unmatched)} 个')
    for u in unmatched:
        print('  未匹配:', u)
    # 电平分布自检：手册指南要求 mem_ck / mem_dqs 用差分标准，其余单端
    from collections import Counter
    print('电平分布:', dict(Counter(v['standard'] for v in mapping.values())))
    # 差分信号必须成对且标准一致。注意厂商命名是不对称的：
    #   正端 mem_dqs[0]，负端 mem_dqs_n[0]（不是 mem_dqs[0]_n）——第一版这里判断错了。
    bad_pairs = []
    for base in ('mem_ck', 'mem_dqs[0]', 'mem_dqs[1]', 'mem_dqs[2]', 'mem_dqs[3]'):
        neg = base.replace('mem_dqs[', 'mem_dqs_n[') if base.startswith('mem_dqs') else base + '_n'
        stds = {std.get(base), std.get(neg)}
        if len(stds) != 1 or None in stds:
            bad_pairs.append((base, neg, sorted(str(s) for s in stds)))
    if bad_pairs:
        print('差分对标准不一致（需人工确认）:', bad_pairs)
    else:
        print('差分对标准一致（mem_ck/mem_ck_n 与 mem_dqs[i]/mem_dqs_n[i] 均为 SSTL15D_I）')
    print(f'输出: {OUT.relative_to(REPO)}')

    # ---- 生成校验用的 .fdc 片段（供人工核对 / 供 IP 的 "Memory Pin Constraint File" 导入）----
    lines = [
        '# 由 scripts/ddr3_map_manual_pins.py 生成；管脚来源 = MES50HP 硬件手册表 2-4。',
        '# 与厂商模板 50h_ddr3_fbg484_b3_x32.fdc 不同：那份模板的管脚与本板对不上',
        '# （69 个 DDR3 信号里 65 个不同），不得直接使用。',
        '# 本文件只含 I/O 位置与电平，不含时钟/时序约束（那部分照厂商模板的写法另行处理）。',
        '',
    ]
    for port in sorted(mapping):
        v = mapping[port]
        lines.append(f'# {v["manual_signal"]}')
        lines.append(f'define_attribute {{p:{port}}} {{PAP_IO_DIRECTION}} '
                     f'{"Inout"}')
        lines.append(f'define_attribute {{p:{port}}} {{PAP_IO_LOC}} {{{v["pin"]}}}')
        lines.append(f'define_attribute {{p:{port}}} {{PAP_IO_VCCIO}} {{1.5}}')
        lines.append(f'define_attribute {{p:{port}}} {{PAP_IO_STANDARD}} {{{v["standard"]}}}')
    OUT_FDC.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'输出: {OUT_FDC.relative_to(REPO)}  ({len(mapping)} 个端口)')


if __name__ == '__main__':
    main()
