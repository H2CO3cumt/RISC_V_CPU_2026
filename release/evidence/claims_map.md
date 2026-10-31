# 交付材料数字对照表（Claim ↔ Evidence ↔ Bitstream）

> 用途：评审/答辩时，材料里出现的**每一个数字**都必须能在这张表里找到
> ①它来自哪个证据文件、②它对应哪个位流（含 SHA-256）、③用什么命令能重新跑出来。
> 表中不含任何"估计""大约""应该"——凡是没测过的，明确写在 **未宣称** 一节。
>
> 生成日期：2026-09-30　　维护规则：任何新数字进入材料前，必须先在本表登记。

---

## 0. Core 指纹（所有数字的共同基准）

| 项 | 值 | 说明 |
|---|---|---|
| `rtl/pipeline_cpu.v` SHA-256 | `B58496706686E37BBA09E01861F1C7FE2AED8A5765C0F277E1F0DF5B91B071C2` | 本届全部数字均基于这一份 Core，**未改动** |
| Core 端口 / 事务语义 | 冻结，未变 | 见 `docs/interfaces.md`；Cache/burst 全部在 Core 外部 |
| 板载晶振 | 50 MHz（`clk_50m = P20`） | **交付设计经片上 PLL 工作在 85 MHz**；"秒"级换算的分母按实际时钟取 |

复现：`Get-FileHash rtl\pipeline_cpu.v -Algorithm SHA256`

---

## 1. 交付位流与综合/时序

> **2026-09-30 交付配置切换**：交付主位流由 **50 MHz 版**改为 **85 MHz PLL 版**。
> 理由：赛题指标第 (2) 条要"**满足时钟约束前提下的最高工作频率**"，
> 交付件**本身工作在 85 MHz** 才能自证，避免"报告写 85 MHz、交的位流却是 50 MHz"的观感问题。
> 50 MHz 版工程原样保留，其位流作为**已验证备用**随包提供
> （对应 `docs/roadmap.md` 任务 35「主版本失败时能切换已验证备用版本」）。

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| **交付主位流（85 MHz）** | `mes50hp_logic_analyzer_pll_top.sbit` | `fpga/logic_analyzer_85m/` | **`C017ED10195502739BEBF914DD3BC6F3CAA84C0EAEB6E9E97559248B003FAA4F`** |
| 交付设计工作频率 | **85.000 MHz**（板载 50 MHz 晶振 × PLL：IDIV 1 → PFD 50 MHz，FDIV 17 → VCO 850 MHz，ODIV0 10） | PDS 时序报告的生成时钟 `clk_50m\|u_pll/u_pll_85m/CLKOUT0_Inferred` | 同上 |
| LUT | **4995**（LUT as Logic：CLMA 3096 + CLMS 1899） | `fpga/logic_analyzer_85m/flow.log` 布局布线后资源表；`automated_metrics.json` → `final.lut` | 同上 |
| FF（寄存器） | **3907**（CLMA 2330 + CLMS 1577） | 同上 → `final.ff_implemented` | 同上 |
| DRM（BRAM） | **6.0** | 同上 → `final.drm` | 同上 |
| APM（乘法器） | **4** | 同上（RV32IM 的 `rtl/mdu.v` 占用） | 同上 |
| Setup WNS | **+0.577 ns** | `fpga/logic_analyzer_85m/report_timing/mes50hp_logic_analyzer_pll_top.rtr`（Slack (MET) 0.577）；`automated_metrics.json` → `final.setup_wns_ns` | 同上 |
| Hold WHS | **+0.308 ns** | 同上（Slack (MET) 0.308）→ `final.hold_whs_ns` | 同上 |
| 估算 Fmax | **89.3841 MHz**（周期 11.1877 ns = 11.7647 − 0.577） | 同上 → `final.estimated_fmax_mhz` | 同上 |

> **2026-10-27 更正**：本表原先登记 LUT 4479 / FF 3610 / WNS +0.588 / WHS +0.310 / Fmax 89.4721 MHz，
> 那组数字对应 **2026-10-10 第三次重打**的位流（`8908FD8C…`，加 M 扩展之前）。
> 2026-10-14 第四次重打加入 `rtl/mdu.v` 与采集源双选后，位流换成 **`C017ED10…`**，
> 但本表只更新了 SHA、没更新资源与时序，导致同一颗位流出现两套数字。
> 现按该位流自己的 P&R 报告（`flow.log` 资源表 + `report_timing/*.rtr` 的 Slack）更正；
> 三处副本 SHA 一致，且已于 2026-10-27 用 `scripts/program_board.ps1 -Config la85` 重新下载到板上，
> 日志为 `PROGRAM PASS` 与 `done bit is 1`。`automated_metrics.json` 的 `final` 段与本次更正一致。
| **已验证备用位流（50 MHz）** | `mes50hp_riscv_logic_analyzer_50m_fallback.sbit` | `fpga/logic_analyzer/` | `8102634A23ACB68BF9EDA4110E48A3ECFE28186A4E76D0C5717856903986B012` |

> **2026-10-14 第四次位流重打（M 扩展 + 采集源双源可选）**：la85 `8908FD8C…` → **`C017ED10…`**、
> la50 `FDDF038C…` → **`8102634A…`**；新增 RV32IM 计分位流 `fpga/coremark_im` = `BE7A4FF3…`。
> 本批还包含：`rtl/mdu.v`（RV32IM）、`logic_analyzer_mmio` 的采集源选择（MMIO 寄存器 18）、
> 板级顶层探针寄存器、新固件（0xA8 命令）。板级证据：五模式 **100/100 PASS**
> （`release/evidence/logic_analyzer_board_85m/`，旧目录备份在 `results/evidence_backup_85m_*`）
> + **Core 探针 6 次采集 PASS**（`release/evidence/core_probe_board/`）
> + RV32IM CoreMark **Score 113.642 / CoreMark-MHz 2.272**（`coremark_board_im.json`）。
>
> **同批补做（2026-10-14，未重打位流）**：采集源开关接进两个上位机界面，并修掉两种
> "采集对、解释错"的假失败（判据改为按 **view** 而不是按模式选，见
> `docs/application_logic_analyzer.md` §6.10.5/§6.10.6）。实板证据：
> `release/evidence/logic_analyzer_board_85m/ui_source_check/pyui_board_check.log`
> （pyUI 真路径四种"模式×源"组合全 PASS：报文长度 16/16/13/13、命令码 0xA8/0xA8/0xA5/0xA5）
> 与同目录 `singlefile_selftest.log`（单文件界面六模式全通过）。
> 同批记录一条已知限制：**触发条件永不出现会把固件停住，只能按 REST 或重下位流恢复**
> （`docs/application_logic_analyzer.md` §6.10.7，实板复现一次后重下 `la85` 恢复）。
>
> **同批追加（2026-10-14，新打一颗位流）**：补齐**与交付同频的 RV32IM 计分点** `cmim85` ——
> 工程 `fpga/coremark_im_85m`（源文件取自 `coremark_85m`，只把镜像换成 `-march=rv32im`，4000 迭代），
> 位流 `EE8B65360B0B07189C66460D813A6CC990FE87BE156AEA5BC7779B5D3C68D6F1`，
> `All Constraints Met`（WNS **+0.250 ns** / 估算 **86.8456 MHz** / 4198 LUT / 3361 FF），
> 实体板 **Score 193.192、CoreMark/MHz 2.272、20.704 s、官方 CRC PASS**（详见 §3.1c）。
> 至此"85 MHz 计分点只有 rv32i 79.587"这一栏补齐，**M 扩展在交付频率上同样跑得通**。

> **2026-10-10 第三次位流重打（移除仪器面板）**：la85 `005BD00B…` → **`8908FD8C…`**、
> la50 `ED38436E…` → **`FDDF038C…`**。上一轮加的 8 键 8 LED 仪器面板**已按用户要求整套移除**
> （用户认为按键没用），LED 回到原来的 `gpio_out`。移除后的资源/时序数字
> （LUT 4479 / FF 3610 / DRM 6.0 / WNS +0.588 / WHS +0.310 / Fmax 89.4721 MHz）
> 与加面板之前那一版**逐项一致**，即回退是功能等价的；`captures=100` 板级复测通过。
> 注意：`.sbit` 文件头里带构建时间戳，所以**即使 RTL 完全相同，每次重打的 SHA-256 也不同**，
> 哈希锁必须在每次重打后刷新。**镜像抓取与仪器读数保留**，只有按键/面板 LED 被移除。

