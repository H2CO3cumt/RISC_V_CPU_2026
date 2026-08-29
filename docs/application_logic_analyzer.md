# 可重构多协议逻辑分析仪应用规格

> 最后更新：2026-08-29  
> 决策状态：比赛应用已选定；当前仍处于 Task 2，应用 RTL 只能在 Task 29 Baseline 冻结并进入 Task 30 后实现。  
> 架构约束：本应用是 Core 外部 MMIO 外设，任何功能都不得修改 IF/ID/EX/MEM/WB、Hazard、Forwarding、Stall 或 Flush。

## 0. 报名信息

### 作品名称（14/15）

`RISC-V多协议逻辑分析仪`

### 作品简介（410/500，按当前文本字符数）

本作品面向RISC-V处理器设计与数字系统调试场景，拟采用Verilog自主实现支持RV32I指令集的五级流水线CPU，包含IF、ID、EX、MEM、WB五级数据通路，并通过数据前递、Load-Use暂停及分支跳转冲刷处理流水线冒险。CPU核心仅通过统一取指/数据事务接口连接SoC，地址译码、RAM、UART、GPIO及逻辑分析仪均位于核心外部，可独立替换而无需修改流水线。系统以单周期CPU作为参考模型，使用自动回归、提交级trace、CoreMark、性能计数器和PDS ILA验证正确性、性能及资源效率。应用端构建8通道可重构多协议逻辑分析仪，由FPGA Capture Engine完成数字采样、边沿/电平触发及触发前后BRAM缓存；RISC-V软件通过MMIO配置外设、读取数据并解析UART/SPI协议，结果经UART发送至Python上位机显示波形、故障标记并导出VCD，体现软硬件协同与模块化扩展能力。

## 1. 作品定位

最终应用确定为：

> **基于自研五级流水 RISC-V 的可重构多协议逻辑分析与故障诊断平台**

以上为技术报告和答辩使用的完整名称；受报名页面15字符限制，报名作品名称统一使用“RISC-V多协议逻辑分析仪”。

系统用 FPGA Capture Engine 高速采集多路数字信号，用自研 RV32I CPU 通过 MMIO 配置采样、触发和缓冲，并通过软件解析 UART/SPI 数据，最后经 UART 发送给 Python 上位机显示波形、标记协议帧并导出 VCD。

该应用用于补齐“实际应用场景、软硬件协同和现场演示”，不能替代 RV32I、五级流水线、CoreMark、Timing、资源效率和 PDS ILA 性能分析主线。

## 2. 不可违反的系统边界

```text
                         +----------------------------+
                         |      pipeline_core         |
                         | IF / ID / EX / MEM / WB    |
                         | Hazard / Forward / Flush   |
                         +-------------+--------------+
                                       |
                         generic data transaction port
                                       |
                   +-------------------+-------------------+
                   |        SoC interconnect/MMIO          |
                   +------+----------+---------+-----------+
                          |          |         |
                         RAM        UART      GPIO
                                                   \
                                                    +----------------------+
logic inputs -> input register -> sample/trigger -> | logic_analyzer       |
                                                    | MMIO wrapper + BRAM  |
                                                    +----------------------+
```

### CPU Core 只负责

- 执行 RV32I 软件。
- 发出 `docs/interfaces.md` 定义的通用取指和数据事务。
- 在外设背压时按统一规则等待。
- 输出提交级 trace 和性能事件。

### 逻辑分析仪外设负责

- 数字输入寄存、采样使能、边沿检测和触发判断。
- 触发前/后数据保存和 BRAM 环形缓冲；本届只实现 Raw，RLE 仅保留为赛后研究。
- MMIO 控制/状态寄存器和采样数据窗口。
- 设备自己的 Busy、Done、Triggered、Overflow 状态。

### SoC 与软件负责

- SoC interconnect 完成地址译码、片选和响应汇合。
- 裸机 C 驱动配置外设、读取结果并解析 UART/SPI 帧。
- UART 外设承担结果传输；Python 上位机负责波形显示和 VCD 导出。

禁止把 `capture_busy`、`triggered`、采样数据、触发状态或应用地址送进 Core 顶层。CPU 只能通过普通 MMIO Load/Store 观察和控制该外设。

## 3. 冻结的功能范围

### 3.1 P0：必须完成的端到端闭环

