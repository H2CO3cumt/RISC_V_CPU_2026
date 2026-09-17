# Architecture Decisions

> 最后更新：2026-09-14
> 当前状态：Task 23 Hazard、Task 24 GCC Pipeline、Task 25 性能监视器、Task 26/28/30 PDS 与 Task 30 自动化 Raw 应用闭环已通过；实体板 CoreMark、物理回环和 PDS ILA 证据需在设备连接后采集。

本文件记录会影响多个模块、软件或验证流程的重要架构决定。尚未到达对应 Gate 的内容只记录约束和待验证项，不提前实现。

## 1. ISA 与软件约束

- 处理器目标固定为 RISC-V Unprivileged ISA `v20240411` 的 RV32I Base Integer ISA `Version 2.1`；本届仅实现本文件和 `docs/task12_instruction_coverage.md` 明确的范围。
- GCC 固定使用 `-march=rv32i -mabi=ilp32`；Windows 当前采用 xPack `riscv-none-elf-` 前缀，并通过 `RISCV_PREFIX` 引用。优化级别、链接选项和 `libgcc` 使用情况随测试镜像一并记录。
- 未声明支持 `M`、`C` 或其他扩展；反汇编出现相关指令时不得由 Testbench 或软件静默绕过。
- 非对齐访问、`FENCE`、`ECALL`、`EBREAK` 等行为在 Task 12 的指令覆盖表中明确。
- `FENCE`（`opcode=0001111`、`funct3=000`）在无 Cache、写缓冲、乱序或并发 I/O 事务的行为级单周期模型中作为保守 no-op 执行：不写 RegFile、不访问 DMEM、PC 顺序加 4。`pred`、`succ`、`fm`、`rs1` 与 `rd` 均不改变此行为，符合简单实现可采用保守 Fence 的约束。
- `FENCE.I`（Zifencei）、`ECALL`、`EBREAK`、CSR 与其他 SYSTEM 编码不在当前 Core 支持范围；译码输出 `illegal=1`，无 RegFile/DMEM/控制流副作用，PC 顺序加 4。该策略不是 RISC-V trap 或 debug 支持；软件不得依赖它，正式异常/中断接口不属于本届范围。

## 2. Reference Model 与验证策略

- 单周期 CPU 是 Pipeline 的 architectural Reference Model。
- Task 13 只建立 `single_cycle_reference_candidate` 和提交级接口。
- Task 17 在 RV32I、GCC、MMIO、UART/GPIO 与正式 Regression 全部 PASS 后冻结 `single_cycle_stable`。
- Single Cycle 与 Pipeline 必须同时比较最终 `x1`～`x31`、关键 RAM 和提交级 trace。
- 提交级 trace 最少包含：`valid`、`pc`、`instruction`、`rd_we`、`rd_addr`、`rd_data`、`mem_we`、`mem_addr`、`mem_data`、byte enable。
- Debug 时报告第一条不一致提交，并沿 `IF -> ID -> EX -> MEM -> WB` 查找第一个错误周期和信号。

## 3. Memory 与 FPGA 实现边界

- 单周期 Reference Model 可使用行为级组合读 IMEM/DMEM，以保持参考模型简单明确。
- 行为级 IMEM 使用 32-bit 字节地址，`addr >> 2` 选择 word；RV32I 非压缩取指必须满足 `addr[1:0] == 2'b00`。初始化先清零全部 word，再用 `$readmemh` 加载 GNU objcopy `-O verilog --verilog-data-width=4` 生成的镜像；非对齐或越界读取返回零。
- 行为级 DMEM 组合返回包含目标地址的完整 32-bit word，在时钟上升沿按 `wstrb[3:0]` 更新 byte lane；越界读取返回零，越界写入忽略。Load 的 lane 选择/扩展和 Store 的数据对齐由独立 Load/Store Unit 负责。
- 最终 FPGA Pipeline 必须使用与紫光同创 FPGA/PDS 实际 BRAM 读写时序一致的 wrapper。
- Task 10 必须通过目标器件、时钟/Reset、BRAM 读写、初始化和资源推断的 PDS 冒烟验证。
- 本届正式目标冻结为盘古 50（MES50HP）的紫光同创 Logos `PGL50H-6IFBG484`，系统时钟 `FPGA_GCLK_50M=P20` 为 50 MHz（20.000 ns），使用 PDS `.fdc`；平台和验证契约见 `docs/fpga_platform.md`。
- MES50HP 的 Reset 选择、按键/LED 极性和 CP2102 UART 管脚全部由 Core 外部 board wrapper/约束处理。默认 `USE_EXTERNAL_RESET=0` 使用内部上电复位；底板 `REST` 是专用固件重加载信号，CPU 人工复位只从低有效用户按键分配。
- 本届使用可综合片上 RAM/BRAM 完成稳定 Baseline，不实现 I/D Cache 或 burst；MMIO 始终属于 uncacheable 区域。
- Task 9 的当前非对齐策略为检测且不拆分事务：`LB/LBU/SB` 接受任意 byte 地址，`LH/LHU/SH` 仅接受 `addr[0]=0`，`LW/SW` 仅接受 `addr[1:0]=2'b00`。不满足对齐时 `misaligned=1`；Store 保持 `wstrb=4'b0000`，禁止任何写副作用。Task 12 再冻结软件可见的完整 ISA 行为。