> **2026-10-10 位流重打（镜像抓取）**：la85 `788F1CEB…` → **`66A1E9A7…`**、
> la50 `BCAE040A…` → **`0477DDA4…`**（旧位流备份 `tmp/la50_archived_BCAE040A.sbit`）。
> 改动：板级顶层 ch7 镜像 `uart0_rx`、采集深度 256→2048、固件新增 `0xA7` 镜像命令并修四处解码缺陷。
> 两个哈希已同步进 `scripts/demo_preflight.ps1`；la85 板级 5 模式 ×20 = **100/100**，
> la50 只做 5 模式 ×3 冒烟（`release/evidence/logic_analyzer_board_50m_recheck/`）。

**交付主位流三处副本（互为校验，哈希完全相同）**：
1. `fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit`（原始交付）
2. `release/final_submission/bitstream/mes50hp_riscv_logic_analyzer.sbit`
3. `release/artifacts/mes50hp_riscv_logic_analyzer.sbit`

**稳定性证据（85 MHz）**：J8 四模式**累计 320 次采集零失败**
（首次验收 80 次 + 3 轮 soak × 80 次）。
证据：`release/evidence/logic_analyzer_board_85m/`、`release/evidence/logic_analyzer_board_85m_soak/`。
> 上面这 320 次是**旧位流（`788F1CEB…`，无镜像）**的成绩；2026-10-10 换位流后重跑的
> 5 模式 ×20 = 100/100 见 §4。两批数字都可以引用，但必须说清是哪一版位流。

> ⚠️ **备用位流的 50 MHz 数字**（不要再当成交付数字引用）：
> 位流 `BCAE040A…`、WNS +1.989 ns、WHS +0.315 ns、估算 Fmax 55.5216 MHz、
> LUT 4536 / FF 3852、工作频率 50 MHz。这些只在"切到备用版本"时才是当前数字。

**切换开关（改回 50 MHz 只需改这几处）**：
`python/release_evidence.py` 的 `configs`、`scripts/export_final_submission.ps1` 顶部的
`$srcProj/$srcTop/$srcFdcName/$srcPds/$srcBrdEvid` 五个变量、
`scripts/create_release_manifest.ps1` 的 `$artifacts`、`scripts/audit_release_package.ps1` 的 `$sourceBitstream`、
`scripts/demo_preflight.ps1` 的标签。原始状态快照在 `tmp/delivery_50m_snapshot/`。

复现：
```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_final_regression.ps1
```
（该脚本内部会重新跑 PDS 时序并刷新 `automated_metrics.json`）

---

## 2. CoreMark（仿真，Before/After）

| 宣称的数字 | Predictor On | Predictor Off | 证据文件 |
|---|---|---|---|
| cycles | **1,251,724** | 1,604,264 | `automated_metrics.json` → `coremark_predictor_on/off` |
| instret（退休指令） | 786,925 | 776,138 | 同上 |
| CPI | **1.5907** | 2.0670 | 同上 → `cpi` |
| 分支 | 216,077 | 212,537 | 同上 |
| Flush（分支惩罚） | **69,120** | 161,742 | 同上 |
| BTB 命中 | **221,615** | 0 | 同上 → `btb_hit` |
| 误预测 | 69,120 | 161,742 | 同上 |
| **加速比** | **−21.98% cycles**（1.2819×） | 基线 | 由上两行计算 |

- 两组的**官方 CRC 校验均在 RTL 仿真中通过**（`validation` 字段），不是"跑完就算"。
- 原始日志：`tmp/coremark/uart-random-0-predictor-1.log` / `-predictor-0.log`。
- 对应位流：交付位流（`BCAE040A…`）——Predictor 是编译期参数，On 为交付配置。

复现：`scripts\run_coremark_pipeline_tb.ps1`

---

## 3. CoreMark（实板）

### 3.1 50 MHz 计分配置（**主口径**）

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 迭代次数 | 1000 | `release/evidence/coremark_board.json` | `fpga/coremark/generate_bitstream/mes50hp_coremark_top.sbit` |
| 总 ticks | **1,068,006,999** | 同上 → `ticks` | = `DC95F9D087B7E29BB8780A46179FDE8D754563BB018B4E973FD08103232F5675` |
| 耗时 | **21.360 s** @ 50 MHz | 同上 → `seconds_x1000` = 21360 | 同上 |
| CoreMark 分数 | **46.816**（`score_x1000` = 46816） | 同上 → `score_x1000` | 同上 |
| CoreMark/MHz | **0.936**（`×1000` = 936） | 同上 → `coremark_per_mhz_x1000` | 同上 |
| 官方 CRC 校验 | **PASS**（`crcfinal = 0xd340`） | 同上 → `validation`；CRC 见 `coremark_uart.log` | 同上 |
| CPI | **≈1.50**（实测 1.494–1.508，**窗口敏感**，见下） | 同上 → `cpi_x1000`；另见 `release/evidence/board/README.md` | 同上 |

### 3.1b 50 MHz **RV32IM** 计分配置（2026-10-14 新增，M 扩展增强口径）

> ⚠️ 这是**另一套 ISA**的配置，不是 3.1 的替代品。`rv32i`（3.1）仍是默认与可比口径；
> 引用分数必须写明用的是哪一个。CoreMark 输出自带 `Compiler flags` 一行可自证。

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 迭代次数 | 2000（运行 17.599 s ≥ 10 s） | `release/evidence/coremark_board_im.json` | `fpga/coremark_im/generate_bitstream/mes50hp_coremark_top.sbit` |
| 总 ticks | **879,950,706** | 同上 → `ticks` | = `BE7A4FF31F2214AC12D230B4B48079B80C4A17A33C72F106ABAB407FD57D6F36` |
| CoreMark 分数 | **113.642** | 同上 → `score_x1000` | 同上 |
| **CoreMark/MHz** | **2.272**（vs rv32i 0.936，**2.43×**） | 同上 → `coremark_per_mhz_x1000` = 2272 | 同上 |
| 官方 CRC 校验 | **PASS**（`crclist 0xe714` / `crcmatrix 0x1fd7` / `crcstate 0x8e3a` / `Correct operation validated.`） | `release/evidence/coremark_uart_im.log` | 同上 |
| CPI | **1.550**（`cycles 1,073,539,140 ÷ instret 692,550,646`，窗口敏感，只写 ≈1.55） | 同上 → `cpi_x1000` = 1550 | 同上 |
| RTL 仿真对照 | 同 TB/程序：rv32i 1,251,724 拍 → rv32im **594,792 拍**（−52.5%） | `tmp/coremark/sim-*.log`（`run_coremark_pipeline_tb.ps1 -March rv32im`） | — |

> ⚠️ **2026-10-14 更正**：本表原写 CPI `1.529`，全仓库找不到任何该值的出处；
> 证据 JSON（`coremark_board_im.json` → `cpi_x1000` = 1550）与串口 PERF 行
> （`cycle=3ffce844` ÷ `instret=29477bf6` = 1.5501）都指向 **1.550**。已按证据改正。

**构造入口**：`scripts/run_coremark_im_pds.ps1 -Iterations 2000`；上板 `program_board.ps1 -Config cmim`。
**改了什么**：`rtl/mdu.v`（新增）+ `rtl/decoder.v` + `rtl/pipeline_cpu.v` + `rtl/single_cycle_cpu.v`，Core 端口未变。

### 3.1c 85 MHz **RV32IM** 计分配置（2026-10-14 新增，与交付同频的 M 扩展点）

