# Project Progress

> 最后更新：2026-09-17
> 状态依据：`AGENTS.md`、`docs/competition_scoring.md`、`docs/roadmap.md`、`docs/architecture.md`、`docs/interfaces.md`、`docs/fpga_platform.md`、`docs/application_logic_analyzer.md` 与当前项目文件。聊天记录不作为任务完成证明。

## 当前阶段

Task 20～32 的自动化 RTL/软件/PDS 证据已经通过，当前执行 Task 33～35 交付冻结。开发阶段的多套验证配置已经收口，发布入口只保留 `mes50hp_logic_analyzer_top` 一套最终配置：RV32I 五级流水线、16 项 BTB、UART/GPIO、十项性能计数器和八通道逻辑分析仪。官方 CoreMark CRC 与 Predictor Off/On 已通过 RTL 仿真；MES50HP JTAG 下载和 J8 四模式物理回环已完成实体验收，CoreMark 实体计分、Fabric Debugger 波形和断电压力仍按各自证据边界单独记录。

> 2026-09-17 接班交付包一致性修复：上一轮导出（08:37）早于当日 J8 隔行脚对约束校正、Capture Engine 分频边沿修复与上位机位中心采样修复（13:45～13:48），因此 `release/final_submission` 与 `release/artifacts` 内仍是旧位流 `01C39461…`，与实体板 80/80 回环所用 `2C09E690…` 不一致；`.fdc`、`README.md`、`reports/timing.rtr`、`rtl/capture_engine.v`、`rtl/logic_analyzer_pattern_gen.v` 与三份上位机工具同样是修复前版本，且包内缺少 `evidence/logic_analyzer_board_final`。已用 PowerShell 7.6.5 重新执行 `export_final_submission.ps1`（`FINAL SUBMISSION EXPORT PASS files=215`）、`create_release_manifest.ps1`（`RELEASE MANIFEST PASS files=1221`）与 `audit_release_package.ps1`（`RELEASE PACKAGE AUDIT PASS final_files=132 artifacts=3`）；最终位流三处副本 SHA-256 均为 `2C09E6904A6C6238CF7158E907087F905C1B7DF46E6D2C9B665E1DE10964746E`。13 页技术报告 PDF 已归档到 `release/materials/technical_report.pdf`（与 `technical_report.docx` 同源渲染件，封面与末页已复核）。本轮未修改任何 RTL。

> 2026-09-17 接班回归复核：`run_final_regression.ps1 -Quick` 输出 `ALL AUTOMATED FINAL REGRESSION PASS`，20 个入口全部 PASS（Task 12/17/23/24/25/26/28/29/30/33 与最终 bitstream 哈希校验 `sha256=2C09E690…`）；Task 23 汇总入口现为 13 个，Task 30 board-top 与 SoC 集成、Python/VCD、冻结范围审计均 PASS。

> 2026-09-17 接班证据复核补充：官方 CoreMark 三项按正式入口重跑并 PASS——固定延迟 `cycles=1852156 retired=779952`、`predictor enabled=1 predict=213756 btb_hit=203492 mispredict=51908`，随机背压 `cycles=3339018`，FPGA memory model `cycles=1831176 bytes=655`；固定延迟结果与 `release/evidence/automated_metrics.json` 的 Predictor On 记录逐字段一致，证明该结论可在当前工作区复现。同时修复 `python/release_evidence.py` 的资源提取缺陷：原实现从 device map 段取 FF（3120）却从综合段取 LUT/DRM，现统一取综合统计 `Total Registers`（3129），并把布局布线后实现 FF 另存为 `ff_implemented=3120`，使自动证据与 `docs/progress.md`、`release/HANDOFF.md` 及技术报告的 3129 FF 一致。

> 2026-09-15 最新交付记录：修复流水线在数据事务等待期间 WB 值不再可转发导致的错误，新增 `task23_wb_hold` 定向用例并将 Task 23 汇总扩为 10 个入口；Task 24 固定/随机背压的完整退休 trace、x1～x31 和关键 RAM 比较继续 PASS。官方 CoreMark checkout 固定到 `1f483d5b8316753a742cbf5590caf5bd0a4e4777`，固定/随机事务仿真均输出官方 CRC。同步 FPGA memory model 为 1,923,077 ticks/iteration、CPI 2.6682、CoreMark/MHz 0.520000；正式镜像为 1000 iterations、50 MHz、串口 `R` 启动，预期计时区间 38.46154 s，实体成绩尚不宣称。

