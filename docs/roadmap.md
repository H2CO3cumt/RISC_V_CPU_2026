# RISC-V CPU 2026 项目路线图

> 平台迁移（2026-09-09）：本届正式 FPGA 平台已由在线 DUT 迁移至盘古 50（MES50HP）`PGL50H-6IFBG484`。本文此前出现的 PG2L200H、S2/S3、27 MHz、在线下载和旧 UART 管脚描述均已失效；平台器件、时钟、UART、Reset、约束和上板验收以 `docs/fpga_platform.md` 为唯一准则。Core/SoC Gate、任务顺序和验收要求不变。

本文档把两个月单人国赛冲刺计划固化为本届交付任务 0～30、Task 32、33～35。Task 31 RLE 仅保留为赛后研究；Task 32 BTB 按最终完善路线进入本届验证与配置。本文档不是进度记录，而是开发顺序、任务内容和验收条件的唯一依据。

新聊天恢复项目时，按以下顺序读取：

1. `AGENTS.md`：项目总规则。
2. `docs/roadmap.md`：完整任务路线和 Gate 条件。
3. `docs/progress.md`：当前任务、已通过测试和已知问题。
4. `docs/competition_scoring.md`：官方要求映射、范围取舍和两个月止损线。
5. `docs/architecture.md`、`docs/interfaces.md`、`docs/fpga_platform.md` 与 `docs/application_logic_analyzer.md`：已确定的架构决定、Core/SoC 接口契约、MES50HP 平台契约和比赛应用规格。
6. 当前 RTL、Testbench、软件和脚本：确认实际实现状态。

聊天记录不能作为完成任务的证据。只有代码、自动化测试结果和项目文档可以证明当前状态。

## 一、路线图使用规则

### 任务固定字段

每个任务固定包含：

- **目标**：完成任务后应获得的能力或工程结果。
- **需要学什么**：动手前必须理解的原理。
- **需要实现什么**：需要新增或修改的工程内容。
- **验收标准**：用于验证结果的测试和可观察现象。
- **通过条件**：允许在 `docs/progress.md` 中标记完成并进入下一任务的最低条件。

### 强制开发顺序

```text
任务 0：项目基线
  ↓
任务 1～3：CPU、RV32I 与工具链基础
  ↓
任务 4～10：单周期基础模块与 FPGA 存储可行性验证
  ↓
任务 11：最小单周期 CPU
  ↓
任务 12～13：完整 RV32I 与单周期候选 Reference Model
  ↓
任务 14～16：GCC、Core/SoC 接口、MMIO、UART、GPIO
  ↓
任务 17：单周期正式 Regression 与最终 Reference Model 冻结
  ↓
任务 18～19：五级流水线基础数据通路
  ↓
任务 20～23：Forwarding、Stall、Flush、复杂 Hazard
  ↓
任务 24～27：GCC Pipeline、性能计数器、综合与上板
  ↓
任务 28～29：CoreMark、性能分析与 Baseline 冻结
  ↓
任务 30：可重构多协议逻辑分析仪
  ↓
任务 33～35：最终 Regression、材料与提交冻结

赛后研究备忘：任务 31 RLE
最终完善项：任务 32 BTB 性能实验；Task 30 与 CoreMark 基线通过后进入 Task 32，再进入 Task 33。
```

### 通用通过规则

一项任务只有同时满足以下条件才算通过：

1. 能用自己的话解释相关原理，不能只会复制代码。
2. 数据通路、模块接口或软件流程已经明确。
3. 实现范围符合当前任务，不提前混入后续优化。
4. 核心 RTL 有独立 Testbench；系统任务有自动化程序或明确的板级验证方法。
5. 测试自动输出明确的 `PASS` / `FAIL`，不以“波形看起来正常”作为唯一依据。
6. 相关 Regression 全部 PASS，且未破坏已通过功能。
7. `docs/progress.md` 已记录完成内容、验证命令、结果、已知问题和下一任务。
8. 重要 Bug 已写入 `docs/debug_log.md`；重要架构决策已写入 `docs/architecture.md`。

### Gate 规则

- 当前 P0 任务未通过时，不得开始依赖它的后续 P0 任务；任务 31 不属于本届执行任务。
- 单周期完整 Regression 未通过时，不得开始五级流水线 RTL。
- 任务 13 只建立候选基线；稳定的单周期 CPU 必须在任务 17 正式 Regression 后冻结为最终 Reference Model。
- Pipeline 与 Single Cycle 必须自动比较 `x1`～`x31`、关键 RAM 数据和按退休顺序生成的提交级 trace。
- 目标 FPGA、PDS、时钟/复位和 BRAM 接口未通过早期可行性验证时，不得把仿真 RAM 行为直接当作可综合实现。
- 最小性能计数器未通过定向测试时，不得开始正式 CoreMark 跑分。
- 本届不得开始 RLE；BTB 仅按 Task 32 冻结规格实现。
  注：**Cache 已于 2026-09-29 经用户批准解冻**，作为 P3 阶段的 S3/S4 任务按闸门推进（`AGENTS.md` §1.14）。
- I/D Cache、burst、完整异常/中断、AI、外部 DDR、HDMI、PCIe、千兆网和自定义指令已从本届范围删除，即使有剩余时间也不得临时回加。
- 任何性能优化都必须提供 Before/After 的功能、频率、资源与性能数据。
- 外设、地址表或板级接口变化不得传播进 CPU Core；违反 `docs/interfaces.md` 的方案不得通过对应 Gate。
- 逻辑分析仪是已选应用，但其规格不得覆盖 Core/SoC 接口契约；应用 RTL 只能在 Task 29 Baseline 冻结后按 Task 30 实现。
- Task 30 的 Raw P0 闭环通过后进入 Task 32 与 Task 33；RLE 不进入本届 Release。

### 60 天国赛冲刺时间盒与止损线

冲刺基准日 `D0 = 2026-08-29`，内部目标日 `D60 = 2026-10-28`。这是项目管理时间盒，不代替官方赛程；若官方截止更早，以官方截止为准。

| 硬节点 | 计划任务 | 必须达到 |
|---|---|---|
| D3 | 硬件平台决策 | 已冻结 MES50HP：`PGL50H-6IFBG484`、50 MHz、`.fdc`、CP2102 UART、按键/LED 及 8 通道逻辑分析仪管脚/电平；Task 10 再完成 BRAM 和实体板冒烟，不要求提前跳过 Task 2 编写 CPU RTL |
| D12 | 2～13 | 完整单周期候选 Reference Model、指令定向测试和提交级接口 PASS |
| D20 | 14～17 | GCC/SoC/UART/GPIO/正式单周期 Regression PASS，冻结 `single_cycle_stable` |
| D35 | 18～25 | 五级流水线、Forwarding、Stall、Flush、复杂 Hazard、GCC Pipeline、性能计数器和提交级对比 PASS |
| D42 | 26～29 | FPGA、上板、CoreMark、ILA 性能证据和 `pipeline_coremark_stable` PASS |
| D52 | 30 | 8 通道 Raw 逻辑分析仪、UART/SPI 解析、Python/VCD 和物理回环端到端闭环 PASS |
| D60 | 33～35 | 最终 Regression、报告、视频、答辩、故障恢复演练和 `competition_final` 冻结 |

若未达到硬节点，按 `docs/competition_scoring.md` 的止损线处理，不得通过恢复 RLE、扩展 BTB 范围、削减验证或过度宣称来掩盖延期。任务 32 只实现已冻结的 16 项直接映射 BTB；任务 34 的图表和证据允许在前序 Gate 完成时同步积累，但最终版本只能在任务 33 后冻结。

---

## 二、任务清单

## 阶段 A：项目基线与基础认知

### 任务 0：建立项目骨架与可恢复开发基线

**优先级：P0**  
**前置任务：无**

#### 目标

建立一个不依赖历史聊天、能够由新 Codex 会话可靠恢复的项目基线，并确认后续开发所需工具和文档位置。

#### 需要学什么

- 路线图、进度记录、架构文档、接口契约、应用规格和 Debug 日志各自的职责。
- RTL、Testbench、软件、脚本和文档之间的关系。
- 仿真、RISC-V 交叉编译、FPGA 综合分别解决什么问题。
- 目标紫光同创 FPGA、PDS 工具、板卡与远程实验平台各自解决什么问题。
- Git 提交、稳定标签和可回退 Baseline 的基本意义。

#### 需要实现什么

- 保留根目录 `AGENTS.md`。
- 建立 `docs/roadmap.md`、`docs/progress.md`、`docs/architecture.md`、`docs/interfaces.md`、`docs/fpga_platform.md`、`docs/application_logic_analyzer.md`、`docs/debug_log.md`。
- 在 `docs/progress.md` 记录当前任务、稳定版本、已通过测试、已知问题和下一步。
- 规划 RTL、Testbench、测试程序、软件、脚本和构建产物目录；实际目录可在首次使用时创建。
- 检查并记录仿真器、波形工具、RISC-V GCC 工具链、GNU Make、Python 串口库和 PDS 版本；缺失项如实记录。
- 记录计划使用的紫光同创 FPGA/开发板；尚未确定时，记录远程 FPGA 平台作为验证路径，并在 D3 前完成平台选择。Task 10 再完成器件、时钟/Reset 和 BRAM 的实际冒烟验收。
- 记录目标时钟、Reset 极性、片上 RAM/BRAM 方案和约束文件的预期位置；未知项允许标为待验证，但不得静默跳过。

#### 验收标准

- 新聊天按文首恢复清单读取项目后，能说清当前 Gate、当前任务、已完成内容和下一步。
- 核心文档职责明确，内容不互相替代。
- 已记录当前可用与缺失的开发工具。
- 已记录板卡或远程平台的验证路径，以及最迟确认时间。

#### 通过条件

- 核心文档存在且内容一致。
- `docs/progress.md` 已明确当前从任务 1 开始。
- 工具和硬件平台的已知/未知状态均已记录，未知项不会阻塞基础认知学习，但会阻塞任务 10 通过。
- 没有在基础认知完成前提前创建大段 CPU RTL。

### 任务 1：建立 CPU 最基础认知

**优先级：P0**  
**前置任务：任务 0**

#### 目标

