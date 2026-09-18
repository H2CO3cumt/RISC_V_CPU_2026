# Project Progress

> 最后更新：2026-09-17（CPI 优化专项轮 + 交付冻结收口）
> 状态依据：`AGENTS.md`、`docs/competition_scoring.md`、`docs/roadmap.md`、`docs/architecture.md`、`docs/interfaces.md`、`docs/fpga_platform.md`、`docs/application_logic_analyzer.md` 与当前项目文件。聊天记录不作为任务完成证明。

## 交付冻结收口（2026-09-17，CPI 专项之后）

### 1. 目录与文件命名去 taskNN 化（不改行为）

开发期的 `taskNN_*` 命名全部改成功能化命名；**文档里的 “Task NN” 过程叙述保留不动**（那是 `docs/roadmap.md` 的任务编号，不是文件名）。

| 现在 | 原 |
|---|---|
| `fpga/coremark`、`fpga/coremark_80m` | `fpga/task28_coremark`、`fpga/task28_coremark_80m` |
| `fpga/coremark_ila` | `fpga/task29_coremark_ila` |
| `fpga/logic_analyzer`、`fpga/logic_analyzer_80m` | `fpga/task30_logic_analyzer`、`fpga/task30_logic_analyzer_80m` |
| `fpga/pipeline_soc`、`fpga/soc_demo` | `fpga/task26_pipeline_soc`、`fpga/task16_soc` |
| `software/logic_analyzer`、`c_smoke`、`c_array_control`、`mmio_demo`、`gpio_only`、`uart_only`、`hello_uart` | `software/task30_*`、`task14_*`、`task16_mmio_demo`、`task17_*`、`task3_hello` |
| 脚本 / TB / 测试程序 共 24 + 18 + 18 个文件 | `run_taskNN_*.ps1`、`tb_taskNN_*.v`、`tb/data/taskNN_*.mem` 等 |

连带修正（都是改名暴露出来的既有脆弱点，不是新功能）：
- `run_soc_harness_tb.ps1` 原来依赖仓库里**已存在的旧固件产物**、自己不做 `make`；固件改名后立刻暴露。已改为自己构建 `software/mmio_demo`。
- 发布审计 `audit_release_package.ps1` 原来把位流哈希**写死**成上一版，任何一次重新综合后必然失败；已改为以 `fpga/logic_analyzer/generate_bitstream/…sbit` 为唯一真实来源，要求三处副本一致。
- 同一审计用 `rg` 做命名检查，本机无 ripgrep 时会中断审计；已加 PowerShell 回退实现（保留「交付包不得出现 taskNN」这条检查）。
- 导出脚本原来整目录删除发布目录，被 PDS GUI 的 `.pds.lock` 占住时会删到一半失败；已改为逐项删除并跳过被占用条目。

验证：`run_final_regression.ps1`（-Quick 与全量）均 `ALL AUTOMATED FINAL REGRESSION PASS`；
6 个 PDS 配方的 `add_design` 相对路径逐个校验存在（0 缺失）；未重建位流，以免动到已上板验证的哈希。

### 2. 实体板 ILA 波形（赛题明确要求的一项）

用 PDS Fabric Debugger 的 TCL 模式（`cdt_dbg.exe`，**不需要点 GUI**）在板子上抓到了 CoreMark 运行中的真实流水线波形：
512 拍窗口、**IPC 0.635 / CPI 1.575**（与整段板级 CPI 1.5388 相差 2.3%），
窗口内 **84.3% 的提交指令落在 libgcc 的软件乘法 `__mulsi3`**，其中数据相关的 `beq` 是 44 次 flush 的主要来源。

证据与复现步骤：`release/evidence/ila_coremark/README.md`；分析脚本 `python/ila_coremark_analysis.py`；
诊断位流构建入口 `scripts/run_coremark_ila_pds.ps1`。

### 3. 发布包已用当前位流重新导出

`export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` 全部 PASS：
`FINAL SUBMISSION EXPORT PASS files=206`、`RELEASE MANIFEST PASS files=1963`、`RELEASE PACKAGE AUDIT PASS final_files=126 artifacts=3`。
包内 README 的时序/资源/位流哈希改为**导出时自动取值**（不再硬编码），当前三处位流副本一致：
`17FD57D8F12FF4DCC8FC3A66D644561973E9D75AB9286F09D2F506F94BCDB092`（LA 50 MHz，已实体板 80/80 回环验证）。
`release/artifacts/` 与包内 `evidence/logic_analyzer_board_final/` 已同步为当前位流的实测证据。

> 遗留：发布目录里仍有一个 `MES50HP_RISCV_Logic_Analyzer.pds.lock`（PDS GUI 自 14:32 起打开着该工程，占用无法删除）。
> 它被清单与审计按设计排除，不影响交付；关掉 PDS GUI 后再执行一次导出即可消除。

---

## CPI 优化专项轮（2026-09-17，T1～T3）—— Score 29.559 → 45.051

本轮只有一个目标：**降 CPI 以提高 Score**。战略前提（上一轮已用实体板证明）：
`Score = Iterations/(Total_Time × Frequency)` 等价于 CoreMark/MHz，是频率归一化的，
提频率只服务第 (2) 项「时钟频率」，**要提 Score 必须降 CPI**。

### T1：先定位，再动手（只读观测，不改 RTL）

新建与实体板**逐拍同源**的观测台（`tb/cpi_board_memory_model.v` + `tb/tb_cpi_attribution.v`
+ `scripts/run_cpi_attribution_tb.ps1`），口径自证：观测台窗口 CPI **2.342** vs 实体板 **2.3443**（差 0.1%）。

第一个错误信号：**`i_req_valid` 有 920,207/1,788,110 拍（51.5%）为低**；
相邻 IF/ID 写入间隔直方图里 **间隔 2 占 86.7%、间隔 1 只有 1 次** —— 取指只能每两拍一条。

根因在 `rtl/pipeline_cpu.v`：请求被接受的当拍 `if_req<=0`，下一拍**没有任何请求对外可见**，
要等到“响应被接收”那一拍的结尾才重新登记，因此“旧响应接收 + 新请求接受”的交接永远无法发生；
实体板取指存储器 `assign req_ready=!rsp_valid` 在交接当拍同样是 0，两边一起把取指钉在 2 拍/条。

严格对账（板级口径，每 1000 条指令）：
`2344.3 = 理想 1000 + stall 106.4 + flush 103.3 + 剩余 1134.6`，
其中剩余的主体就是“每笔取指多花 1 拍”：`2 × 766,004 = 1,532,008 拍`为取指底座，
超出理想执行的 **768,832 拍（43.0%）纯属取指串行化损失**。
`mem_block` 只占 78,158 拍（4.4%），且大多落在取指空洞里几乎免费。

**结论**：原候选「store 提前退休」「REQ→RSP 压一拍」「访存地址提前产生」都不是主要矛盾，**T2 改取指**。

### T2：一轮一块 —— 取指满速交接（`if_arm`）

| 子块 | 内容 | 单独收益（观测台 CPI） |
|---|---|---:|
| A. SoC 侧 | 取指存储器 `req_ready` 由 `!rsp_valid` 改为 `!rsp_valid||rsp_ready` | 2.342 → 2.321（−0.9%，单独无用） |
| B. Core 侧 | `rtl/pipeline_cpu.v` 接受请求当拍立即武装下一笔请求（新增 `if_arm`） | 2.321 → **1.550（−33%）** |

A 单独做几乎没有收益，证明瓶颈在 Core；两者必须一起改。逐条说明见 `docs/rtl_changes.md` 改动 2，
定位过程见 `docs/debug_log.md`，完整归因见 `docs/coremark_cpi_analysis.md`。

### 实体板 Before / After（**全部为实体板实测**）

| 指标 | Before 50 MHz | **After 50 MHz** | 变化 | After 80 MHz PLL |
|---|---:|---:|---:|---:|
| **Score** | 29.559 | **45.051** | **+52.4%** | **72.081** |
| **CoreMark/MHz x1000** | 591 | **901** | **+52.5%** | **901** |
| **CPI** | 2.3443 | **1.5388** | **−34.4%** | 1.5387 |
| ticks | 1,691,496,677 | 1,109,848,679 | −34.4% | 2,774,618,621（2500 iter） |
| cycle_count | 1,693,816,436 | 1,112,164,751 | −34.4% | 2,778,317,919 |
| instret_count | 722,513,265 | 722,746,356 | +0.03% | 1,805,613,110 |
| cycles / iteration | 1,693,816 | 1,112,165 | −34.4% | 1,111,327 |
| 运行秒数 | 33.829 | 22.196 | −34.4% | 34.682 |
| stall / cycles | 4.54% | 8.18% | 占比升高（分母变小） | 8.16% |
| load-use / stall | 9.30% | 23.27% | 真实冒险现被检出 | 23.18% |
| flush / cycles | 4.41% | 6.71% | 绝对值不变 | 6.71% |
| branch / instret | 0.275 | 0.2747 | 不变 | 0.2747 |
| 官方 CRC | 全过 `0xd340` | 全过 `0xd340` | 一致 | 全过 `0x5275` |