> PDS 2026-09-15：Pipeline SoC 为 2267 LUT、1343 FF、1 DRM、setup WNS +6.062 ns、slow-corner hold +0.314 ns、estimated Fmax 71.7463 MHz；CoreMark 为 2438 LUT、1333 FF、33 DRM、setup +5.350 ns、hold +0.313 ns、estimated Fmax 68.2594 MHz；修正精确 pre/post 后的逻辑分析仪为 2998 LUT、1880 FF、7 DRM、setup +5.264 ns、hold +0.315 ns、estimated Fmax 67.8610 MHz。三者在 50 MHz 下均 All Constraints Met，指标由 `run_release_evidence.ps1` 自动提取。

> Task 30 2026-09-15：增加可编程 8 路物理回环发生器，支持静态、计数器、UART 8N1 和 SPI mode 0；正式固件采用 13 字节带 XOR 校验配置包，上电输出 `LA_READY`，无需重新综合即可更改模式、数据、速率、触发和前后采样。独立发生器 TB、MMIO byte-enable、20 轮采集/Reset 压力、交互式 board-top UART、AUTOSTART SoC、Python UART/SPI/VCD 六类入口全部 PASS。Capture Engine 进一步修正为精确 `pre + trigger + post` 计数和逻辑 trigger index，正式 Task 30 bitstream SHA-256 为 `C8123DA9699AE29D528F2FE61BFD8A3064DB678DB9AA1F0050EA490545BF779A`。

> 2026-09-17 实体约束校正：用户提供的实际 J8 约束使用隔行相邻脚对 `3/4、7/8、11/12、15/16、19/20、23/24、27/28、31/32`，原先连续 `3..18` 的文档与实体接线不一致。工程 `.fdc`、平台表、上位机提示和发布材料已按实际 LOC 同步；此前实体 static 出现 `期望 A5、实际 AF` 和 `期望 00、实际 AA`，根因是旧约束使 CH1/3/5/7 输入悬空，不作为逻辑功能失败证据。

> 2026-09-17 实体闭环完成：修复 UART pattern restart 的空闲帧同步、Python 位中心采样，以及 Capture Engine 在分频采样下每系统时钟更新 `previous_sample` 导致边沿丢失的问题；新增 `divided edge retained` 定向测试。最终位流经 PDS 2024.2-SP2 重建并 JTAG 下载，DONE=1。J8 实体回环 static、counter、UART 8N1 `0xA5`、SPI mode 0 `0x3C` 各连续 20 次，共 80/80 PASS；原始串口、JSON 和 VCD 位于 `release/evidence/logic_analyzer_board_final`。

> 2026-09-16 最终 RTL 完善：修复 `soc_fpga_dmem` 运行时写后读闭环；ALU 的 SLT/SRA 改为显式位逻辑；流水线加入 16 项直接映射 BTB 与 2-bit 饱和计数器，新增 prediction/BTB-hit/misprediction 计数和非法指令、未对齐、总线错误事件。预测器单元、别名替换、端到端恢复及错误可观测性测试均 PASS。相同 CoreMark 一次迭代镜像下，Predictor On 为 1,852,156 cycles，Off 为 2,106,042 cycles，减少 253,886 cycles（12.06%）；On 统计 213,756 次预测、203,492 次 BTB hit、51,908 次 misprediction。该结果为 RTL 仿真，不冒充实体成绩。

> 2026-09-17 唯一最终配置：不再把阶段性的 Pipeline、CoreMark 和 DebugCore 配置混入最终下载入口。`mes50hp_logic_analyzer_top` 已用最终 RTL、固件和 J8 隔行相邻脚对重新完成 PDS，50 MHz 下 All Constraints Met，慢角 setup/hold 裕量为 +2.661/+0.312 ns，估算 Fmax 57.6735 MHz，综合资源 3459 LUT、3129 FF、5.5 个 DRM18K 等效块；最终 `.sbit` SHA-256 为 `2C09E6904A6C6238CF7158E907087F905C1B7DF46E6D2C9B665E1DE10964746E`。

> Task 33 2026-09-16 最终收口：`run_final_regression.ps1 -Quick` PASS，覆盖 RV32I、Reference、Pipeline Hazard/Reset/Trace、GCC 等价、BTB、错误可观测性、性能计数器、官方 CoreMark、最终 SoC、逻辑分析仪与范围审计。`create_release_manifest.ps1` 和 `export_final_submission.ps1` 只导出唯一最终 bitstream、对应时序报告与固件镜像；开发阶段配置不再属于交付入口。