## 4. Core / SoC 边界与应用场景

- 五级流水线 Core 与最终外设严格解耦。Core 只负责 RV32I 执行、IF/ID/EX/MEM/WB、Hazard 控制、统一取指/数据事务和提交/性能事件；完整契约见 `docs/interfaces.md`。
- 地址译码、MMIO 互连、RAM/BRAM、UART、GPIO、SPI、传感器、逻辑分析仪、加速器、厂商总线和板级引脚全部位于 Core 外。
- Core 中不得出现设备专用地址、片选、`busy/done` 或协议状态机。低速设备通过统一 `valid/ready` 背压让 Core 等待。
- 基础 SoC 的参考配置为 `RV32I Core + Interconnect + RAM + UART TX/RX + GPIO`，用于证明软件、MMIO 和板级链路，不代表 Core 固定依赖 UART/GPIO。
- 地址映射在 Task 15 固定于 SoC 互连层，任何区域不得重叠；未映射地址行为必须可测试，并预留一个通用 Application MMIO 窗口。调整外设地址不得修改 Core。
- Task 15 地址表冻结如下。地址按 byte 编址，区间首尾均包含；互连必须使每笔请求至多选中一个目标：

| 区域 | 地址范围 | 属性 | Task 15 行为 |
|---|---|---|---|
| RAM | `0x0000_0000`–`0x0000_03FF` | 普通内存 | 当前 256 × 32-bit 行为级 RAM；后续可替换为 BRAM wrapper。 |
| UART | `0x1000_0000`–`0x1000_00FF` | uncacheable MMIO | 预留给 Task 16 UART wrapper。 |
| GPIO | `0x1000_1000`–`0x1000_10FF` | uncacheable MMIO | 预留给 Task 16 GPIO wrapper。 |
| Application MMIO | `0x1000_2000`–`0x1000_2FFF` | uncacheable MMIO | 通用应用窗口；Task 30 才冻结逻辑分析仪寄存器 offset。 |
| 其余地址 | — | 未映射 | 互连接收请求并返回一次 `rsp_valid=1, rsp_error=1`；不选中任何真实目标，也不产生副作用。 |

- Task 15 的互连在请求握手时锁存唯一目标，直到对应响应握手结束前不接收下一笔请求；这个单 outstanding 限制符合第一版事务契约，避免响应返回时混淆来源。
- Task 16 只验证并冻结 Core/SoC 事务语义和基础互连方法。UART、GPIO 的独立与集成测试必须证明外设可替换，Task 16 不提前实现比赛应用。
- 比赛应用已经选定为“基于自研五级流水 RISC-V 的可重构多协议逻辑分析与故障诊断平台”。CPU 仅通过 MMIO 配置 Core 外部 Capture Engine，Raw 采样/触发数据保存在外设 BRAM，再由软件解析 UART/SPI 并经 UART 发送给 Python 上位机；本届冻结 RLE，完整范围见 `docs/application_logic_analyzer.md`。
- 报名页面作品名称固定为“RISC-V多协议逻辑分析仪”（14/15字符）；技术报告可使用上述完整名称。报名简介的唯一版本保存在 `docs/application_logic_analyzer.md`，后续修改必须同步检查500字符限制和未完成功能的措辞。
- 应用选择已经固定，但集成边界保持可替换：删除逻辑分析仪并换成 SPI、传感器或其他加速器时，只能修改应用外设、SoC 地址表和软件，不能修改 CPU Core。