- **双频交叉验证**：CPI 1.5388 / 1.5387（0.006%）、cycles/iteration 差 0.075%、
  `CoreMark/MHz x1000` 均为 901 → 性能与频率无关，两点互为验证。
- 两次运行都满足 **官方四 CRC 全过 + `Correct operation validated.` + 运行 ≥10 s**（22.196 s / 34.682 s）。
- 本轮位流 SHA-256（前 16）：CoreMark 50 MHz `3791D1E7D91D90AC`、CoreMark 80 MHz PLL `34BA88F53FD0FF9C`、
  逻辑分析仪 50 MHz `17FD57D8F12FF4DC`、逻辑分析仪 80 MHz PLL `0388100A6D471402`。
  `rtl/pipeline_cpu.v` SHA-256 前 16：`8E8EB3A69B2EF45E` → **`BD8BA8640C3B6A4D`**。

### 时序（四个配置全部重新综合，全部 `All Constraints Met`）

| 工程 | WNS | WHS | 备注 |
|---|---:|---:|---|
| CoreMark 50 MHz | +2.349 ns | — | 最差路径 `core/rf/regs → imem/mem_7` |
| CoreMark 80 MHz PLL | **+0.667 ns** | +0.312 ns | 估计 Fmax **84.51 MHz**（上一轮 +0.145 ns） |
| 逻辑分析仪 50 MHz | +2.812 ns | — | |
| 逻辑分析仪 80 MHz PLL | **+0.789 ns** | — | 估计 Fmax **85.39 MHz** |

新增的“下一取指 PC → BTB → `if_req_pred_*`”组合链确实成为 80 MHz 最差路径，但余量反而比上一轮更大。

**频率扫描复核（CPI 优化后 RTL，`run_fmax_sweep_rtl.ps1 -Tag cpi3 -Periods '11.765,11.111'`）**：
**85 MHz `All Constraints Met`，WNS +0.393 ns、0 失败端点（改动前 +0.246 ns）**；
90 MHz 仍 VIOLATED（WNS −0.374 ns、102 失败端点）。芯片天花板仍约 **88～90 MHz**。
即「最高工作频率」计分项维持 **85 MHz（时序证据）/ 80 MHz（实体板实跑）** 不变，且余量变大。

### 逻辑分析仪应用（同一份 Core，位流全部重建）

| 配置 | 结果 |
|---|---|
| 50 MHz | `scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` → **80/80 PASS**（static/counter/uart/spi 各 20 轮） |
| 80 MHz PLL | 同上 → **80/80 PASS** |

证据目录：`release/evidence/logic_analyzer_board_cpi50m/`、`logic_analyzer_board_cpi80m/`。

### 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 全套回归（20 个入口） | `scripts\run_final_regression.ps1 -Quick` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 全套回归（含 CoreMark 三个入口） | `scripts\run_final_regression.ps1` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 官方 CoreMark RTL 仿真 On / Off | `run_coremark_pipeline_tb.ps1` / `-DisablePredictor` | cycles 1,852,156 → **1,295,932**（CPI 2.3747 → 1.6539）/ 2,106,042 → **1,604,264**（2.7143 → 2.0670） |
| 板级同源存储器模型 CRC 自检 | `run_coremark_fpga_tb.ps1` | `ALL COREMARK FPGA TOP TEST PASS`，cycles 1,221,446 |
| 实体板 CoreMark 50 MHz | `cdt_cfg` + `coremark_serial.py COM11` | PASS，Score 45.051、22.196 s、crcfinal `0xd340` |
| 实体板 CoreMark 80 MHz PLL | 同上，2500 迭代 | PASS，Score 72.081、34.682 s、crcfinal `0x5275` |
| 实体板逻辑分析仪 50/80 MHz | `run_logic_analyzer_board.ps1` | 各 80/80 PASS |

### 一处必须说明的测试期望更新

`scripts/run_pipeline_load_use_tb.ps1` 的 `EXPECT_LOAD_STALL` **3 → 4**：
测试程序含 4 组相邻 load-use，旧值 3 是“取指每两拍一条”时代的历史标定
（当时取指空洞恰好把 0x24→0x28 这对指令拉开两级）。逐事件探针与完整理由见
`docs/rtl_changes.md` §2.8 与 `docs/debug_log.md`。同一测试的提交级 trace 与最终状态对比全部 PASS。

### 下一步（下一轮候选）

1. **候选 A（收益最大）**：正确预测的跳转不再 Redirect。板级目前约 28,500 次/迭代属于
   “BTB 已预测正确但仍被 `idex_jump` 无条件 Redirect”，每次多花 3 拍 ≈ 7.7% cycles。
   前置条件：BTB 对 jump 的 `update_taken` 目前取自对 JAL/JALR 无意义的 `branch_unit`，需先改成恒 taken。
   预期 CPI 1.5388 → 约 1.42、Score 45.05 → 约 48.8。
2. 候选 B：数据访问 1 拍阻塞与取指重叠（上界 ≈ 7%，风险高）。
3. 已作废候选：原「数据事务 REQ→RSP 压一拍」被 T1 证伪（板级本来就只有 1 拍阻塞）。

### 已知遗留

- `release/artifacts/fmax_tuning_2026-09-17/` 与 `release/final_submission/` 内的位流是**上一轮**版本，
  本轮新位流并存于 `fpga/*/generate_bitstream/`。未静默替换发布清单；
  如需刷新发布包，必须按 `export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` 顺序执行。
- `fpga/soc_demo`、`fpga/pipeline_soc` 的演示位流内嵌同一份 Core，本轮未重建。

---

## 上一轮：性能调优轮（2026-09-17，T0～T6）

本轮在赛题一评分规则范围内对最终版做了频率扫描、CPI 归因、关键路径提取和一处 RTL 优化，
并把 80 MHz PLL 配置做成可交付工程。完整数据见 `docs/performance_tuning.md`，
逐条改动说明见 `docs/rtl_changes.md`，CPI 归因见 `docs/coremark_cpi_analysis.md`。

### 关键结论（数据具体到数字）

1. **"松约束下的估算 Fmax"确实只是下界**。同一份 RTL、同一套配方，只改 `.fdc` 的 `create_clock -period`：
   50 MHz 约束报估算 Fmax 54.96 MHz，70 MHz 约束报 75.60 MHz，80 MHz 报 83.95 MHz，85 MHz 报 85.03 MHz。
   **PDS 的 `Estimated Frequency` 是"约束下反推值"，不能当作芯片上限。**
2. **真实天花板约 89～90 MHz**。优化前 90 MHz 失败（WNS −0.059 ns、TNS −0.455 ns、18 个失败端点），
   85 MHz 恰好通过（WNS **+0.005 ns**）。优化后 90 MHz 仍失败（WNS −0.148 ns、113 个失败端点），
   85 MHz 有 WNS **+0.246 ns**、80 MHz 有 +0.145 ns、70 MHz 有 +1.035 ns、50 MHz 有 +1.693 ns，
   所有实测点 hold WHS ≥ +0.276 ns、THS = 0。**回答用户问题：70 MHz 与 80–85 MHz 都达到；90 MHz 不达到。**
3. **公共瓶颈是性能计数器**。50 MHz 约束下最差 10 条路径有 8 条终点在 `perf/flush_count`，前 3 名全是
   `core/rf/regs/iGopDrm → exalu → N161.eq_* (16 级相等比较) → perf_mispredict → perf_flush (fanout=46) → flush_count[24..60] (10 级 CECO 进位链)`，
   26 级逻辑、arrival 22.789 ns。task30 逻辑分析仪配置是同一瓶颈（25 级、arrival 21.933 ns）。
4. **已落地改动只有一处**：`rtl/perf_monitor.v` 把 9 个事件先锁一拍再驱动计数器，
   切断"事件分类 → 64-bit 计数器进位链"的组合路径。效果：50 MHz 约束下 `perf/` 终点从最差 10 条中占 8 条降为 **0 条**，
   最差路径逻辑级数 26 → 21、逻辑延迟 8.381 → 7.866 ns；85 MHz 的 WNS 从 +0.005 提到 **+0.246 ns**。
   该模块是 Core 外只读统计逻辑，**端口与计数器宽度未变，不触及 Core/SoC 边界、流水线、Hazard、提交 trace 或 Reference Model**。
5. **提频率不会提 Score**。`Score = Iterations/(Total_Time × Frequency)` 等价于 CoreMark/MHz，是频率归一化的；
   提频率只服务于独立的第 (2) 项「时钟频率」。要提 Score 必须降 CPI。
6. **CPI 最大单项优化空间是访存事务等待**：RTL 仿真（官方 CoreMark、Predictor On）CPI 2.3747 中，
   访存相关合计约 **48% cycles、1.14 CPI**（理想执行 1.0000 / Hazard stall 0.2259 / 控制冒险 flush 0.2090 / 访存事务等待 0.9398）。
   把数据事务 `dstate` 的 REQ→RSP 两拍压成一拍估计可回收约一半（CPI 约 −0.4，约 −17%），
   但需要改动流水线访存时序，风险高于本轮改动，**本轮未做，作为下一轮明确建议**。
   板级 `cycle_count/instret_count`（2.2719）不能当 CoreMark 内核 CPI——`ticks` 与 `cycle_count` 窗口相差 18.6%。

### 80 MHz PLL 配置（新增可交付工程）