> Task 29 2026-09-15：用本机 PDS 许可证和官方 `DebugCore 1.4`/`Jtag_Hub 1.5` IP 生成独立诊断配置。`scripts/run_task29_pds.ps1` 自动生成 IP、同步 CoreMark 镜像、编译含 `PDS_COREMARK_ILA` 的顶层并完成 Compile→Synthesize→Place→Route→Timing→Bitstream；192-bit、512-sample probe 包含退休 PC/instruction、寄存器写回、Store、stall/load-stall、branch/taken/flush、请求握手和 reset。结果为 4416 LUT、4458 FF、39 DRM、setup WNS +5.453 ns、hold +0.186 ns，bitstream SHA-256=`B2F4C8A30A6207942786257AEFF9B35DF1DF1EA413F872DAC67E6BD0D5D24506`。Task 28 正式计分镜像不含 DebugCore；当前仅缺实体板下载后 Fabric Debugger 波形证据。

> Task 30 记录（2026-09-17）：`capture_engine.v`、`logic_analyzer_mmio.v`、`application_mmio_mux.v`、板级顶层/约束、可综合固件、RV32I 配置软件和 Python/VCD 工具均已通过自动化回归；J8 隔行相邻脚对的最终 PDS 已重建并满足 50 MHz 全部时序约束。自动化压力与实体板四模式各 20 轮均 PASS，G11 的 8 通道物理闭环证据已签署。

> Task 33～35 准备（2026-09-16）：最终回归、发布清单和复现说明已统一为一套最终配置。官方 CoreMark 源码、BTB Before/After、PDS 产物与最终压缩包均已具备；实体串口、物理回环和断电压力仍不以仿真或综合估算冒充。

> Task 18 完成记录（2026-09-14）：已在 `docs/architecture.md` 冻结 IF/ID、ID/EX、EX/MEM、MEM/WB 的字段、Bubble、MEM 等待和 EX redirect/错误路径响应丢弃的时序约定；在 `docs/interfaces.md` 冻结 `pipeline_cpu` 模块名、复用的通用取指/数据事务端口、提交 trace 和通用性能事件端口。`./scripts/run_pipeline_smoke_tb.ps1` 对 Task 11 程序 PASS，证明候选 Core 的五级基本数据流可运行。当前 `rtl/pipeline_cpu.v` 含有尚未独立验收的 Forwarding、Load-Use Stall 与 Flush 逻辑，不能作为 Task 20～22 或 G7/G8 完成证据；Task 19 必须新增人工 NOP 的独立无 Hazard 程序，并与 frozen single-cycle Reference 自动比较 x1～x31、关键 RAM 及完整提交 trace。

> Task 19 完成记录（2026-09-14）：`tb/data/task19_no_hazard.mem` 在每个 RAW producer/consumer 间插入三条 NOP。`run_pipeline_no_hazard_tb.ps1` 分别在固定延迟及候选 Pipeline 的随机取指/数据背压条件下，逐字段比较前 17 条退休 trace，并比较 `x1`～`x31`、`RAM[0]`；两种模式均 17/17 PASS。Task 19 / 无 Hazard 五级数据通路通过；下一步进入 Task 20。该测试没有用来证明任何 Forwarding、Load-Use 或 Flush 行为。

> Task 20 阶段记录（2026-09-14）：已新增独立 `rtl/forward_unit.v`，并在候选流水线 EX 操作数路径中使用。`run_forward_unit_tb.ps1` 的 9 项选择、优先级、Load 排除、x0 和错误响应测试 PASS；真实相邻/间隔 ALU RAW、双源、同 rd 优先级和 ALU→Store 的 Reference trace 回归已由 Task 20～23 汇总入口覆盖。

> Task 20～23 完成记录（2026-09-14）：Forwarding 端到端镜像覆盖一级/二级、双源、同 rd 优先级、x0 与 ALU→Store；Load-Use 覆盖 Load→ALU/Store/Branch，并在固定时序下精确产生 3 次额外 Bubble（另一个依赖由数据事务整体等待覆盖，无需重复 Stall）；Control Hazard 覆盖 taken/not-taken Branch、JAL/JALR、link 依赖和错误路径 Store；交叉压力覆盖 ALU/Load→Branch/Store、错误 Load/Store 响应、固定/随机背压、请求字段稳定、Store 单次副作用和 Reset 中止。修复了 IF 因原 adapter 空泡未真实激活 Hazard，以及 Redirect 撤回受背压取指 valid 两个问题。`run_task23_regression.ps1` 汇总 9 个入口；全部 PASS 后 Task 23 / G8 通过，允许进入 Task 24。