## 5. Pipeline 与性能观察

- 最终基础架构采用经典 IF、ID、EX、MEM、WB 五级流水线。
- Hazard 按 Forwarding、Load-Use Stall、Branch/Jump Flush、复杂交叉场景依次实现。
- 错误路径指令不得产生寄存器、RAM 或 MMIO side effect，也不得生成有效提交事件。
- Core 输出 retire、stall、load stall、branch、taken branch 和 flush 等统一事件；优先由 Core 外部性能监视器完成 cycle/instret 等计数和 MMIO 映射，避免把软件可见外设接口耦合进流水级控制。
- CoreMark 前必须实现并验证 cycle、instret、stall、load stall、branch、taken branch 和 flush 计数器。
- CoreMark 正式运行不少于 10 秒；保留编译参数、镜像、bitstream、频率和报告的对应关系。
- Pipeline Baseline 冻结时必须保存 ILA 关键波形、CPI 分解、资源、时序、CoreMark/MHz 和 CoreMark/LUT。

### 5.1 Task 18 五级流水线字段与停顿约定

流水线固定为顺序发射、顺序退休的 `IF -> ID -> EX -> MEM -> WB`。所有对外存储访问继续遵循统一事务接口；MEM 级只表达通用读写事务，绝不包含 RAM、UART、GPIO 或应用外设的地址译码。

```text
 fetch_pc -> IF request/response -> IF/ID -> decode -> ID/EX -> ALU/compare -> EX/MEM
                                                        |                         |
                                                        +------ redirect ----------+
 EX/MEM -> generic D request/response -> MEM/WB -> register writeback + commit trace
```

冻结的流水寄存器字段如下：

| 寄存器 | 必须保存的字段 | 目的 |
|---|---|---|
| IF/ID | `valid`、`pc`、`instruction`、取指错误、预测命中/方向/目标 | 将已完成的取指响应和对应预测元数据送入译码；取指错误装入零指令并保留错误位。 |
| ID/EX | `valid`、`pc`、`instruction`、错误位、预测命中/方向/目标、`rs1/rs2 data`、`rs1/rs2/rd`、`imm`、`funct3`、ALU/写回/访存/控制流控制位 | 确保 EX 不依赖后续 IF/ID 的组合译码结果，并可用真实分支结果校验预测。 |
| EX/MEM | `valid`、`pc`、`instruction`、`alu result`、`store data`、`imm`、`rd`、`funct3`、RegWrite/MemRead/MemWrite/ResultSrc | 保持一笔通用数据事务所需字段，直到唯一响应完成。 |
| MEM/WB | `valid`、`pc`、`instruction`、`alu result`、`load result`、`imm`、`rd`、RegWrite/ResultSrc、Store trace 字段及访问错误位 | 唯一产生寄存器写回与提交级 trace 的阶段。 |

`valid=0` 是 Bubble，不能写寄存器、不能建立数据事务、不能产生有效提交。MEM 等待某笔已接受的数据事务响应时，EX/MEM 必须保持，前端停止推进；请求等待 `ready` 时所有请求字段保持稳定。Control redirect 在 EX 级产生：更年轻的 IF/ID 与 ID/EX 指令必须失效，已经接收但属于错误路径的取指响应必须丢弃。已在 MEM 级被下游接受的数据事务不可撤销，因而 redirect 不得影响比该控制流指令更老的 EX/MEM 指令。

Task 18 只冻结以上结构和时序边界。现有候选 RTL 中的 Forwarding、Load-Use Stall 和 Flush 控制不得提前宣称通过；这些功能分别由 Task 20、21、22 的独立定向回归验收。

## 6. 本届评分范围、高阶功能与删减边界