P20 是 50 MHz 固定晶振，>50 MHz 必须倍频；PGL50H PLL 只能整数分频，**无法精确产生 85/90 MHz，但能精确产生 80 MHz**：
`IDIV=1, FDIV=16, ODIV0=10 → PFD 50 MHz, VCO 800 MHz, 输出 80.000 MHz`（VCO 需在 600～1250 MHz 内）。

| 工程 | 顶层 | 80 MHz 时序 | LUT | FF | DRM18K | 位流 SHA-256 |
|---|---|---|---:|---:|---:|---|
| `fpga/coremark_80m` | `mes50hp_coremark_pll_top` | All Constraints Met，WNS +0.721 / WHS +0.312 | 3003 | 2593 | 33.0 | `3BF90440BDC9D2AB463B5D9E389107F846FB1A1A2972D81E03DA9070CC23948F` |
| `fpga/logic_analyzer_80m` | `mes50hp_logic_analyzer_pll_top` | All Constraints Met，WNS +0.652 / WHS +0.312 | 3781 | 3143 | 5.5 | `261D3989AC2D3EC686B9C740B42E988A96175B8534BE5F494D66573A1A54D898` |

PLL 原语 `GTP_PLL_E3` 直接例化在 `fpga/coremark_80m/rtl/pll_80m.v`，**不依赖外部 IP 文件**，完全位于 Core 之外。
UART 波特率按新时钟重算：80e6/115200 = 694 → 实际 115274 baud（−0.064%，在容差内）。
RTL 级闭环测试 `scripts/run_logic_analyzer_pll80_board_top_tb.ps1`（`tb/pll_80m_model.v` 提供 PLL 行为模型）输出
`PLL80 LOCK PASS` / `PLL80 FREQ PASS period_ps=12400` / `PLL80 UART PASS bytes=13` / `PLL80 CAPTURE PASS count=9` / `ALL TASK30 PLL80 BOARD TOP TEST PASS`。

### 官方 50 MHz 工程已用优化后 RTL 重建

| 工程 | 时序 | LUT | FF | 位流 SHA-256 |
|---|---|---|---:|---:|---|
| `fpga/coremark` | All Constraints Met，WNS +1.693 / WHS +0.314 | 2709 | 2585 | `9F42B8F9720D70471F2479D7DAE4F702BF60A22365223207D0BEED68AB596B26` |
| `fpga/logic_analyzer` | All Constraints Met，WNS +2.257 / WHS +0.319 | 3458 | 3137 | `DB705898A42BA25628303017034DDB7531DBA44BDBB58574E5CAFC19AAA331E6` |

调优前后位流与对应时序报告已归档到 `release/artifacts/fmax_tuning_2026-09-17/`（含调优前的逻辑分析仪位流存档 `la_50m_pre_tuning_ARCHIVE.sbit`，SHA-256 `2C09E690…`）。
**注意**：`release/final_submission` 与 `release/artifacts` 顶层的位流仍是调优前版本（`2C09E690…`），
其 `SHA256SUMS.txt` 因此仍然自洽；调优后位流是并存的新交付物，未静默替换发布清单。

### 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 全套回归（20 个入口） | `scripts\run_final_regression.ps1 -Quick` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 性能计数器定向 + MMIO | `run_perf_monitor_tb.ps1` / `run_perf_mmio_tb.ps1` | 13/13、8/8 PASS（含 clear/disable 边界） |
| 官方 CoreMark RTL 仿真 | `run_coremark_pipeline_tb.ps1` | `cycles=1852156 retired=779952`，官方 CRC 全过，**与改动前逐字段一致** |
| 频率扫描（优化前 5 点 / 优化后 7 点，隔离目录） | `scripts\run_fmax_sweep_rtl.ps1` | 见上 |
| 80 MHz PLL 顶层 RTL 闭环 | `scripts\run_logic_analyzer_pll80_board_top_tb.ps1` | `ALL TASK30 PLL80 BOARD TOP TEST PASS` |
| 80 MHz 位流构建（两套工程） | PDS 完整流程 | `All Constraints Met`，0 失败端点 |

### 实体板验证：**已完成**（2026-09-17 补测，JTAG 下载线接上后）

扫描链确认 `Cable index 0: USB Cable II`、器件 `PGL50H`，每次下载 `The done bit is 1`。

| 验证项 | 位流 SHA-256 | 结果 |
|---|---|---|
| 优化后 50 MHz CoreMark | `8001A60D4CB17433` | **Score 29.559**、ticks 1,691,496,677、**33.829 s**、CPI 2.3443，四个官方 CRC 全过 + `Correct operation validated.` |
| 80 MHz PLL CoreMark | `FF6775A465A5CB68` | **Score 47.295**、ticks 4,228,738,028、**52.859 s**、CPI 2.3445，四个官方 CRC 全过 + `Correct operation validated.` |
| 逻辑分析仪 50 MHz 优化版 J8 回环 | `DB705898A42BA256` | static/counter/uart/spi 各 20 次 = **80/80 PASS** |
| 逻辑分析仪 80 MHz PLL 版 J8 回环 | `261D3989AC2D3EC6` | static/counter/uart/spi 各 20 次 = **80/80 PASS** |

**PLL 80 MHz 的独立交叉验证**：80 MHz 实测 1,691,495.2 周期/迭代，50 MHz 实测 1,691,496.7 周期/迭代，
相差 **0.0001%**；反推频率 4,228,738,028 / 52.859 s = **80.00 MHz**，与实测墙钟一致；
UART 按分频 694 输出全部正确，排除时钟错配。

**Score 频率归一化得到实体板证明**：29.559 × (80/50) = 47.295，两者 CoreMark/MHz 都是 **591**。

**测量口径修正**：原板级计数器窗口包含 `COREMARK_READY` 的 UART 轮询等待，导致 CPI 归因失真
（stall 甚至超过 cycles）。已在 `software/coremark/core_portme.c` 的 `start_time()` 加入
`PERF_CONTROL = 1u` 清零（`PERF_WINDOW_ALIGN=1` 开关，纯观测口径修正，不改执行路径）。
修正后 50/80 MHz 两点 CPI 分别为 2.3443 / 2.3445，逐项吻合到 0.02% 以内。

证据：`release/evidence/coremark_uart_opt50m_aligned.log`、`coremark_board_opt50m_aligned.json`、
`coremark_uart_80m_aligned.log`、`coremark_board_80m_aligned.json`、
`release/evidence/logic_analyzer_board_opt50m`、`release/evidence/logic_analyzer_board_80m`。

## 当前阶段

Task 20～32 的自动化 RTL/软件/PDS 证据已经通过，当前执行 Task 33～35 交付冻结。开发阶段的多套验证配置已经收口，发布入口只保留 `mes50hp_logic_analyzer_top` 一套最终配置：RV32I 五级流水线、16 项 BTB、UART/GPIO、十项性能计数器和八通道逻辑分析仪。官方 CoreMark CRC 与 Predictor Off/On 已通过 RTL 仿真；MES50HP JTAG 下载和 J8 四模式物理回环已完成实体验收，CoreMark 实体计分、Fabric Debugger 波形和断电压力仍按各自证据边界单独记录。

> 2026-09-17 接班交付包一致性修复：上一轮导出（08:37）早于当日 J8 隔行脚对约束校正、Capture Engine 分频边沿修复与上位机位中心采样修复（13:45～13:48），因此 `release/final_submission` 与 `release/artifacts` 内仍是旧位流 `01C39461…`，与实体板 80/80 回环所用 `2C09E690…` 不一致；`.fdc`、`README.md`、`reports/timing.rtr`、`rtl/capture_engine.v`、`rtl/logic_analyzer_pattern_gen.v` 与三份上位机工具同样是修复前版本，且包内缺少 `evidence/logic_analyzer_board_final`。已用 PowerShell 7.6.5 重新执行 `export_final_submission.ps1`（`FINAL SUBMISSION EXPORT PASS files=215`）、`create_release_manifest.ps1`（`RELEASE MANIFEST PASS files=1221`）与 `audit_release_package.ps1`（`RELEASE PACKAGE AUDIT PASS final_files=132 artifacts=3`）；最终位流三处副本 SHA-256 均为 `2C09E6904A6C6238CF7158E907087F905C1B7DF46E6D2C9B665E1DE10964746E`。13 页技术报告 PDF 已归档到 `release/materials/technical_report.pdf`（与 `technical_report.docx` 同源渲染件，封面与末页已复核）。本轮未修改任何 RTL。

> 2026-09-17 接班回归复核：`run_final_regression.ps1 -Quick` 输出 `ALL AUTOMATED FINAL REGRESSION PASS`，20 个入口全部 PASS（Task 12/17/23/24/25/26/28/29/30/33 与最终 bitstream 哈希校验 `sha256=2C09E690…`）；Task 23 汇总入口现为 13 个，Task 30 board-top 与 SoC 集成、Python/VCD、冻结范围审计均 PASS。