理解 CPU 执行指令的基本过程，并区分 C 程序、RISC-V ISA 和 RTL 微架构三个层次。

#### 需要学什么

- CPU、ISA、微架构。
- PC、Instruction、Register、ALU、Memory、Clock。
- Combinational Logic 与 Sequential Logic。
- ISA 规定“指令是什么意思”，微架构决定“硬件怎样实现这条指令”。

```text
C 语言程序 -> 编译 -> RISC-V 指令 -> CPU 执行 -> RTL 硬件状态变化
```

#### 需要实现什么

- 本任务不编写 CPU RTL。
- 以 `c = a + b;` 和 `add x5, x6, x7` 为例，画出“读寄存器 -> ALU ADD -> 写回寄存器”的最小数据流。
- 用文字说明 PC 在这条指令执行前后的作用。

#### 验收标准

- 不查资料解释 `add x5, x6, x7`。
- 正确指出 `x6`、`x7` 是源寄存器，`x5` 是目的寄存器。
- 说明 ALU 执行加法，PC 决定当前和下一条指令地址。
- 说明组合逻辑在周期内计算，状态在设计规定的有效时钟沿更新。
- 能准确解释 ISA 与微架构的区别。

#### 通过条件

- 上述问题全部能够独立回答。
- 没有把 C 变量、ISA 寄存器与 RTL 信号混为一谈。

### 任务 2：彻底搞懂 RV32I 指令格式

**优先级：P0**  
**前置任务：任务 1**

#### 目标

能够借助 RV32I 规范正确拆解和解释 R、I、S、B、U、J 六类指令格式。

#### 需要学什么

- `opcode`、`rd`、`rs1`、`rs2`、`funct3`、`funct7`、`immediate`。
- 各字段在六类格式中的位置和作用。
- Immediate 的拼接、对齐和符号扩展。
- `sw` 没有 `rd`、Branch 立即数分散、`jal` 有 `rd`、`lui` 没有 `rs1/rs2` 的原因。

#### 需要实现什么

- 本任务不实现 Decoder RTL。
- 手工分析 `add`、`sub`、`and`、`or`、`xor`、`addi`、`lw`、`sw`、`beq`、`bne`、`jal`、`jalr`、`lui`、`auipc`。
- 建立字段拆解练习记录，写明位段、数值、含义和最终指令。

#### 验收标准

- 随机给出机器码时，能借助规范逐字段拆解。
- 能将 `00a00293` 拆出 `opcode`、`rd`、`funct3`、`rs1`、`imm` 并判断指令。
- 能解释 B-Type 和 J-Type immediate 的重新排列与最低位隐含为 0。

#### 通过条件

- 六类格式均至少完成一个正确拆解练习。
- 指定指令列表全部能判断格式和主要字段。
- 不要求心算，但过程必须正确、可复现。

### 任务 3：搞懂软件如何变成机器码

**优先级：P0**  
**前置任务：任务 2**

#### 目标

理解 C 程序经交叉工具链变成 CPU 可执行机器码的完整链路。

#### 需要学什么

- 编译、汇编、链接、ELF、反汇编和裸机镜像。
- `${RISCV_PREFIX}gcc`、`${RISCV_PREFIX}objdump` 和 `${RISCV_PREFIX}objcopy` 的用途；Windows 当前 `RISCV_PREFIX=riscv-none-elf-`。
- `-march=rv32i -mabi=ilp32` 如何限制编译器只生成目标 ISA/ABI。
- 编译器为什么会生成 ALU、Branch、Load/Store、`jal` 和 `jalr`。
- 手写指令测试与执行任意合法 GCC 输出之间的差别。

#### 需要实现什么

- 编写简单的 `add(int a, int b)`。
- 编写包含 `for` 循环、累加和无限循环的最小裸机 C 程序。
- 固定使用 `-march=rv32i -mabi=ilp32` 编译为 ELF，反汇编并对照机器码分析关键指令。
- 构建脚本统一从 `RISCV_PREFIX` 生成工具名，不依赖某个发行版的固定可执行文件前缀。
- 记录“C 源码 -> ELF -> 汇编 -> 机器码 -> IMEM 初始化文件”的转换方法。
- 检查反汇编中未出现 `M`、`C` 或其他未声明支持的扩展指令；出现时必须修正编译参数或明确软件库实现路径。

#### 验收标准

- 能在反汇编中找到并解释实际出现的 `addi`、`add`、Branch、Load/Store、`jal`、`jalr`。
- 能说明 ELF 与最终写入 FPGA Instruction Memory 的内容并不完全等同。
- 能完整解释上电后 CPU 如何取到程序第一条指令。
- 能解释为什么错误的 `-march`/`-mabi` 会让编译器产生 CPU 无法执行的指令或调用约定。

#### 通过条件

- 至少一个 C 程序成功编译并生成可读反汇编和机器码。
- 能独立讲清完整软件到硬件执行链路。
- 通过后才允许开始 CPU 基础模块 RTL。

---

## 阶段 B：单周期 CPU 基础模块

### 任务 4：实现 Register File

**优先级：P0**  
**前置任务：任务 3**

#### 目标

实现符合 RV32I 要求的 32 × 32-bit 寄存器堆，并掌握同步写、组合读和 `x0` 保护。

#### 需要学什么

- RV32I 的 32 个整数寄存器。
- 两读一写寄存器堆的数据通路。
- 同步写入与组合读取的时序关系。
- `x0` 永远为 0 的架构要求。

#### 需要实现什么

- 新建 `regfile.v`。
- 提供 `rs1_addr`、`rs2_addr`、`rs1_data`、`rs2_data`、`rd_addr`、`rd_data`、`rd_we` 等接口。
- 阻止对 `x0` 的实际写入，并确保读取 `x0` 恒为 0。
- 编写独立 Testbench。

#### 验收标准

- 写入并读回 `x1` 和 `x31`。
- 同时读取两个不同寄存器。
- 尝试写 `x0` 后读取仍为 0。
- 连续多个周期写入并正确读回。
- 逐项输出 `TEST n PASS/FAIL`，最终输出 `ALL TEST PASS`。

#### 通过条件

- Register File 独立 Testbench 全部 PASS。
- 无需人工判断波形即可确定结果。
- 接口和时序约定已记录。

### 任务 5：实现 ALU

**优先级：P0**  
**前置任务：任务 4**

#### 目标

实现 RV32I 基础整数运算，并正确处理有符号与无符号比较、逻辑右移与算术右移。

#### 需要学什么

- `ADD`、`SUB`、`AND`、`OR`、`XOR`。
- `SLL`、`SRL`、`SRA`。
- `SLT` 与 `SLTU`。
- 二进制补码、符号位、移位量低 5 位。

#### 需要实现什么

- 新建 `alu.v`，定义清晰的 ALU control 编码。
- 支持全部上述操作。
- 按项目规则优先用符号位、补码关系、位操作和显式逻辑处理 signed 行为。
- 编写独立 Testbench。

#### 验收标准

- 每种 ALU 操作均有正常值测试。
- 覆盖 `0`、`1`、`FFFFFFFF`、`80000000`、`7FFFFFFF`。
- 专门比较 `SLT/SLTU` 和 `SRA/SRL` 的不同结果。
- 覆盖移位量边界。

#### 通过条件

- 所有 ALU 定向测试自动 PASS。
- 能解释每个极端值为何得到当前结果。

### 任务 6：实现 Immediate Generator

**优先级：P0**  
**前置任务：任务 5**

#### 目标

正确从 32-bit 指令中生成 I、S、B、U、J 五类 32-bit immediate。

#### 需要学什么

- 五类 immediate 的位段来源。
- 符号扩展与高位填充。
- B/J immediate 的位重排和地址对齐。
- U-Type immediate 放置在高 20 位的原因。

#### 需要实现什么

- 新建 `imm_gen.v`。
- 输入 `instruction[31:0]`，输出 `imm[31:0]`。
- 实现 I、S、B、U、J 五类拼接与扩展。
- 编写独立 Testbench。

#### 验收标准

- 每种类型覆盖正数、负数和边界值。
- B/J 类型覆盖前跳、后跳和最小对齐偏移。
- 将输出与手工拆解结果逐项比较。

#### 通过条件

- Immediate Generator 独立测试全部 PASS。
- 能从失败结果定位具体拼接位或符号扩展错误。

### 任务 7：实现 Decoder / Control Unit

**优先级：P0**  
**前置任务：任务 6**

#### 目标

让 CPU 根据指令字段产生正确的数据通路控制信号。

#### 需要学什么

- `opcode`、`funct3`、`funct7` 如何共同确定指令。
- `RegWrite`、`ALUSrc`、`ALUControl`、`MemRead`、`MemWrite`、`ResultSrc`、`Branch`、`Jump` 的作用。
- 主译码与 ALU 译码的关系。
- 非法或未实现编码应如何安全处理。

#### 需要实现什么

- 新建 `decoder.v`，或按设计拆分主控制与 ALU 控制。
- 为当前计划中的 RV32I 指令产生控制信号。
- 默认控制必须避免意外寄存器写和内存写。
- 编写独立 Decoder Testbench。

#### 验收标准

- `add` 选择两个寄存器源、ALU ADD、寄存器写回、无内存写。
- `lw` 选择 `rs1 + imm`、读取内存并写回加载数据。
- `sw` 选择 `rs1 + imm`、写内存且不写寄存器。
- Branch、Jump 和非法编码产生安全、正确的控制组合。

#### 通过条件

- 指定指令类别的 Decoder 定向测试全部 PASS。
- 本任务不引入流水线 Hazard 控制。

### 任务 8：实现 Branch Unit

**优先级：P0**  
**前置任务：任务 7**

#### 目标

实现 RV32I 六种条件分支比较，并正确区分 signed 与 unsigned。

#### 需要学什么

- `BEQ`、`BNE`。
- `BLT`、`BGE` 的有符号比较。
- `BLTU`、`BGEU` 的无符号比较。
- 比较结果如何决定下一 PC。

#### 需要实现什么

- 新建 Branch Unit 或在明确的比较模块中实现六种条件。
- 接收两个比较值和分支类型，输出是否 taken。
- 编写独立 Testbench。

#### 验收标准