> 为什么要有这一点：`cm85`（rv32i，Score 79.587）是**与交付位流同频（85 MHz）**的计分点，
> 但 M 扩展以前只有 50 MHz 一点——`fpga/coremark_im` 的 `.fdc` 写死 `clk_50m -period 20.000`，
> 而 80/85/90 MHz 的计分工程都建在 M 扩展之前、从未重建。本点把这一栏补齐：
> **同一颗 `pll_85m`/同一个顶层，只把程序镜像换成 `-march=rv32im`**（4000 迭代）。
> CoreMark/MHz 不变（2.272，Score 是频率归一化的），涨的是**原始 Score** 与资源效率。

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 迭代次数 / 耗时 | **4000** / **20.704 s**（≥10 s） | `release/evidence/coremark_board_cmim85_20261014.json` | `fpga/coremark_im_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit` |
| 总 ticks | **1,759,901,953**（每迭代 439,975 拍，与 50 MHz 点**完全一致**） | 同上 → `ticks` | = `EE8B65360B0B07189C66460D813A6CC990FE87BE156AEA5BC7779B5D3C68D6F1` |
| CoreMark 分数 | **193.192**（`score_x1000` = 193192） | 同上 → `score_x1000` | 同上 |
| **CoreMark/MHz** | **2.272**（与 50 MHz 的 RV32IM 点**完全相同**，证明 Score 随频率线性、效率不变） | 同上 → `coremark_per_mhz_x1000` = 2272 | 同上 |
| 官方 CRC 校验 | **PASS**（`crclist 0xe714` / `crcmatrix 0x1fd7` / `crcstate 0x8e3a` / `crcfinal 0x65c5` / `Correct operation validated.`） | `release/evidence/coremark_uart_cmim85_20261014.log` | 同上 |
| 自证 ISA | `Compiler flags : -O2 -march=rv32im -mabi=ilp32`（串口原文一行） | 同上日志 | 同上 |
| CPI / IPC | **1.547**（cycles 2,092,164,275 ÷ instret 1,352,157,282）/ IPC 0.646 | 同上 → `cpi_x1000` = 1547 | 同上 |
| 时序 | **`All Constraints Met`**，85.0000 MHz 请求 / **86.8456 MHz** 估算，setup WNS **+0.250 ns** | `fpga/coremark_im_85m/report_timing/mes50hp_coremark_pll_top.rtr` | 同上 |
| 资源（布局布线后） | **4198 LUT / 3361 FF**（9.81% / 5.24%），APM 4（乘法器） | `fpga/coremark_im_85m/flow.log` | 同上 |
| **CoreMark/LUT** | **0.0460**（193.192 ÷ 4198，分母 = 该计分位流 PnR 后的**整机** LUT；**同源同频**对照点见 §3.1d：rv32i 79.587 ÷ 4198 = 0.0190，比值 **2.43×**） | 同上 | 同上 |

### 3.1d 85 MHz **RV32I 同源对照点** `cm85r`（2026-10-14 新增，修掉一处跨修订比较）

> 为什么要有这一点：归档的 `cm85`（rv32i 85 MHz，Score 79.587）是 **2026-09-30** 打的，
> 那时 `rtl/` 里还没有 `mdu.v`，资源是 **3657 LUT / APM 0**；而 `cmim85` 是当前 RTL
> （**4198 LUT / APM 4**）。拿这两颗算 `CoreMark/LUT = Score ÷ LUT` 是**跨 RTL 修订比较**，
> 分母不是同一份实现。本点用**与 cmim85 完全相同的源码**（同一份 `rtl/`、同一颗 `pll_85m`、
> 同一个顶层），只把程序镜像换成 `-march=rv32i`，于是同频同源对比成立。

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 迭代次数 / 耗时 | **2500** / **31.412 s** | `release/evidence/coremark_board_cm85r_20261014.json` | `fpga/coremark_85m_r/generate_bitstream/mes50hp_coremark_pll_top.sbit` |
| 总 ticks | **2,670,014,377**（与归档 cm85 **逐位相同**） | 同上 → `ticks` | = `EC71AFDD427720129EA7A91DEADC1B9FE6620262D7CD51CE072E980D3F1C3CB5` |
| CoreMark 分数 / CoreMark/MHz | **79.587** / **0.936** | 同上 | 同上 |
| 官方 CRC | **PASS** | `release/evidence/coremark_uart_cm85r_20261014.log` | 同上 |
| 时序 | **`All Constraints Met`**，85.0000 MHz 请求 / 86.8456 MHz 估算，WNS **+0.250 ns**（与 cmim85 **逐项相同**） | `fpga/coremark_85m_r/report_timing/mes50hp_coremark_pll_top.rtr` | 同上 |
| 资源（PnR） | **4198 LUT / 3361 FF**（与 cmim85 **逐项相同**） | `fpga/coremark_85m_r/flow.log` | 同上 |
| **CoreMark/LUT** | **0.0190**（79.587 ÷ 4198） | 同上 | 同上 |

**两条结论**（都能自证）：
1. **M 扩展不扰动 RV32I**：同一份程序在带 M 的当前 RTL 上跑出 `ticks = 2,670,014,377`，
   与 09-30 的无 M 位流**逐位相同**（另有 RTL 仿真 1,251,724 拍逐位相同佐证）。
2. **同源同频下 M 扩展把 CoreMark/LUT 提高 2.43×**：0.0190 → 0.0460，且两颗的
   LUT/FF/时序**完全一致**——因为面积不随程序变，涨的全是分数。
   旧稿曾写"0.0218 → 0.0460（2.11×）"，那是拿**不带乘法器**的 rv32i 位流当分母，已更正。

**构造入口**：`scripts/run_coremark_85m_r_pds.ps1 -Iterations 2500`；上板 `program_board.ps1 -Config cm85r`。

**构造入口**：`scripts/run_coremark_im_85m_pds.ps1 -Iterations 4000`；上板 `program_board.ps1 -Config cmim85`。
**工程来源**：源文件取自 `fpga/coremark_85m`（同一颗 `pll_85m` + 同一个顶层 `mes50hp_coremark_pll_top`），
只把镜像换成 `-march=rv32im`；共享 `rtl/`（含 `rtl/mdu.v`）与 cm85 完全相同。
**ISA 自证**：`scripts/check_coremark_elf.ps1 -ExpectArch rv32im2p1` → `rv32i2p1_m2p0_zmmul1p0 ELF with 48 hardware M instructions`。

### 3.2 80 MHz PLL 计分配置（2026-09-30 **首次按当前批次实测**）

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 迭代次数 | 2500 | `release/evidence/coremark_board_cm80_20260930.json` | `fpga/coremark_80m/generate_bitstream/mes50hp_coremark_pll_top.sbit` |
| 总 ticks | **2,670,014,377** | 同上 → `ticks` | = `F0743756903BD5576BDBBC8A08C17CEAE1643A4BC3CA3F560CBAB75315359A75` |
| 耗时 | **33.375 s** @ 80 MHz | 同上 → `seconds_at_80mhz_x1000` = 33375 | 同上 |
| CoreMark 分数 | **74.905**（`score_x1000` = 74905） | 同上 → `score_x1000` | 同上 |
| CoreMark/MHz | **0.936**（与 50 MHz 点**完全相同**） | 同上 → `coremark_per_mhz_x1000` | 同上 |
| 官方 CRC 校验 | **PASS**（`crcfinal = 0x5275`） | 同上 → `validation` | 同上 |
| CPI | 1.507 | 同上 → `cpi_x1000` | 同上 |

> ⚠️ **两个位流不是同一个文件**：50 MHz 点是 `mes50hp_coremark_top.sbit`（`DC95F9D0…`），
> 80 MHz 点是 `mes50hp_coremark_pll_top.sbit`（`F0743756…`）。引用分数必须写明用的是哪颗。
> 也**都不是**第 1 节的交付逻辑分析仪位流（`BCAE040A…`）。

**两个点的自洽性检查（这是它们可信的主要理由）**：

1. 80 MHz 点板子自报 `CoreMark/MHz ×1000 = 936`，与 50 MHz 点的 **936 完全相同**
   —— CoreMark/MHz 与频率无关，两点一致说明测量口径正确；
2. `74.905 × (50/80) = 46.816`，与 50 MHz 点的 Score **严丝合缝**。