> 2026-09-17 接班证据复核补充：官方 CoreMark 三项按正式入口重跑并 PASS——固定延迟 `cycles=1852156 retired=779952`、`predictor enabled=1 predict=213756 btb_hit=203492 mispredict=51908`，随机背压 `cycles=3339018`，FPGA memory model `cycles=1831176 bytes=655`；固定延迟结果与 `release/evidence/automated_metrics.json` 的 Predictor On 记录逐字段一致，证明该结论可在当前工作区复现。同时修复 `python/release_evidence.py` 的资源提取缺陷：原实现从 device map 段取 FF（3120）却从综合段取 LUT/DRM，现统一取综合统计 `Total Registers`（3129），并把布局布线后实现 FF 另存为 `ff_implemented=3120`，使自动证据与 `docs/progress.md`、`release/HANDOFF.md` 及技术报告的 3129 FF 一致。

> 2026-09-15 最新交付记录：修复流水线在数据事务等待期间 WB 值不再可转发导致的错误，新增 `wb_hold` 定向用例并将 Task 23 汇总扩为 10 个入口；Task 24 固定/随机背压的完整退休 trace、x1～x31 和关键 RAM 比较继续 PASS。官方 CoreMark checkout 固定到 `1f483d5b8316753a742cbf5590caf5bd0a4e4777`，固定/随机事务仿真均输出官方 CRC。同步 FPGA memory model 为 1,923,077 ticks/iteration、CPI 2.6682、CoreMark/MHz 0.520000；正式镜像为 1000 iterations、50 MHz、串口 `R` 启动，预期计时区间 38.46154 s，实体成绩尚不宣称。

> PDS 2026-09-15：Pipeline SoC 为 2267 LUT、1343 FF、1 DRM、setup WNS +6.062 ns、slow-corner hold +0.314 ns、estimated Fmax 71.7463 MHz；CoreMark 为 2438 LUT、1333 FF、33 DRM、setup +5.350 ns、hold +0.313 ns、estimated Fmax 68.2594 MHz；修正精确 pre/post 后的逻辑分析仪为 2998 LUT、1880 FF、7 DRM、setup +5.264 ns、hold +0.315 ns、estimated Fmax 67.8610 MHz。三者在 50 MHz 下均 All Constraints Met，指标由 `run_release_evidence.ps1` 自动提取。

> Task 30 2026-09-15：增加可编程 8 路物理回环发生器，支持静态、计数器、UART 8N1 和 SPI mode 0；正式固件采用 13 字节带 XOR 校验配置包，上电输出 `LA_READY`，无需重新综合即可更改模式、数据、速率、触发和前后采样。独立发生器 TB、MMIO byte-enable、20 轮采集/Reset 压力、交互式 board-top UART、AUTOSTART SoC、Python UART/SPI/VCD 六类入口全部 PASS。Capture Engine 进一步修正为精确 `pre + trigger + post` 计数和逻辑 trigger index，正式 Task 30 bitstream SHA-256 为 `C8123DA9699AE29D528F2FE61BFD8A3064DB678DB9AA1F0050EA490545BF779A`。

> 2026-09-17 实体约束校正：用户提供的实际 J8 约束使用隔行相邻脚对 `3/4、7/8、11/12、15/16、19/20、23/24、27/28、31/32`，原先连续 `3..18` 的文档与实体接线不一致。工程 `.fdc`、平台表、上位机提示和发布材料已按实际 LOC 同步；此前实体 static 出现 `期望 A5、实际 AF` 和 `期望 00、实际 AA`，根因是旧约束使 CH1/3/5/7 输入悬空，不作为逻辑功能失败证据。

> 2026-09-17 实体闭环完成：修复 UART pattern restart 的空闲帧同步、Python 位中心采样，以及 Capture Engine 在分频采样下每系统时钟更新 `previous_sample` 导致边沿丢失的问题；新增 `divided edge retained` 定向测试。最终位流经 PDS 2024.2-SP2 重建并 JTAG 下载，DONE=1。J8 实体回环 static、counter、UART 8N1 `0xA5`、SPI mode 0 `0x3C` 各连续 20 次，共 80/80 PASS；原始串口、JSON 和 VCD 位于 `release/evidence/logic_analyzer_board_final`。

> 2026-09-16 最终 RTL 完善：修复 `soc_fpga_dmem` 运行时写后读闭环；ALU 的 SLT/SRA 改为显式位逻辑；流水线加入 16 项直接映射 BTB 与 2-bit 饱和计数器，新增 prediction/BTB-hit/misprediction 计数和非法指令、未对齐、总线错误事件。预测器单元、别名替换、端到端恢复及错误可观测性测试均 PASS。相同 CoreMark 一次迭代镜像下，Predictor On 为 1,852,156 cycles，Off 为 2,106,042 cycles，减少 253,886 cycles（12.06%）；On 统计 213,756 次预测、203,492 次 BTB hit、51,908 次 misprediction。该结果为 RTL 仿真，不冒充实体成绩。

> 2026-09-17 唯一最终配置：不再把阶段性的 Pipeline、CoreMark 和 DebugCore 配置混入最终下载入口。`mes50hp_logic_analyzer_top` 已用最终 RTL、固件和 J8 隔行相邻脚对重新完成 PDS，50 MHz 下 All Constraints Met，慢角 setup/hold 裕量为 +2.661/+0.312 ns，估算 Fmax 57.6735 MHz，综合资源 3459 LUT、3129 FF、5.5 个 DRM18K 等效块；最终 `.sbit` SHA-256 为 `2C09E6904A6C6238CF7158E907087F905C1B7DF46E6D2C9B665E1DE10964746E`。

> Task 33 2026-09-16 最终收口：`run_final_regression.ps1 -Quick` PASS，覆盖 RV32I、Reference、Pipeline Hazard/Reset/Trace、GCC 等价、BTB、错误可观测性、性能计数器、官方 CoreMark、最终 SoC、逻辑分析仪与范围审计。`create_release_manifest.ps1` 和 `export_final_submission.ps1` 只导出唯一最终 bitstream、对应时序报告与固件镜像；开发阶段配置不再属于交付入口。

> Task 29 2026-09-15：用本机 PDS 许可证和官方 `DebugCore 1.4`/`Jtag_Hub 1.5` IP 生成独立诊断配置。`scripts/run_coremark_ila_pds.ps1` 自动生成 IP、同步 CoreMark 镜像、编译含 `PDS_COREMARK_ILA` 的顶层并完成 Compile→Synthesize→Place→Route→Timing→Bitstream；192-bit、512-sample probe 包含退休 PC/instruction、寄存器写回、Store、stall/load-stall、branch/taken/flush、请求握手和 reset。结果为 4416 LUT、4458 FF、39 DRM、setup WNS +5.453 ns、hold +0.186 ns，bitstream SHA-256=`B2F4C8A30A6207942786257AEFF9B35DF1DF1EA413F872DAC67E6BD0D5D24506`。Task 28 正式计分镜像不含 DebugCore；当前仅缺实体板下载后 Fabric Debugger 波形证据。

> Task 30 记录（2026-09-17）：`capture_engine.v`、`logic_analyzer_mmio.v`、`application_mmio_mux.v`、板级顶层/约束、可综合固件、RV32I 配置软件和 Python/VCD 工具均已通过自动化回归；J8 隔行相邻脚对的最终 PDS 已重建并满足 50 MHz 全部时序约束。自动化压力与实体板四模式各 20 轮均 PASS，G11 的 8 通道物理闭环证据已签署。

> Task 33～35 准备（2026-09-16）：最终回归、发布清单和复现说明已统一为一套最终配置。官方 CoreMark 源码、BTB Before/After、PDS 产物与最终压缩包均已具备；实体串口、物理回环和断电压力仍不以仿真或综合估算冒充。

> Task 18 完成记录（2026-09-14）：已在 `docs/architecture.md` 冻结 IF/ID、ID/EX、EX/MEM、MEM/WB 的字段、Bubble、MEM 等待和 EX redirect/错误路径响应丢弃的时序约定；在 `docs/interfaces.md` 冻结 `pipeline_cpu` 模块名、复用的通用取指/数据事务端口、提交 trace 和通用性能事件端口。`./scripts/run_pipeline_smoke_tb.ps1` 对 Task 11 程序 PASS，证明候选 Core 的五级基本数据流可运行。当前 `rtl/pipeline_cpu.v` 含有尚未独立验收的 Forwarding、Load-Use Stall 与 Flush 逻辑，不能作为 Task 20～22 或 G7/G8 完成证据；Task 19 必须新增人工 NOP 的独立无 Hazard 程序，并与 frozen single-cycle Reference 自动比较 x1～x31、关键 RAM 及完整提交 trace。

> Task 19 完成记录（2026-09-14）：`tb/data/no_hazard.mem` 在每个 RAW producer/consumer 间插入三条 NOP。`run_pipeline_no_hazard_tb.ps1` 分别在固定延迟及候选 Pipeline 的随机取指/数据背压条件下，逐字段比较前 17 条退休 trace，并比较 `x1`～`x31`、`RAM[0]`；两种模式均 17/17 PASS。Task 19 / 无 Hazard 五级数据通路通过；下一步进入 Task 20。该测试没有用来证明任何 Forwarding、Load-Use 或 Flush 行为。

> Task 20 阶段记录（2026-09-14）：已新增独立 `rtl/forward_unit.v`，并在候选流水线 EX 操作数路径中使用。`run_forward_unit_tb.ps1` 的 9 项选择、优先级、Load 排除、x0 和错误响应测试 PASS；真实相邻/间隔 ALU RAW、双源、同 rd 优先级和 ALU→Store 的 Reference trace 回归已由 Task 20～23 汇总入口覆盖。

