# -*- coding: utf-8 -*-
"""生成 `fpga/ddr3_smoke/constraints/mes50hp_ddr3_smoke.fdc`（DDR3 冒烟工程的完整约束）。

拼三块：
  1. **DDR3 管脚**：来自 `tmp/ddr3/pinmap_manual.json`（按 MES50HP 官方手册表 2-4 抽取），
     共 71 个信号，全部 `VCCIO=1.5` / `SSTL15_I` 或差分 `SSTL15D_I`。
     —— **不是**厂商模板那份（它 65/69 个管脚与本板不符）。
  2. **系统时钟**：`clk_50m = P20`，50 MHz / 20 ns。DDR3 的 `ref_clk` 与 `free_clk`
     都接它（手册确认 F14/Y11 在本板不是时钟源）。
  3. **UART / LED**：板载 CP2102 `R9`(TX) / `R8`(RX)；LED `B2,A2,B3,A3,C5,A5,F7,F8`。
     取自 `docs/fpga_platform.md` 与现有交付工程，逐字一致。

**不做的事**：不引入 `ref_clk=F14` / `free_clk=Y11` / `pll_lock=U19` 等厂商例程的板级管脚
（那是另一块板的），也不把这些臆测管脚写进约束。
"""
from __future__ import annotations

import json
from pathlib import Path

REPO = Path(r'D:\RISC_V_CPU_2026')
PINMAP = REPO / 'tmp/ddr3/pinmap_manual.json'
OUT = REPO / 'fpga/ddr3_smoke/constraints/mes50hp_ddr3_smoke.fdc'

# 板级管脚（docs/fpga_platform.md；与交付工程逐字一致）
BANK33 = {
    'clk_50m':  ('P20', 'Input'),
    'uart0_rx': ('R8',  'Input'),
    'uart0_tx': ('R9',  'Output'),
}
LED_PINS = ['B2', 'A2', 'B3', 'A3', 'C5', 'A5', 'F7', 'F8']

# DDR3 PHY 的**物理约束**（依厂商 `50h_ddr3_fbg484_b3_x32.fdc`——正是本板封装/容量/通道那一份）。
#
# 背景：DDR3 PHY 时钟走**专用时钟网络**，PLL 必须落在能到达 `IOCLKBUF`/`CLMA` 的位置。
# 不约束时 PDS 把 `u_ipsxb_ddrphy_pll_0` 自动放到 `PLL_158_179`（厂商设计里那是 `pll_1` 的位置），
# 布局阶段于是报：
#
#   Place-0084: IO_CLOCK: driver .../u_ipsxb_ddrphy_pll_0/PLL.u_pll_e3/goppll
#               of buffer .../I_GTP_IOCLKBUF_0/gopclkgate fixed at PLL_158_179
#               is unreasonable.  (net clkout0_wl_0)
#
# 厂商原本用 3 条 `PAP_LOC` 解决（2 条钉 PLL + 1 条钉 ioclk 门控寄存器）。实测：
#
#   1. ioclk 那条**能被解析器接受**（下面 PHY_LOCS 里保留）；
#   2. 两条 PLL 的**照抄过来解析不通**，报
#      `ConstraintEditor-0046: Object 'i:u_dut.I_ipsxb_ddr_top.u_ipsxb_ddrphy_pll_0.u_pll_e3'
#                              can not be found in current view`。
#      原因是路径里那个 `PLL` 是 **generate 块名**（`rtl/pll/ipsxb_ddrphy_pll_v1_7.v` 第 176 行
#      `generate if(L18G_EN == 0) begin : PLL`），约束解析器不认这种路径；
#      对比 ioclk 那条路径里没有 generate 块，就能被接受。
#   3. 于是这两条改用 PDS 在 `Place-0084` 里**自己给出的**办法（报错原文：
#      "You may use the PAP_CLOCK_DEDICATED_ROUTE constraint in the .fdc file to demote this
#       message to a WARNING."）：允许该时钟网用普通走线。不改变任何逻辑，
#      且**最终仍由时序分析把关**——真连不上时 `report_timing` 会报违例，不会静默通过。
#
# ！ 层次分隔符是**点号**：厂商写 `{i:I_ipsxb_ddr_top.u_ipsxb_ddrphy_pll_0.u_pll_e3}`，
#    实测用斜杠 `a/b/c` 会被判"对象不存在"。
# ！ `I_ipsxb_ddr_top` 是**厂商 Example Design 给 DDR3 IP 起的实例名**
#    （`example_design/rtl/test_ddr.v` 第 825 行），不是我们的顶层名；
#    我们的顶层只把整份 `test_ddr` 例化成 `u_dut`，所以路径是 `u_dut.I_ipsxb_ddr_top....`。
# ！ 厂商文件里那两条 PLL 约束留在这里作参考，等找到正确写法后应优先恢复"钉位置"：
#      define_attribute {i:u_dut.I_ipsxb_ddr_top.u_ipsxb_ddrphy_pll_0.u_pll_e3} {PAP_LOC} {PLL_158_199}
#      define_attribute {i:u_dut.I_ipsxb_ddr_top.u_ipsxb_ddrphy_pll_1.u_pll_e3} {PAP_LOC} {PLL_158_179}
PHY_LOCS = [
    # 厂商 `pnr/ddr_test.fdc` 第 48–49 行原文（含 generate 块名 PLL），我们只把根实例换成 u_dut。
    # 注意 `PLL.u_pll_e3` 里的 `PLL` 是 generate 块标签，不是层次分隔符——
    # `rtl/pll/ipsxb_ddrphy_pll_v1_7.v` 第 176 行 `generate if(L18G_EN == 0) begin : PLL`。
    # 一开始误按普通层次写成 `u_pll_e3`，解析器报"对象不存在"。
    ('u_dut.I_ipsxb_ddr_top.u_ipsxb_ddrphy_pll_0.PLL.u_pll_e3', 'PLL_158_199',
     'DDR3 PHY PLL0：厂商约束在 158_199；不约束时 PDS 会放到 158_179（那是 pll_1 的位置），'
     '导致 IOCLKBUF_0 的专用时钟走不通，报 Place-0084'),
    ('u_dut.I_ipsxb_ddr_top.u_ipsxb_ddrphy_pll_1.PLL.u_pll_e3', 'PLL_158_179',
     'DDR3 PHY PLL1：对应厂商同一条'),
    ('u_dut.I_ipsxb_ddr_top.u_ddrphy_top.ddrphy_reset_ctrl.ddrphy_ioclk_gate', 'CLMA_150_192:FF3',
     'ioclk 门控寄存器：厂商约束到该 CLMA 位置'),
]

