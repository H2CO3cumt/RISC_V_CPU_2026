# RISC-V CPU 最终交付说明

更新时间：**2026-10-14（第五次修订：M 扩展 / RV32IM 两个频点 / 采集源双源 / 交付位流哈希刷新）**。
仓库 `D:\RISC_V_CPU_2026` 是权威开发状态，`release/final_submission` 是唯一最终交付目录。

> **2026-10-14 修订说明**：本文件此前停留在 **2026-09-30 快照**（位流 `F7DFD321…`、4814 LUT、
> WNS +0.663、只有 RV32I 数字）。该快照**已过期**，现全部改为当前实测值：
> 交付位流 `C017ED10…`（含 **M 扩展**与**采集源双源可选**）、4995 LUT / 3908 FF、WNS +0.577 ns，
> 并新增 **RV32IM（M 扩展）两个计分频点**（85 MHz Score 193.192 / 50 MHz Score 113.642）。
> **每个数字的来源见 `release/evidence/claims_map.md`**（数字 ↔ 证据文件 ↔ 位流哈希对照表）。

> **2026-09-30 交付配置切换（保留）**：交付主位流由 **50 MHz 版**改为 **85 MHz PLL 版**。
> 理由：赛题指标第 (2) 条要"**满足时钟约束前提下的最高工作频率**"，
> 交付件本身工作在 85 MHz 才能自证，避免"报告写 85 MHz、交的位流却是 50 MHz"的观感问题。
> 50 MHz 版工程（`fpga/logic_analyzer`）**原样保留**，其位流作为**已验证备用**随包提供。

## 唯一最终版本

- 顶层：`mes50hp_logic_analyzer_pll_top`（= `pll_85m` + `mes50hp_logic_analyzer_top`）
- 器件：PGL50H-6IFBG484；板载晶振 50 MHz，经片上 PLL 倍频到 **85 MHz** 供 CPU/SoC 使用
  （`pll_85m`：50 MHz / IDIV 1 = PFD 50 MHz，× FDIV 17 = VCO 850 MHz，/ ODIV0 10 = **85.000 MHz** 精确整数频率）
- 内容：RV32I 五级流水线 **+ 完整 M 扩展（RV32IM）**、16 项直接映射 BTB、机器模式 CSR/Trap 与定时器中断、
  UART/GPIO、十项性能计数器、**八通道 Raw 逻辑分析仪（采集源可选 J8 外部 / Core 内部观测点）**
- 下载文件（主）：`release/final_submission/bitstream/mes50hp_riscv_logic_analyzer.sbit`（**85 MHz**）
- SHA-256：**`C017ED10195502739BEBF914DD3BC6F3CAA84C0EAEB6E9E97559248B003FAA4F`**
- 下载文件（备用）：`release/final_submission/bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit`（50 MHz 版，
  SHA-256 **`8102634A23ACB68BF9EDA4110E48A3ECFE28186A4E76D0C5717856903986B012`**）
- 时序：All Constraints Met；PDS 推导的生成时钟 **85.0000 MHz**，估算 **89.3841 MHz**，
  setup WNS **+0.577 ns**，hold WHS **+0.208 ns**（hold fix 阶段；`automated_metrics.json` 记 0.308 ns，阶段不同）
- 资源（布局布线后）：**4995 LUT、3908 FF（实现 3907）、6 个 DRM18K、APM 4**（APM 4 = M 扩展的乘法器）
- 关键性能：
  - **RV32I**：CoreMark/MHz **0.936**（50/80/85/90 MHz 四点一致）；板级 Score 85 MHz **79.587**、
    50 MHz 46.816、80 MHz 74.905、90 MHz 84.269；CPI **≈1.50**（窗口敏感，不要写四位精度）
  - **RV32IM（M 扩展，2026-10-14 新增）**：CoreMark/MHz **2.272**（**2.43×**）；
    板级 Score **85 MHz（与交付同频）193.192**（4000 迭代 20.704 s）、**50 MHz 113.642**（2000 迭代 17.599 s），
    官方 CRC 全过；**同源同频 CoreMark/LUT 0.0190 → 0.0460（2.43×）**
  - **两个 ISA 并列**：`rv32i` 是默认与可比口径，`rv32im` 是增产配置；引用分数必须写明哪一套、哪个频点
