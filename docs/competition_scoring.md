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

- I/D Cache、2 路组相联和 burst。
- 完整异常/中断。
- AI/YOLO、自定义指令、外部 DDR、HDMI、PCIe、千兆网。
- 16 通道、I²C 解析、协议感知或多级复杂触发、复杂 GUI。

## 5. 本届增强冻结规则

本届目标已经切换为单人 60 天国赛冲刺。RLE 继续冻结；BTB 按最终完善路线纳入，但不得扩展到 Cache 或完整异常/中断。其余时间投入：

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
