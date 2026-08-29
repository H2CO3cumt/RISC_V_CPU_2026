# Core / SoC Interface Contract

> 最后更新：2026-08-29  
> 当前状态：架构语义已确定；尚未开始 RTL，模块名和逐根端口名在 Task 15（单周期）与 Task 18（流水线）分别评审后冻结。

本文档定义 CPU Core 与 SoC、存储器、外设之间的稳定边界。目标是让 UART、GPIO、逻辑分析仪、传感器、SPI 或其他加速器可以在 Core 外部增加、删除或替换，而不重新设计 IF、ID、EX、MEM、WB、Hazard、Forwarding、Stall 或 Flush。

## 1. 分层边界

```text
                          +-------------------------------+
                          |        single/pipeline core   |
  instruction response <-| instruction transaction port  |
  instruction request  ->|                               |
  data response        <-| data transaction port         |
  data request         ->|                               |
  generic interrupt    ->| interrupt input (later Gate)  |
  commit/perf events   <-| trace and event outputs       |
                          +---------------+---------------+
                                          |
                         stable Core / SoC boundary
                                          |
       +------------------+---------------+-------------------+
       | instruction/data adapter + address decode/interconnect|
       +--------+---------+--------+---------+---------+-------+
                |                  |          |         |
              RAM/ROM            UART       GPIO      SPI / sensor /
                                                       logic analyzer /
                                                       accelerator
```

### Core 内部负责

- RV32I 指令执行、PC、Register File、ALU 和 Load/Store 语义。
- 单周期或 IF/ID/EX/MEM/WB 五级流水线数据通路。
- Forwarding、Load-Use Stall、Control Hazard、Branch/Jump Flush。
- 把取指和数据访问表达成统一事务，并正确等待事务完成。
- 提交级 trace 和与流水线行为直接相关的性能事件输出。
- 未来赛后异常/中断研究所需的精确 Trap 行为和通用中断输入扩展点；本届不实现。

### Core 外部负责

- RAM/ROM/BRAM 控制器、Cache、总线 adapter、地址译码和互连。
- UART、GPIO、SPI、传感器、逻辑分析仪、加速器及其寄存器。
- MMIO 地址表、设备片选、未映射地址响应和设备级等待状态。
- 厂商总线/IP 接口、时钟域转换、引脚和板级顶层。
- 可由 Core 事件驱动、再通过 MMIO 读取的性能监视器。

禁止在 Core 中出现 `uart_*`、`gpio_*`、`spi_*`、`sensor_*`、`capture_*` 或某个加速器专用端口、地址常量和状态机。外设变化只能影响 SoC 顶层、互连、外设 RTL、地址表和软件驱动。

换接 UART、GPIO、逻辑分析仪、传感器、SPI 或其他加速器时，只允许替换 Core 外部的 MMIO 从设备、adapter/wrapper、地址表和软件驱动；CPU Core 源文件、Core 顶层端口及 IF/ID/EX/MEM/WB 流水线主体必须保持不变。

## 2. 统一事务语义

第一版采用分离的取指端口和数据端口（Harvard 形式）。接口遵循 request/response 与 `valid/ready` 握手语义；首版允许每个端口最多存在一个未完成事务，以降低实现和验证难度。

### 2.1 取指事务

请求至少包含：

- `valid`：请求有效。
- `ready`：下游在本周期接受请求。
- 32-bit 字节地址 `addr`，RV32I 正常取指时按 4 字节对齐。

响应至少包含：

- `valid`：响应有效。
- `ready`：Core 在本周期接受响应。
- 32-bit 指令 `data`。
- `error`：未映射、访问错误或后续定义的取指故障。

### 2.2 数据事务

请求至少包含：

- `valid`、`ready`。
- 32-bit 字节地址 `addr`，保留有效地址的低两位。
- `write`：读/写方向。
- 32-bit 写数据 `wdata`。
- 4-bit 字节写使能 `wstrb`；`wstrb[n]` 对应对齐字地址 `{addr[31:2], 2'b00} + n` 的 byte lane。

响应至少包含：

- `valid`、`ready`。
- 32-bit 读数据 `rdata`。
- `error`：未映射、访问错误或后续定义的 Load/Store 故障。

数据采用 RV32I little-endian 语义。读响应返回包含目标地址的对齐 32-bit word，Core 根据 `addr[1:0]` 和 Load 类型完成 byte/halfword 选择与扩展；Store 时 Core 产生与 `SB/SH/SW` 对应的 `wstrb` 和按 byte lane 对齐的 `wdata`。下游不需要知道当前执行的是哪一种 RISC-V 指令。非对齐或跨 word 访问的支持策略由 Task 12 明确，接口本身不静默拆分事务。

## 3. 强制握手规则