> Task 20～23 完成记录（2026-09-14）：Forwarding 端到端镜像覆盖一级/二级、双源、同 rd 优先级、x0 与 ALU→Store；Load-Use 覆盖 Load→ALU/Store/Branch，并在固定时序下精确产生 3 次额外 Bubble（另一个依赖由数据事务整体等待覆盖，无需重复 Stall）；Control Hazard 覆盖 taken/not-taken Branch、JAL/JALR、link 依赖和错误路径 Store；交叉压力覆盖 ALU/Load→Branch/Store、错误 Load/Store 响应、固定/随机背压、请求字段稳定、Store 单次副作用和 Reset 中止。修复了 IF 因原 adapter 空泡未真实激活 Hazard，以及 Redirect 撤回受背压取指 valid 两个问题。`run_pipeline_regression.ps1` 汇总 9 个入口；全部 PASS 后 Task 23 / G8 通过，允许进入 Task 24。

> Task 24 完成记录（2026-09-14）：`run_gcc_pipeline_equivalence.ps1` 自动构建并运行 Task 14 的 `c_smoke` 与 `array_control` 两个真实 RV32I GCC 程序；固定/随机取指和数据延迟共四组均通过，77/71 条提交 trace 逐字段与 Task 17 golden 一致，最终状态一致。Pipeline 运行分别记录 259/454 与 214/399 cycles。GCC Pipeline / G9 软件前置通过。

> Task 25 完成记录（2026-09-14）：新增 Core 外 `perf_monitor` 七项 64-bit 计数器与 `perf_mmio` 只读窗口/CONTROL 清零接口。`run_perf_monitor_tb.ps1` 覆盖 cycle、instret、stall、load-stall、branch、taken、flush、Reset、clear、disable；`run_perf_mmio_tb.ps1` 覆盖低/高字、错误 offset 和清零写，均 PASS。Task 24 GCC Pipeline 已接入计数器并输出 perf evidence；计数器不修改 Core/流水线端口。

> Task 26/27 阶段记录（2026-09-14）：`fpga/pipeline_soc` MES50HP Pipeline SoC wrapper 仿真通过，复用统一互连、UART/GPIO、性能计数器和同一 Pipeline Core；`run_mes50hp_pipeline_soc_tb.ps1` 通过连续 UART 双行、LED=0xAA 和 50 MHz wrapper 仿真。命令行 PDS 因 `Flow-0183` 许可证变量缺失而阻塞，实体板 Pipeline 下载尚未取得证据，故 G9 尚未完成。

> Task 15 完成记录（2026-09-12）：单周期 Core 已移除内部 IMEM/DMEM，新增并验证 `i_req_*` / `i_rsp_*` 与 `d_req_*` / `d_rsp_*` 单 outstanding 事务端口；`IF_REQ`/`IF_RSP`/`IF_DONE` 与 `MEM_RUN`/`MEM_REQ`/`MEM_RSP` 在随机取指/数据背压下 PASS。`soc_data_interconnect` 的 RAM/UART/GPIO/Application/未映射地址译码定向测试 PASS；Core→取指 adapter→Core→互连→外部 RAM 集成测试 PASS。历史 Task 12 全量、Task 13 提交 trace、Task 14 GCC 两项均已通过外部 adapter harness 迁移回归。Task 15 Gate 通过；真实 UART/GPIO wrapper 属于下一任务 Task 16。

> Task 16 阶段记录（2026-09-13）：`gpio_mmio` 独立测试 63/63 PASS。UART 已完成 `UART_TX`（15/15 PASS）、8N1 `UART_RX`（正常帧、假起始位、错误停止位、连续帧共 11/11 PASS）及 `uart_mmio`。UART 地址窗口内现定义 `TXDATA=0x00`、`STATUS=0x04`、`RXDATA=0x08`：`RXDATA` 为单字节阻塞读取邮箱，`STATUS[0]` 为 TX ready、`[1]` 为 TX busy、`[2]` 为 RX valid、`[3]` 为 sticky RX overflow、`[4]` 为 sticky frame error，后两位可由 `STATUS` 写 1 清除。TX MMIO 36/36 PASS，RX 邮箱/MMIO 23/23 PASS。真实 UART/GPIO 从设备接入冻结的 `soc_data_interconnect` 后，通用 CPU 事务的 GPIO 写、UART TX、TX busy 读取、UART RX 状态/读取均 20/20 PASS。`tb/tb_soc_harness.v` 进一步使未修改的 `single_cycle_cpu` 实际执行 `software/mmio_demo/build/mmio_demo.mem`；取指 ROM 与数据 RAM 均按链接脚本预加载同一 1 KiB 镜像，CPU 在 2676 个时钟内写出 GPIO=`0xAA`，并由独立 `UART_RX` 线路观察器无帧错误解码 `Hello RISC-V!\r\n`。运行 `./scripts/run_soc_harness_tb.ps1` 为 19/19 PASS。已新增 `fpga/soc_demo`：MES50HP board wrapper、P20/R8/R9/8 个 LED 的真实 `.fdc`、同一程序镜像的取指/数据 RAM 和 PDS 实现配方；`./scripts/run_mes50hp_soc_demo_tb.ps1` PASS，验证上电复位、LED=`0xAA` 和 UART 线路输出。为避免板上串口晚打开而错过单次输出，demo 现在在发送完整 `Hello RISC-V!\r\n` 后持续循环；镜像和综合常量已同步更新。PDS 重新完成 Compile→Synthesize→Place→Route→Timing→Bitstream，新 bitstream 为 `generate_bitstream/mes50hp_soc_demo_top.sbit`，无 `$readmemh` 警告，50 MHz 目标下预计 59.0179 MHz、WNS=3.056 ns、TNS=0。实体板已通过 CP2102 串口完成 UART 验收：115200、8N1、无流控下持续输出 `Hello RISC-V!`。当前可工作的 PDS 管脚映射为 `uart0_tx=R9`、`uart0_rx=R8`；此前无串口输出的根因是未连接独立 USB-UART 数据线。GPIO 的实体 LED 已确认呈现高有效 `0xAA` 模式（LED2、LED4、LED6、LED8 亮）。Task 16 的仿真与实体板验收均已完成，G5 通过。

> Task 17 完成记录（2026-09-13）：`run_single_cycle_reference_regression.ps1` 已接入独立 RAM+GPIO、RAM+UART 与 Task 14 GCC evidence suite。完整入口连续两次均为 14 passed、0 failed；所有系统程序的最终状态、性能和提交 trace golden 均匹配。比较器已验证可对 `rd_data` 与 Store `mem_data` 篡改报告字段级首差、PC 和 instruction。Task 17 / G6 已通过，允许进入 Task 18。当前版本具备创建 `single_cycle_stable` 标签的条件，但该标签尚未创建。

> 平台迁移：正式 FPGA 已由在线 DUT 切换为盘古 50（MES50HP）`PGL50H-6IFBG484`。此前记录的 PG2L200H、S2/S3、27 MHz、`D18`、`AC26`、`AB26` 和在线下载结果只保留为历史实验记录，不能作为当前 Gate 证据。当前目标、已确认管脚和待验证项以 `docs/fpga_platform.md` 为准。

## 已完成