### 3.3 85 MHz PLL 计分配置（2026-09-30 **板级实测最高工作频率点**）

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 迭代次数 | 2500 | `release/evidence/coremark_board_cm85_20260930.json` | `fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit` |
| 总 ticks | **2,670,014,377** | 同上 → `ticks` | = `751C692B8780E3F05BD6D86E8E0F8BA34A83AFE899E5DA86FE7474C49CA970E9` |
| 真实耗时 | **31.412 s** @ 85 MHz | 同上 → `seconds_at_85mhz_x1000` = 31412 | 同上 |
| CoreMark 分数 | **79.587**（`score_x1000` = 79587） | 同上 → `score_x1000` | 同上 |
| CoreMark/MHz | **0.936**（与 50/80 MHz 两点**完全相同**） | 同上 → `coremark_per_mhz_x1000` | 同上 |
| CPI | 1.510 | 同上 → `cpi_x1000` | 同上 |
| 官方 CRC 校验 | **PASS**（`crcfinal = 0x5275`） | 同上 → `validation` | 同上 |

**三频点自洽性（这是本证据可信的核心）**：

| 频率 | Score | CoreMark/MHz |
|---|---|---|
| 50 MHz | 46.816 | **0.936** |
| 80 MHz | 74.905 | **0.936** |
| **85 MHz** | **79.587** | **0.936** |

`79.587 × 80/85 = 74.905`（与 80 MHz 实测**完全相同**）、
`79.587 × 50/85 = 46.816`（与 50 MHz 实测**完全相同**）。

**PDS 时序**：**All Constraints Met**，请求 85.0000 MHz / 估算 **88.2637 MHz** / slack **+0.435 ns**。
PLL 方案：`STATIC_RATIOF 17 → VCO 850 MHz`，`ODIV0 10 → 85.000 MHz`（精确整数频率）。

**逻辑分析仪 85 MHz 位流**：`fpga/logic_analyzer_85m`，SHA-256
`788F1CEB273FA626DF4581FD46B65A2D90761D9A2B393D35FCEE0C111622DCE2`（2026-10-03 重打），
**All Constraints Met**（请求 85.0000 / 估算 90.0766 MHz / slack +0.663 ns），
板级 `LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80`（2026-10-03 用该位流重跑），
证据 `release/evidence/logic_analyzer_board_85m/`。

> **为什么重打**：2026-10-03 尝试给固件加"一次配置连续采 N 窗"的分段命令（`0xA6`），
> 目的是把段间空档从约 19 ms 压到约 15 µs。该固件在板上**行为不可复现**
> （对 `0xA6` 有时无响应、有时回一半；连 `0xA5` 也随之退化），
> 按项目纪律**已整体回退**：重建后的程序镜像 `program.mem`
> SHA-256 = `E3C3CD4A6997CD2A…` 与归档基线**逐位一致**，本位流由此镜像重新生成。
> 分段采集仍可用**上位机路径**（连发 N 包 `0xA5`，段间空档约 19 ms、页面如实标注），
> 固件 `0xA6` 路径**不交付、不宣称**。详见 `docs/progress.md` 与 `docs/debug_log.md` 2026-10-03 一节。

> 完整的做法、坑与边界见 **`release/evidence/board_85m/README.md`**。

### 3.4 Fmax 上界实测（2026-09-30）—— **最大能跑到多少**

完整报告见 **`release/evidence/fmax_ceiling/README.md`**。结论分两个口径：

| 问的是什么 | 答案 |
|---|---|
| PDS 时序能收敛到多少 | **≈90.6 MHz**（CoreMark 配置）/ **≈91.6 MHz**（LA 配置）—— 90 MHz 收敛、95 MHz 违例 |
| **CPU 核心 + 最小 SoC 板级上界** | **90 MHz**（CoreMark Score **84.269**、CRC PASS） |
| **完整逻辑分析仪应用板级上界** | **85 MHz**（90 MHz 下 SPI 模式可复现挂死） |
| 交付配置的诚实口径 | **85 MHz**（交付的是逻辑分析仪应用） |

| 配置 | PDS 目标 | PDS 结果 | Slack | 估算 Fmax | 板级实测 |
|---|---|---|---|---|---|
| LA 80m | 80 MHz | MET | +0.789 | 85.3898 MHz | 四模式 80/80 ✓ |
| LA 85m | 85 MHz | MET | +0.663 | 90.0766 MHz | 四模式 80/80 ✓ |
| LA 90m | 90 MHz | MET | **+0.191** | 91.5742 MHz | static/counter/uart ✓，**spi 挂死** ✗ |
| CM 85m | 85 MHz | MET | +0.435 | 88.2637 MHz | CoreMark **79.587** ✓ |
| **CM 90m** | 90 MHz | MET | **+0.072** | 90.5870 MHz | CoreMark **84.269** ✓ |
| CM 95m | 95 MHz | **VIOLATED** | **−0.391** | 91.5975 MHz | **未上板**（时序不过） |

**四频点 CoreMark 自洽**（四个独立位流）：

| 频率 | Score | CoreMark/MHz |
|---|---|---|
| 50 MHz | 46.816 | **0.936** |
| 80 MHz | 74.905 | **0.936** |
| 85 MHz | 79.587 | **0.936** |
| **90 MHz** | **84.269** | **0.936** |

`84.269 × 85/90 = 79.587`、`× 80/90 = 74.905`、`× 50/90 = 46.816` —— 逐个严丝合缝。

**90 MHz 的失败点（别误读）**：LA 配置在 90 MHz 下 static/counter/uart **都通过**，
只有 **spi** 失败——发 SPI 配置包后固件**永久卡死**（0 字节，之后连 static 也无响应，须重下位流）。
原因是 spi 用 `sample_div=0`（采集引擎每拍采样，90 MS/s），是四模式里最吃时序的路径。
**PDS 的 +0.191 ns 是标称角名义分析，不足以覆盖温度/电压/抖动裕度。**

### 3.3 读数纪律（**踩过的坑，必须遵守**）

**`run_coremark_board.ps1` 无条件把 `clock_hz` 写成 `50000000`。**
在 80 MHz 位上跑时，它算出的 `seconds`（53.400 s）是**错的**，真实耗时是 `ticks/80e6 = 33.375 s`。
归档文件里已补 `clock_hz_actual` / `seconds_at_80mhz_x1000` / `clock_hz_field_note` 三个字段说明此事。
**不要照抄脚本打印的 `seconds`。**

**板级 CPI 有窗口敏感性**：同一颗 cm50 位流两次运行的 `ticks` / `score` / `flushes` **逐位相同**，
但 `cycles` / `instret` / `stalls` 不同 ⇒ CPI 在 **1.494–1.508** 之间浮动。
原因是固件用 `PERF_CONTROL` 的 clear 脉冲把性能计数器窗口对齐到 CoreMark 计时窗口
（`software/coremark/core_portme.c` 的 `PERF_WINDOW_ALIGN`），窗口边界口径导致 ±1% 抖动。
⇒ **Score / ticks 可以照写（完全可复现）；CPI 只能写 ≈1.50，不能写 1.508 这种四位精度。**
完整对照表见 `release/evidence/board/README.md`。

---

## 4. 逻辑分析仪应用（P0 端到端）