- 覆盖 `5 < 10`、`10 > 5`、相等和不相等。
- signed 条件覆盖 `-1 < 1`。
- unsigned 条件覆盖 `FFFFFFFF > 1`。
- 覆盖 `80000000` 与 `7FFFFFFF` 的 signed/unsigned 差异。

#### 通过条件

- 六种分支条件全部自动 PASS。
- 能解释 signed 与 unsigned 测试差异。

### 任务 9：实现 Load / Store 数据处理

**优先级：P0**  
**前置任务：任务 8**

#### 目标

独立解决 RV32I 字节、半字和字的加载、存储、符号扩展与字节使能问题。

#### 需要学什么

- byte、halfword、word 和 little endian。
- 地址低位与数据 lane 的关系。
- `LB/LBU`、`LH/LHU` 的符号扩展差异。
- `SB/SH/SW` 的写掩码和数据排列。

#### 需要实现什么

- 实现 `LB`、`LH`、`LW`、`LBU`、`LHU` 的读数据整理。
- 实现 `SB`、`SH`、`SW` 的写数据和 byte enable 生成。
- 编写独立 Testbench，不依赖完整 CPU。

#### 验收标准

- 地址 `0x1000..0x1003` 依次为 `78 56 34 12` 时，`LW 0x1000 = 0x12345678`。
- 覆盖不同地址低位、正负字节/半字、无符号扩展。
- 覆盖三种 Store 宽度及其写掩码。

#### 通过条件

- Load/Store 数据处理全部自动 PASS。
- 非对齐访问当前策略已明确记录；若暂不支持，测试应能识别。

### 任务 10：实现 Memory，并完成 FPGA 存储可行性冒烟验证

**优先级：P0**  
**前置任务：任务 9**

#### 目标

建立足以验证单周期 CPU 的 IMEM/DMEM 仿真模型，同时确认最终紫光同创 FPGA 所需的同步 BRAM 接口、初始化和 PDS 推断路径可行。

#### 需要学什么

- 指令地址与字索引的转换。
- RAM 初始化文件。
- 同步/异步读写行为对单周期数据通路的影响。
- 仿真 RAM 与 FPGA BRAM 推断的差别。
- PDS 工程、目标器件、时钟/Reset、BRAM IP 或推断模板的最小使用方法。
- 为什么单周期 Reference Model 可以使用行为级组合读存储器，但最终流水线 FPGA 实现必须服从真实 BRAM 延迟。

#### 需要实现什么

- 新建 `imem.v` 和 `dmem.v`。
- IMEM 根据 PC 返回 32-bit instruction。
- DMEM 提供地址、写数据、写使能/字节使能和读数据接口。
- 支持测试所需的初始化和状态检查。
- 本阶段（基础 SoC）不使用 Cache、DDR 或复杂总线；Cache/DDR 属于 P3 阶段（`AGENTS.md` §1.14）。
- 明确区分 Reference Model 的行为级 memory 与 FPGA 同步 BRAM wrapper，不用仿真专用行为冒充可综合 BRAM。
- 建立最小 PDS 冒烟工程，只验证目标器件、时钟/Reset、BRAM 读写与初始化；此步骤不提前实现 CPU RTL。
- 目标工程固定使用 `docs/fpga_platform.md` 定义的 MES50HP `PGL50H-6IFBG484`、50 MHz 和默认内部上电复位路径；底板 `REST` 不作为 CPU Core Reset，人工复位只使用已确认的低有效用户按键。
- 使用 MES50HP 手册已确认的 `FPGA_GCLK_50M`、按键/LED、UART、J8 与 PMOD 管脚及电平创建 `.fdc`；不得使用 TODO、旧平台或猜测管脚。
- 记录实际 BRAM 读延迟、写使能粒度、初始化文件格式、资源推断结果和严重警告。

#### 验收标准

- IMEM 按连续 PC 返回预期指令。
- DMEM 基本读写、连续读写和 byte enable 测试 PASS。
- 初始化内容与读回内容一致。
- 边界和越界行为有明确约定。
- PDS 冒烟综合/实现能够完成，BRAM 行为与文档约定一致，且没有未解释的 Latch、多驱动或未约束时钟。
- MES50HP 最小程序能够通过板载 CP2102 UART（参数由实测冻结）或已确认 LED 给出可重复结果；Reset 默认路径多次启动一致。

#### 通过条件

- IMEM、DMEM 独立 Testbench 全部 PASS。
- 任务 4～10 基础模块 Regression 全部 PASS。
- Reference Model 和 FPGA 两种内存时序模型均已记录。
- MES50HP、PDS 版本、完整目标器件、真实管脚、时钟/Reset 和 BRAM 结果已写入 `docs/progress.md`、`docs/architecture.md` 与 `docs/fpga_platform.md`。
- 通过后才允许集成 CPU；未完成 FPGA 存储可行性验证时，本任务不得标记通过。

---

## 阶段 C：单周期 CPU 与 Reference Model

### 任务 11：搭建最小单周期 CPU

**优先级：P0**  
**前置任务：任务 4～10 全部通过**

#### 目标

首次把基础模块集成为能够自动取指并执行程序的最小单周期 CPU。

#### 需要学什么

- 单周期数据通路。
- PC+4、Branch target、Jump target 的选择。
- ALU 输入选择、Memory 访问和 WriteBack。
- 一条指令在一个周期内的组合路径和状态更新。

#### 需要实现什么

