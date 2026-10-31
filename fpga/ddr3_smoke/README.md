# fpga/ddr3_smoke —— S1（DDR3 打通）专用工程

> 状态：**未完成，停在"IP 生成"这一步之前**。目录里已经备好按本板手册重做的约束与配置单，
> 等确认一件事（见 §3）就可以继续。
> 完整调研见 `docs/ddr3_s1_survey.md`；对应 `docs/handoff_next.md` §3.3 的 S1 闸门。

**这个工程与三个交付工程完全隔离**：`fpga/logic_analyzer`、`fpga/coremark`、`fpga/coremark_80m`
以及演示工程 `fpga/timer_demo` 都**不被本目录改动**。

---

## 1. 为什么不能直接用厂商例程

厂商 IP 包 `D:\Pango\PDS_2024.2-SP2\ip\system_ip\ipsxb_hmic_s\` 里
`pnr\50h_ddr3_fbg484_b3_x32.fdc` 的名字看起来正好匹配本板（50h + FBG484 + x32），
但把它与 **MES50HP 官方硬件手册**表 2-4 逐脚比对：

| 项 | 结果 |
|---|---|
| DDR3 信号 | 手册 72 条 ／ 模板 71 条 |
| **管脚一致** | **仅 4 条** |
| **管脚不一致** | **65 条** |
| 典型错位 | 模板 `mem_ck=F3` ↔ 手册 `F3=ddr3_addr[3]`；模板 `mem_cs_n=C1` ↔ 手册 `C1=ddr3_reset_n` |
| 模板时钟脚 | `ref_clk=F14` ↔ 本板 F14 是**网口 1 的 RX_CLK**；`free_clk=Y11` ↔ 本板是 **J8 扩展口** |

⇒ **厂商模板不能用于本板**：把 DDR3 的 CK/CS 打到网口 RX_CLK 上，
既有损坏风险，也必然跑不通。所以本目录里的管脚约束**全部由手册表 2-4 重新生成**。

## 2. 目录内容

| 文件 | 作用 |
|---|---|
| `constraints/ddr3_pins_from_manual.fdc` | **按手册重做的 71 个 DDR3 端口约束**（61×`SSTL15_I` + 10×`SSTL15D_I`，`VCCIO=1.5`）。由 `scripts/ddr3_map_manual_pins.py` 生成，自检 6 项全过 |
| `doc/ip_config_checklist.md` | HMIC_S IP 的 **96 个配置参数逐项清单**（72 个 `PAD_*` 管脚已按手册填好），由 `scripts/ddr3_ip_config_checklist.py` 生成 |
| `doc/vendor_template_for_reference_DO_NOT_USE.fdc` | 厂商原模板，**只作对照留存，禁止使用** |
| `rtl/` | 空。**可综合源码要由 PDS 的 IP 生成器产出**，见 §3 |

## 3. 已经验过什么（本目录的约束是"被 PDS 接受并落地"的，不是只写在纸上）

`constraints/ddr3_pins_from_manual.fdc` **不是**只做了静态自检，而是真的过了一遍 PDS：

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
  -ExecutionPolicy Bypass -File scripts\run_ddr3_pin_check.ps1
```

该脚本会生成一个不含逻辑的**桩顶层**（只声明 71 个 `mem_*` 端口），交给 PDS 跑
`compile → synthesize → dev_map`，实测结果：

| 项 | 结果 |
|---|---|
| PDS 退出码 | **0** |
| `E:` 行数 | **0** |
| "Found N error(s)" | **0 error(s), 0 critical warning(s)** |
| **实际落到管脚上的 IO 数** | **71 / 71** |
| I/O 标准 / VCCIO 冲突 | 无 |

216 条告警全部是 `ConstraintEditor-4042: lacks attribute 'PAP_IO_DRIVE'/'PAP_IO_SLEW'/'BUS_KEEPER'`
（每个端口 3 条 × 71 ≈ 213），属于"没显式写驱动能力/转换率"的建议性提示，
交付工程同样有这一类告警，不影响功能。

> **一个必须记住的坑**：第一版桩顶层写成了**空模块**，PDS 直接报
> `Create black box for empty module` 并把顶层当黑盒 —— 那时 **I/O 约束根本没被检查**，
> 报出来的 "0 error" 是**假通过**。桩顶层必须有非空逻辑（本脚本给每个 DQ/DQS 加了一条
> 三态驱动），并且校验必须跑到 **`dev_map`** 才算数（管脚位置与电平是在那一步落到器件上的，
> 只跑 compile 不够）。
>
> 这个脚本**不做布局布线、不出版本**，只操作 `tmp/ddr3/pin_check` 临时工程，
> 不触碰任何交付工程，所以不可能影响板上现有位流。