- 评分主线及取舍以 `docs/competition_scoring.md` 为准：完整 RV32I、五级流水线与 Hazard、UART/GPIO、CoreMark 三项性能指标、实际应用、ILA 分析和规范材料全部为 P0。
- 官方“高级控制逻辑”按“动态分支预测以及完整异常/中断”描述。本届不实现完整异常/中断，因此不会仅凭 BTB 宣称完整完成该高级任务。
- 最终流水线采用 16 项直接映射 BTB + 2-bit 饱和计数器，只预测条件分支；IF 携带命中、方向和目标元数据，EX 用真实结果恢复错误路径。
- 以 Predictor Off 为 Always-Not-Taken Baseline，统计 prediction、BTB hit 和 misprediction，并比较 Predictor Off/On 的 CoreMark 周期、CPI、LUT、FF 与 Fmax。
- BTB 单项不宣称完成官方“高级控制逻辑”；完整异常/中断仍不属于本届范围。
- 本届明确删除 I-Cache、D-Cache、burst、完整异常/中断、AI/YOLO、自定义指令、外部 DDR、HDMI、PCIe 和千兆网，不建立这些 RTL 分支，也不在材料中宣称支持。
- 接口文档保留 Cache/中断的未来解耦扩展原则，仅用于防止架构绑死，不表示本届计划实现。
- 逻辑分析仪 P0 固定为 8 通道、基础边沿/电平/掩码触发、前后采样、BRAM、Raw、UART/SPI 软件解析和简单 Python/VCD；本届冻结 RLE。16 通道、I²C、协议感知/多级触发、外部 DDR 和复杂 GUI 均删除。

## 7. 尚待对应 Gate 决定的项目

- 内部上电复位实现和 BRAM 实测结果：Task 10。目标器件、时钟、UART、按键/LED、J8、PMOD 管脚及电平均已由 MES50HP 手册确认；逻辑分析仪 8 路输入/输出映射已冻结，完整表见 `docs/fpga_platform.md`。
- RAM/MMIO 地址映射、单周期 adapter 和互连逐根信号名：Task 15。
- 流水寄存器字段、控制信号和流水线 Core 顶层逐根端口名：Task 18；接口语义必须保持与 `docs/interfaces.md` 一致。
- 逻辑分析仪 8 路物理输入和 8 路激励输出固定在 J8 隔行相邻脚对 `3/4、7/8、11/12、15/16、19/20、23/24、27/28、31/32`（输出奇数脚、输入偶数脚）。板外结果链路使用 CP2102 UART；不能用内部回环冒充物理闭环，也不得要求修改五级流水线主体。
- 赛后 RLE 的记录格式、最大游程和溢出策略：只有本届提交完成且 Task 31 被重新立项时决定。
- BTB 使用 `PC[5:2]` 索引、`PC[31:6]` 标签，在 EX 条件分支解析时更新；错误方向或错误目标均恢复到真实下一 PC，不改变 architectural state 或 Core/SoC 外设接口。

## 8. Task 30 应用层实现决策（2026-09-14）

- Capture Engine 使用系统时钟加 clock-enable，不生成新的采样时钟；默认 8 通道、256 条 Raw BRAM 记录。
- `application_mmio_mux` 将通用 Application 窗口分为性能计数器 `0x1000_2000..0x1000_20FF` 和逻辑分析仪 `0x1000_2100..0x1000_21FF`。两个设备均以单 outstanding `valid/ready` 响应，地址在设备接受请求时转成本地 offset。
- 逻辑分析仪读取采用显式 `READ_INDEX` + `READ_DATA`，不使用读后自增 side effect；因此随机响应背压不会重复或跳过样本。
- MES50HP 应用顶层的 `capture_ch`/`loopback_tx`、UART、LED 和内部上电复位均为 Core 外部板级端口。软件只访问普通 MMIO，Pipeline Core 源文件与基础 SoC 复用不变。
- PDS 顶层使用同步数组和固定深度 `.mem` 初始化 Task 30 IMEM/DMEM，PDS 将其映射到 DRM；`TASK30_SIM` 只改变相对文件路径，不改变存储器时序。正式固件为 `AUTOSTART=0` 的 UART 交互版本。
- `logic_analyzer_pattern_gen` 位于 Core 外，产生静态、计数器、UART 8N1 或 SPI mode 0 激励并送往 J8。采样输入也来自 J8 的相邻输入脚，实体演示用 8 根跳线逐对闭合输出/输入脚。
- Task 28 CoreMark 将 8192-word IMEM、4096-word只读数据和4096-word运行 RAM 分离成同步初始化 DRM。上电等待 `R` 再进入计时区间，避免串口连接延迟进入 CoreMark 时间。