- 交付配置：BTB Predictor **On**（On/Off cycles 1,251,724 / 1,604,264，−21.98%）；I-Cache、D-Cache **全部关闭**（S3/S4 止损触发，见下）
- **稳定性**：85 MHz 交付位流 J8 **五模式 ×20 = 100/100 实体采集 PASS**（含镜像与采集源切换）；
  同批另有 **Core 探针 6 次采集 PASS**（窗口 IPC ≈0.597、停顿占 39.5%）；
  更早批次（旧位流）另有 3 轮 soak × 80 次、累计 **320 次零失败**；
  证据 `release/evidence/logic_analyzer_board_85m/`（含 `ui_source_check/`）、`core_probe_board/`、
  `logic_analyzer_board_85m_soak/`

> **最高工作频率**：赛题指标第 (2) 条要"满足时钟约束前提下的最高工作频率"。
> 板载晶振固定 50 MHz，更高频率只能靠 PLL 倍频。PLL 变体工程
> （`fpga/logic_analyzer_85m`、`fpga/coremark_85m`、`fpga/coremark_85m_r`、`fpga/coremark_im_85m`、
> `fpga/coremark_90m`、`fpga/coremark_95m`），把 `STATIC_RATIOF` 由 16 改成 **17**
> （VCO 800 → **850 MHz**，ODIV0 仍 10）⇒ **85.000 MHz 精确整数频率**，PDS **All Constraints Met**。
>
> **交付件已经就是这一版**：交付主位流工作在 85 MHz。
> - **逻辑分析仪板级五模式 ×20 = 100/100 PASS**（当前位流）
> - **CoreMark 板级实测 85 MHz：RV32I 79.587（`cm85`/`cm85r`）、RV32IM 193.192（`cmim85`）**，CRC 全过
>
> **上界口径（三个层次，别混说）**：
> 1. **交付配置（逻辑分析仪应用）= 85 MHz**（板级实测；90 MHz 下 SPI 模式可复现挂死）；
> 2. **CPU 核心 + 最小 SoC = 90 MHz**（CoreMark Score 84.269、CRC PASS）；
> 3. **PDS 时序收敛上界 ≈ 90.6 MHz**；**95 MHz 时序违例（WNS −0.391 ns），未上板**。
>
> ⚠️ **89.3841 MHz 是 PDS 估算值，不是实测**，不得与上面三个层次混写。
> ⚠️ 50 MHz 工程报出的"估算 Fmax ≈55–58 MHz"是**目标频率造成的假象**（50 MHz 目标下 PDS 的最差路径
> 落在 `imem/RSTA`、`ifid_inst/RS` 这类复位端，与 85 MHz 下真正的关键路径 `RF → fetch_pc/CE` 不是同一条），
> **不能当设计上界**。
> 完整报告：`release/evidence/fmax_ceiling/README.md`。

> **N4 时序余量（2026-09-30，收紧约束候选）**：在同一份 RTL 上收紧约束重跑，
> 12.5 ns 约束下 All Met / Fmax 85.2370 MHz，11.765 ns 约束下 All Met / Fmax 89.2538 MHz。
> 候选 `.sbit` 见 `release/artifacts/fmax_tuning_2026-09-30/`（**这些是"改约束不改设计"的候选**，
> 与 85 MHz 交付位流不是同一颗 —— 交付位流靠 **PLL** 真正跑到 85 MHz）。
> 该候选已做板级功能验证（`702EFAD1…`：`PROGRAM PASS` + J8 四模式 80/80），
> 但那**不等于**板上跑到 89.25 MHz。证据 `release/evidence/fmax_candidate_board/`。

> **高阶项①② 止损记录**：S2 行式突发 PASS（总线周期 48→30，−37.5%）；
> S3 2 路组相联 I-Cache 止损（cycles 1,251,724→2,891,324，2.31× 变慢）；
> S4 2 路组相联 D-Cache 止损（1,251,724→1,348,302，+7.7%）。两者**均默认关闭**。
> 结论：片上 BRAM 访问延迟已优于 Cache 命中延迟，Cache 必须等真实 DDR3/HMIC 后端接入后才可能翻盘。
> S1 DDR3 已板级打通（`S1 DDR3 SMOKE BOARD PASS`），但**尚未接入 CPU 存储路径**。