## 4. IP 生成**已经全程无 GUI 打通**（2026-09-29）

### 4.1 先说结论：不用点界面了

原先以为"必须在 PDS 界面上点一次 Generate"，**这个结论已被推翻**。实测找到的完整无 GUI 通路：

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
  -ExecutionPolicy Bypass -File scripts\run_ddr3_ip_generate.ps1
```

它做三件事（全部无人工点击）：

| 步骤 | 工具 | 说明 |
|---|---|---|
| 1. 创建 IP 实例 | `ip_compiler.exe -c -n <名> -i <实例>.ipc -m <IP模型目录> …` | 产出 `.ipc`（XML，264 个参数）|
| 2. 改成本板参数 | `scripts/ddr3_ipc_patch.py` | 改 `<value>`，**并校验新值在该参数的合法列表里** |
| 3. 生成 IP RTL | `ip_generate.exe -i <实例>.ipc …` | 产出 `rtl/`（64 文件）+ `example_design/` + `pnr/` |

**实测结果（可复现）**：生成的顶层 `ddr3_mes50hp.v` 里
`MEM_DQ_WIDTH = 32`、`MEM_DQS_WIDTH = 4`、`MEM_DM_WIDTH = 4`、
`MEM_ROW/COLUMN/BANK = 15/10/3`，`Done: 0 error(s)`，共 192 个文件。
脚本**自带校验**：位宽不对会直接报错退出，不会静默产出一个错配置的 IP。

> **最容易踩的坑（实测教训，已写进脚本）**：位宽类参数**必须成组改**。
> 只把 `MEM_DQ_WIDTH` 改成 32、却留着 `MEM_DQS_WIDTH=2`，生成出的顶层**仍然是 16 位**
> —— 工具发现这组值自相矛盾后**静默回退**，不报错。必须同时给
> `MEM_DQS_WIDTH=4` 与 `MEM_DM_WIDTH=4`（都等于 DQ 位宽 ÷ 8）。`ddr3_ipc_patch.py` 已成组设好。

### 4.2 万一要手工在界面上做（备用方案）

如果哪天脚本跑不通，界面上做也可以，要点一样：**`Total Data Width` 改 32**、
器件型号选 `MT41K256M16xx-15E`、Step3 勾 `Enable fdc file select` 并指向
`constraints/ddr3_pins_from_manual.fdc`、勾 `Enable CS_n`、`Control/Address Bank` 选 `B3`。
⚠️ **绝不要**用 IP 自带的 `50h_ddr3_fbg484_b3_x32.fdc`（65/69 个管脚与本板不符，有损坏风险）。
逐项手卡见 `doc/ip_gui_手卡.md`。

### 4.3 时钟怎么接（已定）

**`ref_clk` 与 `free_clk` 都接 P20。** 依据：手册确认 F14 是网口 1 的 RX_CLK、
Y11 是 J8 扩展口引脚，都不是时钟源；P20 是板上唯一有据可依的 50 MHz。
PDS 允许一个输入脚驱动多个网络与多个 `create_clock`。
注意 `free_clk` **不是 IP 端口**，是例程给板级逻辑（UART/控制）用的时钟。

## 5. 上板结果（2026-09-29 完成）

**状态：`S1 DDR3 SMOKE BOARD PASS`。** PDS 全流程 0 error 且**时序全部满足**
（Setup WNS +0.367 ns、Hold WHS +0.044 ns，失败端点 0）。

```powershell
# 1) 构建（配方已含一轮额外的 place/route/route_optimize 时序优化，少了它会有小违例）
cd fpga\ddr3_smoke
& 'D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe' -file pds_recipe.tcl -project_name ddr3_smoke

# 2) 下载（新增了 ddr3 配置）
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
  -ExecutionPolicy Bypass -File scripts\program_board.ps1 -Config ddr3

