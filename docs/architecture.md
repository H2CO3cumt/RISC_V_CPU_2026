# Architecture Decisions

> 最后更新：2026-08-29  
> 当前状态：Task 2，尚未开始 CPU RTL。

本文件记录会影响多个模块、软件或验证流程的重要架构决定。尚未到达对应 Gate 的内容只记录约束和待验证项，不提前实现。

## 1. ISA 与软件约束

- 处理器目标为 RV32I，具体 Unprivileged ISA 版本在 Task 12 固定并记录。
- GCC 固定使用 `-march=rv32i -mabi=ilp32`；Windows 当前采用 xPack `riscv-none-elf-` 前缀，并通过 `RISCV_PREFIX` 引用。优化级别、链接选项和 `libgcc` 使用情况随测试镜像一并记录。
- 未声明支持 `M`、`C` 或其他扩展；反汇编出现相关指令时不得由 Testbench 或软件静默绕过。
- 非对齐访问、`FENCE`、`ECALL`、`EBREAK` 等行为在 Task 12 的指令覆盖表中明确。

## 2. Reference Model 与验证策略

- 单周期 CPU 是 Pipeline 的 architectural Reference Model。
- Task 13 只建立 `single_cycle_reference_candidate` 和提交级接口。
- Task 17 在 RV32I、GCC、MMIO、UART/GPIO 与正式 Regression 全部 PASS 后冻结 `single_cycle_stable`。
- Single Cycle 与 Pipeline 必须同时比较最终 `x1`～`x31`、关键 RAM 和提交级 trace。
- 提交级 trace 最少包含：`valid`、`pc`、`instruction`、`rd_we`、`rd_addr`、`rd_data`、`mem_we`、`mem_addr`、`mem_data`、byte enable。
- Debug 时报告第一条不一致提交，并沿 `IF -> ID -> EX -> MEM -> WB` 查找第一个错误周期和信号。

## 3. Memory 与 FPGA 实现边界

- 单周期 Reference Model 可使用行为级组合读 IMEM/DMEM，以保持参考模型简单明确。
- 最终 FPGA Pipeline 必须使用与紫光同创 FPGA/PDS 实际 BRAM 读写时序一致的 wrapper。
- Task 10 必须通过目标器件、时钟/Reset、BRAM 读写、初始化和资源推断的 PDS 冒烟验证。
- 当前目标板卡/器件尚未确定；实体板或远程实验平台最迟在 Task 10 前确定。
- 本届使用可综合片上 RAM/BRAM 完成稳定 Baseline，不实现 I/D Cache 或 burst；MMIO 始终属于 uncacheable 区域。

## 4. Core / SoC 边界与应用场景

- 五级流水线 Core 与最终外设严格解耦。Core 只负责 RV32I 执行、IF/ID/EX/MEM/WB、Hazard 控制、统一取指/数据事务和提交/性能事件；完整契约见 `docs/interfaces.md`。
- 地址译码、MMIO 互连、RAM/BRAM、UART、GPIO、SPI、传感器、逻辑分析仪、加速器、厂商总线和板级引脚全部位于 Core 外。
- Core 中不得出现设备专用地址、片选、`busy/done` 或协议状态机。低速设备通过统一 `valid/ready` 背压让 Core 等待。
- 基础 SoC 的参考配置为 `RV32I Core + Interconnect + RAM + UART TX/RX + GPIO`，用于证明软件、MMIO 和板级链路，不代表 Core 固定依赖 UART/GPIO。
- 地址映射在 Task 15 固定于 SoC 互连层，任何区域不得重叠；未映射地址行为必须可测试，并预留一个通用 Application MMIO 窗口。调整外设地址不得修改 Core。
- Task 16 只验证并冻结 Core/SoC 事务语义和基础互连方法。UART、GPIO 的独立与集成测试必须证明外设可替换，Task 16 不提前实现比赛应用。
- 比赛应用已经选定为“基于自研五级流水 RISC-V 的可重构多协议逻辑分析与故障诊断平台”。CPU 仅通过 MMIO 配置 Core 外部 Capture Engine，Raw 采样/触发数据保存在外设 BRAM，再由软件解析 UART/SPI 并经 UART 发送给 Python 上位机；RLE 只作为不阻塞交付的可选增强，完整范围见 `docs/application_logic_analyzer.md`。
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

## 6. 本届评分范围、高阶功能与删减边界

- 评分主线及取舍以 `docs/competition_scoring.md` 为准：完整 RV32I、五级流水线与 Hazard、UART/GPIO、CoreMark 三项性能指标、实际应用、ILA 分析和规范材料全部为 P0。
- 官方“高级控制逻辑”按“动态分支预测以及完整异常/中断”描述。本届不实现完整异常/中断，因此不会仅凭 BTB 宣称完整完成该高级任务。
- 16 项直接映射 BTB + 2-bit 饱和计数器仅保留为 P2 性能实验。只有任务 30 通过并形成稳定 P0 功能基线，且仍预留至少 7 个有效工作日时才能开始；最终交付不依赖 BTB。
- 若启动 BTB，必须保留 Always-Not-Taken Baseline，统计 prediction、BTB hit、taken、misprediction，并比较 Predictor Off/On 的 CoreMark/MHz、CPI、LUT、FF、Fmax 和错误预测率。
- 若 BTB 不能保持完整 Regression/Timing PASS，或性能收益不足以抵消资源/Fmax 代价，最终提交移除或关闭 BTB，只保留实验记录。
- 本届明确删除 I-Cache、D-Cache、burst、完整异常/中断、AI/YOLO、自定义指令、外部 DDR、HDMI、PCIe 和千兆网，不建立这些 RTL 分支，也不在材料中宣称支持。
- 接口文档保留 Cache/中断的未来解耦扩展原则，仅用于防止架构绑死，不表示本届计划实现。
- 逻辑分析仪 P0 固定为 8 通道、基础边沿/电平/掩码触发、前后采样、BRAM、Raw、UART/SPI 软件解析和简单 Python/VCD；RLE 为 P1 可选增强。16 通道、I²C、协议感知/多级触发、外部 DDR 和复杂 GUI 均删除。

## 7. 尚待对应 Gate 决定的项目

- 紫光同创 FPGA/开发板具体型号、PDS 版本、目标时钟、Reset 极性和引脚约束：Task 10。
- RAM/MMIO 地址映射、单周期 adapter 和互连逐根信号名：Task 15。
- 流水寄存器字段、控制信号和流水线 Core 顶层逐根端口名：Task 18；接口语义必须保持与 `docs/interfaces.md` 一致。
- 逻辑分析仪 8 路输入的物理引脚、最高采样目标和板外 UART 链路：Task 10 根据开发板能力确认，Task 30 实测冻结；这些决定不得要求修改五级流水线主体。
- 可选 RLE 的记录格式、最大游程和溢出策略：只有 Task 31 启动时决定。
- 可选 16 项 BTB 的 PC index/tag 位划分、更新时机和 Flush 恢复细节：只有 Task 32 启动时决定；不得改变 architectural state 或 Core/SoC 外设接口。