开发阶段的 Pipeline、CoreMark 和 DebugCore 配置仅保留为历史验证证据，不是交付入口，也不需要用户选择。

### 交付入口与"提交 FPGA 工程"的最小集合（2026-10-14）

| 类别 | 配置 | 位流 SHA-256 前 16 位 | 用途 |
|---|---|---|---|
| **A 交付应用** | `la85`（`fpga/logic_analyzer_85m`） | `C017ED1019550273` | **作品本体**：指标②最高工作频率 + ④应用场景 |
| **B 计分 RV32IM @85 MHz** | `cmim85`（`fpga/coremark_im_85m`） | `EE8B65360B0B0718` | 指标①CoreMark/MHz + ③CoreMark/LUT（**与交付同频的 M 扩展分数**） |
| **C 计分 RV32I 基线 @50 MHz** | `cm50`（`fpga/coremark`） | `DC95F9D087B7E29B` | 所有 Before/After 的"Before"（46.816） |
| **D 备用应用 @50 MHz** | `la50`（`fpga/logic_analyzer`） | `8102634A23ACB68B` | 主位流异常时的已验证回退 |
| **E 同源对照点 RV32I @85 MHz** | `cm85r`（`fpga/coremark_85m_r`） | `EC71AFDD42772012` | 与 B 同 RTL/同频率/同资源 ⇒ CoreMark/LUT 可**同源**比较 |
| **F ILA 性能分析** | `ila`（`fpga/coremark_ila`） | `B6507CF177BAC2DF` | 指标⑤(2) 要求"用 ILA 波形分析 CoreMark 关键算法的流水线效率" |

- **A 与 B 不是同一颗位流**：`la85` 里 M 扩展**在 RTL 中存在**（资源 APM=4），但它跑的是逻辑分析仪固件
  （rv32i 程序，不执行 M 指令）；"M 扩展的收益"必须由 `cmim85` 来证。
- **C 与 B/E 的分数都要带 ISA 与频率**：46.816（rv32i@50）、79.587（rv32i@85）、113.642（rv32im@50）、
  193.192（rv32im@85）；`CoreMark/MHz` 只有两个值：**0.936（rv32i）/ 2.272（rv32im）**。
- **不必交**（结论用证据文件说话即可）：`la80`/`la90`（频率扫描、90 MHz 下 SPI 挂死）、
  `cm80`/`cm90`/`cm95`（扫描与违例留档）、`tm50`/`tmila`/`ddr3`/`pipeline_soc`/`bram_smoke`/`soc_demo`
  （验证与演示工程，不是交付入口）。
- 提交形式按指南要求是"**打包的工程源码**"：每个配置 = `.pds` + 工程 `rtl/` + `constraints/*.fdc`
  + `pds_recipe.tcl` + 共享 `rtl/`（各工程的配方用 `../../rtl/...` 相对路径引用它）+ 位流 + 证据 JSON/串口日志。


## J8 接线

只需八根杜邦线连接隔行相邻脚对：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。奇数脚为激励输出，偶数脚为采集输入。

## 验证状态

RTL、GCC、官方 CoreMark CRC（RV32I 四点 + RV32IM 两点）、Predictor Off/On、逻辑分析仪（含采集源双源）、Python/VCD 和最终 PDS 均已通过。**交付主位流（85 MHz）已由 JTAG 下载到 PGL50H（DONE=1），J8 五模式 ×20 = 100/100 实体采集 PASS，Core 探针 6 次采集 PASS**；证据位于 `release/evidence/logic_analyzer_board_85m/`（含 `ui_source_check/`）与 `release/evidence/core_probe_board/`。

`release/final_submission`、`release/artifacts` 与 **`fpga/logic_analyzer_85m/generate_bitstream`** 的位流 SHA-256 必须一致（**`C017ED10…003FAA4F`**），位流、时序、约束、固件与实体回环证据必须来自同一次最终构建；任何源文件修改后都要重新执行 `export_final_submission.ps1`、`create_release_manifest.ps1` 和 `audit_release_package.ps1`。发布脚本用 Windows PowerShell 5.1 与 `scripts/resolve_host.ps1` 解析出的宿主均可执行（本机 `pwsh` 不在 PATH，脚本内部统一走 `powershell.exe`）。
（备用位流 `…_50m_fallback.sbit` 必须与 `fpga/logic_analyzer/generate_bitstream` 一致，审计脚本会单独校验。）