- 集成 PC、IMEM、Decoder、RegFile、ImmGen、ALU、DMEM 和 WriteBack。
- 第一版只支持 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ`、`JAL`。
- 编写最小 CPU Testbench 和测试程序。

```asm
addi x1, x0, 5
addi x2, x0, 10
add  x3, x1, x2
sw   x3, 0(x0)
```

#### 验收标准

- CPU 从 Reset PC 开始连续取指。
- 示例程序执行后 `memory[0] = 15`。
- Testbench 有超时保护并自动输出 PASS/FAIL。

#### 通过条件

- 最小程序稳定重复 PASS。
- 能逐周期解释 PC、instruction、源操作数、ALU result、写回和内存写。
- 未通过前不得一次性补全全部 RV32I。

### 任务 12：补全单周期 RV32I

**优先级：P0**  
**前置任务：任务 11**

#### 目标

将最小单周期 CPU 按指令类别扩展为完整目标 RV32I 实现。

#### 需要学什么

- RV32I 各类指令语义和 corner case。
- `LUI/AUIPC`、`JAL/JALR` 的数据通路。
- Load/Store 宽度和 Branch 条件的系统集成。
- 采用的 RV32I 规范版本及系统类指令处理范围。

#### 需要实现什么

- 按顺序补充：R-Type ALU -> I-Type ALU -> Load -> Store -> Branch -> `LUI/AUIPC` -> `JAL` -> `JALR`。
- 每完成一类立即增加定向测试并运行 Regression。
- 建立含“实现、定向测试、Regression”的指令覆盖表。
- 明确采用的 Unprivileged ISA 规范版本、非对齐访问策略以及 `FENCE`、`ECALL`、`EBREAK` 等系统类指令的支持范围。
- 接入与目标 ISA/平台兼容的 RISC-V architectural tests；不能直接运行的测试必须记录原因和等价替代验证。

#### 验收标准

- 每条目标指令都有正常测试和必要的边界测试。
- 指令覆盖表无未解释空项。
- architectural tests 的适用项全部 PASS，不适用项具有明确、可审查的说明。
- 所有既有最小 CPU 测试持续 PASS。
- 完整单周期 RV32I Regression PASS。

#### 通过条件

- 目标 RV32I 指令全部实现并通过定向测试。
- 完整 Regression 可统一、重复运行。
- 未覆盖项和规范选择已明确记录。

### 任务 13：建立单周期候选 Reference Model 与提交级接口

**优先级：P0，关键里程碑**  
**前置任务：任务 12**

#### 目标

建立可重复验证的单周期候选 Reference Model 和提交级观察接口，为 GCC/SoC Regression 与后续流水线逐条指令对比做准备；本阶段尚不冻结最终版本。

#### 需要学什么

- Architectural state 与内部微架构状态的区别。
- Reference Model 在流水线 Debug 中的作用。
- 候选版本、最终冻结版本和可回退基线的区别。
- Architectural commit/retire 的定义。
- 自动状态比较比人工波形比较更可靠的原因。

#### 需要实现什么

- 保存候选版本，例如 `single_cycle_reference_candidate`；不得命名为最终 stable。
- 建立寄存器 `x1`～`x31` 和关键 RAM 状态的导出/比较机制。
- 定义统一提交级 trace，至少包含 `valid`、`pc`、`instruction`、`rd_we`、`rd_addr`、`rd_data`、`mem_we`、`mem_addr`、`mem_data` 和 byte enable。
- 为 Store、Branch、Jump 和不写寄存器的指令定义清楚提交事件，确保 Pipeline 能按同一语义比较。
- 记录候选版本、测试命令、结果和已知限制。

#### 验收标准

- 完整单周期 Regression 重复运行结果一致。
- 状态导出包含 `x1`～`x31` 和测试指定 RAM。
- 同一程序重复运行时提交级 trace 完全一致。
- 故意制造不一致时，比较器输出 FAIL 并指出差异。

#### 通过条件

- `single_cycle_reference_candidate` 可识别、可恢复。
- 最终状态和提交级 trace 导出机制自动 PASS。
- 通过后允许进入 GCC 软件和 SoC 集成；只有任务 17 正式 Regression 通过后才允许冻结 `single_cycle_stable`。

---

## 阶段 D：GCC 程序与基础 SoC

### 任务 14：让 GCC 编译的 C 程序真正运行

**优先级：P0**  
**前置任务：任务 13 候选 Reference Model 通过**

#### 目标

让单周期 CPU 执行由 GCC 生成的真实裸机 C 程序，而不只执行手写汇编。

#### 需要学什么

- `startup.S`、`linker.ld`。
- `.text`、`.data`、`.bss`、stack、entry point。
- 全局变量、函数调用、调用约定的最低必要知识。
- 程序镜像如何装入 IMEM/DMEM。

#### 需要实现什么

- 建立最小启动代码和链接脚本。
- 构建参数固定为 `-march=rv32i -mabi=ilp32`，并记录优化级别、链接选项和是否使用 `libgcc`。
- 编译并运行累加 `0..9`、写入 `volatile int result` 的程序。
- 增加数组、普通函数调用、循环和 `if/else` 测试。
- 建立从 ELF 生成内存初始化文件的可重复流程。

#### 验收标准

- 首个程序结束后 RAM 中 `result = 45`。
- 数组、函数调用、循环和条件判断程序全部自动 PASS。
- 能通过反汇编解释关键控制流和内存访问。

#### 通过条件

- 所有规定 C 程序在单周期 CPU 上稳定 PASS。
- 构建和加载流程可重复，不依赖手工修改机器码。
- 反汇编中没有未声明支持的 ISA 扩展；必要的软件乘除法等运行库路径已验证。

### 任务 15：冻结 Core/SoC 数据接口并实现 Memory-Mapped I/O

**优先级：P0**  
**前置任务：任务 14**

#### 目标

冻结通用 Core/SoC 数据事务接口，并在 Core 外实现 CPU 通过普通 Load/Store 访问 RAM 和外设的 MMIO 机制。

#### 需要学什么

- 地址空间与地址译码。
- RAM、UART、GPIO 的片选。
- request/response、`valid/ready`、背压和一次事务一次 side effect。
- Core、adapter、interconnect、peripheral wrapper 的职责边界。
- `volatile` 对 MMIO C 代码的意义。
- 外设访问与普通内存访问的相同点和不同点。

#### 需要实现什么

- 评审并冻结 `docs/interfaces.md` 中单周期 Core adapter 的逐根信号名，保持 32-bit 字节地址、读写、写数据、4-bit byte strobe 和 `valid/ready` 事务语义。
- 定义地址映射，例如 RAM、`0x10000000` UART、`0x10001000` GPIO，并预留不绑定具体设备的 Application MMIO 窗口；具体常量只存在于 SoC 地址表/软件头文件，不进入 Core。
- 在 Core 外实现地址译码和读数据返回选择。
- 确保一次访问只选中一个目标。
- 定义未映射和边界地址行为。
- 编写接口握手、随机背压、MMIO 地址译码和 side effect Testbench。

#### 验收标准

- RAM、UART、GPIO 地址范围不重叠。
- Application MMIO 预留窗口与现有区域不重叠；Task 30 更换窗口内设备不需要修改 Core 或基础互连协议。
- 对每个区域的读写访问产生正确片选。
- 非目标设备不发生写入。
- 边界和未映射地址测试符合约定。
- `valid && !ready` 时请求字段稳定；被接受的写恰好产生一次 side effect。
- Core 不含设备专用地址、片选或状态信号。

#### 通过条件

- MMIO 自动测试全部 PASS。
- 地址映射已写入 `docs/architecture.md`，逐根接口名和已冻结版本已写入 `docs/interfaces.md`。

### 任务 16：集成 UART + GPIO

**优先级：P0**  
**前置任务：任务 15**

#### 目标

在 Core 外完成可由 RV32I CPU 软件控制的 GPIO 和 UART，形成最基础的参考 SoC，并证明外设配置可以替换而不修改 CPU Core。

#### 需要学什么

- GPIO 输出寄存器。
- UART 发送帧：起始位、数据位、停止位和波特率分频。
- UART 接收帧、状态位和溢出/忙状态的最小处理。
- 通用事务背压与低速外设 wrapper 之间的转换。
- 软件轮询输出字符串的基本方法。
- 为什么外设寄存器、设备状态机和应用数据面都不能进入流水线主体。

#### 需要实现什么

- 先实现 GPIO MMIO 寄存器和外部输出。
- 再实现 UART TX/RX、状态寄存器和 MMIO 读写接口。
- GPIO 软件 Demo 写出 `0xAA`。
- UART 软件 Demo 调用 `uart_puts("Hello RISC-V!\r\n")`。
- 为 GPIO、UART 建立独立测试和 SoC 集成测试。
- 建立 RAM-only、RAM+UART、RAM+GPIO 三种可选 SoC 配置；三者复用同一份 Core 源文件和统一事务接口。
- 记录逻辑分析仪为已选 Task 30 应用，但本任务不实现 Capture Engine；只验证通用 Application MMIO 窗口可以连接 dummy target 而不修改 Core。

#### 验收标准

- GPIO 输出为 `10101010`。
- UART Testbench 正确解码出 `Hello RISC-V!`。
- UART RX 能接收规定字节并由软件读回，忙/空/有效状态符合约定。
- CPU 通过软件访问外设，不依赖 Testbench 直接操纵内部寄存器。
- RAM-only、UART、GPIO 配置切换不修改 Core 源文件；原 Core Regression 全部保持 PASS。
- 任一低速设备等待期间，请求不丢失、不重复，设备 side effect 恰好发生一次。

#### 通过条件

- GPIO、UART TX/RX 独立测试与 SoC 集成测试全部 PASS。
- 系统形成可配置的 `RV32I Core + Interconnect + RAM + optional peripherals`。
- Core/SoC 解耦检查满足 `docs/interfaces.md`；Task 30 只能通过已冻结的 Application MMIO 窗口增加 `docs/application_logic_analyzer.md` 定义的外设，不得修改 Core。

---

## 阶段 E：单周期正式 Regression

### 任务 17：建立正式 Regression，并冻结最终单周期 Reference Model

**优先级：P0**  
**前置任务：任务 16**

#### 目标

建立可重复、自动判定、覆盖单周期 CPU 和基础 SoC 的正式回归系统；在 GCC、外设和 ISA 验证全部通过后，冻结流水线所使用的最终单周期 Reference Model。

#### 需要学什么

- 定向测试、Regression、测试超时和失败退出码。
- 功能覆盖表与指令覆盖表。
- instruction count、cycle count 和 CPI。
- 为什么不能只依赖人工查看波形。
- 最终状态比较与提交级 trace 比较各自能发现什么问题。
- 候选基线升级为最终冻结版本所需的证据。

#### 需要实现什么

- 建立 `tests/`。
- 至少包含 `alu_test`、`branch_test`、`load_store_test`、`jump_test`、`function_test`、`loop_test`、`memory_test`、`gcc_test`。
- 加入适用的 RISC-V architectural tests、MMIO、UART TX/RX、GPIO 和非法/未实现编码安全行为测试。
- 加入 RAM-only、RAM+UART、RAM+GPIO 三种配置回归和可变延迟/随机背压测试；所有配置必须使用同一份单周期 Core 源文件。
- 提供统一运行入口。
- 每项自动输出 PASS/FAIL，任一失败时 Regression 失败。
- 记录 instruction count、cycle count；单周期理论上 `CPI ≈ 1`。
- 对每个系统程序保存最终 architectural state 和按退休顺序输出的提交级 trace。
- 正式 Regression 全部 PASS 后，将任务 13 的候选版本冻结为 `single_cycle_stable` 或等价可识别版本，并记录工具、测试镜像和已知限制。

#### 验收标准

- 一次运行执行全部规定测试。
- 故意破坏一个结果时，系统报告具体失败测试。
- 故意修改一次寄存器写回或内存写入时，trace 比较器报告第一条不一致提交及对应 PC/instruction。
- 连续多次运行结果一致。
- 结果和未覆盖项记录到 `docs/progress.md`。

#### 通过条件

- 单周期完整 Regression 全部 PASS。
- GCC、MMIO、UART TX/RX、GPIO 和适用的 architectural tests 全部 PASS。
- Core/SoC 解耦配置与事务背压测试全部 PASS，新增/移除参考外设未修改 Core。
- `single_cycle_stable` 最终 Reference Model 可恢复，最终状态与提交级 trace 可正常复现。
- 通过后才允许开始流水线设计。

---

## 阶段 F：五级流水线基础数据通路

### 任务 18：先画五级流水线，不写 RTL

**优先级：P0**  
**前置任务：任务 17**

#### 目标

在编写流水线 RTL 前，完整理解 IF、ID、EX、MEM、WB 和流水寄存器的信息流。

#### 需要学什么

- 五级流水线各阶段职责。
- IF/ID、ID/EX、EX/MEM、MEM/WB 的作用。
- 数据和控制信号为何都要随指令向后传递。
- Pipeline latency、throughput 与单周期 CPU 的差别。
- 为什么流水线 Core 必须复用 `docs/interfaces.md` 的通用事务语义，而不能感知 UART/GPIO 等具体设备。

#### 需要实现什么

- 绘制五级流水线数据通路图。
- IF/ID：PC、instruction。
- ID/EX：PC、rs1/rs2 data、imm、rd、rs1、rs2、控制信号。
- EX/MEM：ALU result、store data、rd、控制信号。
- MEM/WB：memory result、ALU result、rd、RegWrite、ResultSrc。
- 在数据通路图外明确 instruction/data transaction port、adapter/interconnect 和外设边界；地址译码不得画入 MEM 流水级。
- 把图和接口决定写入 `docs/architecture.md`，把流水线 Core 顶层逐根端口名和版本写入 `docs/interfaces.md`。

#### 验收标准

- 能将 `add x5, x6, x7` 从第 1 拍 IF 跟踪到第 5 拍 WB。
- 能说明每个关键信号在哪一级产生、在哪一级使用。
- 能解释某一级停顿或清空时各流水寄存器应发生什么。
- 能说明外设延迟如何经统一背压转化为流水线等待，以及为什么不需要设备专用控制信号。

#### 通过条件

- 数据通路图、流水寄存器字段和时序解释通过检查。
- 流水线 Core 边界不含地址译码和任何外设专用信号，并与单周期接口语义兼容。
- 在理解确认前禁止编写流水线 RTL。

### 任务 19：实现没有 Hazard 的五级流水线

**优先级：P0**  
**前置任务：任务 18**

#### 目标

先证明五级流水线基础数据通路正确，不在同一步混入 Forwarding、Stall 和 Flush。

#### 需要学什么

- Pipeline register 的更新与 Reset。
- 有效指令、NOP 和 Bubble 的基本表达。
- 写回时刻与寄存器读取时序。
- Architectural state 对比方法。

#### 需要实现什么

- 实现 IF、ID、EX、MEM、WB 和四组流水寄存器。
- 暂不实现 Forwarding 和自动 Stall。
- 测试程序人工插入足够 NOP，避开数据 Hazard。
- 通过通用存储 adapter 连接 Testbench memory；流水线 Core 不直接实例化 UART、GPIO 或地址译码。
- Pipeline 和 Single Cycle 运行同一程序并自动比较最终状态与提交级 trace；流水线内部空泡不得生成提交事件。

#### 验收标准

- 独立指令和插 NOP 程序执行正确。
- Pipeline 最终 `x1`～`x31` 与关键 RAM 和 Reference Model 一致。
- 提交级 trace 按退休顺序一致；比较器自动输出 PASS/FAIL 和第一条具体差异。

#### 通过条件

- 无 Hazard 流水线 Regression 全部 PASS。
- 最终状态和提交级 trace 均与 `single_cycle_stable` 一致。
- 未加入任何未经验证的 Hazard 优化。

---

## 阶段 G：流水线 Hazard 处理

### 任务 20：实现 Forwarding

**优先级：P0**  
**前置任务：任务 19**

#### 目标

解决相邻或间隔一条指令的普通 ALU RAW 数据依赖，减少人工 NOP。

#### 需要学什么

- RAW dependency。
- `EX/MEM -> EX` 和 `MEM/WB -> EX` 两条转发路径。
- 转发优先级。
- 为什么 `rd = x0` 必须排除。

#### 需要实现什么

- 新建 `forward_unit.v`。
- 为 EX 阶段两个源操作数产生 Forward 选择。
- 从数据依赖条件推导逻辑。
- 增加 Forwarding 定向测试。

#### 验收标准

- 覆盖一级、二级依赖。
- 覆盖 rs1、rs2、双源和连续依赖。
- 覆盖连续写同一目的寄存器和 `x0`。

#### 通过条件

- Forwarding 定向测试全部 PASS。
- Pipeline 与 Reference Model 最终状态及提交级 trace 对比 PASS。
- 能解释转发选择优先级。

### 任务 21：实现 Load-Use Hazard + Stall

**优先级：P0**  
**前置任务：任务 20**

#### 目标

处理 Load 数据尚未产生时下一条指令立即使用它的情况。

#### 需要学什么

- Load 数据在哪一级可用。
- 普通 ALU Forwarding 为什么不能消除所有 Load-Use Hazard。
- Stall 与 Flush 的区别。
- Hold 与 Bubble 如何避免重复执行或丢失指令。

#### 需要实现什么

- 新建或扩展 `hazard_unit.v`。
- 实现 PC Hold、IF/ID Hold、ID/EX Bubble。
- 明确 Stall 时各流水寄存器的行为。
- 增加 Load-Use 定向测试和计数检查。

#### 验收标准

- `lw` 后立即由 rs1 或 rs2 使用。
- Load 后 Store、Branch 等消费者得到正确数据。
- 只停顿必要周期，不丢失或重复提交指令。

#### 通过条件

- Load-Use 测试全部 PASS。
- Pipeline 与 Reference Model 最终状态及提交级 trace 一致。
- 能说明 Hold 和 Bubble 发生的周期。

### 任务 22：实现 Branch / Jump / Control Hazard

**优先级：P0**  
**前置任务：任务 21**

#### 目标

保证 Branch、`JAL`、`JALR` 改变 PC 后，错误路径指令不会提交 architectural side effect。

#### 需要学什么

- Control Hazard。
- Branch 决策级与错误路径指令数量的关系。
- Flush 的含义。
- Jump link value 与 target 的产生时机。

#### 需要实现什么

- 支持全部 Branch、`JAL`、`JALR` 的流水执行。
- 对已进入流水线的错误路径指令执行 Flush。
- 确保被 Flush 指令不能写寄存器、RAM 或 MMIO。
- 增加 Control Hazard 定向测试。

#### 验收标准

- 覆盖 taken、not-taken、连续 Branch、`JAL`、`JALR`。
- 覆盖 Branch + data dependency。
- 用错误路径写寄存器/内存测试证明 side effect 被抑制。

#### 通过条件

- Control Hazard 测试全部 PASS。
- Pipeline 与 Reference Model 最终状态及提交级 trace 一致。
- 能清楚回答 Stall 与 Flush 的差别。

### 任务 23：复杂 Hazard 交叉测试

**优先级：P0**  
**前置任务：任务 20～22**

#### 目标

验证 Forwarding、Stall 和 Flush 同时出现时的优先级和组合行为。

#### 需要学什么

- 多个 Hazard 同周期出现时的控制优先级。
- Store data 与 Branch compare 的转发需求。
- Flush 和 Stall 冲突时的正确处理。
- Architectural commit 与错误路径 side effect。

#### 需要实现什么

- 建立 `hazard_stress_test`。
- 覆盖 ALU -> Branch、Load -> Branch、ALU -> Store、Load -> Store。
- 覆盖 JAL -> dependency、连续 Branch、Branch 后立即 Load、连续写同一 `rd`。
- 覆盖数据事务等待与 Forwarding/Stall/Flush 同周期出现、随机背压、Reset 中止；已接受事务不得丢失或重复。
- 失败时输出 PC、instruction 和关键 Hazard 控制信号。
- 每次 architectural commit 输出统一 trace；发生差异时同时报告 Single Cycle 与 Pipeline 的第一条不一致提交。

#### 验收标准

- 每类交叉场景都有独立、可定位测试。
- 所有场景中 Pipeline 与 Reference Model 最终状态及提交级 trace 一致。
- 错误路径无寄存器、RAM 或 MMIO side effect。
- `valid && !ready` 时事务字段稳定；外设延迟变化不引入设备专用 Hazard 逻辑。

#### 通过条件

- `hazard_stress_test` 全部 PASS。
- 流水线完整功能 Regression PASS。
- 通过后才允许运行 GCC Pipeline 程序。

---

## 阶段 H：GCC Pipeline、性能计数器与 FPGA

### 任务 24：流水线运行真实 C 程序

**优先级：P0**  
**前置任务：任务 23**

#### 目标

证明五级流水线能够稳定执行 GCC 生成的真实 RV32I 程序。

#### 需要学什么

- 编译器生成的真实依赖和控制流模式。
- 函数调用、数组、循环和内存复制对流水线的压力。
- Single Cycle 与 Pipeline 的 architectural equivalence。

#### 需要实现什么

- 重跑任务 14 的全部 C 程序。
- 增加普通函数调用、数组、循环、条件判断和类似 `memcpy` 的操作。
- 所有程序固定使用 `-march=rv32i -mabi=ilp32`，固定优化级别并保存反汇编。
- 自动运行同一镜像或等价镜像于 Single Cycle 和 Pipeline。
- 自动比较最终寄存器、关键 RAM 和提交级 trace。

#### 验收标准

- 每个程序满足 `Single Cycle Result = Pipeline Result`。
- 每个程序的提交级 trace 按退休顺序一致，不受流水线内部 Stall/Bubble/Flush 周期影响。
- GCC Pipeline Regression 可重复运行。
- 失败时能定位第一个 architectural state 差异或第一个错误提交。

#### 通过条件

- 所有规定 C 程序在 Pipeline 上 PASS。
- Single Cycle/Pipeline 最终状态和提交级 trace 自动对比全部 PASS。

### 任务 25：实现并验证性能计数器

**优先级：P0**  
**前置任务：任务 24**

#### 目标

在正式运行 CoreMark 前，用 Core 事件与外部性能监视器建立可验证的性能观察能力，避免只有跑分而无法解释流水线效率，同时不把软件可见 MMIO 寄存器耦合进流水线主体。

#### 需要学什么

- cycle、retired instruction、Stall、Flush 的精确定义。
- `CPI = cycle_count / instret_count`。
- Stall Rate、Branch Rate、Flush Rate。
- 计数器宽度、Reset、读取一致性和溢出。
- CoreMark 计时器与 CPU 性能事件计数器的区别。

#### 需要实现什么

- 从 Core 输出已定义的 retire、stall、load stall、branch、branch taken 和 flush 事件。
- 在 Core 外部性能监视器增加 `cycle_count`、`instret_count`、`stall_count`、`load_stall_count`、`branch_count`、`branch_taken_count`、`flush_count`。
- 提供软件与 Testbench 可读取的一致接口，并支持 CoreMark 所需的可靠计时。
- 为各类事件编写定向计数测试。
- 将计数事件脉冲加入 ILA 观察列表。

#### 验收标准

- 已知短程序的 cycle 和 instret 与手工结果一致。
- 人工制造 Stall、taken Branch 和 Flush 时计数准确。
- 软件读取结果与 Testbench 统计一致。
- 能计算 CPI、Stall Rate、Branch Rate、Flush Rate，并处理 Reset、读取和溢出边界。
- 移除或替换性能监视器的 MMIO wrapper 不需要修改 IF/ID/EX/MEM/WB 或 Hazard 控制。

#### 通过条件

- 性能计数器定向测试全部 PASS。
- 能用实际数据解释至少一个主要性能损失来源。
- 完整 Pipeline/GCC Regression 保持 PASS。
- 未通过本任务时不得进入正式 FPGA 综合或 CoreMark。

### 任务 26：正式 FPGA 综合

**优先级：P0**  
**前置任务：任务 25**

#### 目标

将包含提交级 trace 与性能计数器的稳定流水线 SoC 送入目标 FPGA 工具链，首先实现可综合和 Timing PASS。

#### 需要学什么

- LUT、FF、BRAM、Fmax、Slack、Critical Path。
- 综合、布局布线与静态时序分析。
- 时钟和 Reset 约束。
- 仿真模型与可综合 RTL 的差异。

#### 需要实现什么

- 建立目标 FPGA 工程、顶层、引脚和时钟约束。
- 复用任务 10 已验证的目标器件、时钟/Reset 和 BRAM wrapper，不允许临时换成时序行为不同的 RAM。
- 在构建层级和资源报告中区分 `pipeline_core`、adapter/interconnect、memory 和 peripherals；不得把整个 SoC 误报为 Core 面积。
- 完成综合与实现。
- 检查 RAM 推断、Latch、多驱动和未约束路径等警告。
- 记录资源、频率、Slack 和关键路径。

#### 验收标准

- 综合和实现流程成功。
- 实际 IMEM/DMEM/BRAM 延迟与 Pipeline 设计假设一致。
- 至少对 RAM-only 和基础 UART/GPIO 两种 SoC 配置完成 elaboration/综合检查；两种配置引用相同的 Pipeline Core 源文件。
- 第一目标 Timing PASS，第二目标功能正确，第三目标才是提高 Fmax。
- 无未解释的严重警告。
- 资源和时序报告可复现。

#### 通过条件

- 目标频率下 Timing PASS。
- 构建结果和报告记录到 `docs/progress.md`。
- 不为追求频率破坏功能正确性。

### 任务 27：上板验证

**优先级：P0**  
**前置任务：任务 26**

#### 目标

证明包含外部性能监视器的流水线 SoC 在 MES50HP 的 `PGL50H-6IFBG484` 上能够 Reset、执行软件并通过参考 GPIO/UART 配置展示结果，同时保持 Core 与板级外设解耦。

#### 需要学什么

- 板级时钟、Reset 和引脚行为。
- UART 物理连接和波特率。
- ILA 采样、触发和信号选择。
- 仿真通过但上板失败的常见时序与初始化差异。

#### 需要实现什么

- 建立 Reset -> 程序执行 -> GPIO -> UART 验证流程。
- 使用 `USE_EXTERNAL_RESET=0` 的内部上电复位作为 MES50HP 默认路径；按键低有效、LED 高有效的转换在 board wrapper 完成。若需要 CPU 人工复位，只从手册已确认的低有效用户按键分配，不把 `REST` 固件重加载信号接入 Core。
- UART 使用实体板已验证的 RX=`R8`、TX=`R9` 板载 CP2102 互连；按键/LED、J8、PMOD 和逻辑分析仪映射使用 `docs/fpga_platform.md` 已归档的板级数值。
- 接入 ILA，观察 commit PC/instruction、RegWrite、rd、ALU result、stall、flush 和性能事件脉冲。
- 通过软件和 ILA 检查性能计数器在板上的事件统计。
- 保存关键板级程序和必要 ILA 证据。

#### 验收标准

- 多次 Reset 后 GPIO Demo 结果一致。
- UART 稳定输出预期文本。
- ILA 捕获正常提交、Stall、Flush 和性能事件的关键周期。
- 板级软件读取的性能计数与仿真定义一致。
- 板级行为与仿真结果一致。
- GPIO/UART 仅通过 SoC 顶层和统一互连连接；板级引脚或展示方式变化不修改 Pipeline Core。

#### 通过条件

- GPIO、UART、性能计数器和 ILA 验证全部通过。
- 已记录 MES50HP、`PGL50H-6IFBG484` 完整料号、50 MHz 时钟、Reset 模式、`.fdc`、bitstream 和测试程序版本。
- 通过后才允许进入正式 CoreMark。

---

## 阶段 I：CoreMark、性能分析与稳定 Baseline

### 任务 28：移植并运行 CoreMark

**优先级：P0**  
**前置任务：任务 27**

#### 目标

在具备可靠计时和性能事件统计的稳定流水线 SoC 上正确运行 CoreMark，并建立可复现的比赛性能结果。

#### 需要学什么

- CoreMark v1.0 移植接口和运行要求。
- startup、linker、timer、UART output、memory 和 compiler flags。
- CoreMark、CoreMark/MHz、CoreMark/LUT 的含义和单位。
- 正确运行、性能测量与性能优化是三个不同阶段。

#### 需要实现什么

- 完成 CoreMark 平台适配。
- 使用任务 27 已验证的计时接口和 UART 结果输出。
- 固定 `-march=rv32i -mabi=ilp32`、优化级别、链接选项、数据规模、时钟和内存配置。
- 保存 ELF、反汇编、内存镜像、bitstream 和运行日志之间的版本对应关系。
- 正式测试设置迭代次数，确保运行时间不低于 10 秒。

#### 验收标准

- CoreMark 自检通过并输出有效分数。
- 多次 Reset、多次运行结果稳定。
- 记录 CoreMark、Frequency、CoreMark/MHz、LUT、CoreMark/LUT、CPI、Stall Rate 和 Flush Rate。
- 计时单位和频率换算经过独立检查，避免把周期数、秒和 MHz 混用。

#### 通过条件

- CoreMark 在 FPGA 上稳定、可复现完成，单次正式运行不低于 10 秒。
- 所有编译、硬件、计时和运行条件已记录。
- 首次跑通不夹带 BTB 或任何已经删减的高阶功能。

### 任务 29：冻结 Pipeline CoreMark Baseline

**优先级：P0，关键里程碑**  
**前置任务：任务 28**

#### 目标

冻结一个可回退、可比较的稳定流水线 CoreMark 版本，作为所有高阶优化的 Before 基线。

#### 需要学什么

- 功能基线、时序基线和性能基线。
- 版本冻结和回退策略。
- 优化实验为什么必须一次只改变少量因素。
- 如何用 ILA 波形、提交级 trace 和性能计数器解释 CoreMark 关键循环的流水线效率。
- 比赛性能分析报告需要的可复现证据链。

#### 需要实现什么

- 保存 `pipeline_coremark_stable` 版本或等价 Git 标签。
- 固定 RTL、工具版本、约束、编译参数和测试镜像。
- 汇总 RV32I、流水线、UART、GPIO、GCC、CoreMark、FPGA 验证结果。
- 保存 Frequency、Slack、LUT、FF、BRAM、CoreMark、CoreMark/MHz、CoreMark/LUT、CPI、Stall Rate 和 Flush Rate。
- 用 ILA 抓取 CoreMark 至少一个关键循环，标注 commit、Forwarding、Stall、Branch/Flush，并与性能计数器数据相互印证。
- 形成可直接用于参赛材料的性能分析初稿，包含系统框图、测试条件、关键波形、资源/时序表、性能公式、已知瓶颈和复现步骤。

#### 验收标准

- 完整 Regression 全部 PASS。
- FPGA GPIO/UART 与 CoreMark 稳定。
- ILA 波形能够解释至少一个 CoreMark 性能损失来源，且与计数器统计不矛盾。
- 性能分析初稿中的每个数字均可追溯到日志、报告或构建版本。
- 从冻结版本重新构建可以复现主要结果。

#### 通过条件

- `pipeline_coremark_stable` 可识别、可恢复、可复现。
- Before 数据和基础赛题性能分析材料完整。
- 未达到此条件时不得进入 Task 30；RLE 与 AI 不因 Baseline 通过而恢复；
  Cache 与异常/中断已于 2026-09-28～29 解冻，按各自契约与闸门推进（`AGENTS.md` §1.14）。
  16 项 BTB 只能在 Task 30 与 CoreMark 基线通过后按 Task 32 的冻结规格实现。

---

## 阶段 J：多协议逻辑分析仪应用

### 任务 30：构建可重构多协议逻辑分析仪

**优先级：P0，参赛应用主线**  
**前置任务：任务 29**

#### 目标

在 Task 16 已冻结的通用 Core/SoC 接口上，实现 `docs/application_logic_analyzer.md` 定义的逻辑分析与故障诊断平台，形成“RISC-V 软件控制 + FPGA 高速并行采集”的完整 Demo；应用必须保持为可移除的 Core 外部 MMIO 外设。

#### 需要学什么

- 数字采样、采样定理的工程边界、输入寄存和 metastability 风险。
- 电平/边沿触发、通道掩码、触发前后采样和 BRAM 环形缓冲。
- MMIO 控制面、Capture Engine 数据面以及 UART/SPI 协议解析。
- Python 波形显示、VCD 格式和端到端数据一致性。
- PDS ILA 与参赛作品逻辑分析仪的区别；前者仍用于 CPU 内部性能分析。

#### 需要实现什么

- Capture Engine 可保留便于单元测试的通道参数，但本届上板配置固定为 8 路；实现 clock-enable 采样、边沿/电平/掩码触发、触发前后采样和 BRAM 环形缓冲。
- 实现 Raw 记录模式；本届不实现 RLE，Task 31 仅保留为赛后研究备忘。
- 实现独立 `logic_analyzer_mmio` wrapper，通过 Task 15 预留的 Application MMIO 窗口连接，不向 Core 增加任何端口或地址。
- 编写裸机 C 驱动，完成配置、Arm/Stop、状态查询、数据读取以及 UART/SPI 捕获数据解析。
- 经基础 UART 外设输出原始数据、解析结果和元数据；Python 上位机显示波形、触发位置、协议帧并导出 VCD。
- 建立可重复 GPIO/UART/SPI 物理引脚回环激励，支持现场修改数据、速率和触发条件而不重新综合。
- 为每个外设子模块、MMIO wrapper、软件驱动、上位机和 SoC 闭环建立自动测试或可重复板级测试。
- 保存加入应用前后 Core 源文件清单/校验值，证明应用集成没有修改 Pipeline Core。

#### 验收标准

- 已知、边界和伪随机输入在不同采样间隔下均被逐样本正确捕获。
- 上升沿、下降沿、电平/掩码触发以及触发前后样本位置全部自动 PASS。
- Raw 数据与已知激励逐样本一致，覆盖静态、低翻转、高翻转和伪随机波形。
- RISC-V 软件正确解析规定 UART/SPI 帧；UART 输出、Python 波形、VCD 和 BRAM 原始内容一致。
- 随机背压、Reset、Overflow、连续至少 20 次采集无死锁、丢样或重复 MMIO side effect。
- RAM-only、基础 UART/GPIO、逻辑分析仪三种 SoC 配置使用同一份 Pipeline Core；完整 Regression、CoreMark 和提交级 trace 保持 PASS。
- 报告最高稳定采样频率、8 路通道、触发延迟、Raw 深度、UART 吞吐以及三种 SoC 配置的资源/Fmax。
- 不得增加 16 通道、I²C、协议感知/多级复杂触发、外部 DDR 或复杂 GUI；范围审计不通过则本任务 FAIL。
- 演示流程、Reset 步骤、输入条件、预期结果、故障恢复和 3 分钟视频素材均已形成项目文件。

#### 通过条件

- `docs/application_logic_analyzer.md` 的 P0、自动化验证和必需量化指标全部完成；RLE 不属于本任务通过条件。
- 端到端 Demo 可重复，RISC-V 控制面与 FPGA Capture Engine 数据面分工清楚、可解释。
- 应用集成没有破坏 Baseline Regression、CoreMark、Timing 或资源可接受性。
- Core 不含逻辑分析仪专用端口、地址和状态；应用没有修改 IF/ID/EX/MEM/WB、Hazard、Forwarding、Stall 或 Flush。

---

## 阶段 P3：高阶项①——DDR3 真实后端 + 行式突发 + 2 路组相联 Cache

> **范围依据**：`AGENTS.md` §1.14（2026-09-29 经用户批准的范围变更）。
> **执行细则与止损**：`docs/handoff_next.md` §3.3。
> **接口契约**：`docs/interfaces.md` §5.1；存储层次与实测数字：`docs/architecture.md` §3.1。

### P3.S1 DDR3 打通（**已完成 2026-09-29**）

**验收条件（已全部满足）**：

- [x] PDS 全流程 `compile → … → gen_bit_stream` **0 error**；
- [x] **时序全部满足**（Slow 角 Setup WNS **+0.367 ns**、Hold WHS **+0.044 ns**，失败端点 0）；
- [x] 实板验收 `S1 DDR3 SMOKE BOARD PASS`：`DDR3 初始化完成` / `DLL 锁定` /
      心跳翻转 / 无校验错误 / **BIST 错误计数全程为 0** / BIST 状态机在推进；
- [x] 已知偏差如实记录：状态寄存器 `pll_lock` 位恒为 0（判定该位不可信，见 `docs/ddr3_s1_survey.md` §2.4.2）。

**未覆盖**：`test_ddr` 例程只做 BIST，**没有吞吐/延迟数字**；要报"真实后端性能"需另加带计数器的访问器。

### P3.S2 行式突发接口（**已完成 2026-09-29**）

**验收条件（已全部满足）**：

- [x] Core 侧端口与 `docs/interfaces.md` §2 语义**一字未改**（`rtl/pipeline_cpu.v` 哈希仍为 `B58496706686E37B…`）；
- [x] 突发只发生在 Core 外部的适配器 ↔ 存储之间（`rtl/soc_line_burst_adapter.v`）；
- [x] 功能 TB 10/10 PASS（命中/未命中/跨行/背压/复位/越界/写直通）；
- [x] **量化证据**：24 次读（3 整行 × 8 字顺序）下游总线周期 **48 → 30（−37.5%）**、
      请求数 **24 → 3（−87.5%）**，前提校验"两种模式填充次数相同"PASS；
- [x] **止损未触发**（规则要求"无下降则停"，实测下降 37.5%）；
- [x] Trap 契约 99/99 PASS；`run_final_regression.ps1` `ALL AUTOMATED FINAL REGRESSION PASS`。

### P3.S3 2 路组相联 I-Cache（**模块完成；集成后净收益为负，按止损回退，默认关闭**）

**参数**：2 路 × 32 组 × 32 B = 2 KB，带 Off 开关。

**已完成**：`rtl/soc_icache_2way.v` + `tb/tb_soc_icache_2way.v`（**26 项 PASS**）。
模块级量化（慢后端）：命中率 87%、下游请求 −87.5%、下游总线周期 −70%、Core 等待 −50%。
覆盖命中/冲突 miss/跨行/替换/背压/复位/出错行不缓存/越界/Off 直通。

**止损触发（实测）**：接进取指路径后 CoreMark **1,251,724 → 2,891,324 拍（慢 2.31 倍）**。
根因：`rtl/pipeline_cpu.v` 第 727–741 行的"响应接收 + 新请求接受同拍交接"让**零等待**后端
每拍取一条，而本 Cache 命中响应是**寄存**的，每次取指 1 拍 → 2 拍。

**处置**：`ENABLE_ICACHE` 与 `CACHE_EN` **默认 0**；未重新出版本；模块保留但不接入。
**未闭环**：零气泡（组合）命中路径——本会话尝试三次均失败（见 `docs/debug_log.md`）。

### P3.S4 2 路组相联 D-Cache（**已完成并闭环：功能正确；当前后端下无净收益，按止损默认关闭**）

**参数**：2 路 × 32 组 × 32 B = 2 KB，写穿 + 写缓冲，带 Off 开关。

**已完成**：`rtl/soc_dcache_2way.v` + `tb/tb_soc_dcache_2way.v`（**19 项 PASS**）。

**四项必做功能均已验证**：

- [x] **写穿 + 写缓冲**（不做写回）：写命中就地合并进行并写穿到下游；写未命中不分配；
      单条目写缓冲，占满时让 Core 等待；
- [x] **MMIO 强制绕行**：`> CACHEABLE_LAST_ADDR`（默认 `0x0000_FFFF`）一律不进 Cache，
      不查表/不分配/不更新；用"写 MMIO 再读回"验证副作用未被缓存；
- [x] **Store→Load 转发**：写缓冲里未落盘的字节按 `wstrb` 覆盖读回值（两条来源都覆盖）；
- [x] 字节写按 `wstrb` 逐字节合并（未选中字节保持原值）；
      另覆盖：读未命中行填充、同行命中、2 路冲突仍命中、复位重填、越界 error。

**量化（并给出前提）**：

| 后端 | 配置 | 下游读请求 | 下游总线周期 |
|---|---|---|---|
| 慢（读首拍 4 拍） | Off | 32 | 192 |
| 慢 | **On**，命中率 90% | **3（−90%）** | **39（−79%）** |
| **零等待** | Off（对照） | 32 | 64 |

**已知边界（如实记录）**：上表的量化用的是**行填充式慢后端模型**，不是 CoreMark 实数。

**2026-09-29 第九轮：S4 已闭环，端到端结论如下（这一节是最终口径）**：

- **功能正确性已证明**（这是本项最关键的进展）：①**影子内存逐笔比对零错读**
  （每笔被 Core 接受的数据读都与同一份 `coremark_dmem.mem` 的影子比对）；
  ②**UART 日志逐行对比**（基线 vs D-Cache）**只有计时/性能行不同**，
  所有 CRC、`Correct operation validated.`、`COREMARK_DONE` **逐字相同**，`bytes` 同为 655。
  集成过程中修掉三个真 bug（TB 并联接线 4 根网双驱动 → `x`；MMIO 直连读锁存位置 + 适配器无视 `m_rd_len`；
  **不可缓存读未门控 `cacheable_q` 而写坏数据阵列**），见 `docs/debug_log.md` 第七~九轮。
- **端到端收益：无**。零等待 BRAM 后端下 **1,251,724 → 1,348,302 拍（+7.7%，净亏）**。
- **因此按本节止损规则触发「Cache Off/On 无净收益」→ 默认关闭（`ENABLE_DCACHE=0`），
  不得宣称端到端收益。** 与 S3 同源：Cache 的收益完全取决于后端有多慢；
  当前片上 BRAM 比"Cache 命中"还快，前提不成立。要兑现必须先把 **DDR3/HMIC 行突发后端真正接进 SoC**
  （S1 只证明了板级连通）。

### P3 总止损线与降级方案

- **止损**：突发无周期收益 → 停（**S2 已排除**）；Cache Off/On 无净收益 → 回退
  （**S3 已触发并回退**）；时序违例 → 回退；任何 Trap / CoreMark / 应用回归退化 → 回退到最近通过版本。
- **降级**：DDR3 打不通时把行式突发实现在片上 BRAM 后端（宽 BRAM + 多拍），
  可交付 Cache 与 Off/On 数字，但按清单口径**只能算原型，不能宣称完成官方整组**。
  **注**：S1 已在实板跑通，本降级路径当前不需要。

## 阶段 K：赛后研究备忘与最终交付

### 任务 31（赛后冻结）：实现并量化 RLE

**优先级：赛后研究，不属于本届交付**

**前置任务：本届 `competition_final` 已冻结并完成提交，且用户重新立项**

#### 目标

在不改变 Raw P0 数据路径和 Core/SoC 边界的前提下，为逻辑分析仪增加可关闭的无损 RLE，量化静态和低翻转波形的等效深度收益。

#### 需要学什么

- 游程编码、最大游程分裂、最坏情况膨胀和 Raw 回退。
- 压缩比、资源/Fmax 代价和 Round-trip 验证。

#### 需要实现什么

- 增加可关闭的 `rle_encoder`，记录 `(sample_value, run_length)`，保留 Raw 模式。
- 明确记录格式、最大游程、Overflow 和模式切换语义。
- 提供软件解压器或参考模型，自动证明 `decompress(compress(input)) == input`。
- 对静态、低翻转、高翻转和伪随机输入比较压缩率、资源和 Fmax。

#### 验收标准

- 最大游程、游程分裂、高翻转、Overflow、Reset 和模式切换测试全部 PASS。
- Raw 与 RLE 解压后的样本和触发位置完全一致。
- 加入 RLE 后 P0 Regression、CoreMark 和 Timing 保持 PASS。

#### 通过条件

- Round-trip、完整 Regression 和板级演示全部 PASS，并形成 Before/After 数据时，RLE 才能进入赛后研究基线。
- 任一条件失败时不得冻结赛后 RLE 研究基线；无论结果如何，均不得修改本届 `competition_final`。

### 任务 32：16 项 BTB + 2-bit 预测性能实验

**优先级：P0，最终完善项**

**前置任务：Task 28 CoreMark 基线和 Task 30 应用闭环；不依赖任务 31**

#### 目标

在不改变 architectural state 和 Core/SoC 接口的前提下，实验 16 项直接映射 BTB + 2-bit 饱和计数器能否改善 CoreMark/MHz。BTB 单项不得宣称完整完成官方“高级控制逻辑”。

#### 需要学什么

- Prediction、resolution、speculation 与 retirement。
- BTB valid/tag/target/index/alias、2-bit 状态和 misprediction recovery。
- Prediction Accuracy、Branch Penalty、CPI、Fmax 与资源效率的共同权衡。

#### 需要实现什么

- 保留 Predictor Off / Always-Not-Taken Baseline；实现仅预测条件 Branch 的 16 项 BTB。
- 正确处理 hit/miss、tag alias、target 更新、Reset、Stall/Flush 冲突和错误目标恢复。
- 增加 prediction、BTB hit 和 misprediction 事件，并由 Core 外部性能监视器计数。
- 用相同软件、频率和内存配置完成 Off/On CoreMark、资源、Timing、ILA 和 Regression 对比。

#### 验收标准

- Predictor 单元测试、Branch/Hazard Regression 和提交级 trace 全部 PASS。
- 错误路径无寄存器、RAM、MMIO 或外设 side effect。
- Off/On CoreMark 均运行不少于 10 秒，记录准确率、CPI、CoreMark/MHz、LUT、FF、Fmax 和 Slack。

#### 通过条件

- Predictor On 的完整 Regression、Timing 和板级运行全部 PASS，且 CoreMark 周期具有可复现正收益时，才允许进入最终候选配置。
- 任一条件失败则最终配置退回 Predictor Off Baseline，并保留实验记录。

### 任务 33：最终系统 Regression 与范围审计

**优先级：P0**  
**前置任务：任务 30 与任务 32；任务 31 本届固定跳过**

#### 目标

在制作参赛材料前冻结唯一可提交系统，证明 RV32I、流水线、基础外设、CoreMark 和逻辑分析仪 P0 全部可恢复、可重复，并确认本届冻结和明确不做的功能没有进入最终配置。

#### 需要学什么

- Release Candidate、配置矩阵和可追溯构建。
- 功能范围审计与避免无意过度宣称。
- 源文件清单、校验值、工具版本和 bitstream 对应关系。

#### 需要实现什么

- 建立 P0 Baseline、RAM-only、UART/GPIO、逻辑分析仪的最终配置矩阵；不得加入 RLE/BTB 配置。
- 一次性运行 RV32I、单周期、Pipeline、Hazard、GCC、MMIO、UART/GPIO、逻辑分析仪 P0、CoreMark 和提交级 trace Regression。
- 上板连续执行 CoreMark、GPIO/UART Demo 和至少 20 次逻辑分析仪采集。
- 保存 RTL、约束、软件、测试镜像、bitstream、PDS 报告和工具版本校验值。
- 审计工程与材料，确认没有 I/D Cache、burst、异常/中断、AI、DDR、HDMI、PCIe、千兆网、自定义指令、16 通道、I²C 或复杂触发/GUI 的实现与声明。
- 比较三种 SoC 配置的 Core 源文件清单/校验值，确认外设变化没有修改 Core。

#### 验收标准

- 所有配置自动输出明确 PASS/FAIL，任一失败时 Release Candidate 失败。
- 多次构建与运行结果一致，工具、镜像和 bitstream 可对应。
- 错误路径、随机背压和 Reset 不产生重复或丢失 side effect。
- 最终提交配置、本届冻结/删除功能及其范围理由已经记录。

#### 通过条件

- 完整最终 Regression、CoreMark、Timing 和板级压力测试全部 PASS。
- 范围审计无违规功能、无未解释警告、无过度宣称。
- `competition_release_candidate` 或等价版本可恢复。

### 任务 34：完成技术报告、演示视频与答辩证据

**优先级：P0**  
**前置任务：任务 33**

#### 目标

把已经通过验证的系统整理为可评审、可复现、不过度宣称的国赛材料，突出基础任务完整性、CoreMark 三项性能指标、Core/外设解耦、逻辑分析仪应用和 ILA 性能分析；本届材料不展示 RLE/BTB。

#### 需要学什么

- 技术报告的证据链、图表表达和复现信息。
- 3分钟演示视频的叙事结构与现场答辩节奏。
- 如何用 PDS ILA、提交级 trace 和性能计数器解释流水线。
- 如何区分“已实现并验证”“实验结果”和“明确未实现”。

#### 需要实现什么

- 完成系统框图、五级流水数据通路、Core/SoC边界、16 项 BTB 和逻辑分析仪数据流；不加入未实现的 RLE 结构图。
- 整理模块层级、关键状态机与流水控制注释，解释时钟/Reset/IO 约束和主要时序路径，满足赛题的代码规范与时序约束说明要求。
- 汇总RV32I覆盖、Regression、CoreMark/MHz、CPI、Fmax、Slack、LUT/FF/BRAM和CoreMark/LUT。
- 加入 CoreMark 关键循环的 PDS ILA 波形，解释 Forwarding、Stall 和 Flush。
- 汇总逻辑分析仪采样频率、触发延迟、Raw 深度、UART 吞吐及软硬件采样对比；不报告未实现的 RLE 压缩比。
- 制作3分钟演示视频：作品定位、CPU证据、现场可变输入采样、协议解析、量化结果和解耦证明。
- 准备答辩问题：RV32I、Hazard、Reference Model、CoreMark、Timing、MMIO 解耦、逻辑分析仪和 BTB Before/After；明确 RLE 冻结为赛后研究，BTB 不等同于完整高级控制逻辑。
- 所有材料明确列出删减项，不出现Cache、异常中断、AI等未实现功能的暗示。

#### 验收标准

- 报告中每个关键结论都能追溯到日志、波形、报告或自动测试。
- 核心模块职责清楚、关键控制和非显然时序具有有效注释，约束文件无未解释路径。
- 视频不依赖剪辑掩盖失败，现场演示步骤与视频一致。
- 图表中的频率、资源、程序镜像和最终功能开关配置一致。
- PDS ILA与作品逻辑分析仪用途区分清楚。
- 作品名称和简介与 `docs/application_logic_analyzer.md` 的报名版本一致。

#### 通过条件

- 技术报告、演示视频、答辩PPT和复现说明完成内部核对。
- 无无法复现的数据、无未验证声明、无Core/外设耦合表述。
- 材料所用Release Candidate与任务33一致。

### 任务 35：最终提交冻结与现场演示复盘

**优先级：P0**  
**前置任务：任务 34**

#### 目标

冻结最终提交包和现场演示版本，保证换电脑、断电、重复Reset或输入条件改变后仍能按文档恢复和演示。

#### 需要学什么

- 最终版本冻结、校验值、备份与回退。
- 现场故障树、最小恢复路径和备用演示策略。
- 答辩中准确陈述实现边界和量化结果。

#### 需要实现什么

- 冻结RTL、Testbench、软件、Python上位机、约束、bitstream、报告、PPT、视频和复现说明。
- 保存最终文件清单、校验值、工具版本、板卡、引脚、电源、串口和跳线连接图。
- 准备稳定的逻辑分析仪 P0 主 bitstream，并保留已经验证的 `pipeline_coremark_stable` 诊断 bitstream；两者均必须来自已通过对应 Regression 的冻结配置。
- 在干净环境执行从构建、下载、Reset、CoreMark到逻辑分析仪采集的完整复现。
- 至少完成三轮计时答辩演练和现场故障恢复演练。
- 冻结后只允许修复阻塞性Bug；任何修改必须重跑任务33的完整Regression并重新生成校验值。

#### 验收标准

- 提交包在另一台符合工具要求的电脑或干净目录可按说明恢复。
- 多次断电、Reset和重新连接串口后演示结果一致。
- 现场可修改UART/SPI数据、速率和触发条件，无需重新综合即可正确采集。
- 主版本失败时能切换已验证备用版本，不使用未验证临时代码。
- 作品名称、简介、代码、bitstream、报告、PPT和视频版本完全对应。

#### 通过条件

- `competition_final` 或等价不可混淆版本已冻结并至少双份备份。
- 最终清单中的测试、报告、视频和现场演示全部复核PASS。
- 没有遗留必须由用户临时决定的功能、接口、版本或演示步骤。

---

## 三、阶段 Gate 汇总

| Gate | 任务范围 | 必须达到的出口条件 |
|---|---:|---|
| G0 项目基线 | 0 | 文档、工具和板卡/远程平台验证路径可让新聊天恢复项目 |
| G1 基础认知 | 1～3 | 能解释 CPU/ISA/微架构、拆指令、完成 C 到机器码链路 |
| G2 基础模块 | 4～10 | 所有基础模块独立 Testbench PASS，PDS/目标器件/BRAM 冒烟验证 PASS |
| G3 最小单周期 | 11 | 最小程序执行后 `memory[0] = 15` |
| G4 单周期候选基线 | 12～13 | 完整 RV32I 定向/architectural tests PASS，候选 Reference Model 和提交级 trace 可复现 |
| G5 基础 SoC | 14～16 | GCC、MMIO、UART TX/RX、GPIO 和随机背压全部 PASS；Core/SoC 接口已冻结，RAM-only/UART/GPIO 配置复用同一 Core |
| G6 最终单周期基线 | 17 | 正式 Regression 全部 PASS，`single_cycle_stable` 与提交级 trace 已冻结 |
| G7 流水线基础 | 18～19 | 无 Hazard Pipeline 的最终状态和提交级 trace 与 Reference Model 一致；流水线 Core 不含地址译码或外设专用逻辑 |
| G8 Hazard | 20～23 | Forwarding、Stall、Flush、交叉 Hazard 与提交级对比全部 PASS |
| G9 Pipeline/FPGA | 24～27 | GCC Pipeline、性能计数器、Timing 和板级验证全部 PASS |
| G10 性能基线 | 28～29 | CoreMark 运行不少于 10 秒，ILA/性能报告完整，Baseline 已冻结 |
| G11 逻辑分析仪应用 | 30 | Raw P0、UART/SPI 解析、Python/VCD、连续 20 次采集和必需量化报告全部 PASS；三种 SoC 配置复用同一 Pipeline Core |
| 赛后研究 | 31 或 32 | 本届冻结，不进入 Gate、最终配置或参赛材料；仅在 `competition_final` 后重新立项 |
| G13 最终系统候选 | 33 | P0 全配置 Regression、CoreMark、Timing、板级压力和范围审计 PASS；本届冻结/删除功能不进入最终配置 |
| G14 参赛交付 | 34～35 | 报告、PPT、视频、复现包、最终 bitstream、必要时的备用 bitstream 和现场演练完成，最终版本冻结且可恢复 |

## 四、当前起点

项目必须从 **任务 0：建立项目骨架与可恢复开发基线** 开始核对。任务 0 通过后，进入 **任务 1：建立 CPU 最基础认知**。

在 `docs/progress.md` 明确记录当前任务之前，不得根据聊天记忆假设任何任务已经完成。