| 宣称的数字 | 值 | 证据目录 | 位流 SHA-256 |
|---|---|---|---|
| 板级测试（85 MHz 交付位流） | **100/100 PASS**（5 模式 × 20 次：static/counter/uart/spi/**mirror**） | `release/evidence/logic_analyzer_board_85m/` | 交付位流 `66A1E9A7…` |
| 静态模式 | 20/20 | `.../static/` | 同上 |
| 计数器模式 | 20/20 | `.../counter/` | 同上 |
| UART 模式 | 20/20 | `.../uart/` | 同上 |
| SPI 模式 | 20/20 | `.../spi/` | 同上 |
| **镜像抓取（上位机字符串）** | **20/20**，每次回包都带 `LA TEXT … ascii=HELLO,RISC-V bytes=0000000C` | `.../mirror/` | 同上 |
| 板级测试（50 MHz 备用位流） | 15/15 PASS（5 模式 × 3 次冒烟，**不是** 20 轮全量验收） | `release/evidence/logic_analyzer_board_50m_recheck/` | 备用位流 `0477DDA4…` |
| 抓取深度（Raw 缓存） | **2048 样本**（2026-10-10 由 256 提高；`logic_analyzer_mmio` 的 `DEPTH` 参数） | PDS 报告 `u_soc/analyzer/cap/mem = 2048 x 8`；`docs/application_logic_analyzer.md` §6.7 | 同上 |
| 单次实际返回样本数 | 依模式而定：static 5、counter 5、uart **207**、spi 85、**mirror 2048** | 各模式 `summary.json` 的 `samples` 字段 | 同上 |
| 单次实际触发位置 | 依模式而定：static 0、counter 0、uart **15**、spi 4、**mirror 0（= 起始位）** | 各模式 `summary.json` 的 `trigger` 字段 | 同上 |

> **2026-10-27 更正**：本表原登记 uart 样本 240、触发位置 48，与仓库内 20 次归档证据
> （`release/evidence/logic_analyzer_board_85m/uart/summary.json` 全为 `samples=207`、`trigger=15`）不符。
> 当日插好 J8 八组回环跳线后，用 `python/logic_analyzer_serial.py COM11 --mode uart --runs 3` 复测三次，
> 三次均 `PASS`，`samples=207`、`trigger=15`，日志头为 `LA RAW count=000000CF trigger=0000000F`、
> 解出 `UART:000000A5`，与归档证据逐字节一致。故按 207 / 15 更正；原 240 / 48 无法在本配置下复现。
| 捕获通道 | 8（**ch7 = 上位机串口线镜像**，J8-31/32 回环） | `.../mirror/summary.json` + 波形页 `decode{channel:7}` | 同上 |
| **仪器读数（新增）** | 每通道：边沿数、频率、周期（中位数）、周期抖动、占空比、最小/最大脉宽；协议：帧数、帧错误、位宽、推算波特率 | `逻辑分析仪演示.py` 右栏读数表 + 导出测量报告 | 同上 |
| 仲裁/触发诊断 | 4 组静态值 00/55/AA/FF | `.../diagnostic_static_*/` | 同上 |

> ⚠️ **不要与 PDS ILA 混淆**：`coremark_ila` 与 N2 的 Trap 抓取用的是 PDS DebugCore 探针，
> 窗口是 **512 样本**（见 §6）。作品自带的八通道逻辑分析仪 Raw 深度是 **2048 样本**。
> 材料里同时出现 2048 和 512 时，必须指明说的是哪一个，否则会被当成自相矛盾。

> **"展示效果"这条口径（2026-10-10）**：镜像模式的波形页上，12 个字符逐帧标注
> （`'H' 0x48` … `'V' 0x56`），状态栏打印 `报文 "HELLO,RISC-V"`。
> 判据是"从波形解出来的字节**逐字节等于**上位机发出去的那句话"，不是"解出了东西"。

样本日志格式（可逐行核对）：

```text
LA_ARMED                                       ← 交互式固件：Arm 生效后才打印这一行
LA RAW count=00000800 trigger=00000000         ← 镜像抓取：2048 个采样点、触发点在第 0 点
00000000 00000000 … 00000080 00000080 …        ← ch7 = 上位机串口线（bit7），其余 7 路固定低
LA TEXT hex=00000048… ascii=HELLO,RISC-V bytes=0000000C   ← 板子自己把波形解回的整句
LA_DONE
LA_READY
```

四模式（0xA5 命令）的日志里没有 `LA_ARMED` 与 `LA TEXT` 两行，其余格式不变；
上面这份是 0xA7 镜像抓取的格式。

> **2026-09-30 重新上板复核**：交付位流 `la50` 重新下载后跑同一套四模式，
> 再次得到 `LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80`，
> 证据落在 `release/evidence/logic_analyzer_board_recheck_20260930/` 与
> `release/evidence/board/run01/logic_analyzer/`（两处内容一致，互为副本）。
> 旧证据 `release/evidence/logic_analyzer_board_final/` **保持不动**，仍为 09-29 的首批证据。
> ⚠️ 上面这几条 09-29/09-30 的 80/80 是**旧位流（无镜像）**的记录；当前交付位流的口径见本节的
> "板级测试（85 MHz 交付位流）"一行（100/100）。

---

## 5. N1：板级裸机定时器中断（M-24 前半）

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 中断记录条数 | 12（6 s 抓取） | `release/evidence/timer_demo_board/timer_demo_board.json` | `fpga/timer_demo/generate_bitstream/mes50hp_timer_demo_top.sbit` |
| 固件预期周期 | 12,500,000 拍 = 250.0 ms | 同上 → `delta_ticks` | = `5E58B4217AB9591AF974C5B1897A287A007B7E7E219F122244E44A4958B7765B` |
| 固件自计时期中位数 | **12,517,376 拍 = 250.348 ms** | 同上 → `mtime_period_ticks_median` / `mtime_period_ms_median` | 同上 |
| 自计时容差 | 65,536 拍（0.52%）且判定通过 | 同上 → `self_timed_period_ok` | 同上 |
| 计数器序列 | `890123456789` | 同上 → `count_sequence` | 同上 |
| LED 序列 | `010101010101` | 同上 → `led_sequence` | 同上 |

> 偏差来源已定位：ISR 内在阻塞式 UART 打印期间 `mtimecmp` 未重载，造成每次约 +17.4k 拍的固定叠加；
> 固件已改为"先重载再打印"，容差按 65536 拍判定。**这是设计取舍，不是未知误差。**

---

## 6. N2：ILA 抓 Trap 进入/返回（M-24 后半）

| 宣称的项 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| ILA 位流 | `mes50hp_timer_demo_top.sbit` | `fpga/timer_demo_ila/generate_bitstream/` | **`452EE532DAC8AB9A86CDF9C6859892F7BA466EA035EF6A6C46FAAA9598248B74`** |
| 时序 | clean（0 失败端点） | PDS `report_timing` | 同上 |
| 器件 IDCODE | `0x00521899` | 抓取日志 | 同上 |
| 下载线 | `PANGO USB CABLE II cable driver: D2XX DLL` | 抓取日志 | 同上 |
| 抓取 A（触发 `ila_event_trap`） | trap 落在第 **256** 样本（= 触发点），return 在第 **251** 样本 | `fpga/timer_demo_ila/evidence/A_trap_enter/waveform.txt` | 同上 |
| 抓取 B（触发 `ila_event_trap_return`） | return 落在第 **256** 样本，trap 在第 **261** 样本 | `fpga/timer_demo_ila/evidence/B_trap_return/waveform.txt` | 同上 |
| 抓取深度 | 512 样本/次（**PDS DebugCore 探针**口径，≠ 作品自带逻辑分析仪的 256） | 两个 waveform.txt | 同上 |
| `irq_timer` | 全部 512 样本为 **1** | 两个 waveform.txt | 同上 |
| illegal / misaligned / bus_error | 全部 512 样本为 **0** | 两个 waveform.txt | 同上 |
| 证据文件哈希 | A-txt `A7FAB1B1…`、A-vcd `E9EC8F47…`、B-txt `80F384A3…`、B-vcd `8BCDBC60…` | 见 `fpga/timer_demo_ila/evidence/README.md` | 同上 |

> **2026-09-30 补充复现**：本次上板会话中下载线同样识别为 `PANGO USB CABLE II`，
> 且 `scripts\program_board.ps1` 对 `la50` / `cm80` / `ddr3` 三个配置均返回
> `PROGRAM PASS` + `The done bit is 1`，说明下载链路稳定。

**ILA 探针能证什么、不能证什么（必须如实说）**：

- **能证**：`event_trap` 与 `event_trap_return` 各产生**恰好一个**脉冲，且出现在预期样本位置；
  两次抓取互为正/反向触发，说明该事件不是毛刺而是可重复的真实事件。
- **不能证**：`mcause` / `mepc` 的**数值**。PDS 拒绝跨层引用（`Verilog-4311`），
  且 Core 端口已冻结（`AGENTS.md` §1.14），无法把这些值引到探针上。
  这两个数值由**固件 UART 记录**证明（第 5 节 N1），不是 ILA 证明的。
- **未解释**：两次抓取都显示 trap 与 return 间隔恰好 **5 个样本**。
  这是可复现的观测，但本轮**没有**把它换算成周期（ILA 采样间隔未标定），
  也**没有**给出因果解释。材料中不得把"5 样本"写成"5 个周期"。

复现：
```powershell
scripts\run_timer_demo_ila_pds.ps1
scripts\run_ila_trap_capture.ps1 -Mode capture -TrigUnit 0 -TrigFunc 0 -TrigRadix 0 -TrigValue <192位模式>
```

---

## 7. S1：DDR3 打通（板级）

| 宣称的项 | 值 | 证据位置 | 位流 SHA-256 |
|---|---|---|---|
| 板级结论 | **`S1 DDR3 SMOKE BOARD PASS`** | `docs/ddr3_s1_survey.md` §2.4.2 | `fpga/ddr3_smoke/generate_bitstream/mes50hp_ddr3_smoke_top.sbit` |
| Setup WNS | **+0.367 ns**（0 失败端点） | 同上 §2.4.2 表 | = `FAEDF47618647C36FACBFF6DF0E5DE623F20ECD461FFA6997D724ABE93561B76` |
| Hold WHS | **+0.044 ns**（0 失败端点） | 同上 | 同上 |
| 位流大小 | 2,101,696 bytes | 同上 | 同上 |
| BIST 错误计数 | 全程 **0** | 同上板级日志 | 同上 |
| DDR3 初始化 | `ddr_init_done = 1`、`dll_lock = 1` | 同上 | 同上 |
| 心跳 | 8 s 内 155 次采样翻转 16 次 | 同上 | 同上 |
| 板上 LED 人工判据 | LED1 亮 / LED2 亮 / LED3 闪 / LED4 灭 | 同上（用户实测） | 同上 |

复现：`python python\ddr3_smoke_board.py --port COM11 --seconds 8`

**已知偏差（未消除，必须写进材料）**：`0x80` 的 bit0（`pll_lock` 状态位）在 31 次连续采样中**恒为 0**，
但同寄存器 `dll_lock=1`、`ddr_init_done=1`、BIST 正常循环三者不可能同时成立，
且板上 LED1 实测常亮 ⇒ 判定**该状态位本身不可信**（极性/连线问题），非"PLL 未锁定"。
本项**不计入通过判据**。

**✅ 证据落点的缺口已于 2026-09-30 补齐**：S1 的板级日志现已有独立证据目录
**`release/evidence/ddr3_smoke_board/`**（`board_run_20260930.log` + `README.md`），
并已于同日**重新上板复现** `S1 DDR3 SMOKE BOARD PASS`。

**未宣称**：DDR3 **吞吐量/延迟数字**。`test_ddr` 例程只做 BIST 与状态寄存器，**没有性能测量**。
本节拿到的是"控制器在本板真正工作"，**不是**"DDR3 性能数字"。
也**没有**把 DDR3 接入 CPU 存储路径（只做了板级连通性）。

---

## 7.1 三轮 Reset/断电一致性（**未做，用户 2026-09-30 决定不做**）

`docs/roadmap.md` 任务 35 的验收条目「多次断电、Reset 和重新连接串口后演示结果一致」
要求三轮（`release/evidence/board/run01..03`）。

| 项 | 状态 |
|---|---|
| `run01` | **已完成**——重新下载（Reset 等价），LA 80/80 + CoreMark `ticks=1068006999`。**未断电。** |
| `run02` / `run03` | **未做** |
| 原因 | **用户 2026-09-30 明确表示"不用三轮一致性，我感觉没意义"** |

> ⚠️ **这必须记为"用户决定不做"，不是"已完成"，也不是"不适用"。**
> 若最终提交需要这一条，用 `scripts\run_board_rounds.ps1 -Round all -PauseSeconds 120 -PowerCycled` 补跑。
> 该脚本**不能替你断电**，也会如实把未断电的轮次记成 `re-download`；
> 详见 `release/evidence/board/README.md`。

---

## 8. N4：Fmax 调优（收紧约束候选；**已做板级功能验证，但仍是候选、未替换交付位流**）

产物目录：`release/artifacts/fmax_tuning_2026-09-30/`

| 约束周期 | 目标频率 | 估算 Fmax | Setup WNS | All Met | LUT | FF | 候选位流 SHA-256 |
|---|---|---|---|---|---|---|---|
| 20.000 ns | 50 MHz（= 交付值） | 55.5216 MHz | +1.989 | MET | 4536 | 3852 | （与交付一致，见 §1） |
| 13.333 ns | 75 MHz | 80.0897 MHz | +0.847 | MET | 4805 | 3858 | — |
| 12.500 ns | 80 MHz | 85.2370 MHz | +0.768 | MET | 4814 | 3858 | `2CAE5ED7B7A5D1128ACD3D330F89300E00FC87118BCCCF0772A4600C0C244C82` |
| 11.765 ns | 85 MHz | **89.2538 MHz** | +0.561 | MET | 4794 | 3858 | `702EFAD1BA11A94858392DC775C3AE864963850E706B6779253A8FA6C813AA9E` |

附表：`sweep_summary.csv`、`rtl_sha256.txt`（证明四个点用的是同一份 RTL）。

**诚实边界（不得省略）**：

1. 交付位流**没有被替换**。上表是"在更紧的时序约束下仍能收敛"的**候选**产物。
2. 三个候选 `.sbit` 哈希与交付位流**不同**，原因是构建目录不同导致布局种子不同，**不是设计不同**。
3. **89.25 MHz 是 PDS 的估算值**，而板载时钟固定 50 MHz，实际运行频率仍是 50 MHz。
   "Fmax 提升"指的是**时序余量**变宽（20 ns 约束下 Fmax 从 55.52 MHz 到 89.25 MHz），
   **不是**板上跑得更快。
4. **≥90 MHz 本轮未测**。
5. 20 ns 那一组复现出的 `est 55.5216 / WNS 1.989 / LUT 4536 / FF 3852`
   与 `automated_metrics.json` **完全一致**，这是本轮 RTL 快照可信的交叉证明。

### 8.1 候选位流已做板级验证（2026-09-30）

| 项 | 结果 |
|---|---|
| 被测位流 | `la_85m_constraint11p765ns.sbit`（`702EFAD1…`，11.765 ns 约束） |
| 下载 | `PROGRAM PASS config=custom`、`The done bit is 1` |
| 板级验收 | **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80`**（四模式各 20/20） |
| **与交付位流的等价性** | 四个模式的 `summary.json` 与原始日志**逐字节相同** ⇒ 收紧约束**只改布局布线、不改功能** |
| 证据 | `release/evidence/fmax_candidate_board/`（165 文件 + README） |