- 模块保持参数化以便单元测试，但本届上板配置固定为 8 路，不实现或宣传 16 路版本。
- 使用系统时钟和 clock-enable 产生可调采样间隔，不为简单分频创建新的逻辑时钟。
- 支持上升沿、下降沿、电平值和通道掩码触发。
- 支持触发前/触发后采样以及 BRAM 环形缓冲。
- 支持 Raw 原始采样模式。
- CPU 可通过 MMIO 配置、Arm、Stop、查询状态、设置读指针并读取数据。
- RISC-V 裸机软件至少完成 UART 与 SPI 捕获数据解析，并输出帧边界、字节值和错误信息。
- UART 将原始采样、解析结果和元数据发送到 Python 上位机。
- Python 上位机只实现必要的数字波形、触发位置、协议帧显示和 VCD 导出，不开发复杂 GUI 框架。
- 提供可重复的板内 GPIO/UART/SPI 激励与物理引脚回环演示，不依赖人工制造不可复现波形。

### 3.2 赛后研究：RLE（本届冻结）

- 实现 RLE 无损压缩模式，记录 `(sample_value, run_length)`，并保留 Raw 模式作为最坏情况回退。
- 提供硬件解压参考模型或软件解压器，自动证明 `decompress(compress(input)) == input`。
- 统计压缩前/后样本数、压缩比和溢出状态。
- 对静态、低翻转、高翻转和伪随机波形分别报告压缩率，禁止只展示最有利样本。
- 对比 CPU 软件轮询采样与 Capture Engine 的无丢样最高输入频率，量化硬件并行采集收益。

本届 60 天国赛冲刺不启动 RLE，不创建对应 RTL，不进入 G11、最终配置或参赛材料。只有 `competition_final` 冻结并完成本届提交后，用户重新立项，才允许按本节开展赛后研究。Raw 模式构成本届完整应用；材料不得暗示已经支持压缩。

### 3.3 明确不做

- 不采集模拟电压，不宣称替代示波器。
- 不把本应用称为或替代 PDS ILA；PDS ILA 仍用于分析 CPU 内部 CoreMark 流水线行为。
- 不在应用中引入 YOLO、图像链路、PCIe、千兆网或大模型。
- 不实现 16 通道、I²C 解析、协议感知触发、多级复杂触发或复杂 GUI。
- 本届始终不接外部 DDR，不为了扩大深度破坏 BRAM 版本。
- 不为本应用增加自定义 RISC-V 指令，不修改 CPU Pipeline。

## 4. 外设内部模块建议

模块名在 Task 30 评审后冻结，职责现在固定如下；`rle_encoder` 不属于本届模块清单，仅在赛后重新立项 Task 31 时加入：

| 模块 | 职责 | 独立测试重点 |
|---|---|---|
| `capture_input` | 输入寄存、通道掩码、当前/上一采样值 | 边沿与掩码 |
| `sample_enable_gen` | 根据分频值产生单周期采样使能 | 周期、Reset、动态配置边界 |
| `trigger_engine` | 电平/边沿触发匹配 | 每类触发和多通道组合 |
| `capture_buffer` | BRAM 环形缓冲、前后触发计数 | wrap、触发位置、首尾样本 |
| `rle_encoder`（赛后） | 相同样本游程压缩 | 最大游程、频繁翻转、溢出、Round-trip |
| `logic_analyzer_mmio` | 控制、状态和数据窗口 | byte enable、背压、一次 side effect |
| `logic_analyzer_top` | 仅组合外设子模块，不实例化 CPU | 模式切换和端到端外设测试 |

所有模块使用 Verilog，并遵守项目的最小修改、独立 Testbench 和明确 PASS/FAIL 规则。

## 5. MMIO 寄存器语义草案

具体基地址由 Task 15 的 SoC 地址表预留，具体 offset 在 Task 30 RTL 前冻结。地址常量只能存在于 SoC 地址表、外设 wrapper 和软件头文件，不得进入 Core。