- [x] 项目基线与核心文档建立
- [x] 赛题需求分析
- [x] CPU 基础概念
- [x] 按 2026 紫光同创 RISC-V 赛题重新校准任务顺序和 Gate
- [x] 确立 CPU Core / SoC 外设解耦原则并建立 `docs/interfaces.md` 接口契约
- [x] 选定“可重构多协议逻辑分析仪”应用并建立功能、MMIO、验证和量化指标规格
- [x] 固定报名作品名称“RISC-V多协议逻辑分析仪”（14/15字符）和436字符作品简介（2026-09-17 改为 B 版叙事稿：偏应用闭环叙事、不含具体量化数字）
- [x] 根据官方赛题页建立 `docs/competition_scoring.md`，明确基础、性能、应用、文档和高阶任务映射
- [x] 冻结最终范围：基础项、16 项 BTB 和官方性能指标全保留，应用固定 8 通道 Raw P0 闭环，RLE 移至赛后研究
- [x] 在项目根目录初始化本地 Git 仓库，默认分支为 `main`，并建立首版 `.gitignore`
- [x] 从本届路线删除Cache/burst、完整异常中断、AI、DDR/HDMI/PCIe/千兆网、自定义指令及逻辑分析仪扩展项
- [x] 冻结本届正式 FPGA 平台为盘古 50（MES50HP）`PGL50H-6IFBG484`；50 MHz、CP2102 UART、按键/LED 及扩展 I/O 的已确认信息已归档
- [x] RV32I 指令格式
- [x] GCC 工具链与 Task 3 软件到机器码学习验收
- [x] Register File：学习者完成 `rtl/regfile.v` 的 32 × 32-bit、双组合读、单同步写与 `x0` 双层保护；`tb/tb_regfile.v` 的 10 项独立测试全部 PASS（2026-09-03）。
- [x] ALU：学习者完成 `rtl/alu.v` 的 10 种基础整数运算；31 项独立定向测试全部 PASS，并完成补码回绕、signed/unsigned 比较、逻辑/算术右移及移位量低 5 位解释验收（2026-09-03）。
- [x] Immediate Generator：学习者完成 `rtl/imm_gen.v` 的 I、S、B、U、J 五类立即数生成；Agent 编写独立 Testbench 和运行入口，25 项定向测试全部 PASS，并完成位重排、符号扩展、B/J 对齐和默认安全值解释验收（2026-09-04）。
- [x] Decoder / Control Unit：学习者完成 `rtl/decoder.v`，能够依据 `opcode`、`funct3`、`funct7` 译码 R-Type、I-Type ALU、Load、Store、Branch、JAL/JALR、LUI/AUIPC，并对非法/未实现编码保持无寄存器、内存或控制流副作用；Agent 编写独立 Testbench 和运行入口，64 项定向测试全部 PASS（2026-09-07）。
- [x] Branch Unit：学习者完成 `rtl/branch_unit.v`，支持 BEQ、BNE、BLT、BGE、BLTU、BGEU，并通过符号位与无符号比较正确实现 signed 比较；Agent 编写独立 Testbench 和运行入口，32 项定向测试全部 PASS（2026-09-07）。
- [x] Load / Store 数据处理：实现 `rtl/load_store_unit.v`，支持 `LB/LBU/LH/LHU/LW` 的 lane 选择与扩展，以及 `SB/SH/SW` 的 lane 对齐写数据与 `wstrb`；非对齐访问检测为 `misaligned=1`，并禁止 Store 写入。独立 Testbench 35/35 PASS（2026-09-07）。
- [x] Task 10 Memory + FPGA Gate：学习者完成 `rtl/dmem.v` 与 `rtl/imem.v`；DMEM 14/14、IMEM 12/12 独立测试 PASS，并确认 GNU objcopy 生成的真实 Verilog 程序镜像可由 `$readmemh` 直接加载（2026-09-08）。MES50HP `PGL50H-6IFBG484` PDS 工程以 `P20` 50 MHz 时钟、`B2` 高有效 LED1 完成实现，`GTP_DRM36K_E1` 1K×32 BRAM 映射确认；同一 bitstream 已通过 JTAG 下载两次，LED1 两次均点亮。Task 10 / G2 正式 PASS（2026-09-10）。
- [x] Task 11 最小单周期 CPU：学习者完成 `rtl/single_cycle_cpu.v`，将 PC、IMEM、Decoder、ImmGen、RegFile、ALU、Branch Unit、Load/Store Unit、DMEM、WriteBack 与 PC 选择器集成为单周期数据通路。独立 Testbench 以包含 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ`、`JAL` 的程序执行验证；检查 `x1=5`、`x2=10`、`x3=15`、`x4=15`、`x5=10`、`x6=0`、`x7=40`、`dmem[0]=15`、`dmem[1]=10` 与最终 `PC=48`，10/10 PASS，并具有 500 ns 超时保护（2026-09-11）。学习者已完成状态更新、访存地址/数据分离、BEQ 比较/跳转目标分离及 JAL 双路径的逐周期解释验收；Task 11 / G3 正式 PASS。

## 当前工具与平台状态

- 仿真器：Icarus Verilog 12.0 Windows 稳定包安装于 `D:\Tools\iverilog-v12`，当前仿真脚本默认使用且 Task 4～10 当前基础模块回归 PASS。OSS CAD Suite 内置的 14.0 development 版 `vvp.exe` 在 2026-09-07 出现启动级应用程序崩溃，已停用并记录于 `docs/debug_log.md`。
- RISC-V GCC：xPack GNU RISC-V Embedded GCC 15.2.0，安装于 `D:\Pango\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1`；前缀为 `riscv-none-elf-`，`RISCV_PREFIX` 与 PATH 已配置。
- RISC-V 工具链验证：使用 `-march=rv32i -mabi=ilp32` 成功完成 C 编译、链接、反汇编以及 BIN/IHEX 生成；输出为 ELF32 little-endian RISC-V，`rv32i/ilp32/libgcc.a` 存在。
- GNU Make：xPack Windows Build Tools 4.4.1，安装于 `D:\Tools\xpack-windows-build-tools-4.4.1-3`，已通过实际 Makefile 构建验证。
- PDS：2024.2-SP2-EN，安装于 `D:\Pango\PDS_2024.2-SP2`；`pds_shell -version` 验证通过，PATH 已配置。MES50HP PDS/BRAM/JTAG/LED1 冒烟已完成，Task 10 / G2 PASS；SPI Flash 固化另行处理。
- Python/串口：Python 3.13.15 位于 `D:\Python313`；pySerial 3.5 位于 `D:\Python313\Lib\site-packages`，导入和串口枚举验证通过。
- Python D 盘约束：`PYTHONUSERBASE=D:\PythonUser`、`PIP_CACHE_DIR=D:\PythonCache\pip`，后续用户包与缓存固定到 D 盘。
- 目标 FPGA/平台：已冻结为盘古 50（MES50HP），器件为 `PGL50H-6IFBG484`；系统时钟 `FPGA_GCLK_50M=P20` 为 50 MHz（20.000 ns），约束格式 `.fdc`。
- UART：板载 CP2102，实体板已验证 RX=`R8`、TX=`R9`；115200、8N1、无流控下持续输出 `Hello RISC-V!`。此前无输出的根因是未连接独立 USB-UART 数据线，而不是 FPGA 管脚或波特率。
- Reset/I/O：默认 `USE_EXTERNAL_RESET=0` 使用内部上电复位；底板 `REST` 经 J4 Pin14 连接专用固件重加载电路，不作为普通用户 I/O。8 个用户按键低有效、8 个用户 LED 高有效，全部管脚与 3.3 V 电平已归档于 `docs/fpga_platform.md`。
- 固定编译目标：`-march=rv32i -mabi=ilp32`。
- 详细工具版本、路径、校验值和验证结果见 `docs/toolchain.md`。

## 当前稳定 RTL

- `rtl/regfile.v`：Register File 独立测试 10/10 PASS。
- `rtl/alu.v`：ALU 独立定向测试 31/31 PASS，Task 5 Gate 已通过。
- `rtl/imm_gen.v`：Immediate Generator 独立定向测试 25/25 PASS，Task 6 Gate 已通过。
- `rtl/decoder.v`：Decoder 独立定向测试 64/64 PASS，Task 7 Gate 已通过。
- `rtl/branch_unit.v`：Branch Unit 独立定向测试 32/32 PASS，Task 8 Gate 已通过。
- `rtl/load_store_unit.v`：Load / Store 数据处理独立定向测试 35/35 PASS，Task 9 Gate 已通过。
- `rtl/dmem.v`：行为级 DMEM 组合读、同步 byte-enable 写和越界保护独立测试 14/14 PASS；Task 10 Memory 阶段已纳入正式 Gate。
- `rtl/imem.v`：行为级 IMEM 组合读、对齐/越界保护、零初始化和 `$readmemh` 程序初始化独立测试 12/12 PASS；Task 3 的真实 `hello.mem` 已成功读回。
- `rtl/single_cycle_cpu.v`：Task 11 最小单周期 CPU，集成 Testbench 10/10 PASS；覆盖 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ` 与 `JAL` 的最小数据通路与控制流，Task 11 / G3 已通过。Task 12 的 FENCE/非法 SYSTEM 边界整机测试 32/32 PASS。
- Task 13 候选 Reference 观察：`rtl/single_cycle_cpu.v` 保持上述 ISA 行为，并输出只读提交级 trace；`tb/tb_single_cycle_reference_trace.v` 验证 10 条退休记录以及候选实例间的 `x1`～`x31`/关键 DMEM 一致性。该版本不是最终 `single_cycle_stable`。
- `fpga/bram_smoke/rtl/bram_smoke_top.v`：1024×32 同步 BRAM 自检核心，PDS 映射为 `GTP_DRM36K_E1`，实体 LED1 自检 PASS。
- `fpga/mes50hp_bram_smoke/rtl/mes50hp_bram_smoke_top.v`：MES50HP board wrapper，固定 `P20` 50 MHz 与 `B2` 高有效 LED1。

## 当前 Regression

- Task 20～23 / G8：`./scripts/run_pipeline_regression.ps1` 汇总 Forward Unit、Hazard Unit、无冒险、Forwarding、Load-Use、Control Hazard、复杂 Hazard、Reset 中止和旧 smoke 共 9 个入口。提交级比较覆盖固定/随机背压；压力程序 20/20 trace PASS，合法 Store trace 与 RAM side effect 均恰好 2 次，错误路径/错误响应无副作用。Reset 测试证明未接受 Store 被中止、重启后只产生一次写入。