# 3) 板级验收（读厂商例程的状态寄存器）
python python\ddr3_smoke_board.py --port COM11 --seconds 8
```

位流 SHA-256：`FAEDF47618647C36FACBFF6DF0E5DE623F20ECD461FFA6997D724ABE93561B76`

### 5.1 串口协议与**波特率公式**（最容易搞错的一条）

命令协议来自 `example_design/rtl/uart_ctrl_32bit/ipsxb_cmd_parser_32bit.v`（明文）：

- 写：`'w'`(0x77) + addr[7:0] + addr[15:8] + addr[23:16] + data[31:0]（共 8 字节）
- 读：`'r'`(0x72) + addr[7:0] + addr[15:8] + addr[23:16]（共 4 字节），返回 4 字节**小端**

**波特率 = `clk / (clk_div × 6)`，不是 `clk / clk_div`。**
依据是 `ipsxb_seu_uart_tx.v` 第 37、49–57 行——`clk_en` 之后还有一级 **6 分频**：

```verilog
wire bit_en;                 // 5 div from clk_en
if(cnt == 3'd5) cnt <= 3'd0;         // cnt: 0..5，六分频
assign bit_en = (cnt == 3'd5) && clk_en;
```

所以 50 MHz + 厂商原值 `CLK_DIV_P = 16'd72` → 50e6/(72×6) = **115,740 baud**
（对 115200 误差 0.47%，可用）。**这个值不要改**：本项目一度按 `clk/clk_div`
把它改成 434，得到 19,201 baud、6 倍偏差，结果在 115200/57600/9600/230400/38400
五种波特率下**一个字节都收不到**；恢复 72 后立刻正常。

### 5.2 状态寄存器（`test_ddr.v` 第 389、402 行）

```text
0x80 : {15'b0, heart_beat_led(bit16), 3'b0, ddr_init_done(bit8),
        3'b0, dll_lock(bit4), 3'b0, pll_lock(bit0), 3'b0, err_flag_led(bit20)}
0x8B : {14'b0, test_rd_state, test_wr_state, test_main_state, err_cnt}
       err_cnt 是 wire [7:0] -> bit7:0（**只有 8 位**）；main=bit11:8、wr=bit14:12、rd=bit17:15
```

**位宽必须照信号真实宽度解**：`err_cnt` 只有 8 位，若按 10 位解会得出 768 这种
超过 255 的"错误计数"，从而误判 BIST 失败。

### 5.3 板上 LED

`led[3:0] = {err_flag_led, heart_beat_led, ddr_init_done, pll_lock}`，对应
`B2`(pll_lock) / `A2`(ddr_init_done) / `B3`(心跳) / `A3`(err_flag)。
正常状态：前两个常亮、心跳闪、err_flag 不亮。

### 5.4 已知偏差（如实记录）

状态寄存器 `pll_lock` 位（`0x80` bit0）在 31 次连续采样中**恒为 0**，
但 `dll_lock`=1、`ddr_init_done`=1、BIST 正常循环、`err_cnt`=0 不可能同时成立
（这些都需要稳定的 PLL 时钟），且板上 LED1 实测常亮
⇒ 判定**该状态位本身不可信**（极性/接线），不是"PLL 没锁"。验收脚本把它列为 NOTE。

### 5.5 本目录尚未做的事

`test_ddr` 例程只做 BIST 与状态寄存器，**没有吞吐量/延迟测量**。
所以已拿到的是"**DDR3 控制器在本板真正工作**"的证据，**不是** DDR3 性能数字。
若要把 DDR3 当"真实存储后端"报数，需要在 Core 外再加一层带计数器的访问器。

## 6. 重新生成约束与配置单

```powershell
# 生成按手册重做的管脚映射与 .fdc（需要 tmp/ddr3/manual_pins.json，它由手册 PDF 抽出）
python scripts\ddr3_map_manual_pins.py
# 生成 IP 配置单（需要厂商 IP 安装目录）
python scripts\ddr3_ip_config_checklist.py
# 按手册管脚修正 IP 的分组参数（含一致性断言）
python scripts\ddr3_ipc_fix_groups.py
# 生成工程约束（管脚 + PHY 位置约束）
python scripts\ddr3_gen_smoke_fdc.py
# 把约束交给 PDS 验一遍（compile -> synthesize -> dev_map，不出版本）
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
  -ExecutionPolicy Bypass -File scripts\run_ddr3_pin_check.ps1
```

前几个脚本都带自检：管脚是否与手册逐条一致、是否有重复管脚、是否与 3.3 V 外设冲突、
byte lane 分组是否与手册一致、分组参数两族是否自洽。

> **电平标准**：`61×HSTL15_I + 10×HSTL15D_I`（CK 与 4 对 DQS 用差分）。
> 这是照官方例程 `07_ddr3_test` 改的——原先按"DDR3 常用"写的
> `SSTL15_I/SSTL15D_I` 与官方不符，接收门限不同。