| 寄存器 | 软件可见语义 |
|---|---|
| `CONTROL` | Arm、Stop、软清除；本届无 RLE 模式位 |
| `STATUS` | Armed、Triggered、Done、Overflow；本届无模式切换状态 |
| `SAMPLE_DIV` | 采样使能间隔，非法值行为必须定义 |
| `CHANNEL_MASK` | 参与保存/显示的有效通道 |
| `TRIGGER_MASK` | 参与触发比较的通道 |
| `TRIGGER_VALUE` | 电平触发目标值 |
| `TRIGGER_RISE` | 上升沿触发掩码 |
| `TRIGGER_FALL` | 下降沿触发掩码 |
| `PRE_COUNT` | 触发前保留样本数 |
| `POST_COUNT` | 触发后继续采样数 |
| `TRIGGER_INDEX` | 触发样本在逻辑数据流中的位置 |
| `CAPTURE_COUNT` | 实际有效 Raw 记录数 |
| `READ_INDEX` | 数据窗口读指针 |
| `READ_DATA` | 读取一条 Raw 记录 |

必须明确每个寄存器的只读/只写属性、Reset 值、byte enable、写一清零和读 side effect。第一版优先让 `READ_INDEX` 显式递增，避免隐式读 side effect；若采用读后自增，必须用随机背压测试证明一次读取只自增一次。

## 6. 自动化验证矩阵

### 外设独立测试

- 固定、递增、翻转和伪随机输入的逐样本比对。
- 不同 `SAMPLE_DIV` 的采样间隔。
- 上升沿、下降沿、电平和掩码触发。
- 未触发、立即触发、缓冲区 wrap、前后触发边界。
- Raw 模式容量、Overflow 和 Stop/Reset。
- 赛后若重新立项 RLE：另行增加单样本、最大游程、游程分裂、高翻转输入和自动解压 Round-trip；不计入本届测试矩阵。
- MMIO 连续读写、byte enable、随机背压和 Reset；不得丢失或重复命令。

### SoC 集成测试

- 同一份 Pipeline Core 分别连接 RAM-only、UART/GPIO 和 UART/GPIO/逻辑分析仪配置。
- CPU 用 C 驱动完成配置、采样、读取、UART/SPI 解码和 UART 输出。
- 错误路径 Store 不得 Arm、Stop、清状态或移动读指针。
- 逻辑分析仪处于等待、采样、传输和 Overflow 状态时，Core Regression、GCC 程序和提交级 trace 保持 PASS。
- 构建清单或源码校验值证明增加应用前后 Core 文件完全相同。

### 上板验收

- GPIO/UART/SPI 激励经物理引脚回环后，采样数据与已知发送序列逐位一致。
- 现场改变数据、速率、触发边沿或触发值，系统无需重新综合即可由软件重新配置并正确采集。
- Python 上位机显示的样本数、触发位置和协议字节与 FPGA/软件日志一致。
- 多次 Reset 和连续至少 20 次采集结果一致，无死锁、丢样或重复 side effect。

## 7. 必须报告的量化指标

- Pipeline Core：CoreMark/MHz、Fmax、CoreMark/LUT、CPI、Stall/Flush Rate。
- Capture Engine：最高稳定采样频率、通道数、触发延迟、Raw 深度。
- 赛后若重新立项 RLE：另行报告典型/最坏压缩比、等效采样深度、额外 LUT/FF/BRAM 和 Fmax 影响；本届材料不报告压缩数据。
- SoC：纯 Core、基础 UART/GPIO、加入逻辑分析仪三种配置的 LUT/FF/BRAM/Fmax。
- 软硬件协同：CPU 轮询与硬件 Capture Engine 的最高无丢样频率和 CPU 占用对比。
- 数据链路：UART 有效吞吐、一次完整采集上传时间和上位机重建时间。

所有性能结论必须同时给出测试条件、编译参数、目标器件、时钟、输入模式、样本数量和 Before/After 数据。

## 8. G11 完成定义

只有以下项目全部满足，Task 30/G11 才能标记完成：

1. P0 全部功能具有独立自动测试且全部 PASS；RLE 不属于本届 G11 范围。
2. 裸机 C 驱动、UART/SPI 解析、UART 传输和 Python 上位机形成可重复闭环。
3. 已知激励、随机激励、随机背压、Reset 和连续采集测试全部 PASS。
4. 三种 SoC 配置复用完全相同的 Pipeline Core，原完整 Regression 与 CoreMark 保持 PASS。
5. 应用 RTL 不含 CPU 内部信号，CPU Core 不含任何逻辑分析仪端口、地址、状态和协议逻辑。
6. 资源、时序、采样、吞吐和软硬件对比数据完整；本届不要求且不展示 RLE 压缩数据。
7. 现场演示脚本、故障恢复流程、3 分钟演示视频素材和答辩证据形成项目文件，不依赖历史聊天。