- Task 30 本地 Regression：`run_capture_engine_tb.ps1`、`run_logic_analyzer_tb.ps1`、`run_application_mmio_mux_tb.ps1`、`run_logic_analyzer_soc_tb.ps1`、`run_logic_analyzer_board_top_tb.ps1`、`run_logic_analyzer_python.ps1` 全部 PASS；Task 30 板级顶层仿真使用综合可见 Task 30 固件常量，UART 前缀、GPIO=0x5A、Raw count=10 和 trigger_index=4 均通过。
- Task 28/29 性能证据：官方 CoreMark fixed/random 与同步 FPGA memory model 均验证官方 CRC；仿真估算 CoreMark/MHz=0.520000、CPI=2.6682、正式 CoreMark 配置 estimated Fmax=68.2594 MHz、2438 LUT。Task 29 DebugCore 配置为 4416 LUT、4458 FF、39 DRM、setup/hold WNS=+5.453/+0.186 ns。所有数值分别标注“RTL 仿真估算”或“PDS 综合/布局布线结果”，实体成绩与 Fabric Debugger 波形尚未宣称。
- Task 33～35 本地准备：所有历史含 `exit` 的子脚本均在独立 PowerShell 子进程中运行；2026-09-16 `run_final_regression.ps1 -Quick` 与 `run_scope_audit.ps1` PASS，四份 bitstream 均纳入产物存在性与 SHA-256 检查。新增 `release/board_validation` 自包含板级包（4 个 PDS 工程、共享 RTL/约束/DebugCore IP、4 份 `.sbit`、PyUI 和串口工具），并生成 `MES50HP_board_validation_package.zip`；`audit_board_validation_package.ps1` 检查通过。完整 `competition_final` 仍被实体板 CoreMark、Fabric Debugger、物理回环和断电压力证据阻塞。
- Task 34 候选材料：已生成 13 页技术报告 DOCX/PDF、12 页答辩 PPTX、三分钟视频脚本、答辩问答稿和现场恢复卡。DOCX/PDF 已逐页渲染检查；PPTX 已通过 12 页版式、SimHei 字体、3 个原生表格、1 个原生图表、包完整性和重新导入检查，并逐页检查渲染图。所有自动性能数字均注明 RTL 仿真估算或 PDS 结果，实体证据位置明确保留为待补，未宣称 Task 34/35 最终完成。

- Task 19 无 Hazard 基线：`run_pipeline_no_hazard_tb.ps1` 固定/随机延迟下 17/17 trace、x1～x31 和 RAM 状态 PASS；后续 Task 20～23 单独覆盖 Hazard、错误响应和 Reset，不混淆基线证据。

