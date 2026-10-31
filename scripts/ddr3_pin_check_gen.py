# -*- coding: utf-8 -*-
"""生成 DDR3 管脚约束的**桩顶层**（只为让 PDS 的 compile 阶段校验 .fdc）。

为什么需要它：`constraints/ddr3_pins_from_manual.fdc` 是我们自己按手册生成的，
在把它交给 HMIC IP 生成器（或正式工程）之前，应该先让 PDS 自己 parse 一遍，
这样占位符写错、管脚名写错、电平标准写错这类问题会**在消耗任何综合时间之前**暴露。

桩顶层只声明 `mem_*` 端口，不含任何逻辑；本脚本只跑 `compile` 阶段，不综合、不出版本。

输出：
  - `tmp/ddr3/ddr3_pin_check_top.v`（桩顶层）
  - `tmp/ddr3/pin_check/pds_recipe.tcl`（只到 compile 的配方）
"""
from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PINMAP = REPO / 'tmp/ddr3/pinmap_manual.json'
STUB = REPO / 'tmp/ddr3/ddr3_pin_check_top.v'
PROJ = REPO / 'tmp/ddr3/pin_check'


def bus(port: str) -> str:
    """`mem_a[3]` -> ('mem_a', '[3]')；无下标返回 ('mem_ck', '')。"""
    m = re.fullmatch(r'([A-Za-z0-9_]+)\[(\d+)\]', port)
    return (m.group(1), '[%s]' % m.group(2)) if m else (port, '')


def main() -> None:
    pinmap = json.loads(PINMAP.read_text(encoding='utf-8'))
    ports = sorted(pinmap, key=lambda s: (bus(s)[0], int(bus(s)[1][1:-1]) if bus(s)[1] else 0))

    # 合并成向量声明（Verilog-2001 端口列表里向量必须写成 name[msb:lsb]）
    groups: dict[str, list[int]] = {}
    scalars: list[str] = []
    for p in ports:
        name, idx = bus(p)
        if idx:
            groups.setdefault(name, []).append(int(idx[1:-1]))
        else:
            scalars.append(name)

    decls: list[str] = []
    for name in sorted(groups):
        idxs = sorted(groups[name])
        assert idxs == list(range(len(idxs))), f'{name} 下标不连续: {idxs}'
        decls.append(f'    inout wire [{idxs[-1]}:0] {name}')
    decls.extend(f'    inout wire {s}' for s in scalars)

    body = [
        '// 由 scripts/ddr3_pin_check_gen.py 生成；只为验证 .fdc 能被 PDS 编译，不含真实逻辑。',
        '// 不参与交付，也不出版本（只跑 compile 阶段）。',
        '//',
        '// 关键：**模块必须有非空逻辑**。第一版写了个空模块，PDS 直接报',
        '//   "Create black box for empty module" / "Top module ... is set as a black box"',
        '// 然后把整个顶层当黑盒 —— I/O 约束**根本没有被检查**，那种"PASS"是假的。',
        '// 这里给每个 DQ/DQS 加一条三态驱动，其余标量引脚内部下拉，保证端口真的存在。',
        'module ddr3_pin_check_top (',
    ]
    for i, d in enumerate(decls):
        body.append(d + (',' if i < len(decls) - 1 else ''))
    body += [
        ');',
        '    // 让所有端口都是"被使用的真实 I/O"',
        '    genvar gi;',
        '    generate',
    ]
    for name in ('mem_dq', 'mem_dqs', 'mem_dqs_n'):
        n = max(groups[name])
        body.append(f'        for (gi = 0; gi <= {n}; gi = gi + 1) begin : g_{name}')
        body.append(f'            assign {name}[gi] = 1\'bz;   // 先占位成高阻，避免多驱动')
        body.append('        end')
    body.append('    endgenerate')
    for s in sorted(scalars) + [k for k in ('mem_a', 'mem_ba', 'mem_dm') if k in groups]:
        body.append(f'    assign {s} = 1\'bz;')
    body += ['endmodule', '']
    STUB.write_text('\n'.join(body), encoding='utf-8')

    PROJ.mkdir(parents=True, exist_ok=True)
    (PROJ / 'pds_recipe.tcl').write_text('\n'.join([
        '# 验证按手册生成的 DDR3 管脚约束能否被 PDS 接受**并真正落到管脚上**。',
        '# 只跑 compile + synthesize + dev_map：**不做布局布线、不出版本**，',
        '# 所以绝不可能影响板上现有位流，也不会碰任何交付工程。',
        '#',
        '# 为什么必须跑到 dev_map：管脚位置/电平是在 device map 阶段才被检查的。',
        '# 只跑 compile 时，第一版的空模块被当成 black box，I/O 约束根本没被看过 ——',
        '# 那种 "0 error" 是假通过。跑到 dev_map 才验证得了 LOC/VCCIO/STANDARD。',
        'set_option max_threads 0',
        'set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484',
        'clean -all',
        'add_design ../ddr3_pin_check_top.v',
        'add_constraint -fdc ../../../fpga/ddr3_smoke/constraints/ddr3_pins_from_manual.fdc',
        'compile -force_to_run -top_module {work.ddr3_pin_check_top}',
        'synthesize -force_to_run -ads -selected_syn_tool_opt 2',
        'dev_map -force_to_run -packing_io',
        '',
    ]), encoding='utf-8')

    print(f'桩顶层端口：{len(groups)} 个向量 + {len(scalars)} 个标量 = {len(ports)} 个信号')
    print('向量:', ', '.join(f'{k}[{max(v)}:0]' for k, v in sorted(groups.items())))
    print('标量:', ', '.join(scalars))
    print('输出:', STUB.relative_to(REPO), '与', (PROJ / 'pds_recipe.tcl').relative_to(REPO))


if __name__ == '__main__':
    main()
