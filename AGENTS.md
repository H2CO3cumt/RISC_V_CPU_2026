# Repository Guidelines

本文件是 **RISC-V CPU 2026 Competition Project** 的项目总规则。凡在本项目根目录或其子目录中开展的分析、设计、编码、测试、调试和文档工作，均必须遵守本文件。若子目录存在更具体的 `AGENTS.md` 或 `AGENTS.override.md`，其规则只能细化本文件，不得削弱正确性、验证和开发顺序要求。

## 1. 项目目标

本项目用于参加 2026 全国大学生嵌入式芯片与系统设计竞赛紫光同创 FPGA 创新设计赛道 RISC-V CPU 方向。

1. 使用 Verilog 自主实现支持 RV32I 的处理器。
2. 首先完成稳定的单周期 RV32I CPU，并将其作为 Reference Model。
3. 在此基础上完成经典五级流水线：IF、ID、EX、MEM、WB。
4. 正确处理 Data Hazard、Forwarding、Load-Use Stall、Control Hazard、Branch/Jump Flush。
5. 五级流水线 CPU Core 与 SoC/外设严格解耦；Core 只通过统一取指、数据访问和提交/性能事件接口对外连接，未实现的中断扩展不得引入设备专用端口。
6. 在 Core 外集成 RAM、UART、GPIO 和 MMIO；更换或增加 SPI、传感器、逻辑分析仪或加速器时不得重新设计流水线主体。
7. 支持以 `-march=rv32i -mabi=ilp32` 编译的 RISC-V GNU bare-metal C 程序，最终运行 CoreMark。Windows 当前固定使用 xPack 的 `riscv-none-elf-` 前缀，并通过用户环境变量 `RISCV_PREFIX` 统一引用，不得在构建脚本中硬编码其他前缀。
8. 本届正式 FPGA 平台冻结为盘古 50（MES50HP）开发板：紫光同创 Logos `PGL50H-6IFBG484`、50 MHz 系统时钟、PDS `.fdc`、板载 CP2102 USB-UART 和用户按键/LED；在正式 CPU 综合前完成 PDS、时钟/复位、BRAM 读写时序和实体板下载的早期可行性验证，完整契约见 `docs/fpga_platform.md`。
9. 在运行 CoreMark 前完成最小性能计数器，并用提交级 trace 自动比较 Single Cycle 与 Pipeline。
10. 评分主线固定为：完整 RV32I、五级流水线与 Hazard、UART/GPIO、CoreMark/MHz、Fmax、CoreMark/LUT、实际应用、代码规范和 ILA 性能分析；评分依据与范围取舍以 `docs/competition_scoring.md` 为准。
11. 在 `pipeline_coremark_stable` 后，以 Core 外部 MMIO 外设方式完成“可重构多协议逻辑分析与故障诊断平台”的 P0 端到端闭环；应用范围和验收以 `docs/application_logic_analyzer.md` 为准。
12. 按最终完善路线，比赛版本纳入 16 项直接映射 BTB + 2-bit 饱和计数器，并保留 Predictor Off/On 的 Before/After 数据；RLE 仍冻结为赛后研究，不进入本届配置。
13. 官方“高级控制逻辑”同时包含动态预测与完整异常/中断；本届不以 BTB 单项宣称完成该高级任务。本届明确不实现 I-Cache、D-Cache、burst、完整异常/中断、AI/YOLO、外部 DDR、HDMI、PCIe、千兆网和自定义 RISC-V 指令。

## 2. 开发与教学原则

本项目首先用于真正学习 CPU 微架构，而非单纯完成比赛工程。

- 不得未经请求重写整个 CPU，也不得为了代码更漂亮而大规模重构。
- 用户询问新知识点时，先判断其理解：明确正确与错误之处，再解释原理。
- 用户理解模块结构前，不直接生成大段完整 RTL。
- 按“原理 -> 数据通路 -> 接口 -> RTL -> Testbench -> Debug”推进。
- 项目 RTL 默认由用户在理解原理、数据通路和接口后亲自编写；Agent 负责提供必要的小型语法/位段模板、审查代码和协助 Debug，除非用户另行明确授权，否则不得代写或替换 RTL。
- 独立 Testbench、自动化测试入口和 Regression 默认由 Agent 设计并编写；测试用例与期望结果必须向用户说明，并以用户编写的 RTL 为被测对象运行和报告 PASS/FAIL。
- 已经 Regression PASS 的模块不得无理由修改；代码修改应保持最小范围。
- 涉及 RTL 时优先阅读和分析已有代码，不随意改变已验证行为。
- 每项工作必须给出明确验收标准，并说明是否具备进入下一 Gate 的条件。
- Core/SoC 边界以 `docs/interfaces.md` 为准；不得为了某个外设把设备专用控制、地址译码或协议状态机塞入 CPU Core。

### 2.1 学习实施方式

为保证学习者建立可迁移的数据通路与控制逻辑模型，而不是只完成样例抄写，RTL 学习默认采用以下闭环：