- Task 2 学习验收 PASS：可借助 RV32I 格式模板拆解 R、I、S、B、U、J 六类指令；正确解释 `lw`、`sw`、`bne`、`lui`、`jal`、`jalr` 的主要语义，以及 B/J immediate 的位重排、符号扩展和最低位对齐规则。
- Task 3 学习与构建验收 PASS：完成最小裸机 C 程序、`_start`、链接脚本和 Makefile；使用 `make clean; make all` 生成 ELF、反汇编、BIN、IHEX、Verilog IMEM 初始化文件，并通过 RV32I-only ISA 检查。已能解释 C → ELF → objdump/objcopy → IMEM → `_start` → `main` 的执行链路，以及 `jal`、`jalr`、`bne`、`sw` 的实际作用。
- Task 5 PASS：运行 `.\scripts\run_alu_tb.ps1`，ADD、SUB、AND、OR、XOR、SLL、SRL、SRA、SLT、SLTU、默认控制及关键边界共 31/31 PASS；学习者能够解释补码回绕、signed/unsigned 比较、逻辑/算术右移以及 `b[4:0]` 移位量规则。
- Task 6 PASS：运行 `.\scripts\run_imm_gen_tb.ps1`，I/S/B/U/J 类型的零值、正负数、边界值、B/J 最小对齐偏移、多个共享格式 opcode 和默认安全值共 25/25 PASS；学习者能够解释立即数位重排、符号扩展、B/J 最低位补零以及组合逻辑必须覆盖默认输出的原因。
- Task 7 PASS：运行 `.\scripts\run_decoder_tb.ps1`，R-Type、I-Type ALU、Load、Store、Branch、JAL/JALR、LUI/AUIPC 及非法/未实现编码共 64/64 PASS；学习者能够解释主译码与完整合法性检查、`RegWrite`/Memory/Branch/Jump 副作用抑制、ALU A/B 来源和 ALU/Memory/`PC+4`/Immediate 写回选择。随后运行 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64 Regression，全部 PASS。
- Task 8 PASS：运行 `.\scripts\run_branch_unit_tb.ps1`，BEQ、BNE、BLT、BGE、BLTU、BGEU、相等/不等、正负数、signed/unsigned 极值差异及非法 `funct3` 共 32/32 PASS；学习者能够解释异号时由符号位决定 signed 大小、同号补码可直接比较，以及 `0xFFFFFFFF` 在 signed/unsigned 下的不同结果。随后运行 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32 Regression，全部 PASS。
- Task 9 PASS：运行 `.\scripts\run_load_store_unit_tb.ps1`，覆盖五种 Load 的全部 byte lane、符号/零扩展、两种 halfword、三种 Store 宽度与 byte enable、所有当前定义的非对齐访问、非法 `funct3` 和空闲安全默认值，共 35/35 PASS。随后运行 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32 与 Load/Store 35/35 Regression，全部 PASS。
- Task 10 行为级 Memory 阶段 PASS：学习者完成 `rtl/dmem.v` 与 `rtl/imem.v`，能够解释字节地址到 word index/byte lane 的转换、`SB/SH/SW` 与 `wstrb`、组合读/同步写、指令对齐和 `$readmemh` 初始化。运行 `.\scripts\run_dmem_tb.ps1` 为 14/14 PASS；运行 `.\scripts\run_imem_tb.ps1`，连续取指、空 Memory 清零、非对齐/越界保护、手工初始化文件和 GNU objcopy 真实 `hello.mem` 共 12/12 PASS。随后使用 Icarus 12 稳定包重跑 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32、Load/Store 35/35、DMEM 14/14、IMEM 12/12，全部 PASS。新增最小 PDS BRAM 冒烟工程 `fpga/bram_smoke`：同步读 RAM 的上电复位、写入、隔拍读回和低有效 LED PASS 指示经 `.\scripts\run_bram_smoke_tb.ps1` PASS。该行为级记录保留为历史细节；MES50HP 硬件 Gate 结果见下一条。
- Task 10 MES50HP 硬件 Gate PASS：PDS 目标为 `PGL50H-6IFBG484`，使用 `P20` 50 MHz 与 `B2` LED1；`GTP_DRM36K_E1` 1K×32 BRAM 映射已确认。相同 bitstream 已通过 JTAG 下载两次，LED1 两次均点亮，证明内部上电复位、BRAM 自检和板级约束具有重复性。首次尝试的 SPI Flash 扫描报 `JtagServer-0335` / `Configuration-0008`，但这只影响持久化 Flash 固化，不阻塞临时 JTAG FPGA 冒烟；Task 10 / G2 正式 PASS（2026-09-10）。
- Task 11 / G3 PASS：运行 `./scripts/run_single_cycle_cpu_tb.ps1`，程序镜像 `tb/data/single_cycle_smoke.mem` 从 Reset PC=0 连续取指，覆盖 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ`、`JAL`，检查 7 个寄存器状态、两处 DMEM 状态和最终 PC 共 10 项，全部 PASS；Testbench 具备 500 ns 超时保护。随后重跑 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32、Load/Store 35/35、DMEM 14/14、IMEM 12/12 Regression，全部 PASS（2026-09-11）。学习者已完成关键状态与数据流的逐周期解释验收。
- Task 12 / G4 PASS：采用 RISC-V Unprivileged ISA `v20240411` 的 RV32I Base Integer ISA `Version 2.1`。已审查并修复 JALR target bit 0 清零，完成 U-Type、所有 R/I-Type ALU、五种 Load、三种 Store、六类 Branch、JAL/JALR 与自然对齐策略的定向整机验证；系统类边界冻结为合法 `FENCE` 的保守 no-op，以及 `FENCE.I`、ECALL、EBREAK、CSR 和未支持编码的 `illegal=1` 无副作用策略。`docs/rv32i_instruction_coverage.md` 已覆盖全部目标指令、边界、上游测试和不适用项。固定提交的上游 `riscv-tests` 中，RV32UI Core 29/29 PASS、Memory 10/10 PASS；统一入口 `./scripts/run_rv32i_regression.ps1` 包含 22 个测试入口、逐项失败退出，用户本地 PowerShell 已输出最终 `ALL TASK12 REGRESSION PASS`（2026-09-12）。允许进入 Task 13；本阶段仅建立候选 Reference Model，不得称为或冻结为 `single_cycle_stable`。
- Task 13 / G4 PASS：建立 `single_cycle_reference_candidate`，在 `rtl/single_cycle_cpu.v` 增加只读提交级 trace：`valid`、`pc`、`instruction`、寄存器写回和 Store 的原始字节地址、lane 对齐写数据及 byte enable。`tb/tb_single_cycle_reference_trace.v` 检查固定程序的 10 条退休记录（含 Load、Store、Branch、JAL）、`x1`～`x31` 和关键 DMEM，并确认故意改变 `rd_data` 会报告第一条不一致字段。`./scripts/run_single_cycle_reference_trace_tb.ps1` PASS；`./scripts/run_single_cycle_regression.ps1` 连续两次运行 trace 测试和 Task 12 全量 Regression。该版本不是 `single_cycle_stable`；GCC、统一事务接口、MMIO/UART/GPIO 和 Task 17 正式冻结仍未开始。
- [x] Task 14 / GCC 裸机程序 PASS：新增可重复的 `./scripts/run_c_program_regression.ps1`，固定使用 `-march=rv32i -mabi=ilp32 -O1`，自动检查反汇编不含未声明 ISA 扩展。`c_smoke` 验证启动栈、函数调用/返回、循环与 `.bss`，在复位前注入垃圾值后确认启动代码清零 `.bss`，最终 `result=45`。`c_array_control` 验证 `.data` 预加载、`.bss` 清零、局部数组、函数调用、两段循环及 `if/else` 真/假分支，最终 `seed=3`、`result=18`、`false_result=-1`。两项程序及全部自动断言 PASS（2026-09-12）；详细加载约定见 `docs/gcc_programs.md`。允许进入 Task 15；候选 Reference 仍不是 `single_cycle_stable`。
- [x] Task 15 / Core-Soc 数据接口、取指接口、地址译码与外部 adapter PASS：`i_req_*`/`i_rsp_*`、`d_req_*`/`d_rsp_*` 端口及单 outstanding 等待状态已接入；RAM/UART/GPIO/Application/未映射区域地址范围已冻结并完成互连定向测试；随机取指/数据背压、请求字段稳定、一次写一次副作用及 Core→互连→外部 RAM 集成全部 PASS。Task 12 29+10 项 RV32UI、Task 13 trace、Task 14 GCC 两项均通过迁移后的外部 adapter harness。Task 15 Gate 通过；下一目标为 Task 16 真实 GPIO/UART wrapper。

## 当前已知问题

- **实体板验证已完成（2026-09-17）**：JTAG 下载线接上后，优化后 50 MHz 与 80 MHz PLL 两套 CoreMark 位流
  均已在实体板复测通过（Score 29.559 / 47.295，33.829 s / 52.859 s，CRC 全过），两套逻辑分析仪位流
  各 80/80 J8 回环 PASS。详见上文「实体板验证」小节与 `docs/performance_tuning.md` §5.4。
- **发布包仍是调优前位流**：`release/final_submission` 顶层指向 `2C09E690…`，其清单自洽；
  调优后位流归档在 `release/artifacts/fmax_tuning_2026-09-17/` 并已通过实体验证。
  若要提升为正式发布版本，必须按顺序执行
  `scripts\export_final_submission.ps1` → `scripts\create_release_manifest.ps1` → `scripts\audit_release_package.ps1`（均需 pwsh 7）。
- **性能计数器窗口口径**：板级七项计数器必须用 `PERF_WINDOW_ALIGN=1` 镜像采集，否则 `COREMARK_READY`
  的 UART 轮询等待会污染计数（stall 甚至超过 cycles）。历史 `release/evidence/coremark_board.json`
  即为此种失真数据，仅 `ticks`/`score` 字段仍然有效，**不得**用它做 CPI 归因。
- **PDS 布局布线不具确定性**：同一 RTL 重复构建的 WNS 可差约 ±0.3 ns；所有 Before/After 结论都在同一批扫描内比较，
  并记录 RTL/FDC SHA-256，禁止跨批次混用数值。
- **85 MHz 零余量点**：调优前 85 MHz 的 WNS 仅 +0.005 ns，属"能过但不可用"；调优后为 +0.246 ns。
  选用 85 MHz 实跑需先完成实体板验证（且需 PLL 或外部时钟源，因为 P20 固定 50 MHz）。
- D3 硬件平台决策和 Task 10 Memory/FPGA Gate 已完成；MES50HP BRAM、`.fdc`、内部上电复位、JTAG 下载与 LED1 冒烟均已两次 PASS。SPI Flash 扫描/固化仍未完成，但它不是本次临时 JTAG 冒烟或 Task 10 Gate 的阻塞项。
- 历史在线 DUT 的 `Top.fdc`、器件和报告仅作为旧平台实验归档，已不再写入 `docs/fpga_platform.md`，也不得用于当前 PDS 工程、约束或 Gate 结论。当前工程必须复核 `PGL50H-6IFBG484`，不得沿用旧平台器件或管脚。
- PDS 批处理许可证路径可通过 `-LicenseFile` 或 `PANGO_LICENSE_FILE` 提供；当前四套工程均已完成批处理实现并生成 bitstream。许可证文件属于本机外部依赖，不进入仓库或发布包。
- MES50HP 手册已经确认实际使用接口的管脚和 3.3 V 电平；后续 `.fdc` 直接采用 `docs/fpga_platform.md` 的冻结映射。下载阶段只需通过板载 JTAG 实测 PDS 流程，不再把“缺少管脚/电压资料”列为阻塞项。
- OSS CAD Suite 内置 Icarus 14.0 development 的 `vvp.exe` 当前不可用；仿真脚本已切换到 `D:\Tools\iverilog-v12`，该问题不再阻塞当前 RTL 回归，但在升级工具前不得重新启用开发快照。
- 逻辑分析仪 8 路输入和 8 路回环激励输出已冻结为 J8 隔行相邻脚对 `3/4、7/8、11/12、15/16、19/20、23/24、27/28、31/32`，全部为 3.3 V；内部回环不能单独替代 Task 30 的物理闭环验收。
- CoreMark：官方 EEMBC checkout 已固定到 `1f483d5b8316753a742cbf5590caf5bd0a4e4777`，fixed/random 与 FPGA memory model 仿真均通过官方 CRC；实体板分数尚未采集，报告只能将当前值标为仿真估算。
- Git 仓库已建立，首次基线提交与 GitHub 私有远程状态见本次 Git 配置结果。

## 国赛冲刺基线

- 冲刺基准日：`D0 = 2026-08-29`；内部目标日：`D60 = 2026-10-28`。若官方截止更早，以官方截止为准。
- 本届唯一交付主线：Task 0～30、Task 32、33～35；Task 31 RLE 固定跳过。
- 硬节点：D3 硬件平台决策、D12 单周期候选 Reference、D20 `single_cycle_stable`、D35 Pipeline/GCC/性能计数器、D42 `pipeline_coremark_stable`、D52 逻辑分析仪 P0、D60 `competition_final`。
- 国赛证据链固定为：正确性（指令/Regression/提交级对比）、性能（CoreMark/MHz、Fmax、CoreMark/LUT、CPI）、应用（8 通道 Raw UART/SPI 闭环）、工程质量（Core/SoC 解耦、可复现构建、报告/视频/答辩）。
- 提前完成产生的时间只用于 Regression、Timing/CoreMark 复现、P0 稳定性和参赛材料，不恢复已冻结功能。

## 下一目标

**已完成（2026-09-17）**：调优后两套 CoreMark 位流与两套逻辑分析仪位流均已在实体板验证通过
（Score 29.559 @50 MHz / 47.295 @80 MHz PLL；两套 LA 各 80/80 J8 回环）。剩余动作是**把调优后位流提升为正式发布包**：
按 `scripts\export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` 顺序执行（均需 pwsh 7）。

**次要（可选，独立一轮）**：数据事务握手流水化（`rtl/pipeline_cpu.v` 的 `dstate` REQ→RSP），
按实体板 CPI 归因（访存相关约占 4.5% stall + 主体事务等待）估计可降 CPI 约 0.4（约 −17%），
是 Score 第 (1) 项最显著的剩余空间；
必须独立一轮做 Before/After 并重跑 Task 23/24 全套 + 提交级 trace 对比 + 实体板 CoreMark。

主线目标：Task 33～35。自动化总回归、唯一最终配置发布包（位流/时序/约束/固件/上位机/实体证据一致）和候选材料已完成；实体 CoreMark 分数已补齐。下一步补齐 Task 29 Fabric Debugger 波形与三轮断电压力证据，随后更新报告/PPT/视频真实素材并再次运行完整回归、发布清单和包审计。

学习方式：先评审 `valid/ready` 请求/响应语义、地址/字节写使能和一次请求一次副作用，再由学习者实现最小范围的 Core 访存端口 RTL；Agent 负责 adapter/互连/外设侧 Testbench、随机背压和地址译码验证。任何新接口必须保持 Core 不含设备地址或专用端口。

并行的非 RTL 状态：D3 平台选择和管脚/电平归档已经完成，目标固定为 MES50HP；PDS、内部上电复位、BRAM 与实体 JTAG/LED 冒烟已作为 Task 10 证据归档。后续不得因板级冒烟通过而跳过 Task 11 的数据通路学习与单周期 CPU 验收。

## 更新规则

每完成一个任务，必须同步更新本文件：

1. 将通过验收的任务标记为 `[x]`，未通过的任务保持 `[ ]`。
2. 将“当前阶段”推进到下一个任务；不得跳过 `docs/roadmap.md` 的前置任务和 Gate。
3. 在“当前稳定 RTL”中列出已经通过相关 Regression 的稳定文件。
4. 在“当前 Regression”中记录测试名称和 `PASS` / `FAIL`；失败时不得标记任务完成。
5. 在“当前已知问题”中记录尚未解决的问题；重要 Bug 同时写入 `docs/debug_log.md`。
6. 将“下一目标”写成当前任务的具体验收目标。
7. 更新顶部日期，并确保记录与当前代码和实际测试结果一致。