> ⚠️ **这次验证证明的是"更紧约束的布线功能正确"，不是"板上跑到了 89.25 MHz"。**
> 板载晶振固定 50 MHz，候选位流在板上**仍以 50 MHz 运行**。
> **"板级实测过的最高频率"目前是 80 MHz**（`fpga/logic_analyzer_80m` 与 `fpga/coremark_80m`
> 两个 PLL 变体；后者 2026-09-30 实测 CoreMark Score 74.905）。
> 要得到 **实测的 85 MHz**，必须做 **PLL 变体**（`FDIV 16→17`：VCO 850 MHz / ODIV0 10 = 85.000 MHz 精确值），
> 那是**新建工程**，尚未做。

---

## 9. 高阶项①② 止损记录（S2/S3/S4）

| 项 | 结论 | 数字 | 证据 |
|---|---|---|---|
| S2 行式突发 | **PASS** | 总线周期 **48 → 30**（−37.5%） | `docs/progress.md`、`docs/debug_log.md` |
| S3 2 路组相联 I-Cache | **止损触发 → 默认关闭** | cycles 1,251,724 → **2,891,324**（2.31× 变慢） | 同上 |
| S4 2 路组相联 D-Cache | **止损触发 → 默认关闭** | cycles 1,251,724 → **1,348,302**（+7.7%） | 同上 |

**架构结论**：片上 BRAM 的访问延迟已经优于 Cache 命中延迟，
因此 Cache 在"后端仍是 BRAM"的前提下**不可能**产生净收益；
必须等真实 DDR3/HMIC 后端接入存储路径后才可能翻盘。
**当前交付配置 = Cache 全部关闭**，交付位流与 CoreMark 分数均不含 Cache。

> ⚠️ 注意：S3/S4 的 cycles 数字与第 2 节的 On/Off 数字是**不同实验组**。
> 引用时不要混：第 2 节是 Predictor On/Off，本节是 Cache On/Off（基线同为 1,251,724）。

---

## 10. Trap 契约

| 宣称的项 | 值 | 证据文件 |
|---|---|---|
| Trap 契约条目 | **M-01 … M-24 全部 PASS** | `docs/trap_contract.md` |
| 剩余"部分通过"条目数 | **0** | 同上 |
| 独立断言数 | **99/99 PASS** | `tb/` + `scripts/run_trap_pipeline_tb.ps1` |
| M-24 收口日期 | 2026-09-30 | 同上 |