> Task 24 完成记录（2026-09-14）：`run_task24_gcc_pipeline.ps1` 自动构建并运行 Task 14 的 `c_smoke` 与 `array_control` 两个真实 RV32I GCC 程序；固定/随机取指和数据延迟共四组均通过，77/71 条提交 trace 逐字段与 Task 17 golden 一致，最终状态一致。Pipeline 运行分别记录 259/454 与 214/399 cycles。GCC Pipeline / G9 软件前置通过。

> Task 25 完成记录（2026-09-14）：新增 Core 外 `perf_monitor` 七项 64-bit 计数器与 `perf_mmio` 只读窗口/CONTROL 清零接口。`run_perf_monitor_tb.ps1` 覆盖 cycle、instret、stall、load-stall、branch、taken、flush、Reset、clear、disable；`run_perf_mmio_tb.ps1` 覆盖低/高字、错误 offset 和清零写，均 PASS。Task 24 GCC Pipeline 已接入计数器并输出 perf evidence；计数器不修改 Core/流水线端口。

> Task 26/27 阶段记录（2026-09-14）：`fpga/task26_pipeline_soc` MES50HP Pipeline SoC wrapper 仿真通过，复用统一互连、UART/GPIO、性能计数器和同一 Pipeline Core；`run_mes50hp_pipeline_soc_tb.ps1` 通过连续 UART 双行、LED=0xAA 和 50 MHz wrapper 仿真。命令行 PDS 因 `Flow-0183` 许可证变量缺失而阻塞，实体板 Pipeline 下载尚未取得证据，故 G9 尚未完成。

> Task 15 完成记录（2026-09-12）：单周期 Core 已移除内部 IMEM/DMEM，新增并验证 `i_req_*` / `i_rsp_*` 与 `d_req_*` / `d_rsp_*` 单 outstanding 事务端口；`IF_REQ`/`IF_RSP`/`IF_DONE` 与 `MEM_RUN`/`MEM_REQ`/`MEM_RSP` 在随机取指/数据背压下 PASS。`soc_data_interconnect` 的 RAM/UART/GPIO/Application/未映射地址译码定向测试 PASS；Core→取指 adapter→Core→互连→外部 RAM 集成测试 PASS。历史 Task 12 全量、Task 13 提交 trace、Task 14 GCC 两项均已通过外部 adapter harness 迁移回归。Task 15 Gate 通过；真实 UART/GPIO wrapper 属于下一任务 Task 16。

> Task 16 阶段记录（2026-09-13）：`gpio_mmio` 独立测试 63/63 PASS。UART 已完成 `UART_TX`（15/15 PASS）、8N1 `UART_RX`（正常帧、假起始位、错误停止位、连续帧共 11/11 PASS）及 `uart_mmio`。UART 地址窗口内现定义 `TXDATA=0x00`、`STATUS=0x04`、`RXDATA=0x08`：`RXDATA` 为单字节阻塞读取邮箱，`STATUS[0]` 为 TX ready、`[1]` 为 TX busy、`[2]` 为 RX valid、`[3]` 为 sticky RX overflow、`[4]` 为 sticky frame error，后两位可由 `STATUS` 写 1 清除。TX MMIO 36/36 PASS，RX 邮箱/MMIO 23/23 PASS。真实 UART/GPIO 从设备接入冻结的 `soc_data_interconnect` 后，通用 CPU 事务的 GPIO 写、UART TX、TX busy 读取、UART RX 状态/读取均 20/20 PASS。`tb/tb_task16_soc_harness.v` 进一步使未修改的 `single_cycle_cpu` 实际执行 `software/task16_mmio_demo/build/task16_mmio_demo.mem`；取指 ROM 与数据 RAM 均按链接脚本预加载同一 1 KiB 镜像，CPU 在 2676 个时钟内写出 GPIO=`0xAA`，并由独立 `UART_RX` 线路观察器无帧错误解码 `Hello RISC-V!\r\n`。运行 `./scripts/run_task16_soc_harness_tb.ps1` 为 19/19 PASS。已新增 `fpga/task16_soc`：MES50HP board wrapper、P20/R8/R9/8 个 LED 的真实 `.fdc`、同一程序镜像的取指/数据 RAM 和 PDS 实现配方；`./scripts/run_mes50hp_task16_soc_tb.ps1` PASS，验证上电复位、LED=`0xAA` 和 UART 线路输出。为避免板上串口晚打开而错过单次输出，demo 现在在发送完整 `Hello RISC-V!\r\n` 后持续循环；镜像和综合常量已同步更新。PDS 重新完成 Compile→Synthesize→Place→Route→Timing→Bitstream，新 bitstream 为 `generate_bitstream/mes50hp_task16_soc_top.sbit`，无 `$readmemh` 警告，50 MHz 目标下预计 59.0179 MHz、WNS=3.056 ns、TNS=0。实体板已通过 CP2102 串口完成 UART 验收：115200、8N1、无流控下持续输出 `Hello RISC-V!`。当前可工作的 PDS 管脚映射为 `uart0_tx=R9`、`uart0_rx=R8`；此前无串口输出的根因是未连接独立 USB-UART 数据线。GPIO 的实体 LED 已确认呈现高有效 `0xAA` 模式（LED2、LED4、LED6、LED8 亮）。Task 16 的仿真与实体板验收均已完成，G5 通过。