### 2026-10-14 新增并已通过的板级证据

| 项 | 结论 | 证据 |
|---|---|---|
| RV32IM 计分（与交付同频 85 MHz） | Score **193.192**、CoreMark/MHz **2.272**、4000 迭代 20.704 s、官方 CRC PASS | `release/evidence/coremark_board_cmim85_20261014.json` |
| RV32I 同源对照点（85 MHz） | Score **79.587**、ticks **2,670,014,377**（与 09-30 归档位流逐位相同） | `release/evidence/coremark_board_cm85r_20261014.json` |
| 采集源双源可选（界面路径） | pyUI 四种"模式×源"组合全 PASS + 单文件界面六模式通过 | `release/evidence/logic_analyzer_board_85m/ui_source_check/` |
| Core 探针（自研仪器量自研 CPU） | 窗口 IPC ≈0.597、停顿占 39.5%、4 次冲刷 | `release/evidence/core_probe_board/` |

### 2026-09-30 新增并已通过的板级证据

| 项 | 结论 | 证据 |
|---|---|---|
| 板级裸机定时器中断（N1，M-24 前半） | 12 次中断，固件自计时中位数 12,517,376 拍 = **250.348 ms** | `release/evidence/timer_demo_board/timer_demo_board.json` |
| ILA 抓 Trap 进入/返回（N2，M-24 后半） | 两次抓取互为正/反向触发，trap 与 return 各**恰好一个**脉冲；M-24 收口为 PASS | `fpga/timer_demo_ila/evidence/` |
| CoreMark 关键循环 ILA 波形（Task 29） | 512 cycle 抓取 + 周期表 | `release/evidence/ila_coremark/` |
| 板级 CoreMark 计分 | 1000 迭代，`ticks=1068006999`，**46.816 分**，CRC PASS | `release/evidence/coremark_board.json` |
| S1 DDR3 板级连通 | `S1 DDR3 SMOKE BOARD PASS`，BIST 错误全程 0 | `docs/ddr3_s1_survey.md` §2.4.2 |
| Trap 契约 | M-01…M-24 **全部 PASS**，剩余"部分通过"条目 **0** | `docs/trap_contract.md` |

> ⚠️ S1 DDR3 的板级日志目前**只存在于 `docs/ddr3_s1_survey.md` 正文**，`release/evidence/` 下**没有**独立目录。
> 若要求"每个数字都有独立证据文件"，DDR3 是唯一不满足的条目——**已知缺口，尚未补齐**。

## 参赛材料

- `release/materials/technical_report.docx` / `.pdf`：13 页技术报告（含当前限制与后续工作）。
- `release/materials/defense_presentation.pptx`、`defense_qa.md`、`video_script.md`、`field_recovery_card.md`：答辩 PPT、问答稿、三分钟视频脚本和现场恢复卡。
- `release/evidence/automated_metrics.md` / `.json`：自动提取的资源、时序与 Predictor Before/After 指标。
- **`release/evidence/claims_map.md`（2026-09-30 新增）**：数字 ↔ 证据文件 ↔ 位流 SHA-256 对照表，含"未宣称清单"。**评审前先看这份。**
- `release/artifacts/fmax_tuning_2026-09-30/`：N4 Fmax 收紧约束扫描的候选产物与 `sweep_summary.csv`。
- `docs/demo_runbook.md`：现场演示分镜与一键命令（含断电/复位恢复流程）。

实体板 CoreMark 分数（RV32I 四点 + RV32IM 两点）与 Task 29 Fabric Debugger 波形均已补齐（见上表）。
**三轮断电压力：`run01` 已做（重下载 = Reset 等价，未断电）；`run02`/`run03` 未做，用户 2026-09-30 决定不做**
（见 `release/evidence/board/README.md`）。
**已知限制（2026-10-14 记录）**：逻辑分析仪固件在"触发条件永不出现"时会停在无超时的采集完成轮询上，
串口不再响应，只能按板上 `REST` 或重下同一位流恢复（`docs/application_logic_analyzer.md` §6.10.7）；
是否给固件加 Arm 超时（需重建位流、刷新全部哈希）由用户决定，本批保持位流不变。
因此当前发布标识保持 `competition_final_candidate`。
