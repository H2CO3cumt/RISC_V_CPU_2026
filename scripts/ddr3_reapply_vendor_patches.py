# -*- coding: utf-8 -*-
r"""重新生成 HMIC_S IP 之后，把必须改的厂商示例文件补丁重新打上。

## 为什么需要它

`ip_generate.exe` 会**整体重生成** `example_design/`，所以任何手工改动都会被冲掉。
实测被冲掉的只有一处，但它会让串口直接不可用：

`example_design/rtl/test_ddr.v` 里

    ipsxb_uart_ctrl_top_32bit #( .CLK_DIV_P (16'd72) ) u_ipsxb_uart_ctrl (...)

原注释写 "115200bps for 50MHz clk"，但**两个数自相矛盾**：50_000_000 / 72 ≈ 694 kbaud，
不是 115200。而且同一文件顶部 `parameter TH_1S = 27'd50_000_000;` 表明原设计就是按 50 MHz 写的。
50 MHz 下要得到 115200 baud，分频比应为 50_000_000 / 115200 = 434.03 → 取 **434**
（实际 115207 baud，误差 0.007%）。

**能不能不改厂商文件？** 不能只靠参数覆盖：`test_ddr` 端口表里没有 `CLK_DIV_P`
（只有 MEM_ROW/COL/BADDR/DQ/DM/DQS 这些），所以没法在例化 `test_ddr` 时传进去。
要彻底避开改厂商文件，得自己复制一份 DDR3 控制器 wrapper 并重连 60+ 根端口，风险大于收益；
因此选择"改 + 可复现地重打"，并把这条记进 `fpga/ddr3_smoke/README.md` 的已知风险。

本脚本**幂等**：已经是 434 就报"已打过"；找不到目标就报错退出，不静默成功。

## 补丁 2：把 `free_clk` 改成内部接 `ref_clk`（与官方例程 07_ddr3_test 结构一致）

官方例程（`C:\Users\xwc\Desktop\07_ddr3_test`）里同一个 `test_ddr.v` 的写法是：

```verilog
//input   free_clk        ,        ← 端口被注释掉
assign free_clk = ref_clk ;        ← 模块内部直接把两者接在一起
```

而 `ip_generate` 给我们这份（较旧版本）暴露了两个独立输入端口 `ref_clk` / `free_clk`。
两者都源自同一个 50 MHz 引脚，但**在时序分析里是两个不同的时钟对象**：

- 官方：全程只有 `ref_clk` 一个时钟域 → 实测 `Design Summary : All Constraints Met.`
- 我们：多出 `free_clk` 那一支 → 时序报 232 个端点 hold 违例（WHS -4.411 ns）
  以及 setup/恢复类路径的怪异结果。

本补丁把 `test_ddr` 的 `free_clk` 输入端口改成模块内 `assign free_clk = ref_clk;`，
与官方结构一致。顶层相应不再连 `free_clk`。

用法：
  python scripts/ddr3_reapply_vendor_patches.py [--check]
  --check 只检查不写（用于流水线里断言补丁在位）
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

REPO = Path(r'D:\RISC_V_CPU_2026')
TARGET = REPO / 'fpga/ddr3_smoke/ip/ddr3_mes50hp/example_design/rtl/test_ddr.v'

ORIG = "    .CLK_DIV_P                  (16'd72                       ), //115200bps for 50MHz clk."
MARK = '// ===== CHANGE by RISC_V_CPU_2026'
MARK2 = '// ===== CHANGE2 by RISC_V_CPU_2026'


def patched_block(indent: str = '    ') -> str:
    """UART 分频补丁 —— **结论：保持厂商原值 16'd72，不改**。

    这里曾经把它改成 16'd434，理由是"注释说 115200bps for 50MHz clk，
    而 50e6/72 ≈ 694k 与之矛盾"。**那个推理是错的**，白折腾了一轮：

    读 `ipsxb_seu_uart_tx.v` 明文源码（第 37、49–57 行）才知道，
    `clk_en` 之后还有一级 **6 分频**（`cnt==3'd5` 归零，即 0..5 六个状态）：

        wire bit_en;                 // 5 div from clk_en
        if(cnt == 3'd5) cnt <= 3'd0;
        assign bit_en = (cnt == 3'd5) && clk_en;

    所以**波特率 = clk / (clk_div × 6)**，不是我原先假定的 clk / clk_div：

        厂商原值 72 : 50e6 / (72×6)  = 115,740 baud（对 115200 误差 0.47%，接收端完全容）
        我改的 434: 50e6 / (434×6) =  19,201 baud  ← 与 115200 差 6 倍，一个字节都收不到

    实测证据：改成 434 后，板上 LED 显示 pll_lock / ddr_init_done 都亮、心跳在闪
    （说明 DDR3 本身初始化成功），但串口在 115200/57600/9600/230400/38400 五种波特率下
    **全都收不到任何字节**。这正是分频算错 6 倍的典型现象。

    ⇒ 保留 16'd72。本函数返回原样文本（不改任何东西），仅留档说明。
    """
    return indent + ".CLK_DIV_P                  (16'd72                       ), //115200bps for 50MHz clk."


def patch_free_clk(text: str) -> tuple[str, str]:
    """把 `free_clk` 输入端口改成模块内 `assign free_clk = ref_clk;`（对齐官方结构）。

    必须分**两处**改：端口表里删掉该端口行，模块体开头（`) ;` 之后）再插入 wire+assign。
    第一版把 `wire/assign` 直接插在端口表中间，Verilog 非法，
    报 `'test_ddr' is referenced to undefined module`（模块根本没编译出来）。
    """
    if MARK2 in text:
        return text, '已打过（free_clk = ref_clk）'
    m = re.search(r'^[ \t]*input[ \t]+free_clk[ \t]*,?[ \t]*\r?\n', text, re.M)
    if not m:
        return text, '找不到 `input free_clk` 端口，跳过（结构可能已与官方一致）'
    text = text[:m.start()] + text[m.end():]

    # 在模块端口表结束的 `);` 之后插入声明
    hdr = re.search(r'^\)\s*;\s*\r?\n', text, re.M)
    if not hdr:
        raise SystemExit(f'找不到模块端口表结尾的 ");"，无法插入 free_clk 声明: {TARGET}')
    decl = (
        '// ===== CHANGE2 by RISC_V_CPU_2026 (S1) =====\n'
        '// 官方例程 07_ddr3_test 的同一文件把 free_clk 端口注释掉，改为内部\n'
        '// `assign free_clk = ref_clk;`。两者同源，但保留成两个输入端口会让时序分析\n'
        '// 把它们当成两个时钟域（实测 232 个端点 hold 违例 WHS -4.411 ns）。\n'
        'wire  free_clk;\n'
        'assign free_clk = ref_clk;\n'
        '// ===== END CHANGE2 =====\n'
    )
    text = text[:hdr.end()] + decl + text[hdr.end():]
    return text, '已打补丁：free_clk 端口 => 内部 assign free_clk = ref_clk'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()

    text = TARGET.read_text(encoding='utf-8')

    # --- UART 分频：**保持厂商原值**，不改 ---
    # 若发现被改成了 434（历史遗留），改回 72。
    m = re.search(r'\.CLK_DIV_P\s*\(\s*16\'d434\s*\)[^\n]*', text)
    if m:
        text = text[:m.start()] + ".CLK_DIV_P                  (16'd72                       ), //115200bps for 50MHz clk." + text[m.end():]
        print(f'已撤销历史错误改动: CLK_DIV_P 434 => 72（正确波特率 115740，见上方说明）({TARGET.name})')
    else:
        print(f'UART 分频保持厂商原值 16\'d72（未改动）: {TARGET.name}')

    # --- free_clk 内部接 ref_clk（对齐官方例程结构）---
    if args.check and MARK2 not in text:
        raise SystemExit(f'FAIL: {TARGET.name} 的 free_clk 补丁不在位')
    text2, msg = patch_free_clk(text)
    print(f'free_clk 结构 {msg}  ({TARGET.name})')
    if text2 != text:
        TARGET.write_text(text2, encoding='utf-8')


if __name__ == '__main__':
    main()