> Task 17 完成记录（2026-09-13）：`run_task17_regression.ps1` 已接入独立 RAM+GPIO、RAM+UART 与 Task 14 GCC evidence suite。完整入口连续两次均为 14 passed、0 failed；所有系统程序的最终状态、性能和提交 trace golden 均匹配。比较器已验证可对 `rd_data` 与 Store `mem_data` 篡改报告字段级首差、PC 和 instruction。Task 17 / G6 已通过，允许进入 Task 18。当前版本具备创建 `single_cycle_stable` 标签的条件，但该标签尚未创建。

> 平台迁移：正式 FPGA 已由在线 DUT 切换为盘古 50（MES50HP）`PGL50H-6IFBG484`。此前记录的 PG2L200H、S2/S3、27 MHz、`D18`、`AC26`、`AB26` 和在线下载结果只保留为历史实验记录，不能作为当前 Gate 证据。当前目标、已确认管脚和待验证项以 `docs/fpga_platform.md` 为准。

## 已完成

- [x] 项目基线与核心文档建立
- [x] 赛题需求分析
- [x] CPU 基础概念
- [x] 按 2026 紫光同创 RISC-V 赛题重新校准任务顺序和 Gate
- [x] 确立 CPU Core / SoC 外设解耦原则并建立 `docs/interfaces.md` 接口契约
- [x] 选定“可重构多协议逻辑分析仪”应用并建立功能、MMIO、验证和量化指标规格
- [x] 固定报名作品名称“RISC-V多协议逻辑分析仪”和410字符作品简介
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

- Task 20～23 / G8：`./scripts/run_task23_regression.ps1` 汇总 Forward Unit、Hazard Unit、无冒险、Forwarding、Load-Use、Control Hazard、复杂 Hazard、Reset 中止和旧 smoke 共 9 个入口。提交级比较覆盖固定/随机背压；压力程序 20/20 trace PASS，合法 Store trace 与 RAM side effect 均恰好 2 次，错误路径/错误响应无副作用。Reset 测试证明未接受 Store 被中止、重启后只产生一次写入。