1. 请求只在 `req_valid && req_ready` 的周期被接受。
2. `req_valid && !req_ready` 时，Core 必须保持地址、方向、写数据和字节使能不变。
3. 每个被接受的请求必须产生且只能产生一次响应；写响应表示完成确认，其 `rdata` 被 Core 忽略。第一版同一端口不得在上一事务完成前发出第二个事务。
4. 一次请求握手只建立一个写事务。目标 side effect 可以在下游稍后完成，但必须在成功响应前恰好发生一次；保持 `req_valid`、等待、Stall 或响应重放不得造成重复写。
5. 下游延迟只能通过统一握手令 Core 等待，不得向 Core 增加 `uart_busy`、`spi_done` 等设备专用控制信号。
6. 被 Flush 的错误路径指令不得发出数据事务；已经被下游接受的事务必须按架构规定完成或在发出前被阻止，不能依赖外设撤销 side effect。
7. `rsp_valid && !rsp_ready` 时，下游必须保持响应数据和错误标志稳定，直到响应被 Core 接受。
8. 请求和响应通路不得形成无法收敛的组合环；具体寄存切分在对应 Gate 结合时序报告决定。
9. Reset 后不得残留有效请求、响应或设备写 side effect。

对首个行为级单周期 Reference Model，可使用始终就绪、固定零/一拍响应的 adapter；该简化只属于测试/存储 adapter，不能改变上述 Core 边界。流水线版本必须能通过可变延迟和随机背压测试。

## 4. MMIO、地址译码与外设替换

- Core 只发出普通数据事务，不判断地址属于 RAM 还是外设。
- SoC 互连根据地址表选择唯一目标，并汇合目标的响应。
- 未映射地址、重叠区域和访问宽度错误由互连/目标 wrapper 按 Task 15 约定返回，不在流水线中硬编码。
- UART、GPIO 是基础 SoC 的参考配置，不是 Core 的组成部分。
- 替换或新增 SPI、传感器、逻辑分析仪或加速器时，只增加/替换目标 wrapper、地址区域和软件驱动；Core 源文件及其回归测试不得改动。
- 当前比赛应用已经选定为可重构多协议逻辑分析仪，其 Capture Engine、Trigger、BRAM 和 MMIO wrapper 均属于外设层；本届冻结的 RLE 即使赛后研究也只能位于外设层。具体功能以 `docs/application_logic_analyzer.md` 为准，且该应用规格不得覆盖或削弱本文的 Core/SoC 契约。
- MMIO 写必须精确且不可重复；具备 side effect 的读同样不得被预取、合并或重复。

## 5. 调试、性能与赛后扩展点

- 本届不实现 I/D Cache 或 burst。未来赛后如研究，I-Cache 只能位于取指端口与下级存储之间，D-Cache 只能位于数据端口与 SoC 互连之间，且不得改变 Core 事务语义。
- SoC 的地址属性表仍保留 cacheable/uncacheable 概念；所有 MMIO 区域始终为 uncacheable。
- Core 输出统一提交级 trace。具体 ILA、波形采集器或调试桥只观察这些输出，不反向侵入流水级控制。
- Core 输出 `retire`、`stall`、`load_stall`、`branch`、`branch_taken`、`flush` 等事件；外部性能监视器负责计数和 MMIO 映射。若后续有充分理由把计数寄存器放入 Core，仍不得引入任何外设专用依赖。
- 本届不实现异常/中断。赛后如研究，Core 仍只能接收通用中断源或聚合结果，不使用 UART/GPIO/SPI 专用中断端口；中断控制器和源映射属于 SoC。

## 6. 冻结与变更规则

- 本文当前冻结的是边界、事务字段和握手语义，不虚构 RTL 已实现或验证。
- Task 15 冻结单周期 Core adapter、地址表和互连的逐根信号名；Task 18 复核流水线是否复用同一语义，并冻结流水线 Core 顶层端口。
- 后续允许在 adapter 后连接简单 RAM、BRAM、Cache、厂商总线或外设互连，但不得让这些变化传播进流水线主体。
- Task 15 只在 SoC 地址表中预留通用 Application MMIO 窗口；Task 30 才冻结逻辑分析仪具体寄存器 offset。两次冻结均不得改变 Core 端口。
- 接口如需不兼容变更，必须先在 `docs/architecture.md` 记录原因、影响和迁移办法，并重跑 Core、互连和 SoC Regression。

## 7. 解耦验收矩阵

| 层级 | 必测内容 | PASS 条件 |
|---|---|---|
| Core | 通用存储模型、固定延迟、随机背压、Reset、Flush | 请求保持稳定；无丢失、重复事务；错误路径无 side effect |
| Interconnect | RAM/MMIO/未映射/边界/重叠防护 | 每次只选中一个目标，响应返回正确发起端 |
| Peripheral | UART、GPIO 及后续设备的独立协议测试 | 不依赖 Core 内部信号即可独立 PASS |
| SoC 组合 | RAM-only、RAM+UART/GPIO、RAM+UART/GPIO/逻辑分析仪 | 使用同一份 Core 源文件，换配置后原 Core Regression 保持 PASS |
| Reference 对比 | Single Cycle 与 Pipeline 运行同一程序 | 最终 architectural state 与提交级 trace 一致 |

只有同时满足以下条件，才能宣称 Core/外设已解耦：

1. Core 顶层没有设备专用信号、地址和逻辑。
2. 至少三种 SoC 组合复用完全相同的 Core 源文件。
3. 可变延迟/背压不会造成重复或丢失 Load/Store/MMIO 事务。
4. 新增或替换外设不需要修改 IF/ID/EX/MEM/WB、Hazard、Forwarding、Stall 或 Flush。
