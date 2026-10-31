# 2026 紫光同创 RISC-V CPU 赛题评分映射与范围决策

> 平台迁移（2026-09-09）：正式 FPGA 证据统一改为 MES50HP `PGL50H-6IFBG484`。本文历史性的“在线 DUT / PG2L200H / 27 MHz”叙述不再有效；所有板级指标和验收以 `docs/fpga_platform.md` 为准，评分范围与 Core/SoC 解耦边界不变。

> 最后更新：2026-08-30
> 用途：把官方赛题要求转换为本项目两个月、单人开发的优先级。本文只做任务映射，不虚构官方未公布的数值权重。

## 1. 依据与边界

本项目采用以下依据：

1. 仓库保存的《全国大学生嵌入式芯片与系统设计竞赛 2026 选题指南（紫光同创）》RISC-V CPU 赛题页：`tmp/pdfs/riscv-topic-10.png`、`tmp/pdfs/riscv-topic-11.png`。
2. 大赛官网[“评审依据”](https://fpga2024.fpgachina.cn/question)：完成度、难度与工作量；适用性与创新性；平台结合和综合性能；报告规范性；现场演示、能力测评与答辩表现（2026-08-29 核对）。

现有赛题页没有给出各项百分比或固定分值，因此不得在报告或计划中写成“某项必得多少分”。本项目只按“是否明确出现在赛题要求、是否形成可测结果、两个月内的投入产出比”排序。

## 2. 官方要求提取

### 基础任务

1. 实现支持 RV32I 基础整数指令集的通用处理器。
2. 流水线不少于 3 级，并完善数据冲突和分支跳转等底层逻辑。
3. 集成 UART、GPIO 等基础外设，用于系统控制和结果输出。

### 高阶任务

1. 2 路组相联的指令/数据 Cache，并优化总线突发传输。
2. 动态分支预测器（如 BTB）以及完整 RISC-V 异常/中断处理。
3. 基于 RISC-V 的边缘 AI 加速系统。

高阶任务在原文中按成组能力描述。本项目不会把“只完成 BTB、没有完整异常/中断”表述成完整完成高级控制逻辑，也不会为了表面覆盖而交付未经充分验证的 Cache 或 AI 模块。

### 性能测评

- 指南列出的参考软件工具链为 `riscv32-unknown-elf-gcc`。本项目使用已验证的 xPack `riscv-none-elf-` 前缀，并固定 `-march=rv32i -mabi=ilp32`；必须保存 ELF 属性和反汇编证据，证明目标 ISA/ABI 一致。
- CoreMark v1.0，正式运行时间不低于 10 秒。
- 执行效率：CoreMark/MHz。
- 时钟频率：满足时序约束的最高工作频率。
- 资源效率：CoreMark/LUT。
- 应用场景：基于实际用途构建完整系统。
- 技术实现与文档：模块化、合理时序约束、代码注释、性能分析报告，以及用 ILA 分析 CoreMark 关键算法时的流水线效率。

### 官方三个指标的**实测值**（2026-10-14 更新：新增 RV32IM 增强配置）

| 指南指标 | 实测值 | 证据 |
|---|---|---|
| (1) 执行效率 **CoreMark/MHz** | **rv32im 2.272**（`cmim85` @85 MHz：**Score 193.192**、4000 迭代、20.704 s、官方 CRC 全过；`cmim` @50 MHz：Score 113.642、2000 迭代、17.599 s）<br>rv32i **0.936**（`cm85` @85 MHz Score 79.587；`cm50` @50 MHz Score 46.816）——**两套 ISA 并列，默认与可比口径仍是 rv32i** | `release/evidence/coremark_board_cmim85_20261014.json`、`coremark_board_im.json`、`coremark_board_cm85_20260930.json`、`release/evidence/board/run01/` |
| (2) 时钟频率（最高工作频率） | **板级实测 85.000 MHz**（PLL 变体，CoreMark Score 79.587 + 逻辑分析仪 80/80）；PDS 估算 Fmax 89.2538 MHz | `release/evidence/board_85m/` |
| (3) 资源效率 **CoreMark/LUT** | **同源同频（85 MHz，同一份 RTL）**：rv32im **0.0460**（193.192 ÷ **4198 LUT**） vs rv32i **0.0190**（79.587 ÷ 4198 LUT）⇒ **2.43×**，且两颗位流的 LUT/FF/WNS 完全一致（面积不随程序变，涨的全是分数）<br>其他口径：rv32im 50 MHz 0.0291（113.642 ÷ 3903）；rv32i 50 MHz 0.0137（46.816 ÷ 3416）——**不同频/不同 ISA 的分母不许混用** | `fpga/coremark_im_85m/flow.log`、`fpga/coremark_85m_r/flow.log`、`fpga/coremark_im/flow.log`、`fpga/coremark/flow.log` |

- **运行时间**：rv32i 50 MHz 21.360 s；**rv32im 50 MHz 17.599 s / 85 MHz 20.704 s**；80/85 MHz 位流 33.375 / 31.412 s —— **均 ≥10 秒** ✓
- **RV32IM 是并列的增强配置**（2026-10-14 用户批准，`AGENTS.md` §1.7）：`-march=rv32im`，
  CoreMark 输出自带 `Compiler flags` 一行可自证；**引用分数必须写明哪一套 ISA**，
  且**不得**把 2.272 说成"rv32i 的成绩"。
- **RV32IM 现在有两个频点**：50 MHz（Score 113.642）与 **85 MHz（Score 193.192，与交付同频）**。
  两个点的 `ticks/迭代` 都是 **439,975 拍**（逐位一致），CoreMark/MHz 都是 **2.272** ——
  这既证明 Score 随频率线性，也证明 85 MHz 的 M 扩展位流与 50 MHz 点跑的是同一份工作负载
  （`docs/progress.md` §1「RV32IM 85 MHz 计分点」）。
- **应用场景**：八通道多协议逻辑分析仪 P0 闭环 + **采集源双源可选**
  （J8 外部 / Core 内部观测点，`docs/application_logic_analyzer.md` §6.10）；
  板级五模式 **100/100 PASS** + Core 探针 6 次采集 PASS。
- **补充分析证据**：`release/evidence/core_probe_board/`（**作品自带的逻辑分析仪**采自研 CPU：
  窗口 IPC ≈0.597、停顿占 39.5%）。
- **应用场景**：八通道多协议逻辑分析仪 P0 闭环（指南原文把"逻辑分析仪"列为适用场景），
  板级 J8 四模式 **80/80 PASS**
- **分析报告**：`release/evidence/ila_coremark/`（512 拍窗口，IPC 0.635 / CPI 1.575，
  84.3% 提交落在 `__mulsi3`）
- ⚠️ 引用纪律：CoreMark 分数来自 **CoreMark 专用位流**，不是交付的逻辑分析仪位流；
  板级 **CPI 有窗口敏感性**（1.494–1.508），只能写 **≈1.50**。
  完整清单见 `release/evidence/claims_map.md` §3.3 与 §12。

## 3. 本项目的得分主线

| 赛题维度 | 本项目交付证据 | 优先级 | 完成条件 |
|---|---|---:|---|
| RV32I 核心 | 单周期 Reference + 五级流水 CPU | P0 | 指令定向测试、GCC 程序和 Regression PASS |
| 流水线与冲突 | Forwarding、Load-Use Stall、Branch/Jump Flush | P0 | 与单周期最终状态和提交级 trace 一致 |
| 基础外设 | Core 外 MMIO、UART TX/RX、GPIO | P0 | 独立测试、SoC 测试和板级演示 PASS |
| 软件生态 | `-march=rv32i -mabi=ilp32` 裸机程序 | P0 | 可重复构建、加载和运行 |
| 性能 | CoreMark/MHz、Fmax、CoreMark/LUT | P0 | FPGA 实测、运行不少于 10 秒、结果可复现 |
| 分析能力 | 性能计数器、CPI 分解、PDS ILA 波形 | P0 | 至少解释一个 CoreMark 关键循环瓶颈 |
| 应用场景 | 8 通道多协议逻辑分析仪 P0 闭环 | P0 | 采集、触发、MMIO、UART/SPI 解析、VCD 和现场演示闭环 |
| 工程质量 | 模块化、Testbench、统一 Regression、报告 | P0 | 自动 PASS/FAIL、版本可追溯、文档与演示一致 |
| RLE | 逻辑分析仪无损压缩及量化 | 本届冻结 | 仅保留为赛后研究，不进入本届实现、配置或材料 |
| BTB | 16 项 BTB + 2-bit 预测性能实验 | 已纳入最终版本 | 提供 Off/On 数据，但不宣称完成完整高级控制逻辑 |

## 4. 两个月范围决策

### 必须保留

- 完整 RV32I，而不是只支持 CoreMark 恰好用到的指令子集。
- 五级流水线、Forwarding、Load-Use Stall、Control Hazard 与 Flush。
- UART、GPIO、Core/SoC 解耦和统一 MMIO。
- FPGA Timing PASS、稳定上板、CoreMark 三项官方性能指标。
- 正式 FPGA 证据统一来自 MES50HP `PGL50H-6IFBG484`、50 MHz 和板载 CP2102 UART；其他平台的历史结果不得替代目标平台 Timing/上板数据。
- 逻辑分析仪 Raw 模式端到端应用闭环。
- 自动 Regression、提交级 trace、ILA 性能分析和参赛材料。

### 已从本届执行范围冻结

- RLE：仅保留赛后研究说明，本届不启动 Task 31。
- BTB：Task 32 纳入最终完善路线，必须保持架构状态、完整 Regression 和 Timing 正确。
- 超出 P0 演示所需的压力测试规模和配置组合。

### 本届不做

> ⚠️ **2026-09-30 更新：本节原先的前两条已经作废**，不要照旧引用。
> 经用户 2026-09-29 批准，**I/D Cache、2 路组相联、burst 与外部 DDR3 已纳入本届**
> （`AGENTS.md` §1.14），并且 **S1～S4 已全部执行完毕**；
> **机器模式 CSR/Trap 与定时器中断也已实现并进入交付配置**（`docs/trap_contract.md` M-01…M-24 全 PASS）。
> 详见 `docs/progress.md` 与 `docs/handoff_next.md` §3.3。

- ~~I/D Cache、2 路组相联和 burst~~ → **已做**：S2 行式突发 PASS（总线周期 48→30，−37.5%）；
  S3 I-Cache 与 S4 D-Cache 功能正确但**净收益为负，按止损默认关闭**（片上 BRAM 延迟已优于 Cache 命中）。
  S1 DDR3 板级打通但**未接入 CPU 存储路径**。
- ~~完整异常/中断~~ → **已做**：机器模式 CSR/Trap/MRET + 三根通用中断输入，
  契约 M-01…M-24 全 PASS、99/99 断言，板级定时器中断演示 + ILA 抓到 Trap 进入/返回。
- **确实仍未做**：AI/YOLO、自定义指令、HDMI、PCIe、千兆网；外部 DDR 仅到板级连通（未接入）。
- **确实仍未做**：16 通道、I²C 解析、协议感知或多级复杂触发、复杂 GUI。
- RLE 仍冻结为赛后研究。

## 5. 本届增强冻结规则

本届目标已经切换为单人 60 天国赛冲刺。RLE 继续冻结；BTB 按最终完善路线纳入。
**2026-09-29 范围变更**：Cache/burst/外部 DDR3 经用户批准纳入本届，作为官方高阶项①
（`AGENTS.md` §1.14、`docs/handoff_next.md` §3.3），因此本句原先"不得扩展到 Cache"已作废；
"完整异常/中断"仍按下文既有边界。其余时间投入：

1. RV32I、Pipeline、Hazard、GCC、UART/GPIO、FPGA、CoreMark 和逻辑分析仪 P0 的完整 Regression。
2. Timing、资源和 CoreMark 三项指标的重复构建与复现。
3. 随机背压、Reset、错误路径 side effect 和连续板级采集稳定性。
4. 技术报告、3 分钟视频、PPT、答辩和现场故障恢复演练。

只有本届 `competition_final` 已冻结并完成提交后，用户重新立项，才允许把 Task 31 RLE 作为赛后研究启动。赛后结果不得反向混入已冻结的本届提交版本。

## 6. 进度止损线

| 时间点 | 必须达到 | 未达到时的动作 |
|---|---|---|
| D3 | 冻结 MES50HP（`PGL50H-6IFBG484`、50 MHz、`.fdc`、内部上电复位默认路径、CP2102 UART） | 当前已达成；若平台接入或器件信息失效，当日恢复目标平台路径，不得拖到 Task 10；完整管脚和 BRAM 实测仍由 Task 10 验收 |
| D12 | 单周期候选 Reference Model | 停止应用讨论，只推进单周期正确性；重新评估 D20 是否可达 |
| D20 | GCC、MMIO、UART/GPIO、单周期正式 Regression | 不增加任何新外设功能；若延期超过 3 天，标记原 60 天全范围为红色风险 |
| D35 | 五级流水线 Hazard、GCC Pipeline、提交级对比和性能计数器 PASS | 未通过前不得进入 FPGA/CoreMark，更不得开始应用 RTL |
| D42 | FPGA、CoreMark Baseline 和性能数据 | 未冻结 `pipeline_coremark_stable` 时不得开始 Task 30；优先保住完整 CPU+SoC 交付 |
| D52 | 逻辑分析仪 P0 端到端闭环 | 立即冻结功能，禁止新增配置，只修复阻塞性 Bug 并进入最终材料 |
| D60 | Release、报告、视频、答辩演练 | 冻结 `competition_final`；冻结后修改必须重跑完整最终 Regression |

这些是项目管理止损线，不是官方赛程或官方分值。

> **D52 的三条例外（用户明确批准，与 Cache 那次同性质的显式范围变更）**：
> ① **镜像抓取**：上位机串口线镜像到 ch7，采集深度 256→2048（`docs/application_logic_analyzer.md` §6.7）；
> ② **仪器化：读数**：每通道/协议读数与测量报告（同文 §6.8）。
>    （其中八键八灯面板于同日经用户决定**整套移除**，LED 回 `gpio_out`；详见 §6.8.2。）
> ③ **仪器面板：交互旋钮**（2026-10-10 批准，同文 §6.9）：把固件一直都在收、
>    却写死在模式默认里的时基、触发方式/通道/电平、`pre`/`post`、激励速率与数据接到 pyUI 上，
>    并加连续采集停止条件。**只动主机端**：`rtl/*.v`、固件与位流一字未改，位流哈希不变。
>    它补的是 G11 既有验收项"现场改变数据、速率、触发边沿或触发值，无需重新综合"——
>    原来这条只能靠命令行参数证明。
> 三条都必须同时满足：Core 端口与事务语义不变、原 P0 验收（现为 5 模式 ×20 = 100/100）复测通过、
> 位流哈希与 `claims_map` 同步、新增测试进入 `run_final_regression.ps1`。
> 其中第 ③ 条的新增测试**已自动进入最终回归**：新用例在
> `python/test_logic_analyzer_serial.py` 与 `python/test_logic_analyzer_ui.py`（新增），
> 都落在 `run_logic_analyzer_python.ps1` 的发现范围 `test_logic_analyzer*.py` 内，
> 而该入口由 `run_final_regression.ps1` 第 70 行调用（本轮实测 24 项 OK）；
> 板级 100/100 复测**已于 2026-10-12 完成**（la85 交付位流，五模式 ×20 =
> `LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`，退出码 0），
> 证据刷新到 `release/evidence/logic_analyzer_board_85m/`，交付包已按
> export → manifest → audit 重新导出并通过审计。
> **除这三条外 D52 依然有效**：不得新增通道数、协议种类、协议感知触发或复杂 GUI。