复现：`scripts\run_trap_pipeline_tb.ps1` → `ALL TRAP PIPELINE TEST PASS`

---

## 11. 一键复现全部数字

```powershell
# 必须用 PowerShell 7（见 release/HANDOFF.md 的工具链说明）
pwsh -NoProfile -File scripts\run_final_regression.ps1
```
该脚本覆盖：Trap 99 断言 + 最终回归 + CoreMark 仿真 + PDS 时序/资源刷新 + 范围审计。
当前实测输出（2026-09-30）：
```
ALL TRAP PIPELINE TEST PASS
COREMARK PIPELINE EXECUTION PASS cycles=1251724 retired=786925 bytes=655
ALL AUTOMATED FINAL REGRESSION PASS
core = B58496706686E37B
```

---

## 12. 未宣称（No-Claim）清单

以下内容**没有**进入任何材料，因为**没有可复现证据**：

| 项 | 原因 |
|---|---|
| DDR3 吞吐量 / 延迟数字 | `test_ddr` 例程无性能测量 |
| DDR3 已接入 CPU 存储路径 | 只做了板级连通性（S1），后端接入**未开始** |
| ILA 的 `mcause` / `mepc` 数值 | PDS 拒绝跨层引用，Core 端口冻结 |
| Trap↔return 的"5 样本"因果解释 | 观测可复现，采样间隔未标定，未换算为周期 |
| ~~板上 Fmax / 板上 89.25 MHz~~ | **已由板级实测取代**：89.2538 MHz 仍是 PDS 估算，但**板级实测点已有 85 / 90 MHz**（见 §3.3 与 §3.4） |
| **把 89.2538 MHz 说成"实测"** | 它是 PDS 时序分析的估算值。**实测值见 §3.4**。两者不得混写 |
| **说"板上能跑 95 MHz"** | 95 MHz 配置 PDS **时序违例**（WNS −0.391 ns），**未上板**、不要当结果用 |
| **说"逻辑分析仪应用能跑 90 MHz"** | 90 MHz LA 位流 PDS 过（+0.191 ns）但板上 **SPI 模式可复现挂死**；LA 应用上界是 **85 MHz** |
| 85/90 MHz 下的 N1 定时器中断 / N2 ILA 抓 Trap / S1 DDR3 | PLL 变体**只做了**逻辑分析仪四模式 + CoreMark；其它板级项目仍以 50 MHz 交付配置的证据为准 |
| 温度/电压拉偏下的上界 | 本轮**没有**温箱与可调电源，所有上界都是**常温常压**结论 |
| 集成慢后端下 Cache 的 Off/On 收益 | 该测量不可信，已在文档中标注为不可用 |
| S3 零气泡（组合逻辑命中路径） | **未解决**，从未实现成功 |
| **板级 CPI 的四位精度** | 有窗口敏感性（实测 1.494–1.510）⇒ 只能写 **≈1.50**；Score/ticks 不受影响 |
| **三轮断电一致性** | **用户 2026-09-30 决定不做**（不是完成，也不是不适用）——见 §7.1 |
| **80 MHz 逻辑分析仪回环结果** | `logic_analyzer_board_final` 只有 50 MHz 的 80/80；80 MHz 只测了 CoreMark |
| **断电冷启动后的一致性** | `run01` 只做了"重新下载"（Reset 等价），**没有真的断过电** |

> ✅ **已从本清单移除**：~~当前批次的 80 MHz 板级 CoreMark 分数~~ —— 2026-09-30 已首次按当前批次实测，
> Score **74.905** / CoreMark/MHz **0.936** / CRC PASS，见 §3.2。
> ~~任何 ≥90 MHz 的板级点~~ —— 已测到 90 MHz（CPU 配置通过），见 §3.4。

---

## 13. 材料 ↔ 生成器对照（**改数字必须改脚本，改产物是白改**）