1. 先解释指令语义、状态更新、数据通路和控制选择；此阶段不展示完整 RTL。
2. 学习者先用自然语言、表格或连线图说明源操作数、ALU 输入/结果、写回来源、内存副作用和下一 PC。
3. 学习者在不参照完整实现样例的前提下自行编写小范围 RTL；Agent 不预先代写模块主体。
4. Agent 审查学习者代码时优先指出错误信号、错误周期和原因；学习者先自行修正。只有在连续尝试后仍受阻时，Agent 才提供最小必要的语法、位段或局部连接提示。
5. Agent 负责独立 Testbench、测试程序、Regression 和 PASS/FAIL 报告；测试结果必须回到数据通路解释，不得只以“能运行”作为理解证明。
6. 每完成一类指令或控制路径，必须进行一次不看代码的逐周期推演，覆盖 PC、RegFile、DMEM 和相关组合路径，再进入下一类功能。

除非学习者明确要求代写完整 RTL，或为修复已定位的阻塞性问题确有必要，否则不得把完整可直接套用的 RTL 实现作为教学起点。

## 3. Verilog 编码规则

项目主要使用 Verilog。允许使用 `integer` 有符号变量；其他有符号操作应优先通过符号位、补码关系、位操作和显式逻辑实现。

除非存在明确且已说明的工程理由：

- 不改变现有模块名。
- 不改变已经确定的端口。
- 不改变 Testbench 的验证接口。
- 不引入不必要的 SystemVerilog 特性。
- 新增或修改涉及状态机、`valid/ready` 握手、暂停、Flush、Forwarding、访存副作用或提交时机的 RTL 时，必须在状态编码、状态转移条件和非直观时序控制处添加简洁中文注释，说明该逻辑的“为什么”和对应周期行为；不得只保留难以理解的裸条件表达式。
- 不在 Core 顶层引入 UART、GPIO、SPI、传感器、逻辑分析仪或加速器专用端口；协议差异必须由 Core 外部 adapter/wrapper 隔离。
- MES50HP 默认由顶层内部上电复位启动，`USE_EXTERNAL_RESET=0`。底板 `REST` 经延时复位芯片连接 PGL50H 专用 `RSTN`，用于重新加载固件，不作为普通用户 I/O；CPU 人工复位若启用，只从手册确认的低有效 `KEY1..KEY8` 中分配并在 board wrapper 内处理。
- MES50HP 的 8 个用户按键按低电平有效，8 个用户 LED 按高电平点亮；极性转换集中在 Core 外部 board wrapper。
- `.fdc` 只能使用 MES50HP 手册已给出的真实管脚与电平；禁止 TODO、示例板管脚和臆测管脚。UART RX=`R8`、TX=`R9`、50 MHz 时钟=`P20`，按键/LED、J8、PMOD 及本届逻辑分析仪固定映射以 `docs/fpga_platform.md` 为准；实际使用的 3.3 V I/O 使用 `LVCMOS33`。

## 4. 强制开发顺序

必须遵循 `docs/roadmap.md` 定义的 Gate：

```text
RISC-V 基础 -> RV32I ISA -> 单周期模块 -> 单周期 CPU
-> GCC C 程序 -> Core/SoC Interface -> MMIO/UART/GPIO -> Regression/Reference Freeze
-> 五级流水线 -> Forwarding -> Stall -> Flush
-> Commit Trace/GCC Pipeline -> Performance Counters -> FPGA
-> CoreMark -> Performance Analysis -> Logic Analyzer Application
-> Final Regression/Materials/Release

最终增强与验证：16-entry BTB 性能实验 -> Final Regression/Materials/Release
赛后研究（不属于本届 Release）：RLE
```

基础阶段未通过时，不得建议直接进行增强项。I/D Cache、异常/中断、AI、RLE 和其他已冻结功能不属于本届执行路线。BTB 只在流水线、CoreMark 与性能计数基线通过后进入最终配置。

## 5. Debug 原则

出现错误时禁止首先猜测。必须沿 `IF -> ID -> EX -> MEM -> WB` 查找“第一个发生错误的周期”和“第一个发生错误的信号”，再从该点定位根因。

重点检查：PC、instruction、rs1、rs2、rd、immediate、ALU input/result、memory address/data、RegWrite、MemRead、MemWrite、Forwarding、Stall、Bubble、Flush。

## 6. Testbench 与 Regression

- 所有核心模块必须具有独立 Testbench，不能只依靠人工查看波形。
- 测试必须输出明确结果，例如 `TEST xxx PASS`、`TEST xxx FAIL`、`ALL TEST PASS`。
- 修改任何核心 RTL 后，必须重新运行相关 Regression，并报告执行命令、结果和未覆盖项。
- 未通过测试时不得宣称任务完成或进入下一开发阶段。

## 7. Reference Model