- Task 30 本地 Regression：`run_capture_engine_tb.ps1`、`run_logic_analyzer_tb.ps1`、`run_application_mmio_mux_tb.ps1`、`run_task30_logic_analyzer_soc_tb.ps1`、`run_task30_board_top_tb.ps1`、`run_logic_analyzer_python.ps1` 全部 PASS；Task 30 板级顶层仿真使用综合可见 Task 30 固件常量，UART 前缀、GPIO=0x5A、Raw count=10 和 trigger_index=4 均通过。
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
- Task 11 / G3 PASS：运行 `./scripts/run_single_cycle_cpu_tb.ps1`，程序镜像 `tb/data/task11_single_cycle.mem` 从 Reset PC=0 连续取指，覆盖 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ`、`JAL`，检查 7 个寄存器状态、两处 DMEM 状态和最终 PC 共 10 项，全部 PASS；Testbench 具备 500 ns 超时保护。随后重跑 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32、Load/Store 35/35、DMEM 14/14、IMEM 12/12 Regression，全部 PASS（2026-09-11）。学习者已完成关键状态与数据流的逐周期解释验收。
- Task 12 / G4 PASS：采用 RISC-V Unprivileged ISA `v20240411` 的 RV32I Base Integer ISA `Version 2.1`。已审查并修复 JALR target bit 0 清零，完成 U-Type、所有 R/I-Type ALU、五种 Load、三种 Store、六类 Branch、JAL/JALR 与自然对齐策略的定向整机验证；系统类边界冻结为合法 `FENCE` 的保守 no-op，以及 `FENCE.I`、ECALL、EBREAK、CSR 和未支持编码的 `illegal=1` 无副作用策略。`docs/task12_instruction_coverage.md` 已覆盖全部目标指令、边界、上游测试和不适用项。固定提交的上游 `riscv-tests` 中，RV32UI Core 29/29 PASS、Memory 10/10 PASS；统一入口 `./scripts/run_task12_regression.ps1` 包含 22 个测试入口、逐项失败退出，用户本地 PowerShell 已输出最终 `ALL TASK12 REGRESSION PASS`（2026-09-12）。允许进入 Task 13；本阶段仅建立候选 Reference Model，不得称为或冻结为 `single_cycle_stable`。
- Task 13 / G4 PASS：建立 `single_cycle_reference_candidate`，在 `rtl/single_cycle_cpu.v` 增加只读提交级 trace：`valid`、`pc`、`instruction`、寄存器写回和 Store 的原始字节地址、lane 对齐写数据及 byte enable。`tb/tb_single_cycle_reference_trace.v` 检查固定程序的 10 条退休记录（含 Load、Store、Branch、JAL）、`x1`～`x31` 和关键 DMEM，并确认故意改变 `rd_data` 会报告第一条不一致字段。`./scripts/run_single_cycle_reference_trace_tb.ps1` PASS；`./scripts/run_task13_regression.ps1` 连续两次运行 trace 测试和 Task 12 全量 Regression。该版本不是 `single_cycle_stable`；GCC、统一事务接口、MMIO/UART/GPIO 和 Task 17 正式冻结仍未开始。
- [x] Task 14 / GCC 裸机程序 PASS：新增可重复的 `./scripts/run_task14_regression.ps1`，固定使用 `-march=rv32i -mabi=ilp32 -O1`，自动检查反汇编不含未声明 ISA 扩展。`task14_c_smoke` 验证启动栈、函数调用/返回、循环与 `.bss`，在复位前注入垃圾值后确认启动代码清零 `.bss`，最终 `result=45`。`task14_array_control` 验证 `.data` 预加载、`.bss` 清零、局部数组、函数调用、两段循环及 `if/else` 真/假分支，最终 `seed=3`、`result=18`、`false_result=-1`。两项程序及全部自动断言 PASS（2026-09-12）；详细加载约定见 `docs/task14_gcc_programs.md`。允许进入 Task 15；候选 Reference 仍不是 `single_cycle_stable`。
- [x] Task 15 / Core-Soc 数据接口、取指接口、地址译码与外部 adapter PASS：`i_req_*`/`i_rsp_*`、`d_req_*`/`d_rsp_*` 端口及单 outstanding 等待状态已接入；RAM/UART/GPIO/Application/未映射区域地址范围已冻结并完成互连定向测试；随机取指/数据背压、请求字段稳定、一次写一次副作用及 Core→互连→外部 RAM 集成全部 PASS。Task 12 29+10 项 RV32UI、Task 13 trace、Task 14 GCC 两项均通过迁移后的外部 adapter harness。Task 15 Gate 通过；下一目标为 Task 16 真实 GPIO/UART wrapper。

## 当前已知问题

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

Task 10 已正式关闭：MES50HP 迁移冒烟工程使用 `P20` 50 MHz 时钟、`B2` 高有效 `LED1`，复用已验证的 1024×32 同步 BRAM 自检；本地 Testbench 输出 `ALL MES50HP BRAM SMOKE TEST PASS`，同一 bitstream 已通过 JTAG 下载两次且 LED1 两次点亮。SPI Flash 固化暂缓，当前不要把它当作 CPU 学习阻塞项。

主线目标：Task 33～35。自动化总回归、唯一最终配置发布包（位流/时序/约束/固件/上位机/实体证据一致）和候选材料已完成；下一步仅在 MES50HP 连接后补齐实体 CoreMark 分数、Task 29 Fabric Debugger 波形与三轮断电压力证据（J8 隔行相邻脚对四模式 80/80 实体回环已完成），随后更新报告/PPT/视频真实素材并再次运行完整回归、发布清单和包审计。当前不得冻结 `competition_final`。

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