| 材料 | 生成者 | 说明 |
|---|---|---|
| `release/final_submission/**` | `scripts/export_final_submission.ps1` | **会先清空该目录再重建**；README 由脚本里的 `$readme` here-string 生成。要改 README 必须改脚本。模板里 markdown 行内代码要用**双反引号**——PowerShell 双引号 here-string 会把 `` `r `` 当回车，把 `release/...` 吃成 `elease/...` |
| `release/build_manifest.txt`、`release/SHA256SUMS.txt` | `scripts/create_release_manifest.ps1` | `scope=` / `board_results=` / `board_not_collected=` 三行是硬编码的，改状态要改脚本 |
| `release/materials/technical_report.docx` | `scripts/generate_technical_report.py` | 需 `python-docx`（**本机当前未安装**，`ModuleNotFoundError: No module named 'docx'`） |
| `release/materials/defense_presentation.pptx` | `scripts/generate_defense_deck.mjs` | 需 Node + `@oai/artifact-tool`（Codex 运行时插件缓存）；`RUNTIME_PYTHON` 指向 codex runtime |
| `release/materials/*.md` | 手写 | 直接改 |

**发布链（必须 PowerShell 7）**：
```powershell
pwsh -NoProfile -File scripts\export_final_submission.ps1   # FINAL SUBMISSION EXPORT PASS files=214
pwsh -NoProfile -File scripts\create_release_manifest.ps1   # RELEASE MANIFEST PASS files=2260
pwsh -NoProfile -File scripts\audit_release_package.ps1     # RELEASE PACKAGE AUDIT PASS final_files=131 artifacts=3
```

### 13.1 位流哈希的四处登记点（重打位流必须同步改）

改一处漏三处是**本轮实际踩到的坑**（`scripts/demo_preflight.ps1` 有 3/5 个哈希过期，
现场自检必然 FAIL）。重打位流后要同步：

1. `release/evidence/claims_map.md`（本表）
2. `scripts/demo_preflight.ps1` 顶部 `$bitstreams` 的 5 个哈希
3. `docs/reproduction.md` §「正式配置与诊断配置」
4. `release/HANDOFF.md` 与 `release/materials/field_recovery_card.md`

（`release/build_manifest.txt` 与 `release/SHA256SUMS.txt` 由脚本自动重算，无需手改；
`audit_release_package.ps1` 以 `fpga/logic_analyzer/generate_bitstream` 为唯一真实来源自动比对，也不写死。）

---

*本表由 N3 材料收口任务建立（2026-09-30）。新增数字请追加到对应小节并注明证据文件与位流哈希。*

---

## 14. M 扩展乘法并行部分积（2026-10-19，**新配置，非交付位流**）

> 背景：`rtl/mdu.v` 的乘法由"两级串联 16x32 部分积"改为"四路并联 16x16 + 窄位宽加法树"，
> 乘法占用 EX 由 3 拍降到 2 拍（`MUL_LAT` 参数，默认已切到 2）。
> 完整记录见 `docs/mdu_parallel_partial_product.md`。
> ⚠️ **这两颗位流是 CoreMark 计分位流，不是交付的逻辑分析仪位流**；交付 la85 未重打。

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 基线（`MUL_LAT=3`）ticks / 每迭代 | **1,759,901,953** / 439,975.5 | `release/evidence/coremark_board_mul3_85m_20261019.json` | `C7C41A3308B7851B8BBFF2054A9998E3A7CC96A7FFB73AAE2B189C3EDF11DF1E` |
| 基线 Score / CoreMark/MHz | 193.192 / 2.272 | 同上 | 同上 |
| **改后（`MUL_LAT=2`）ticks / 每迭代** | **1,722,317,953** / **430,579.5** | `release/evidence/coremark_board_mul2_85m_20261019.json` | `18F35C77C73E258D30551F57F684357E6C800F4E60F61F11B9D18B3162949FEF` |
| **改后 Score / CoreMark/MHz** | **197.408（+2.183%）** / **2.322（+2.20%）** | 同上 | 同上 |
| 耗时（两次均 ≥10 s） | 20.704 s → **20.262 s**（4000 迭代） | 两个串口日志 | 同上 |
| 官方 CRC | `crcfinal 0x65c5`、`Correct operation validated.`，两次相同 | `coremark_uart_mul3_85m_20261019.log` / `..._mul2_...log` | 同上 |
| `flush_count` | 43,406,274，**两次逐位相同** | 两个 JSON | 同上 |
| RTL 仿真 cycles（rv32im 一次迭代） | 604,288 → **594,792（−1.571%）**；`instret` 与四行 CRC 三方相同 | `tmp/cm_rv32im_mullat*.log`、`docs/mdu_parallel_partial_product.md` §3.1 | — |
| PDS 时序/面积（85 MHz，同配方） | WNS +0.281 → **+0.115 ns**（仍 `All Constraints Met`）；LUT 4185 → **4139** | `fpga/coremark_mul{3,2}_85m/report_timing/`、`flow.log` | 同上 |

**两个自洽点（可作为可信性理由）**：

1. 基线 ticks `1,759,901,953` 与 2026-10-14 归档 `cmim85` **逐位相同** ⇒ 基线可复现、当前源码树未改变行为。
2. 仿真窗口 ticks 差 **9,396 拍/迭代** = 实板 (1,759,901,953 − 1,722,317,953) ÷ 4000 **9,396 拍/迭代**，两者完全相同。

**⚠️ 口径纪律（不得违反）**：

- 这两次采集用的是默认 `PERF_WINDOW_ALIGN=0` 镜像，性能计数器自由运行，
  PERF 行里的 `cycle / instret / stall / branch` 与 JSON 里的 `cpi_x1000` **含启动与等待 `R` 的轮询，
  两次采集不可比**，**不得引用任何 CPI 数字**（要做 CPI 归因必须用 `PERF_WINDOW_ALIGN=1` 镜像）。
- 可引用的只有 `ticks / Score / CoreMark/MHz / CRC / flush_count`。
- 交付逻辑分析仪位流（la85）**未重打**，`release/` 内既有位流与哈希全部未变；
  上板验证完成后板子已恢复为交付位流 `la85`（`C017ED10…`）。

---

## 15. 提交级 trace 可视化（2026-10-21，**附加演示位流，非交付位流**）

> 范围变更经用户 2026-10-21 批准。规格见 `docs/application_logic_analyzer.md` §6.11，
> 逐条过程记录见 `docs/progress.md` 2026-10-21 章节，证据目录 `release/evidence/trace85_board/`。
> **`la85` 位流、100/100 板级验收证据与本节之外的既有哈希全部未变。**

| 宣称的数字 | 值 | 证据文件 | 位流 SHA-256 |
|---|---|---|---|
| 位流（85 MHz PLL，`All Constraints Met`） | `fpga/trace85/generate_bitstream/mes50hp_trace_pll_top.sbit` | `fpga/trace85/pds_trace85_build.log`、`report_timing/mes50hp_trace_pll_top.rtr` | `945F36E497740628A635E295F6132E86D88D5FEA2C25CA2C43C221A9664F290D` |
| 资源 | LUT **3810+2144**（15% / 13%）、APM 4、**DRM 40 / 134（30%）**、`LUT as Distributed RAM = 0` | 同上 | 同上 |
| PLL 输出 | 11.7647 ns = **85.000 MHz** | 同上（Clock Summary） | 同上 |
| **阶段 0 实板：处理过程窗口** | **100 条提交 / 8 打点 / 19 个 PC / status=0x4**；**每字符 12 条提交**（marks 间隔 `[12,12,12,12,12,9,12]`） | `release/evidence/trace85_board/trace_phase0.{log,json,html}` | 同上 |
| 阶段 0 判据 | **15/15 PASS**，含 `pc 与位流镜像同源` 不一致 **0 条**、`store 有效地址与记录低 12 位一致` 不一致 **0 条**、`打点值等于发送的字符` | 同上 | 同上 |
| 阶段 0 总线/MMIO | 17 次写存储里 **8 次命中 MMIO**（全部是打点寄存器 `0x1000222C`，一字符一次）、9 次写数据 RAM（`0xEE8…`） | 同上 | 同上 |
| **阶段 1 实板：含轮询的窗口** | **4096 条（写满）/ 3 打点 / 22 个 PC / status=0xC**（溢出合法：`count==容量`） | `release/evidence/trace85_board/trace_phase1.{log,json,html}` | 同上 |
| **阶段 1 空转占比** | **前 4 个热点占整窗 99.49%**；三条 UART 忙等指令各 **1358 / 1358 / 1357** 次 | 同上 | 同上 |
| 阶段 1 判据 | **14/14 PASS**，`pc 与位流镜像同源` 在 4096 条上不一致 **0 条** | 同上 | 同上 |
| 端到端仿真（真 SoC + 真固件） | `ALL CORE TRACE SOC TEST PASS`（场景 1 `declared=100`、场景 2 `declared=859`） | `scripts\run_core_trace_soc_tb.ps1` | — |
| 仿真↔实板一致 | 阶段 0 的 8 个打点索引在仿真与实板上**完全相同**：`[7,19,31,43,55,66…]`（实测 `[7,19,31,43,55,67,76,88]`） | 两处 json | — |

**可以宣称**：这台自研逻辑分析仪能对自研 CPU 做**提交级**采集与回放，逐条给出
`pc / 指令 / 写回寄存器与数据 / 写存储地址与数据`，并且 4096 条记录的指令字与
位流镜像逐条对得上。

**不得宣称**（`docs/application_logic_analyzer.md` §6.11 同款边界）：

- **不是实时流式**：132 位/条、85 MHz 下内核产出约 600 MB/s，115200 只有 11.52 kB/s，
  差约 5 万倍；口径是"Arm → 收尾 → 上传一窗 → 回放"。
- **记录里的 `mem_addr` 只有低 12 位**（IMEM/DMEM 各 4 KB），光看记录分不出 RAM 和 MMIO；
  页面用窗口内已知的基址寄存器还原 32 位有效地址，还原不出来就标"地址未知"，不猜高 20 位。
- **load 的地址不在记录里**（`trace_mem_we` 的语义是"是否写存储"）；只有值一定正确。
- **没有时间戳**，所以是**提交级**视图；每拍的取指/停顿/冲刷要看 8 通道 Core 探针的波形页。
- 不称为 PDS ILA，也不宣称替代它。
- 这是**附加演示位流**；CoreMark 分数与 Fmax 仍只引用计分位流，不得混用。

**⚠️ 板子当前状态**：验证结束后板子停在 `tr85`（trace 演示位流）。
要恢复交付状态只需 `scripts\program_board.ps1 -Config la85`。

### 15.1 离线回放样本（`python/samples/trace_hello_rv.log`，2026-10-28 登记）

> 交付包 `tools/samples/trace_hello_rv.log` 是同一份文件。它是**没有开发板时**第 ② 页
> 唯一的数据源，所以它的来源必须和上面那一枪一样可查。

| 项 | 值 |
|---|---|
| 文件 | `python/samples/trace_hello_rv.log`（= `release/evidence/trace85_board/trace_phase0.log` 的逐字节副本） |
| 文件 SHA-256 | `46E05077478BFD5C6044FFCECBD59A77F1ABE4E35CC5CF58A4890964A05FC016` |
| 它对应哪一枪 | 上表"阶段 0 实板：处理过程窗口"——发送 `hello,rv`、100 条记录 / 8 打点 / `status=0x4` |
| **配对镜像** | `fpga/trace85/rtl/logic_analyzer_program.mem`，SHA-256 `7C45D16DB5AD12A39747AB0BAC88B8B7E83E9918694F8444E4B76AB0C0F64F78` |
| 判据复核（2026-10-28） | **15/15 PASS**，`pc 与位流镜像同源` 不一致 **0** 条 |
| 复现 | `cd python; python test_trace_ui.py`（`OfflineReplaySampleTests` 三项即此关系） |

**纪律**：样本与 `program.mem` 是一对。重新生成 trace85 固件镜像后，必须重录样本或重新对齐，
否则第 ② 页离线回放的 `pc 与位流镜像同源` 会全错（2026-10-28 修掉的就是这个：
旧样本停留在 2026-10-23 的固件，PC 整段比现在低 `0x434`，100 条全不一致）。
另注：判据的 `sent_text` 必须取**打点值**（`chr(m["value"])`），
不能取回包 `TRACE TEXT`（那是大写化之后的，会多出 2 条假 FAIL）。
