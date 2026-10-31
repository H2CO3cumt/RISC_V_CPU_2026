# -*- coding: utf-8 -*-
"""生成 `fpga/ddr3_smoke/pds_recipe.tcl`（DDR3 冒烟工程的 PDS 构建配方）。

源文件来自三处，全部由本脚本自动收集，避免手抄漏文件：
  1. 我们自己的板级顶层 `fpga/ddr3_smoke/rtl/mes50hp_ddr3_smoke_top.v`；
  2. HMIC_S IP 生成的 RTL：`fpga/ddr3_smoke/ip/<实例>/rtl/**`（含加密的 `.vp`）；
     —— `pds_shell` 能直接吃 `.vp`（本工程前面的 PDS 构建实测过），无需预先解密；
  3. 厂商 Example Design：`.../example_design/rtl/**`（含 `uart_ctrl_32bit/`）。
     bench 目录**不加入**（那是仿真用的 testbench）。

约束只用我们按手册生成的 `constraints/mes50hp_ddr3_smoke.fdc`；
**不用** IP 自带的 `pnr/*.fdc`（那份 65/69 个管脚与本板不符）。

顶层 = `mes50hp_ddr3_smoke_top`（板级 wrapper，不改厂商源文件）。
"""
from __future__ import annotations

import argparse
from pathlib import Path

REPO = Path(r'D:\RISC_V_CPU_2026')
SMOKE = REPO / 'fpga/ddr3_smoke'


def collect() -> tuple[list[str], list[str]]:
    """返回 (rtl 源文件列表, example_design 源文件列表)，路径相对 fpga/ddr3_smoke。"""
    ip_dirs = sorted(p for p in (SMOKE / 'ip').iterdir() if p.is_dir())
    if not ip_dirs:
        raise SystemExit('没有找到 IP 实例目录（先跑 scripts/run_ddr3_ip_generate.ps1）')
    inst = ip_dirs[0]

    def rel(p: Path) -> str:
        return p.relative_to(SMOKE).as_posix()

    rtl = sorted({rel(p) for p in (inst / 'rtl').rglob('*')
                  if p.is_file() and p.suffix in ('.v', '.vp')})
    ex = sorted({rel(p) for p in (inst / 'example_design/rtl').rglob('*')
                 if p.is_file() and p.suffix in ('.v', '.vp')})
    # 实例根目录下的**顶层包装**（由 IP 模板编译而来）也必须加入：
    #   <实例>.v                  —— DDR3 控制器顶层（test_ddr 例化的就是它）
    #   <实例>_ddrphy_top.v       —— PHY 顶层
    # 第一版漏了这两个，compile 直接报
    #   `'ddr3_mes50hp' is referenced to undefined module`。
    wrapper = sorted({rel(p) for p in inst.glob('*.v')})
    if not rtl:
        raise SystemExit(f'{inst}/rtl 为空')
    if not ex:
        raise SystemExit(f'{inst}/example_design/rtl 为空')
    if not wrapper:
        raise SystemExit(f'{inst} 根目录没有顶层包装 .v（IP 生成不完整）')
    return rtl, ex, wrapper


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--top', default='mes50hp_ddr3_smoke_top')
    ap.add_argument('--stop', default='gen_bit_stream',
                    choices=['compile', 'synthesize', 'dev_map', 'place', 'route', 'gen_bit_stream'],
                    help='跑到哪一步为止（调试时用 compile/synthesize 省时间）')
    args = ap.parse_args()

    rtl, ex, wrapper = collect()
    lines = [
        '# MES50HP DDR3 冒烟工程 PDS 配方（由 scripts/ddr3_gen_smoke_recipe.py 生成，勿手改）。',
        '#',
        '# 与交付工程完全隔离：只读写 fpga/ddr3_smoke/，不触碰',
        '# fpga/logic_analyzer、fpga/coremark、fpga/coremark_80m、fpga/timer_demo。',
        '#',
        '# DDR3 占 Bank 3 的 1.5 V；板级时钟/UART/LED 是 3.3 V —— 两侧电平由',
        '# constraints/mes50hp_ddr3_smoke.fdc 分别声明，不混用。',
        'set_option max_threads 0',
        'set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484',
        'clean -all',
        '',
        '# ---- 1) 我们的板级顶层 ----',
        'add_design rtl/mes50hp_ddr3_smoke_top.v',
        '',
        '# ---- 2) HMIC_S IP 生成的 RTL（含加密 .vp）----',
    ]
    lines += [f'add_design {p}' for p in rtl]
    lines += ['', '# ---- 3) IP 实例根目录的顶层包装（<实例>.v / <实例>_ddrphy_top.v）----']
    lines += [f'add_design {p}' for p in wrapper]
    lines += ['', '# ---- 4) 厂商 Example Design ----']
    lines += [f'add_design {p}' for p in ex]
    lines += [
        '',
        '# ---- 5) 约束（按 MES50HP 手册生成，**不是** IP 自带那份）----',
        'add_constraint -fdc constraints/mes50hp_ddr3_smoke.fdc',
        '',
        f'compile -force_to_run -top_module {{work.{args.top}}}',
    ]
    if args.stop != 'compile':
        lines.append('synthesize -force_to_run -ads -selected_syn_tool_opt 2')
    if args.stop in ('dev_map', 'place', 'route', 'gen_bit_stream'):
        lines.append('dev_map -force_to_run -packing_io')
    if args.stop in ('place', 'route', 'gen_bit_stream'):
        lines.append('place -force_to_run -optimize_multi_corner_timing')
    if args.stop in ('route', 'gen_bit_stream'):
        lines += ['route -force_to_run', 'route_optimize -force_to_run -fix_hold_violation']
    if args.stop == 'gen_bit_stream':
        lines += ['report_timing -force_to_run', 'gen_bit_stream -force_to_run']

    out = SMOKE / 'pds_recipe.tcl'
    out.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'输出 {out.relative_to(REPO)}（跑到 {args.stop}）')
    print(f'  IP RTL        : {len(rtl)} 个文件')
    print(f'  IP 顶层包装   : {len(wrapper)} 个文件 -> {", ".join(Path(w).name for w in wrapper)}')
    print(f'  Example Design: {len(ex)} 个文件')
    print(f'  顶层          : {args.top}')


if __name__ == '__main__':
    main()