# 放宽专用时钟走线的网（见上面第 3 点）。
# 已停用：实测 `define_attribute {n:clkout0_wl_0} ...` 报
#   ConstraintEditor-0046: Object 'n:clkout0_wl_0' can not be found in current view
# ——该网名是**布局阶段**才产生的（综合网表 `ddr3_mes50hp_syn.vm` 里搜不到），
# 约束解析期拿不到，所以这条路走不通，改回"钉 PLL 位置"。
DEDICATED_ROUTE_RELAX: list[tuple[str, str]] = []


def main() -> None:
    pinmap = json.loads(PINMAP.read_text(encoding='utf-8'))

    lines = [
        '# MES50HP DDR3 冒烟工程约束（由 scripts/ddr3_gen_smoke_fdc.py 生成，勿手改）。',
        '#',
        '# 管脚来源分三块：',
        '#   1) DDR3：MES50HP 官方硬件手册表 2-4（按信号逐条抽取，非厂商模板）',
        '#      —— 厂商自带的 50h_ddr3_fbg484_b3_x32.fdc 有 65/69 个管脚与本板不符，禁止使用；',
        '#   2) 时钟：clk_50m = P20（板上 50 MHz；DDR3 的 ref_clk/free_clk 都接它。',
        '#      手册确认 F14 是网口 1 RX_CLK、Y11 是 J8 扩展口，都不是时钟源）；',
        '#   3) UART/LED：板载 CP2102 R9/R8 与用户 LED，取自 docs/fpga_platform.md。',
        '',
        '### ============ 1. 时钟 ============',
        'create_clock -name {clk_50m} [get_ports {clk_50m}] -period {20.000} -waveform {0.000 10.000}',
        '',
        '### ============ 2. 板级 3.3V 外设 ============',
    ]
    for port, (pin, direction) in BANK33.items():
        lines += [
            f'define_attribute {{p:{port}}} {{PAP_IO_DIRECTION}} {{{direction}}}',
            f'define_attribute {{p:{port}}} {{PAP_IO_LOC}} {{{pin}}}',
            f'define_attribute {{p:{port}}} {{PAP_IO_VCCIO}} {{3.3}}',
            f'define_attribute {{p:{port}}} {{PAP_IO_STANDARD}} {{LVCMOS33}}',
        ]
    for i, pin in enumerate(LED_PINS):
        lines += [
            f'define_attribute {{p:led[{i}]}} {{PAP_IO_DIRECTION}} {{Output}}',
            f'define_attribute {{p:led[{i}]}} {{PAP_IO_LOC}} {{{pin}}}',
            f'define_attribute {{p:led[{i}]}} {{PAP_IO_VCCIO}} {{3.3}}',
            f'define_attribute {{p:led[{i}]}} {{PAP_IO_STANDARD}} {{LVCMOS33}}',
        ]

    lines += ['', '### ============ 3. DDR3（Bank 3，1.5V）============']
    # 按"控制/地址 → 数据"的顺序输出，便于人工核对
    order = (['mem_rst_n', 'mem_ck', 'mem_ck_n', 'mem_cke', 'mem_cs_n',
              'mem_ras_n', 'mem_cas_n', 'mem_we_n', 'mem_odt']
             + [f'mem_a[{i}]' for i in range(15)]
             + [f'mem_ba[{i}]' for i in range(3)]
             + [f'mem_dq[{i}]' for i in range(32)]
             + [f'mem_dm[{i}]' for i in range(4)]
             + [f'mem_dqs[{i}]' for i in range(4)]
             + [f'mem_dqs_n[{i}]' for i in range(4)])
    missing = [p for p in order if p not in pinmap]
    if missing:
        raise SystemExit(f'手册映射里缺这些端口: {missing}')
    for port in order:
        v = pinmap[port]
        # DDR3 侧方向：DQ/DQS 双向，其余输出。
        direction = 'Inout' if ('dq' in port) else 'Output'
        # 电平标准**照官方例程 `07_ddr3_test`（本板跑通的工程）**：
        #   CK / DQS 及它们的反相端用差分 `HSTL15D_I`（10 个：ck, ck_n, 4×dqs, 4×dqs_n）
        #   其余单端信号用 `HSTL15_I`（61 个）
        # 一开始我们按"DDR3 常见是 SSTL15"写了 SSTL15_I / SSTL15D_I，与官方例程不符——
        # 接收门限不同，必须按官方基准改。
        std = 'HSTL15D_I' if ('dqs' in port or port in ('mem_ck', 'mem_ck_n')) else 'HSTL15_I'
        lines += [
            f'# {v["manual_signal"]}',
            f'define_attribute {{p:{port}}} {{PAP_IO_DIRECTION}} {{{direction}}}',
            f'define_attribute {{p:{port}}} {{PAP_IO_LOC}} {{{v["pin"]}}}',
            f'define_attribute {{p:{port}}} {{PAP_IO_VCCIO}} {{1.5}}',
            f'define_attribute {{p:{port}}} {{PAP_IO_STANDARD}} {{{std}}}',
        ]

    lines += ['', '### ============ 4. DDR3 PHY 物理约束 ============']
    for inst, loc, why in PHY_LOCS:
        lines += [
            f'# {why}',
            f'define_attribute {{i:{inst}}} {{PAP_LOC}} {{{loc}}}',
        ]
    for net, why in DEDICATED_ROUTE_RELAX:
        lines += [
            f'# {why}',
            f'# 放宽"专用走线"要求（Place-0084 的官方处理办法）；最终仍由时序分析把关。',
            f'define_attribute {{n:{net}}} {{PAP_CLOCK_DEDICATED_ROUTE}} {{FALSE}}',
        ]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(lines) + '\n', encoding='utf-8')

    n33 = len(BANK33) + len(LED_PINS)
    print(f'输出 {OUT.relative_to(REPO)}')
    print(f'  3.3V 板级信号 {n33} 个（时钟 {len(BANK33)} + LED {len(LED_PINS)}）')
    print(f'  DDR3 信号 {len(order)} 个（1.5V；61×HSTL15_I + 10×HSTL15D_I，'
          f'与官方例程 07_ddr3_test 逐脚一致）')
    print(f'  合计 {n33 + len(order)} 条管脚约束')
    print(f'  DDR3 PHY 位置约束 {len(PHY_LOCS)} 条 + 专用走线放宽 {len(DEDICATED_ROUTE_RELAX)} 条')


if __name__ == '__main__':
    main()