稳定的单周期 RV32I CPU 是流水线 CPU 的 Reference Model。任务 13 只能建立候选基线；只有 GCC、MMIO/UART/GPIO 和正式 Regression 全部通过后，才允许冻结最终 Reference Model。一旦冻结，不得随意重构。

对同一测试程序，Single Cycle CPU 与 Pipeline CPU 的最终 architectural state 必须一致，包括 `x1` 至 `x31` 和关键 RAM 数据。对比应自动化并产生明确 PASS/FAIL 结果。

除最终状态外，还必须支持按退休顺序比较提交级 trace，至少包含 `valid`、`pc`、`instruction`、寄存器写回和内存写入信息。出现差异时应报告第一条不一致提交，而不是只报告程序结束后的差异。

## 8. Core / SoC 解耦

- CPU Core 只负责 ISA 执行、单周期或流水线数据通路、Hazard 控制、统一取指/数据事务以及提交/性能事件。
- RAM/BRAM、地址译码、MMIO 互连、UART、GPIO、SPI、传感器、逻辑分析仪、加速器、厂商总线和板级引脚均属于 Core 外部。
- Core 不得包含设备专用地址常量、片选、Busy/Done 状态或协议状态机。低速设备只能通过统一事务的背压使 Core 等待。
- UART、GPIO 是基础 SoC 的参考配置，不是五级流水线的固定组成部分。以后替换或新增外设时，Core 源文件和 Core Regression 必须保持不变。
- 本届不实现 Cache；接口只保留未来可插拔能力，所有 MMIO 区域始终属于 uncacheable，任何未来 Cache 也不得改变 Core/SoC 边界。
- 本届不实现异常/中断；若赛后研究，只允许使用通用中断输入，具体中断源和聚合逻辑仍属于 SoC。
- 边界、握手、事务副作用和验证矩阵以 `docs/interfaces.md` 为唯一接口契约。
- 最终应用已选定为可重构多协议逻辑分析仪，但“应用已确定”不等于“Core 可以感知应用”。Capture Engine、触发、BRAM、状态寄存器和上位机链路全部位于 Core 外；赛后若研究 RLE，也只能位于 Core 外。详细范围以 `docs/application_logic_analyzer.md` 为准。

## 9. 性能优化原则

优化优先级为：Correctness、Timing Pass、Stable FPGA Operation、Performance Counters、CoreMark、CPI Analysis、Logic Analyzer P0 Demo、BTB Before/After、Fmax/Area Optimization。本届不启动 RLE。

任何性能优化必须提供 Before/After 数据；不得仅因增加模块而判断优化成功。功能正确性或时序稳定性下降时，应优先恢复正确性。

两个月 P0 范围已冻结：逻辑分析仪固定为 8 通道、基础触发、前后采样、BRAM、Raw、UART/SPI 软件解析和简单 Python/VCD；本届不实现 RLE。不得增加 16 通道、I²C、协议感知/多级复杂触发、外部 DDR 或复杂 GUI。

国赛冲刺以 `docs/roadmap.md` 的 60 天硬节点为准。Task 0～30、33～35 构成本届唯一交付主线；任何提前完成产生的余量优先用于 Regression、Timing、CoreMark 复现、逻辑分析仪稳定性、报告、视频和答辩演练，不得用来恢复已冻结功能。

## 10. 项目文档

每完成一个重要任务，更新 `docs/progress.md`，记录已完成内容、Testbench 状态、当前稳定版本、已知问题和下一任务。

- 重要 Bug 写入 `docs/debug_log.md`。
- 重要架构决策写入 `docs/architecture.md`。
- Core/SoC 边界、事务语义和接口冻结状态写入 `docs/interfaces.md`。
- 逻辑分析仪的功能范围、MMIO 语义、测试矩阵和量化指标写入 `docs/application_logic_analyzer.md`。
- 官方评分依据、任务映射和范围取舍写入 `docs/competition_scoring.md`。
- 开发 Gate 和验收条件以 `docs/roadmap.md` 为准。
- MES50HP 的器件、时钟、Reset、有效电平、UART、J8、PMOD 和约束纪律以 `docs/fpga_platform.md` 为准。
- CoreMark 关键循环的 ILA 波形、CPI 分解和资源/时序数据必须形成可提交的性能分析材料。
- 学习者掌握工程的阅读、重建与多视角追问计划写入 `docs/learning_plan.md`；该文件只记录学习进度与自检结果，不作为项目完成度证据，也不得替代 `docs/progress.md`。
- 不得将历史聊天作为唯一项目记录。

## 11. 协作与变更要求

- 修改前说明分析依据和预期影响，修改后报告验证结果。
- 保留用户已有改动，不擅自回退、不覆盖无关工作。
- 优先采用可审查的小提交；提交说明使用简短祈使句并聚焦单一变更。
- Pull Request 应说明架构影响、验证命令与结果、已知风险；流水线或控制逻辑变化可附关键波形或 trace。
- 若现有代码、文档或测试与本规则冲突，应先指出冲突并与用户确认，不得静默扩大修改范围。
