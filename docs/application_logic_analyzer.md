# 可重构多协议逻辑分析仪应用规格

> 平台迁移（2026-09-09）：正式硬件平台改为盘古 50（MES50HP）`PGL50H-6IFBG484`。本文中任何在线 DUT、PG2L200H、S2/S3、27 MHz 或 `AC26`/`AB26` 的历史描述均由 `docs/fpga_platform.md` 取代；应用范围、8 通道物理闭环要求和 Core 外设解耦边界不变。

> 最后更新：2026-09-16
> 决策状态：Task 30 RTL、MMIO、SoC 仿真、Python/VCD 工具与 PDS bitstream 已完成；自动化 20 轮采集/Reset 压力 PASS。实体板物理回环和板上连续采集仍未取得证据，不能标记 G11 完成。
> 架构约束：本应用是 Core 外部 MMIO 外设，任何功能都不得修改 IF/ID/EX/MEM/WB、Hazard、Forwarding、Stall 或 Flush。

## 0. 报名信息

### 作品名称（14/15）

`RISC-V多协议逻辑分析仪`

### 作品简介（436/500，按当前文本字符数）

> 版本说明（2026-09-17）：报名页采用 **B 版叙事稿**——偏应用闭环叙事，不写入具体量化数字，量化成绩（CoreMark/MHz、CPI、Fmax、BTB 条目数、通道数等）在技术报告、答辩 PPT 与"技术指标"栏中给出。不得在本简介中出现 RLE、压缩、Cache、异常/中断等本届冻结内容，也不得把逻辑分析仪写成 CPU 内部功能。

本作品面向RISC-V处理器设计与数字系统调试场景，用Verilog自主实现支持RV32I的五级流水线CPU，数据前递、Load-Use暂停、分支跳转冲刷与BTB动态分支预测共同处理流水线冒险；核心只通过统一的取指与数据事务接口连接SoC，低速外设统一以背压让核心等待，地址译码、RAM、UART、GPIO与逻辑分析仪全部位于核心之外，更换外设无需触碰流水线。正确性以单周期CPU为参考模型，由自动回归、提交级trace逐条比对与官方CoreMark校验守住，性能则靠性能计数器与PDS ILA实测波形解释流水线效率。应用端把可重构多协议逻辑分析仪做成完整闭环：FPGA采集引擎完成数字采样、电平与边沿触发和触发前后BRAM缓存，RISC-V软件经MMIO配置并读取原始采样，解析UART与SPI协议后由UART送往Python上位机，现场显示波形、触发位置与协议帧、标记帧错误并导出VCD，波形、速率与触发条件均可现场重构而无需重新综合，体现软硬件协同与模块化扩展能力。

## 1. 作品定位

最终应用确定为：

> **基于自研五级流水 RISC-V 的可重构多协议逻辑分析与故障诊断平台**

以上为技术报告和答辩使用的完整名称；受报名页面15字符限制，报名作品名称统一使用“RISC-V多协议逻辑分析仪”。

系统用 FPGA Capture Engine 高速采集多路数字信号，用自研 RV32I CPU 通过 MMIO 配置采样、触发和缓冲，并通过软件解析 UART/SPI 数据，最后经 UART 发送给 Python 上位机显示波形、标记协议帧并导出 VCD。

该应用用于补齐“实际应用场景、软硬件协同和现场演示”，不能替代 RV32I、五级流水线、CoreMark、Timing、资源效率和 PDS ILA 性能分析主线。

### 目标 FPGA 平台

- 本届正式平台冻结为 `docs/fpga_platform.md` 定义的 MES50HP：紫光同创 Logos `PGL50H-6IFBG484`、50 MHz、板载 CP2102 UART、8 个用户按键/LED 和 J8 扩展口。
- Capture Engine、输入选择、低有效转换和板级显示全部位于 Core 外；平台适配不得修改 Pipeline Core。
- MES50HP 手册已给出完整管脚与电平。为匹配实体接线，8 路回环使用 J8 隔行相邻脚对：输出 `J8-3,7,11,15,19,23,27,31`（`AB13,W11,Y10,Y12,U10,V9,W8,Y6`），输入 `J8-4,8,12,16,20,24,28,32`（`Y13,V11,W10,W12,T10,U9,V7,W6`），均为 3.3 V I/O。
- Task 10 只需按 `docs/fpga_platform.md` 的顺序建立 `.fdc`、连接跳线并完成实体板电气/回环冒烟；内部 pattern loopback 不能冒充物理闭环。

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

- 所有上板结果来自 MES50HP 的冻结配置，UART 实体板已验证 RX=`R8`、TX=`R9`；最终 UART 参数及其他约束只允许采用官方资料和实体板实测确认的值。
- GPIO/UART/SPI 激励经物理引脚回环后，采样数据与已知发送序列逐位一致。
- 现场改变数据、速率、触发边沿或触发值，系统无需重新综合即可由软件重新配置并正确采集。
- Python 上位机显示的样本数、触发位置和协议字节与 FPGA/软件日志一致。
- 多次 Reset 和连续至少 20 次采集结果一致，无死锁、丢样或重复 side effect。

## 6.5 A6 故障诊断闭环（2026-09-28 新增）

进阶任务包的 A6 要求"在现有逻辑分析仪上建立可控故障注入、Raw/VCD/解析结果与真值自动比较，
形成量化报告和现场步骤"。本节记录落地方式与判据。

### 6.5.1 闭环链路（全部复用现有 RTL，不新增外设）

```text
确定性通道源 ──┬──────────────────────────────► capture_engine（现有）──► Raw 流
              │                                        ▲
              └── 可控故障注入（第 N 个采样点翻转指定位）┤
                                                       │
   真值流 CLEAN + 引擎实见流 SEEN + 读出流 CAP ─────────┘
                            │
                            ▼
        python/logic_analyzer_fault_diag.py（独立判定 + 量化报告）
```

- Testbench：`tb/tb_logic_analyzer_fault_diag.v`，通道源是 8 位自由计数器（完全确定），
  触发条件为电平 `channels==0x40`、`pre=8`/`post=8`，因此采样窗口固定为触发点前后各 8 个样本。
  注入由宏 `TB_FD_INJ_TICK` / `TB_FD_INJ_MASK` 控制，**只影响一拍**。
- 判定器：`python/logic_analyzer_fault_diag.py`，只看日志，判定**四件事**——
  **采集保真**（CAP 逐样本等于 SEEN：不多、不少、不重排、不改值）、
  **VCD 链路保真**（用生产用的同一份 `python/logic_analyzer.py` 把采集流导出成 VCD，
  再解析回样本流，必须与 CAP 逐样本一致——覆盖"Raw → 上位机文本协议 → VCD"整条交付链路）、
  **定位**（CAP 与真值的首个差异的索引与通道位必须正好等于注入描述）、
  **不误报**（注入点落在窗口之外时必须报不出任何差异）。

### 6.5.2 四个场景与实测结果

| 场景 | 注入 | 期望 | 实测 |
|---|---|---|---|
| `post` | 第 60 个采样点翻转 `0x02` | 窗口内，定位到采集索引 4 / 通道 1 | 索引 **4**、掩码 `0x02` ✓ |
| `pre` | 第 57 个采样点翻转 `0x80` | 窗口内，定位到采集索引 1 / 通道 7 | 索引 **1**、掩码 `0x80` ✓ |
| `before` | 第 40 个采样点翻转 `0x04` | 窗口外（窗口是 56~72），不得报出差异 | 差异数 **0** ✓ |
| `none` | 不注入 | 采集流与真值完全一致 | 差异数 **0** ✓ |

四个场景的采集样本数都是 17（= pre 8 + 触发 1 + post 8），触发索引 8，无溢出；
**采集保真与 VCD 链路保真四个场景全部 PASS**（VCD 内同样是 17 个采样点、触发索引 8）。
逐场景报告还会给出**具体是哪一位翻转**，例如 `post` 场景：
采集索引 4（绝对采样点 60）、通道 1、真值 `0x3c` vs 采集 `0x3e`。
**采集保真四个场景全部 PASS**。

命令：`scripts\run_logic_analyzer_fault_diag.ps1` → `ALL LOGIC ANALYZER FAULT DIAG PASS (4 scenarios)`。
量化报告写入 `tmp/logic_analyzer_fault_diag/fault_report.md`（汇总表）与
`fault_report_<场景>.json/.md`（逐场景明细，含首个差异的索引、绝对采样点、通道位、
真值与采集值）。

### 6.5.3 现场步骤（接上实板 UART 后照此执行）

1. 下载交付位流：`scripts\program_board.ps1 -Config la50`（含 DebugCore 时加 `-UseDebugger`）；
2. 把待诊断信号接到 8 路采集输入，用上位机配置：`sample_div`、`channel_mask`、
   触发条件、`pre/post`，与本节的仿真配置保持一致以便对照；
3. `Arm` 后触发一次，通过 UART 把 Raw 流导出（协议见 §5 与
   `python/logic_analyzer_serial.py`）；
4. 用同一份 `python/logic_analyzer_fault_diag.py` 的判据思想做比较：把"已知正确的参考流"
   作为 CLEAN、"实际采集"作为 CAP，脚本会直接给出**首个差异的采样点序号与通道位**；
5. 把 `fault_report.md` 连同 VCD 一起归档：报告里"首个差异 + 通道掩码"就是故障定位结论。

**边界与纪律**：A6 只做"采集—定位—复现—回归"闭环，**不标称 AI 高阶任务**；
采样资源与时序不得因此退步（`capture_engine.v` 未被改动，PDS 结果见 `docs/progress.md` 时序表）。

## 6.6 上位机波形可视化链（2026-10-09 冻结）

上位机对评委可见的部分只有这一条链，三处产物必须同源：

```text
FPGA 采集 → 固件 UART 文本回包（LA RAW count=… trigger=… + 十六进制样本）
   ├─ scripts/logic_analyzer_capture.ps1   （零依赖：Windows 自带 PowerShell + .NET 串口）
   │      └─ <mode>_NN.{log,vcd,html} + 波形预览.html（自包含页面，双击即可看）
   └─ python/logic_analyzer_serial.py      （pyUI 路径：pyserial）
          └─ 同一套 {log,vcd,html}，并把每一轮通过 on_run 回调交给
             python/waveform_panel.py 的实时面板
```

- **页面模板只有一个**：`python/waveform_viewer.html`。PowerShell 采集器与 Python 上位机都用它，
  所以模板升级后必须用 `scripts\logic_analyzer_capture.ps1 -FromCaptures <采集目录>` 把
  `release/evidence/logic_analyzer_board_85m/` 下四个模式页与总览页**离线重建**，
  否则交付包里"板级实测波形页"会比模板旧一代（本轮实际发生过）。
- **判据与标注必须同源**：页面上框出的第 1 个字节，就是采集脚本判 PASS 用的那个字节；
  UART 的 `bit_samples` 也必须与采集时一致（85 MHz 非分段为 16，分段窗口为 10）。
  标注与判据不同源时，波形上标的字节会和"上位机报 PASS 的字节"对不上，比不标更坏。
- **可选字段按需透传**：`sample_ns`/`sample_hz`（时基未标定时页面**明说"未标定"**，不猜）、
  `decode`（协议 spec，页面自己重新解码）、`tag_names`（通道别名）、`segments`（分段接缝）。
  `python/logic_analyzer.py::write_waveform_page` 只在调用方给了字段时才写进页面——
  凭空补默认值会画出根本不存在的帧或时间轴。
- **交付包根目录的 `波形预览.html`** 由 `export_final_submission.ps1` 从
  `release/evidence/logic_analyzer_board_85m/波形预览.html` 复制而来；改成旧模板会让整份交付件
  退回"只有波形、没有协议标注"的观感。
- 测试入口：`scripts\run_waveform_viewer_test.ps1`（解析/时基/解码纯函数 + 真页面的
  绘制调用与光标 Δt）、`scripts\run_logic_analyzer_python.ps1`、`python\tests\test_waveform_page.py`、
  `python\tests\test_waveform_panel.py`。

## 6.7 镜像抓取：上位机发字符串、逻辑分析仪抓这根线（2026-10-10 新增）

### 6.7.1 为什么加这一条

原来的板级演示里，UART/SPI 模式抓的是 pattern_gen **重复发送的同一个字节**（UART=`0xA5`、
SPI=`0x3C`），而且窗口只有 240/85 个采样点：UART 页上只有 **1 条通道线、1.5 帧**，
SPI 页 1 个字节，static/counter 页因为"触发在第 0 个采样点就命中"只有 **5 个点**。
页面渲染能力（缩放、光标、帧标注、VCD）一直是够的，差的是**被抓的内容**。

镜像模式把被测信号换成"上位机真正发出去的串口线"：上位机发一句 ASCII（默认
`HELLO,RISC-V`），逻辑分析仪抓下来并把这句报文逐字符标在波形上。

### 6.7.2 通路与边界

```text
上位机串口助手/PyUI ──CP2102──► uart0_rx ──板级顶层一行 assign──► J8-31（ch7 输出）
                                                                     │ 杜邦线 31↔32
   Python/PowerShell 上位机 ◄──UART── RV32I 固件 ◄── capture_engine ◄── J8-32（ch7 输入）
```

- **Core 完全不变**：镜像只是一根板级连线（`assign loopback_tx={uart0_rx,sample_outputs[6:0]}`），
  不新增寄存器、不新增端口、不改 `pipeline_cpu.v` 的任何事务语义。
- **选 ch7 的原因**：它是四模式里唯一空闲的通道（uart 只用 ch0、spi 只用 ch0~2、
  static 要求全等 `0xA5` 而 PC 线空闲为 1 正好等于 `0xA5` 的 bit7、counter 只要求"值有变化"），
  所以四个既有模式的判据**一条都不用改**。
- **8 路物理回环保留**：J8 仍然是 3↔4、…、31↔32 八对；只是第 8 对的激励源从
  pattern_gen 换成了上位机串口线。

### 6.7.3 协议与参数

- 新命令前缀 **`0xA7`**（镜像），13 字节布局不变，只重定义两个字段：
  `[2]` = 每比特采样点数、`[10]|[11]` = **16 位 post**（小端）；`pre` 由固件固定为 0
  ——镜像抓取必须是"窗口从起始位开始"。
- 触发 = **ch7 起始位下降沿**、`pre=0`、`post=深度-1`。这就是逻辑分析仪的标准用法：
  触发在帧头，整句一次抓完。
- 采样深度 **256 → 2048**（`logic_analyzer_mmio` 例化 `capture_engine #(.DEPTH(2048))`；
  `capture_engine.v` 本身未改，它自己的 TB 仍用 8/16/256）。PDS 里这块存储从
  `256×8 / GTP_DRM9K` 变成 `2048×8`，整机 BRAM 约多占 1 个 DRM18K 等效块。
- 每比特 **8 个采样点**（85 MHz：`sample_div=91`；50 MHz：`sample_div=53`），
  12 字符 = 120 bit 需 960 点；窗口 2048 点 ≈ 2.2 ms，报文本身 1.04 ms，
  留一倍余量吸收 USB 串口的字节间间隙。
- **顺序是硬约束**：固件 Arm 生效后先打印 `LA_ARMED`，上位机**必须等到这一行**才发字符串；
  否则字符串会比 Arm 早到，窗口从报文中间开始。

### 6.7.4 判据（判据与页面标注必须同源）

运行 `--mode mirror` / `-Modes mirror` 时，PASS 的条件是：

1. **逐字节相等**：从波形里解出来的字节序列必须**完全等于**上位机发出去的那句话
   （不是"解出了东西"——半比特错位正是那样混过去的）；
2. **帧错误为 0**；
3. 页面框出的第 1 个字节 = 发送字符串的首字符（页面上标的和判据用的是同一个字节）；
4. 窗口长度 ≥ `字符数 × 10 × 每比特点数`。

### 6.7.5 本轮修掉的四个真 bug（都由证据定位）

| # | 现象 | 根因 | 证据 |
|---|---|---|---|
| 1 | 固件把线上真实的 `0xA5` 解成 `0x4A` | `decode_uart` 在位边界取样，缺 2026-09-30 在 Python/PowerShell 侧补上的半比特居中 | `release/evidence/logic_analyzer_board_85m/uart/uart_00.log` 的 `UART:0000004A` |
| 2 | 上位机把实板捕获解成乱码，而板上固件解对了 | Python / PowerShell / 波形页 JS 三处解码器都从 `i=1` 起扫；镜像 `pre=0` 时窗口第 0 个采样点**就是**起始位 | 实板 `mirror_00.log`：固件 `ascii=HELLO,RISC-V`，上位机 `b'\x1511=,RISC-V'` |
| 3 | 12 个字符错 5 个（`HE??RI??-V`） | 解码成功后固定跳 10 个比特；实板采样边沿有 ±1 点抖动、帧长在 79~81 点浮动，误差逐帧累积到半个比特 | 实板 run-length `(72,1,9)`、`(137,1,7)`；改成"每帧用自己的起始位重新对齐"后 4 次全对 |
| 4 | SPI 从 20/20 PASS 变 FAIL | 触发在 SCLK 上升沿而 pattern_gen 自由运行 → 窗口落在字节任意 bit 上，落 b6 只剩 7 个脉冲、CS 提前拉高、整字节被丢弃。**老固件的 PASS 一直是相位运气** | `spi_00.log` 位图 7 脉冲后 CS 拉高；改触发 CS 下降沿后稳定 |

第 2、3 条的修法必须在 **Python、PowerShell、波形页 JS、固件流式解码器四处同改** ——
"判据与标注必须同源"在这里是硬约束：任何一处漏改，页面上标的字节和判据用的字节就不是同一个。

### 6.7.6 实测结果（2026-10-10）

- **实体板五模式验收**：`scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 -ClockHz 85000000`
  → `LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`（四模式各 20 + 镜像 20）。
  每次镜像抓取的回包都带 `LA TEXT … ascii=HELLO,RISC-V bytes=0000000C`，即**板上固件自己**
  把波形解回了整句。
- **备用位流（la50，50 MHz）**：同一份源码重建，5 模式 ×3 冒烟 `captures=15` PASS，
  证据 `release/evidence/logic_analyzer_board_50m_recheck/`。
- **交付波形页**：`-FromCaptures` 离线重建 `WAVEFORM REBUILD PASS pages=5`；镜像页为
  2048 点、`decode{protocol:uart, channel:7, bit_samples:8}`、`tag_names{7:"PC_TX"}`、
  备注写明"上位机发送 HELLO,RISC-V · ch7 = J8-31/32 回环 · 触发 = 起始位下降沿"。
- **资源与时序未退化**：la85 `Design Summary : All Constraints Met`，
  LUT 2856 / FF 2198 / DRM 6（原 5.5 等效块），`LUT as Distributed RAM = 0`（2048×8 没被推成分布式 RAM）。
- **止损记录**：DEPTH=2048 首次编译被 PDS `Verilog-4092 Loop limit 2000 exceeded` 拦下
  （`capture_engine.v` 复位清 BRAM 的 for 循环）；只删该循环，采集器独立 TB 与压力 TB 仍全 PASS。

### 6.7.7 测试入口与两个仿真 TB 的坑

| 测试 | 命令 | 覆盖 |
|---|---|---|
| 镜像端到端（仿真） | `scripts\run_logic_analyzer_mirror_tb.ps1` | 真实板级顶层 + 真实固件；J8 八对回环用 `assign` 模拟；场景 A 短报文冒烟、场景 B 整句 + 2048 点（与交付配置一致）。已加入 `scripts\run_final_regression.ps1` |
| 镜像端到端（实板） | `scripts\run_logic_analyzer_board.ps1 -Port COM11 -ClockHz 85000000` | 四模式各 20 次 + 镜像 20 次；50 MHz 备用位流传 `-ClockHz 50000000` |

仿真 TB 里的两个坑（都实测踩过）：Verilog 标准转义**没有 `\r`**：`"LA_ARMED\r\n"` 里的 `\r`
会被当成普通字符 `r`，模式串与真实回包差一字节、匹配永远失败，必须用 `8'h0D`/`8'h0A` 拼。
另外仿真里的 `sample_div` **不能照抄实板值**（实板比特周期 737 拍、仿真只有 8 拍；
抄过来变成 0.8 个采样点/比特，一帧都解不出来）。

## 6.8 仪器化：读数（**保留**）+ 面板（**已移除**）（2026-10-10）

### 6.8.1 为什么加这两样

原来的问题不是功能少，是**不像仪器**：只给波形不给结论，脱离电脑什么都不显示。
两条对应措施（用户 2026-10-10 明确批准，属于 `docs/competition_scoring.md` §6 D52
"P0 闭环后冻结功能"的例外）：

1. **仪器读数**（**保留，当前交付的一部分**）：从"看波形"升级成"给结论"——频率、周期、
   占空比、脉宽、边沿数、帧数/帧错误、推算波特率，并导出测量报告；
2. **仪器面板**（**当日即被用户否决并整套移除**）：8 个用户按键 + 8 个 LED 做成面板，
   不开电脑也能操作与读状态。用户反馈"按键没用"——见 §6.8.2。

### 6.8.2 仪器面板：**已移除**（2026-10-10 第三次变更）

> **用户 2026-10-10 决定：按键没用，整套移除；LED 也退回原来的 `gpio_out`。**
> 移除范围：`rtl/la_panel.v`、`tb/tb_la_panel.v`、`scripts/run_la_panel_tb.ps1`（三处已删除）、
> `logic_analyzer_mmio` 的面板端口、四个板级顶层的 `key_n`/LED 接线、`.fdc` 的 KEY1..KEY8 管脚、
> PDS 清单与导出脚本里的对应条目。
> 移除后位流的资源/时序（LUT 4479 / FF 3610 / DRM 6.0 / WNS +0.588 / WHS +0.310 /
> Fmax 89.4721 MHz）与加面板之前**逐项一致**，`captures=100` 板级复测通过 —— 证明移除是干净的。
> 下面这一节保留下来只作为"当时的定义"存档，**不再代表当前实现**。

<details><summary>（已废弃）面板定义存档</summary>

#### 面板定义（已废弃）

| 按键 | 功能 | | LED | 含义 |
|---|---|---|---|---|
| KEY1 | Arm 一次采集 | | LED1 | ARMED |
| KEY2 | Stop | | LED2 | TRIGGERED |
| KEY3 | Clear（清状态与计数） | | LED3 | DONE |
| KEY4 | 时基档位 +1（逐拍 / ≈1 MS/s / ≈100 kS/s） | | LED4 | OVERFLOW |
| KEY5 | 触发方式（电平 → 上升沿 → 下降沿） | | LED5 | 心跳（通电在跑） |
| KEY6 | 触发通道 +1（ch0…ch7 循环） | | LED6 | 亮 = 边沿触发 |
| KEY7 | **交回上位机**（面板参数作废，恢复 MMIO 控制） | | LED7-8 | 时基档位编码 |
| KEY8 | 预留 | | | |

- 实现在 `rtl/la_panel.v`（**Core 外部**）：两级同步 + 1.2 ms 消抖，按下沿产生**单拍**控制脉冲。
- 时基档位按 `CLK_HZ` 参数算，50 MHz 备用位流自动得到自己的分频，不写死 85 MHz 常数。
- **接管规则**：只有按过键（`panel_active=1`）面板才接管采样参数；KEY7 交还。
  `logic_analyzer_mmio` 对面板输入的判定一律用 `=== 1'b1`，所以**没接面板/没按键时
  行为与加面板之前逐位相同** —— 这是"加面板不许动坏 100/100 验收"的硬约束，
  由板级 TB 的 `PANEL CLEAR/ARM` 用例和 100/100 复测共同守住。

</details>

### 6.8.3 读数规格（**保留**）

- **每通道**：上升沿/下降沿数、频率、周期、周期抖动（min…max）、占空比、最小/最大脉宽；
  不足两个边沿的通道标 `—`（一条直线测不出频率，硬报 0 Hz 是假读数）。
- **周期取上升沿间隔的中位数**：平均值会被字节间隙带偏——实测 SPI 的 SCLK 因此读成
  10.07 MHz，真值 10.62 MHz，换中位数后偏差 0.00%。
- **协议层**：帧数/字节数、帧错误、每位采样点数、位宽、推算波特率、解码内容。
- 读数与判据**同源**：界面右栏、网页波形页、Markdown 报告、`--selftest` 输出
  用的是同一套 `measure_*` / `protocol_readings` 函数，不另写第二份实现。
- 已知偏差口径：位宽 = 每比特采样点数 × 采样点周期，本身带量化误差。
  实测 mirror 位宽 8658.8 ns vs 真实 8680 ns（**−0.24%**），推算波特率 115.5 kBd vs 115200
  —— 这个 0.24% 是"每比特 8 个采样点"的取整造成的，**必须照实说明，不许当成测量精度**。

### 6.8.4 验证结果（**移除面板后重测**）

| 验证 | 命令 | 结果 |
|---|---|---|
| 板级 TB（仿真） | `scripts\run_logic_analyzer_board_top_tb.ps1` | `ALL LOGIC ANALYZER BOARD TOP TEST PASS`（LED 断言回到 `led==8'h5A`，即 `gpio_out`） |
| 镜像端到端（仿真） | `scripts\run_logic_analyzer_mirror_tb.ps1` | PASS（2048 点 + 整句解码） |
| 最终回归 | `scripts\run_final_regression.ps1` | `ALL AUTOMATED FINAL REGRESSION PASS`（已无面板条目） |
| 读数（实板） | `逻辑分析仪演示.py --selftest` | 五种模式读数与已知参数吻合（见 §6.8.3 偏差口径） |
| 移除不破坏原通路 | `scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` | **`captures=100` PASS** |
| 演示前自检 | `scripts\demo_preflight.ps1 -Port COM11` | `DEMO PREFLIGHT PASS warnings=0` |

> 面板时期的 `run_la_panel_tb.ps1`、`PANEL LED/CLEAR/ARM` 三条用例、面板单测均已随面板一并删除，
> 上表是**当前**可复现的验证集合。

### 6.8.5 实体按键的现场步骤（**已作废**，面板已移除）

1. 下载交付位流后**不要插 USB**，只给板子供电；
2. 按 **KEY1**：LED2（TRIGGERED）+ LED3（DONE）应亮起，LED1 熄灭 —— 说明脱离电脑完成了一次采集；
3. 按 **KEY3**：LED2/LED3 熄灭 —— 状态被清掉；
4. 按 **KEY4/KEY5/KEY6** 若干次：LED7-8（时基档位）与 LED6（边沿触发）应跟着变；
5. 按 **KEY7**：面板交还控制权，接上 USB 后上位机照常工作；
6. 这一步的判据是**人眼看 LED**，脚本无法替代；录像时应拍下按键与 LED 的对应关系。

## 6.9 仪器面板：把旋钮接到界面上（2026-10-10 第四轮，用户批准的范围变更）

### 6.9.1 为什么加这一条

原来的上位机只能"选模式 + 点采集"：时基（`sample_div`）、触发方式、触发通道、触发电平、
触发前/后点数、激励速率与激励数据**全部写死在 `mode_config()` / `default_config()` 里**，
界面上一个旋钮都没有。

但这些字段固件一直都在收：13 字节报文的 `[1]`～`[11]` 直接写进
`LA_DIV`、`LA_TR_MASK`、`LA_TR_VALUE`、`LA_TR_RISE`、`LA_TR_FALL`、`LA_PRE`、`LA_POST`
（`software/logic_analyzer/logic_analyzer.c` 第 153～158 行）。
所以这一轮**不改 RTL、不改固件、不重新综合位流**，只把已经存在的能力接到界面上。

它同时补上 G11 的一条既有验收项："现场改变数据、速率、触发边沿或触发值，
系统无需重新综合即可由软件重新配置并正确采集"——原来这条只能靠命令行参数证明。

### 6.9.2 范围与边界

| 项 | 内容 |
|---|---|
| 界面 | `python/mes50hp_validation_ui.py`（交付包里是 `tools/pyUI.py`，入口 `启动逻辑分析仪.cmd`） |
| 旋钮 | 时基 `sample_div`、触发方式 level/rise/fall、触发通道 ch0…ch7、触发电平、`pre`、`post`、激励速率 `pattern_div`、激励数据 `data` |
| 配套只读项 | 板级时钟（85 MHz 交付位流 / 50 MHz 备用位流）——镜像模式的时基按它反算，填错必然解出乱码 |
| 停止条件 | 连续采集"采满 N 次后停"（0 = 一直采） |
| 明确不动的 | `rtl/*.v`、`software/logic_analyzer/*`、位流与 `.fdc`：**位流哈希不变** |
| 单文件上位机 | `逻辑分析仪演示.py` 本轮不动，仍是"一键采集 + 自检"那条路；旋钮只长在一个界面上，避免两份推导 |

`channel_mask` **故意不做成旋钮**：固件把 `LA_CH_MASK` 写死成 `0xFF`（同文件第 154 行），
报文里没有这个字节。给一个点得动、硬件不认的控件，比不给更坏。

### 6.9.3 必须同源的两处

1. **参数推导只有一处**：`python/logic_analyzer_serial.py::apply_knobs`。
   界面、命令行与采集路径都调它；未知字段、越界、镜像模式不支持的字段一律抛 `ValueError`。
   采集器内部会**静默截断** `pre`/`post`（`rtl/capture_engine.v` 第 21～24 行），
   悄悄把操作员输入的窗口改成另一个值，比当场报错更坏，所以拦住的责任在界面这一层。
2. **位点数按固件同一个公式重算**：`(pattern_div + 1) // (sample_div + 1)`，
   与固件第 177 行完全一致（整数除法，不是四舍五入）。
   不重算就会出现"页面标注的字节和判据用的字节不是同一个"——§6.7.5 修过的第 2、3 号 bug 属于这一类。
   镜像模式的最小窗口 `字符数 × 10 × 每比特采样点数` 也只有一个函数
   （`mirror_required_samples`），界面的事前校验与 `run_captures` 的事后判据共用同一个数。

### 6.9.4 模式相关约束（界面自动禁用控件并显示理由）

- **镜像模式只接受 `post`**：`sample_div` 必须与上位机波特率匹配、`data` 在 0xA7 里表示
  "每比特采样点数"、`pre` 被固件固定为 0、触发固定为 ch7 起始位下降沿（§6.7.3）。
- **电平触发值必须与掩码同位**：`capture_engine.v` 第 25 行是
  `(channels & active_mask) == (trigger_value & active_mask)`。
  所以"ch7 高电平"要写 `mask=0x80, value=0x80`；若按直觉写 `value=1`，
  它会被 AND 成 0，触发电平正好反掉。界面按"通道 + 高/低"两个控件收，换算集中在 `_collect_knobs`。
- **时基不能比激励速率还慢**（UART 模式）：每比特不足 1 个采样点时解码不成立，直接报错。

### 6.9.5 现场怎么用

1. 勾「使用面板参数」——界面先自动载入当前模式的默认值（空输入框会被当成 0，所以必须先预填）；
2. 只改要改的那一个（例如时基从 26 改成 52），下面一行实时显示"每比特几个采样点 / 窗口多少点"，
   写错的值当场变红并给出原因；
3. 点「按面板参数采集当前模式」——勾了面板就**只采当前模式**：
   拿 UART 的触发去打 SPI 只会永远等不到触发，现场表现是等满超时；
4. 每一轮的**报文十六进制与全部参数**都打进日志，事后可按字节复现这一枪。

### 6.9.6 连带的死路径处理：`-Oneshot`

`scripts/logic_analyzer_capture.ps1` 的 `-Oneshot -Segments N` 发的是 **0xA6** 前缀，
而交付固件只认 0xA5 与 0xA7（`logic_analyzer.c` 第 214 行）。原来的行为是**卡到超时**
（默认 70 s）才失败，现场点到会当场卡住。

现在改为**打开串口之前就拒绝**，并新增显式开关 `-AllowUnsupportedFirmwareSegments`
（默认关闭）：实现保留给将来真正支持 0xA6 的固件，误用则在 1 秒内看到原因。
主机端拼接 `-Segments N`（**不加** `-Oneshot`）仍然可用，实测 `pages=1` PASS。

### 6.9.7 验证

| 验证 | 命令 | 结果 |
|---|---|---|
| 旋钮推导与校验 | `python -m unittest discover -s python -p 'test_logic_analyzer*.py'` | **24 项 OK**（含 10 项旋钮、5 项面板） |
| 不勾面板时逐字节不变 | 与交付包旧版 `tools/logic_analyzer_serial.py` 对拍：5 模式 × 2 时钟 × 2 波特率 | 报文与 cfg **0 处不符** |
| 上位机入口 | `scripts\run_logic_analyzer_python.ps1` | `ALL LOGIC ANALYZER PYTHON TEST PASS` |
| 零依赖采集器离线重建 | `scripts\logic_analyzer_capture.ps1 -FromCaptures <目录> -Modes static,counter,uart,spi,mirror` | `WAVEFORM REBUILD PASS pages=5` |
| `-Oneshot` 拒绝 | 不带开关 | 开串口前抛错，错误文本点名 0xA5/0xA7 |
| `-Oneshot` 显式开关 | 带 `-AllowUnsupportedFirmwareSegments` | 越过闸门，错误变成"串口打不开"（证明拦它的是闸门） |
| **实板验收（D52 要求的复测）** | 下载 la85（`program_board.ps1 -Config la85`，`PROGRAM PASS` / `done bit is 1`）后跑 `run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 -ClockHz 85000000` | **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`**（2026-10-12，退出码 0）；证据重建 `pages=5` 后归档到 `release/evidence/logic_analyzer_board_85m/`（306 文件，旧证据备份在 `results/evidence_backup_85m_20261012/`） |
| 发布链（pwsh 7） | export → manifest → audit | `FINAL SUBMISSION EXPORT PASS files=296` / `RELEASE MANIFEST PASS files=3891` / `RELEASE PACKAGE AUDIT PASS final_files=297 artifacts=3`；包内 `tools/mes50hp_validation_ui.py` 与仓库源文件逐字节一致 |

**实板复测已完成（2026-10-12）**：下载交付位流 la85（`PROGRAM PASS`、`done bit is 1`、
SHA256 `8908FD8CB3AE72ED…`）后，五模式 ×20 次实板验收
**`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`**（退出码 0），
证据页重建 `pages=5` 后归档到 `release/evidence/logic_analyzer_board_85m/`。
交付包已按 export → manifest → audit 重新导出并通过审计。

**旋钮路径也单独上过板**：① UART 模式把激励速率与时基同时减半
（`pattern_div 433→866`、`sample_div 26→52`，重算后位点数仍是 16）→ PASS，208 点 / 触发 16，字节解对；
② 镜像模式把窗口 `post 2047→1200`（1201 点仍 ≥ 整句所需的 960 点）→ PASS，并**逐字节解出 `HELLO,RISC-V`**。
即"旋钮 → 报文 → 实板采集 → 判据"整条链在真板上成立；证据 `results/knob_probe/`。

## 6.10 采集源双源可选：J8 外部 / Core 内部观测点（2026-10-14，用户批准的范围变更）

### 6.10.1 为什么加这一条

"逻辑分析仪"这个应用原来的**被测对象是它自己**：激励发生器 → J8 回环 → 采集自己发出去的波形。
它证明的是"仪器能采、能解、能显示"，但**和自研 CPU 没有关系**——这正是评审最容易问的一句
"你这和外设有什么关系"。本轮把被测对象补上另一半：让同一台仪器直接采自研 CPU 的总线与流水线行为。

外设本身**没有换**：官方指南 `tmp/pdfs/competition_guide.txt` 第 210～212 行把"逻辑分析仪"
与游戏机、工控机、适配采集卡并列写进"应用场景构建"的示例，换掉它反而是离开官方点名的场景。
本轮改的是**被测对象**，不是外设种类。

### 6.10.2 通路与边界

- 8 根探针全部是 Core **已有的冻结观测输出**与统一事务端口（`docs/interfaces.md` §293～299）：
  `i_req_valid` / `i_req_ready` / `i_rsp_valid` / `d_req_valid` / `d_req_ready` /
  `event_stall` / `event_flush` / `trace_valid`。
- **Core 端口与事务语义一字未改**；探针只在板级顶层把 Core 的既有输出接到采集引擎的
  `probe_channels`，属于 Core 外部的观测层。
- 选择由 **MMIO 寄存器 18**（`LA_SRC`，偏移 0x48）控制：0 = J8 外部（**默认，与加这个功能前逐位一致**），
  1 = Core 内部观测点。因此现场切换采集源**不需要重新综合**，沿用 G11 的既有验收方式。

### 6.10.3 通道定义与典型用法

| 通道 | 信号 | 一眼能看出什么 |
|---|---|---|
| ch0 | `i_req_valid` | 取指请求是否满速（历史上这里只有 48.5% 拍有效，是 CPI 优化的起点） |
| ch1 | `i_req_ready` | SoC 接受取指 |
| ch2 | `i_rsp_valid` | 取指响应返回 |
| ch3 | `d_req_valid` | 访存请求在场 |
| ch4 | `d_req_ready` | SoC 接受访存（对比 ch3/ch4 就是"每笔访存 1 拍阻塞"） |
| ch5 | `event_stall` | 流水线暂停（`mem_block` / `load_use` / M 扩展除法迭代） |
| ch6 | `event_flush` | 控制流重定向（含 Trap） |
| ch7 | `trace_valid` | 退休一条指令——数它的脉冲数除以窗口长度就是窗口 IPC |

- 触发 ch6 上升沿：窗口以一次**控制流冲刷**为中心，往回看就是"这次冲刷是怎么来的"。
- 触发 ch5 上升沿：窗口以一次**流水线暂停**为中心，回答"这条指令为什么没往前走"。
- 全速采样（`sample_div=0`）：2048 点 = 2048 拍 ≈ 24 µs @85 MHz，够看几十条指令。

### 6.10.4 协议：0xA8 命令（16 字节）

`0xA5`（四模式）与 `0xA7`（镜像）的 13 字节布局已被上位机、解析器与板级 100/100 证据锁死，
因此**新开一条命令**而不是往老报文里挤：

```
[0]=0xA8 [1]=mode [2]=data [3]|[4]=pattern_div [5]|[6]=sample_div
[7]=trigger_type [8]=trigger_mask [9]=trigger_value
[10]|[11]=pre（16 位小端）[12]|[13]=post（16 位小端）
[14]=采集源(0=J8,1=Core) [15]=XOR 校验([0..14])
```

比 `0xA5` 长的原因：`0xA5` 的 pre/post 各只有 1 字节，装不下"全速采样 + 以一次冲刷为中心的
2048 点窗口"。老命令的路径逐字节不变（`python/test_logic_analyzer_serial.py` 的
`test_legacy_packet_is_byte_identical_without_source` 锁住这条）。

### 6.10.5 判据

`python/logic_analyzer_serial.py` 的 `capture_view()` 断言窗口里
**既有提交脉冲（ch7）又有取指请求（ch0）**：

- `commits = 窗口内 ch7 为 1 的采样点数 ≥ 8`
- `fetch_valid = 窗口内 ch0 为 1 的采样点数 ≥ 8`

只看"采到 2048 个点"是不够的——采到一整窗 0 也满足点数的形式条件，而那正是
"源没切过去"或"Core 卡死"时的样子。

**判据按"采集源"选，不能按模式选（2026-10-14 补）**：8 根线的物理含义由采集源决定，
所以"用什么模式采"（窗口与触发预设）与"这一窗是什么"必须分开，函数是
`capture_view(mode, source)`：

| 采集源 | 模式 | view | 通道含义与判据 |
|---|---|---|---|
| Core | `core` | `core` | ch0..ch7 = 上表八个观测点；判提交 ≥ 8 且取指 ≥ 8 |
| Core | `uart` / `spi` / … | `core` | 同上。模式只贡献窗口与触发预设，**不做该协议的解码** |
| J8 | `uart` / `spi` / … | `mode` | 历史语义：协议解码 + 各模式判据（逐字节不变） |
| J8 | `core` | `raw` | 8 根线是 J8 引脚，没有 CPU trace；只报点数/跳变，无协议判据 |

不分开会出现两种"采集是对的、解释是错的"的假失败，实板都复现过（`python/ui_source_board_check.py`）：
uart 模式 + Core 源会被按 UART 帧解码而报 `UART decode mismatch`；
core 预设 + J8 源会在波形页上把一根普通外部线标成 `trace_valid`。
同一份规则在两个上位机里各有一份实现（`python/logic_analyzer_serial.py` 与自包含的
`逻辑分析仪演示.py`），必须同时改；单文件版的 `capture_view` 是复制品，不是另一个口径。

### 6.10.6 两个界面都必须有这个开关（2026-10-14 补）

功能最早只做在 RTL、固件与库里：命令行能跑，两个界面上都点不出来，现场演示等于用不上。
现在两个上位机都有独立的**「采集源」下拉框**（`J8 外部 8 路` / `Core 内部观测点`）：

- `python/mes50hp_validation_ui.py`（pyUI）：面板旋钮 + 波形标题里写明真实源；
- `逻辑分析仪演示.py`（单文件）：面板旋钮 + 读数区在 Core 源下改报提交/停顿/冲刷/IPC；
- 切换采集源时窗口会自动换成新源下的合法默认值：切到 Core 给"全速 + 2048 点"，
  切回 J8 把 pre/post 压回 255 以内（否则 `apply_knobs` 会正确拦下，现场却以为功能坏了）。

| 验证 | 命令 | 结果 |
|---|---|---|
| MMIO 源选择（模块级） | `scripts\run_logic_analyzer_tb.ps1` | `SRC DEFAULT PASS` / `SRC SELECT PASS` / **`SRC CORE CAPTURE PASS`** / `SRC BACK TO J8 PASS`（让 `channels` 与 `probe_channels` 取不同值，采回来的必须跟着选中的源走） |
| 上位机报文与判据 | `python -m unittest discover -s python -p 'test_logic_analyzer*.py'` | **50 项 OK**（老报文逐字节不变、0xA8 布局与校验、非法源报错、`capture_view` 四种组合、pyUI 的界面标题与"控件真的布局出来"、单文件演示器的 4 项界面级用例） |
| pyUI 真路径实板四组合 | `scripts\run_ui_source_board.ps1 -Port COM11`（内部调 `python/ui_source_board_check.py`）→ `release/evidence/logic_analyzer_board_85m/ui_source_check/pyui_board_check.log` | `UI BOARD CHECK PASS`：core+Core / uart+Core / uart+J8 / core+J8 四枪全 PASS，报文长度 16/16/13/13、命令码 0xA8/0xA8/0xA5/0xA5、`[14]` = 1/1 |
| 单文件界面实板六模式 | 同一个脚本的第二段（`python 逻辑分析仪演示.py --selftest COM11`）→ `ui_source_check/singlefile_selftest.log` | `全部通过`，六模式 PASS（含 Core 源读数：提交 1187 拍、停顿 785 拍、冲刷 4 次、窗口 IPC 0.597） |
| 实板（命令行口径） | `scripts\run_core_probe_board.ps1 -Port COM11` | 见 `release/evidence/core_probe_board/`（两组触发各 3 次） |
| 实板（板级验收加跑 Core 源） | `run_logic_analyzer_board.ps1 -Port COM11 -IncludeCoreSource` | 默认仍是"五模式 ×20 = 100/100"这条冻结口径；加开关后**额外**跑 Core 源若干枪并打印 `LOGIC ANALYZER CORE SOURCE PASS`，不改动既有计数 |
| 交付包内说明 | `docs/logic_analyzer_quick_start.md`（导出为 `逻辑分析仪使用说明.md`） | 已写清两种采集源、Core 源的通道含义与读数变化、以及"触发不出现需按 REST 恢复" |

### 6.10.7 已知限制：触发条件永不出现会停住固件（必须按 REST 恢复）

固件在 Arm 之后是**无超时**轮询采集完成位（`software/logic_analyzer/logic_analyzer.c` 第 189 行
`while ((LA_STATUS & 4u) == 0u) { }`）。如果上位机发了一条**永远不会命中的触发**（例如在 J8 源下
等一个没有信号的外引脚上升沿），固件会停在这个循环里：串口一个字节都不再输出，后续任何报文
都不会被读取，**只有按板上 `REST` 或重新下载同一位流才能恢复**（2026-10-14 实板复现一次，
重下 `la85` 后恢复正常，`PROGRAM PASS` / done bit 1）。

- 现场纪律：先 static / counter 确认接线与触发有信号，再打协议模式；调试时优先用
  **电平触发**（上电即命中），不要用"等一个不存在的外部沿"。
- 上位机已把这条写进报错：超时且**一个字节都没收到**时，`run_captures` 直接提示
  "固件停在等待采集完成，只能按 REST 或重下位流"，而不是让现场去猜接线或串口。
- 未修的代价：给固件加 Arm 超时需要重建位流，会作废已冻结的交付位流哈希与全部引用它的证据，
  因此本届**保持位流不变并记录为已知限制**，恢复路径见 `release/materials/field_recovery_card.md`。

## 6.11 提交级 trace 子窗口：把探头从"引脚"伸到"流水线内部"（2026-10-21，用户批准的范围变更）

### 6.11.1 为什么加这一条

§6.10 已经把被测对象从"本机自己发出去的波形"换成了"自研 CPU 的 8 个观测点"，但 8 根数字线
只能回答"这一拍有没有提交/停顿/冲刷"，回答不了"**是哪条指令、动了哪个寄存器、写了哪个地址**"。
本轮把采样记录从"8 位数字线"换成"**一条完整的退休指令记录**"，让同一台仪器能画出
逐指令的数据流向。

三点必须同时记住，否则会把它讲成别的东西：

1. **数据源早就在 Core 的端口上**：`trace_*` 11 个字段是 `pipeline_cpu` 在 Task 18 就冻结的
   对外观测输出（`docs/interfaces.md` §6.1），`docs/interfaces.md` §5 原文就写着
   "ILA、波形采集器或调试桥**只观察这些输出**"。本轮之前板级顶层把它们全部悬空
   （`.trace_pc()` …），综合时直接被优化掉——**能看，只是我们没接**。
2. **它不是"实时"的**：一条记录 132 位（≈17 字节），85 MHz / 窗口 IPC≈0.6 下内核产出约
   600 MB/s，而 115200 8N1 只有 11.52 kB/s，**差约 5 万倍**。所以口径与真实逻辑分析仪一致：
   **Arm → 触发/收尾 → 上传一窗 → 上位机回放**。"实时"这个词不进任何材料。
3. **它不是 PDS ILA 的替代品**，也不这么宣称；ILA 仍用于 CoreMark 关键循环的流水线效率分析。

### 6.11.2 通路与边界（Core 一字未改）

```text
pipeline_cpu（端口/事务语义一行未动）
   │ trace_valid / pc / instruction / rd_we / rd_addr / rd_data
   │ mem_we / mem_addr / mem_data / mem_strb / error
   ▼
rtl/trace_buffer.v      ← Core 外部：4096 × 132 位记录 + 256 × 24 位打点表
   ▼
rtl/core_trace_mmio.v   ← 它的 MMIO 从端口（APP 窗口第 3 个子区间）
   ▼
rtl/application_mmio_mux3.v  → 0x1000_2200..0x1000_22FF
   ▼
固件 0xAA 命令：arm → 收字符串并逐字符打点 → stop → 逐条导出
   ▼
python/trace_view.py + python/trace_viewer.html → 单页数据流可视化
```

- **新增子区间不动既有窗口**：perf 仍是 `0x1000_2000`、逻辑分析仪仍是 `0x1000_2100`
  （`docs/interfaces.md` §3.2 允许"复用 APP 窗口内部子区间"）。
- **既有两个子窗口逐位不变**：`application_mmio_mux.v`、`perf_mmio.v`、`logic_analyzer_mmio.v`
  **一个字节都没动**；新写的 `application_mmio_mux3.v` 只是在外层把 `req_addr[11:8]==4'h2`
  截走，其余原样转给原来的 mux。`tb/tb_core_trace_mmio.v` 的 T10 专门断言这一点。
- **Core 不认识这个外设**：`pipeline_cpu` 顶层没有 trace 专用端口（用的就是已有的 `trace_*`），
  也没有任何设备地址或状态机。

### 6.11.3 记录格式（132 位，逐位固定）

| 位段 | 字段 | 说明 |
|---|---|---|
| `[11:0]` | `pc` | 退休 PC 低 12 位（IMEM 4 KB，`pc[11:2]` 是字索引） |
| `[43:12]` | `instruction` | 原始指令字 |
| `[44]` | `rd_we` | 本指令写回寄存器 |
| `[49:45]` | `rd` | 目的寄存器号 |
| `[81:50]` | `rd_data` | 写回数据（**Load 读到的数据就在这里**） |
| `[82]` | `mem_we` | 本指令写存储 |
| `[94:83]` | `mem_addr` | 写存储字节地址 |
| `[98:95]` | `mem_wstrb` | 字节写使能 |
| `[130:99]` | `mem_data` | 写存储数据 |
| `[131]` | `error` | 该条退休记录被抑制了架构副作用 |

**存 `instruction` 而不让上位机按 pc 去 ELF 里查**，是为了"同源"可判：上位机可以逐条断言
`trace_instruction == imem[pc>>2]`（用位流里**同一份** `logic_analyzer_program.mem`），
对不上就说明页面用的镜像和位流里的不是同一份——这种错误在页面上**看起来完全正常**。

**已知边界（必须原样进材料）**：`mem_addr` 只存**低 12 位**（IMEM/DMEM 各 4 KB），
所以**光看记录分不出 RAM 还是 MMIO**；而且 `trace_mem_addr` 只在 **store** 时有效
（`trace_mem_we` 的语义就是"本指令是否写存储"），**load 的地址不在记录里**。

上位机的处理办法是**还原而不是猜**：用窗口内已写过的寄存器值反推 32 位有效地址
（`rs1 + imm`），还原得出来就按 MMIO/RAM 分类并显示全地址，还原不出来就标"地址未知"
并只显示低 12 位。还原值还要与记录里的低 12 位**逐条对拍**
（判据 `store 有效地址与记录低 12 位一致`）——这条判据让"寄存器跟踪"与"地址字段"
互相钉住，任一边错都会当场露出来。

实测（阶段 0 那一枪）：17 次写存储里 8 次命中 MMIO，全部是固件自己写打点寄存器
`0x1000222C`（一字符一次），另外 9 次写数据 RAM（缓冲 `0xEE8…`）。

### 6.11.4 MMIO 寄存器（窗口内 byte offset）

| offset | 名字 | 语义 |
|---|---|---|
| `0x00` | `CTRL` | 写 `[0]`=arm `[1]`=stop `[2]`=clear（三个自清脉冲） |
| `0x04` | `STATUS` | `[0]`=armed `[1]`=recording `[2]`=done `[3]`=overflow |
| `0x08` | `COUNT` | 已记录条数 |
| `0x0C` | `MARKCOUNT` | 已打点个数 |
| `0x10` | `RD_INDEX` | 记录读指针 |
| `0x14`/`0x18`/`0x1C`/`0x20`/`0x30` | `RD_W0..W4` | 一条记录的 5 个 32 位字 |
| `0x24` | `MARK_INDEX` | 打点表读指针 |
| `0x28` | `MARK_RD` | `{8'b0, index[15:0], value[7:0]}` |
| `0x2C` | `MARK_WR` | 写 `[7:0]` = 打一个点（自清脉冲） |

所有寄存器按 `wstrb` 门控，零 strobe 无副作用；读寄存器**不产生** arm/打点等副作用
（`tb/tb_core_trace_mmio.v` 的 T3/T4 守着）。

**为什么要 5 个字**：132 位装不进 4 个 32 位字。第一版把 `RD_W3` 写成
`{28'b0, rd_record[131:96]}`，会**静默截掉**第 128…131 位（`error` 位与 `mem_data` 最高 4 位），
页面上表现为"看着有数据、其实少了几位"。现改为 5 个字读全，不做有损截断。

### 6.11.5 固件命令 0xAA（4 字节）

```text
[0]=0xAA [1]=字符数 [2]=阶段 [3]=XOR([1..2])
```

**两档被测程序**（都烧在位流里，现场切换不需要重新综合）：

| 阶段 | 固件做什么 | 字符上限 | 为什么要有这一档 |
|---|---|---:|---|
| `0` | 小写转大写 + 逐字节 XOR + 写回缓冲 | 32 | 最干净的"一遍过"负载：一字符 ≈ 12 条提交，字符与指令一一对齐 |
| `1` | 同上，但 **Arm 在接收之前** | 32 | 把"等下一个字节"的轮询摊开：实测 99.49% 的窗口是空转 |

**为什么没有第三档**：2026-10-22 试过加"冒泡排序"（读-改-写成对出现，依赖最密），
板级跑通了（16 字符 → 980 条提交、比较 120 次 = n(n-1)/2、判据 15/15 PASS），
但它把**镜像模式**测坏了：DMEM 只有 4 KB、栈顶固定 `0x1000`，加排序后 `.bss` 结束在
`0x0FD4`，**栈余量只剩 44 字节**，而镜像路径需要约 224 字节栈帧 → 栈压进 `.bss`
踩坏 `dec[]`，`run_logic_analyzer_mirror_tb` 由 PASS 变 2 条 FAIL。
结论：**交互固件已顶到 4 KB DMEM 的天花板**，再加功能必须先扩 DMEM，
而那会作废已冻结的 `la85`/`la50` 位流与 100/100 证据。故本轮撤回该档，
密度改由"加维度"解决（见 §6.11.10）。

为什么另开一条命令：`0xA5`/`0xA7`（13 字节）与 `0xA8`（16 字节）的布局都被上位机、解析器与
板级 100/100 证据锁死，往老报文里挤会波及全部既有证据；新命令只在用新功能时出现，
老路径逐字节不变。

阶段 0 / 1 靠 **打点**（`MARK_WR`）把字符锚到记录位置：固件收到某个字符的瞬间写一次
`MARK_WR`，记录下的 index 就是"此刻已记录多少条"，上位机据此把这个字符精确锚到一条指令上。

**2026-10-24 追加：`0xAB` 组合命令（4 字节）**

```text
[0]=0xAB [1]=字符数 [2]=波形窗口档（0=256 / 1=512 / 2=1024 / 3=2048 个后触发样本） [3]=XOR([1..2])
```

一次回包里**同时**给两块：先波形（`LA RAW count=… trigger=… window=… div=…` + 每样本 8 位
十六进制），再指令流（字段与 `0xAA` 逐字段相同）。它解决的是"波形与指令流永远对不上"：
tr85 位流里 8 通道分析仪（Core 探针源）和提交级 trace 本来就在同一个设计里，但过去是两条
命令、两次运行。对齐方法与实测证据见 §6.11.13 与 `release/evidence/trace85_board_wave/`。

代价如实记：这条命令在 4 KB 镜像里装不下（实测溢出 436 字节），所以 **tr85 的固件镜像扩到
8 KB**（`-DRAM_KB=8` + `link8k.ld`：栈顶 0x1000→0x2000、存储器 DEPTH 1024→2048、
互连 `RAM_LAST_ADDR` 0x0FFF→0x1FFF）。**交付工程 la85/la50 的固件仍是 4 KB、逐字节不变**，
这一条由 `scripts/generate_logic_analyzer_fpga_memory.ps1` 的 `-RamKb` 参数保证（默认 4）。

### 6.11.6 上位机判据（与页面标注同源）

`python/trace_view.py` 是**唯一实现**：记录位段拆解、RV32I(+M) 反汇编、依赖边、判据、页面
生成全在这一份里，页面显示的助记符就是判据用的那一个。

| 判据 | 不过就说明 |
|---|---|
| 记录条数自洽 | 头部 `count` ≠ 实际导出行数 |
| 打点数 = 字符数、打点值 = 发送的字符 | 字符↔指令的锚点错位 |
| 打点索引单调且不越界 | 打点表被覆盖或索引口径不一致 |
| 大写化结果 / 大写字符计数 / XOR 校验 | 固件处理逻辑与上位机期望不一致 |
| 收尾状态位（armed=0 recording=0 done=1） | Arm/Stop 没按预期收尾 |
| **未溢出**（`overflow==0` 或 `count>=窗口容量`） | 见下条"假 overflow" |
| `rd_we` 不得指向 x0；store 必须有字节使能；pc 4 字节对齐 | 记录本身被写坏 |
| **pc 与位流镜像同源**（逐条 `instr == imem[pc>>2]`） | 页面用的镜像和位流里的不是同一份 |
| **store 有效地址与记录低 12 位一致** | 基址寄存器跟踪错了，或记录地址字段被写坏 |

**假 overflow 的教训**：`overflow` 最初按 `done && trace_valid` 置起，而软件 `stop` 之后 CPU
当然还会继续退休指令，于是**每一次正常收尾都报溢出**（实测 `status=0x0C`）。现在只有
"被容量写满而收尾"（`full`）才允许置 overflow，判据也要求 `count>=窗口容量` 才认可溢出位。

### 6.11.7 上位机时序纪律（会被吞命令，不是 RTL 缺陷）

`uart_rx` **没有接收 FIFO**。固件在 Arm 之后会先阻塞打印 `TRACE_ARMED`/`LA_READY`，
这期间到达的命令字节会被后续字节覆盖 —— 实测表现为"固件再也不响应后面的命令"，
仿真里白等 300 万拍。

- **必须先等到 `TRACE_ARMED` 才发字符串**（否则窗口从报文中间开始）；
- **必须先等到 `LA_READY` 才发下一条命令**（`python/trace_board.py` 用
  `logic_analyzer_serial.synchronize_ready()` 做同一件事）。

这条纪律与 §6.7.3 镜像模式"必须等到 `LA_ARMED` 才发字符串"是同一条。

### 6.11.8 交付形态：独立位流，la85 不动

- 工程：`fpga/trace85/`（85 MHz PLL，与 la85 同频同频方案），入口
  `scripts\run_trace85_pds.ps1` 与 `scripts\program_board.ps1 -Config tr85`。
- **`la85` 位流、100/100 板级验收证据、`claims_map` 的四份哈希一个字节不动**；
  trace 是本届的**附加**演示能力，不改交付配置。
- 与 la85 顶层的差异只有三处：`application_mmio_mux` → `application_mmio_mux3`；
  `trace_*` 由悬空改为接线；多一个 `core_trace_mmio` 实例。
- PDS recipe **必须显式列出 `rtl/fetch_fifo.v` 与 `rtl/ras.v`**：
  `pipeline_cpu` 无条件例化 `ras`，缺模块会让整个 flow 以"未定义模块"失败
  （归档的 la85 配方正是缺这两个，所以从当前源码树重建会失败）。

### 6.11.9 界面：一个窗口两页（2026-10-22 用户要求）

`python/mes50hp_validation_ui.py`（交付包内 `tools/pyUI.py`）改成 **`ttk.Notebook` 两页**：

| 页 | 内容 |
|---|---|
| **① 逻辑分析仪（八通道波形）** | 原来那一整套：位流路径、CP2102 串口、仪器面板旋钮、实时波形面板、日志。**一行没动**（G11 的 100/100 验收与既有 11 条界面单测仍全 PASS） |
| **② CPU 数据流（寄存器热力图）** | 发字符串 + **界面内画出的**一条时间轴（四组泳道共享一根轴）/ 逐条指令表 / 依赖详情 / 播放与拖动 |

第 2 页长什么样（全部用 Tk Canvas 现画，**不打开浏览器**；版面在 2026-10-23 第三轮重排过，见 §6.11.10）：

| 版面 | 看什么 |
|---|---|
| 顶部输入行 | 「发送给 CPU 的字符串」输入框、阶段下拉、「采集」、「连续采集」、「同时导出网页」 |
| 校验/预演行 | `8 个字符 · 阶段 0 · 会得到 'HELLO,RV' · up=7 · xor=0x0000006A`——与自动判据同源（`trace_view.expected_phase0`）；非法输入按钮置灰 + 红字 |
| **左侧指令流** | 窗口内 ±60 条，`>` 标当前（**整行铺底色**）、`+` 标"给它提供数据的记录"；点任意行即选中，右侧光标立刻跳过去 |
| **右侧时间轴**（**一块** Canvas） | 顶部一根记录号标尺 + 四组泳道（寄存器 / PC / 写存储地址 / 事件），一条竖光标贯穿全部泳道；选中指令在各泳道里用黄框标出它自己那一行，寄存器泳道再画出"谁写了它"的依赖横线。细节见 §6.11.10 |
| 播放条 | ▶ 播放 / ◀ ▶ 单步 / 拖动条，一条记录 80 ms 推进 |
| 底部标签页 | 「这条指令」= PC / 反汇编 / 写回值 / 写存储地址与数据 / **数据从哪来**（源寄存器 ← 哪条记录、值是多少）/ **数据去了哪**；「判据日志」= 每次采集的 15~20 条判据逐条打印（PASS/FAIL 带实测值） |

**"连续采集（实时刷新）"** 就是"实时"：上一枪跑完立刻再采一枪并重画，
所以板子上的活动一直在动，而不是只画一次。

不用界面时还有两个入口：

```powershell
python python\trace_board.py --port COM11 --phase 0 --text "任意 ASCII ≤32 字符"
python\capture_trace.cmd          # 双击，会问你要发什么（也可 capture_trace.cmd "abc"）
```

**边界**：字符数按阶段不同（阶段 0 只记处理过程、阶段 1 连串口轮询一起记），两者都 ≤32 字符、
只能 ASCII；能选的被测程序只有固件里烧进去这两档，加第三档要改固件重打位流（第三档"冒泡排序"
2026-10-22 试过并回退了，原因见 §6.11.5）。

### 6.11.10 第 2 页的时间轴：一块画布、一根轴、一根光标（2026-10-23 第三轮重排）

用户对上一版（四块各自独立的 Canvas）的评语是"第二页太乱了"，并要求参考网上成熟的做法。
找到的三个参考指向同一个范式：

| 参考 | 借鉴的规则 |
|---|---|
| Perfetto / Chrome tracing 的 track 视图 | 多条 lane **共享同一根时间轴**，只有一个光标，选中项详情另开一栏 |
| GTKWave / Surfer 波形 | 左侧信号名栏 + 右侧波形、单光标、分组表头 |
| Ripes（RISC-V 模拟器） | 架构状态（寄存器/存储）与流水线分开看，靠光标/步进同步 |

上一版失败的正是把这三条全反着做了：四块画布、四套横轴刻度、四套小标签。现在合成**一块**画布：

- 左栏 82 px 放泳道名，右侧是唯一的可绘区；顶部**一根**记录号标尺，四组泳道共用它；
- 一条黄色虚线光标贯穿到底；选中指令在每组泳道里用**空心黄框**标出它自己那一行
  （填色会盖住那一行真正的数据块），寄存器泳道再从"写它的那条记录"拉一条依赖横线过来；
- 组名条（寄存器 / PC / 写存储地址 / 事件）贴在左栏顶部，像 GTKWave 的 group header。

| 泳道 | 行 = | 色 = |
|---|---|---|
| 寄存器 | 本窗口**用到的**寄存器，含"只被读、从没被写"的（实测 100 条记录有 130 次读，旧版一次都没画） | 填充色 = 值从哪来（青=load、绿=ALU、紫=立即数、黄=PC）；行底细条 = 这条指令**读**了它 |
| PC | 出现最多的 12 个 PC | 绿=有写回、紫=有写存储、灰=其它 |
| 写存储地址 | 真正被写过的地址（MMIO 打完整 8 位，数据 RAM 打低 16 位）；一笔都没有时写"本窗口没有任何写存储"，不留空白格 | 绿=数据 RAM、青=MMIO、粉=打点寄存器、深灰=地址还原不出来 |
| 事件 | 一条带子分上下两半 | 上=字符打点，`h e l l o , r v` 贴在锚点竖线上；下=每次写存储的竖条，条高 = 写了几个字节 |

三个值得记下来的量化教训：

1. **行数不是越多越好**。上一版 PC 泳道把 19 个 PC 全画出来、每行 5 px，7 pt 的字直接重叠成糊。
   现在所有泳道**共用同一个行距**（由可用高度与总行数一次算出，下限 7 px、上限 20 px），
   行数放不下就按热度砍行——宁可少画几行，也不要画成一串虚线点。
2. **一列只能放一条记录**。阶段 1 一枪 4096 条，压进 ~1160 px 就是一列叠 3～4 条，
   颜色只能"谁最后写谁说了算"，整块面板糊成一条色带（实测截图如此）。
   现在一条记录**至少占 3 px**（`_TL_PX_PER_REC`），超出的部分取光标附近一段滚动显示，
   并多画一条**全览条**（整窗密度 + 黄框标出"现在看的是哪一段"）；
   标尺上写的始终是真实记录号，例如 `放大显示 #0–#376 / 共 4096 条`。
3. **静态层和光标层分开画**。数据块只在"数据 / 尺寸 / 视窗段"变化时重建，
   选中变化只重画 `tl_cur` 标签下的光标与高亮——4096 条的窗口播放时不卡。

**一个必须如实说的限度**：一条记录 3 px 意味着 4096 条要看约 11 屏，**不是"一眼看全"**。
本页从不假装能一次看全 4096 条：要么看全览条的密度，要么看某一段的逐条细节。

**一个 Tk 的坑（写在这里免得下次再踩）**：`tk.Text` 的标签名 `sel` 是**保留名**，
由 `-selectbackground` 接管，外面 `tag_configure("sel", background=...)` 会被静默忽略——
`tag_names()` 里有、`tag_cget()` 也读得回颜色，界面上却一点底色都没有。当前行的高亮标签因此叫 `cur`。

### 6.11.13 波形与指令流**按拍对齐**（2026-10-24：0xAB 组合采集）

这一节是目前为止这个演示里**唯一别人不容易复制的部分**，因为它要的是"同一次运行里的两种观测"。

**做了什么**：让 8 通道分析仪（Core 探针源）和提交级 trace 在**同一次运行**里同时开窗，
并把两块放进一份回包。固件顺序是刻意的（`trace_and_wave`）：先 arm trace → 再 arm LA
（触发 = 退休脉冲上升沿、`div=0` 每拍一采样）→ 跑负载 → 等 LA 采满 → **最后**才 stop trace。
于是"波形窗口整段被 trace 覆盖"这件事由固件结构保证，而不是靠运气。

**对齐怎么算**（`trace_view.align_wave`，单测在 `python/tests/test_trace_view.py`）：

1. 在 trace 里找 `LA CONTROL = 1` 的那条 store（`0x1000_2100`）——"波形开始采样"的锚点；
2. 波形里 **bit7（`perf_retire`）** 的个数 C = 这段窗口里退休了多少条指令 ⇒ 覆盖记录 `[offset, offset+C)`；
3. **交叉校验**：波形里 **bit3&bit4（`d_req_valid & d_req_ready`）** 的拍数，必须等于区间内
   **load+store 的条数**。两条来源完全独立：一条是 Core 的握手线，一条是提交记录。

**实板一枪（2026-10-24，证据在 `release/evidence/trace85_board_wave/`）**：

```
ALIGN offset=1 anchor=1 delta=0 tied=[0, 2] cycles=512 retire=316 dv=97 rec=97 mismatch=0
```

- 512 拍里 **316 个退休脉冲**（窗口 IPC ≈ 0.62），覆盖记录 **#1..#316**；
- 波形 **97 个数据访问脉冲** ↔ 区间内 **97 条访存指令**，**差 0**——这就是"对齐不是画的、是证的"；
- 候选偏移 `[0, 2]` 同样吻合（处理循环周期性），所以界面与文档**都标注 ±1 条记录的精度**。

**界面上怎么看**：第 2 页多两个控件——窗口档下拉（512/1024/2048 拍）与「波形+指令」按钮。
采回来后时间轴的横轴**从"记录号"变成"拍号"**，最上面多一组 **Core 探针（每拍）** 泳道
（提交/冲刷/停顿/数据就绪/数据请求/取指响应/取指就绪/取指请求，按语义成对配色、带阶跃沿），
下面四组泳道里的每条记录**右边界 = 它退休的那一拍**、左边界 = 上一条退休的下一拍
（多拍指令因此自然变宽——那是真实的时间宽度；访存指令的数据访问脉冲也正好落在自己的块里）。
点任意位置，光标落在那一拍并显示 `拍N` 气泡，对应的指令在左表里高亮；
选中一条指令时，它那一拍的**提交脉冲**与**块内的数据访问脉冲**会被标成白芯琥珀框——
这就是"对齐"在画面上的样子，不必去读判据日志。

**必须如实说的三条**：

1. **对齐精度 ±1 条记录**：arm 写自己退休那一拍既是"第 0 个样本"也可以是"下一个样本"的
   边界；交叉校验能证伪错误偏移，但周期性负载下不能唯一确定 ±1。界面、判据文本与证据
   README 三处都写这一句（2026-10-24 评估过用"故意写未映射地址制造 `error=1` 哨兵"来消除它，
   判断为**不值得**：那等于污染"未出错"的语义与既有判据）。
2. **窗口覆盖率**：判据直接给出 `覆盖 N/M 条（x%）`。实测 512 拍覆盖 316/323（97.8%）、
   2048 拍覆盖 1237/1247（99.2%）——差的那几条是"LA 采满之后、trace 停止之前"还在退休的指令，
   如实计数，不抹平。
3. 这仍然是**采集后回放**，不是实时流式：一枪要等收尾再上传（132 位/条 vs 115200）。

### 6.11.11 浏览器页面里有什么（可选产物）

`python/trace_viewer.html` 是单页自包含页面（无框架、无网络依赖），**只在勾选
「同时导出网页」或走命令行时产生**；界面上看的是上面那条时间轴（§6.11.10），
浏览器页是同一份数据的另一种摆法。产物由
`python/trace_view.py::write_trace_page` 把数据塞进 `__TRACE_DATA__` 占位符：

| 版面 | 看什么 | 实现 |
|---|---|---|
| 顶部总览（`overview`） | 每条指令一根竖条，按类别着色（ALU/load/store/branch/M 扩展），下拉高度区分"有写回/有写存储"；打点字符贴在底部 | `drawOverview()` |
| **总线/MMIO 泳道**（`buslane`） | 每次写存储一根竖条：绿=数据 RAM、青=MMIO 命中、紫=写打点寄存器、深灰=地址还原不出来 | `drawBusLane()` |
| **寄存器热力图**（`regmap`） | 横轴=记录序号、纵轴=x0…x31，方格=该条记录写回了这个寄存器；黄底行=当前选中指令**读**的寄存器 | `drawRegMap()` |
| 指令表 | 逐条 `# / PC / 反汇编 / 结果与副作用 / 标签`（字符锚点、写回、写存储、error） | `renderList()` |
| 右栏 | 当前指令详情、**数据从哪来**（源寄存器 ← 最近一次写它的记录，可点击跳转）、**数据去了哪**（窗口内读者）、寄存器此刻的值（x0–x31 网格） | `renderDetail()` |
| 时间轴 | 播放/单步/拖动/点击任意画布跳转；`←/→/空格` 快捷键 | `select()` / `togglePlay()` |

**"流水线占用"这一项的处理方式（必须照实讲）**：提交级记录里**没有时间戳**，
一条记录 = 一条退休指令，因此**每拍的取指/停顿/冲刷无法从本页得到**，也不做任何推测。
那一层由已有的 **8 通道 Core 探针波形页**（§6.10，`trace_valid`/`event_stall`/`event_flush`
等 8 根线，全速 2048 点）和 PDS ILA 负责。两者是分工，不是替代关系：
波形页看"每拍在干什么"，本页看"每条指令搬了什么数据"。

### 6.11.12 验证入口

| 层 | 命令 | 判据 |
|---|---|---|
| trace 缓冲单元 | `scripts\run_trace_buffer_tb.ps1` | `ALL TRACE BUFFER TEST PASS`（10 项，逐字段对拍） |
| MMIO + 三目标汇合 | `scripts\run_core_trace_mmio_tb.ps1` | `ALL CORE TRACE MMIO TEST PASS`（11 项，含"既有两子窗口逐位不变"） |
| 端到端仿真（真 SoC + 真固件） | `scripts\run_core_trace_soc_tb.ps1` | `ALL CORE TRACE SOC TEST PASS`（两场景：只记处理过程 / 连轮询一起记；PASS 后用同一份日志自动生成两页） |
| 上位机（判据+页面） | `python -m unittest python.tests.test_trace_view` | 30 项 OK（含页面 JS 用 `node --check` 解析、JS 引用的 DOM id 全存在） |
| 上位机（输入框 + 时间轴） | `scripts\run_trace_python.ps1` | `ALL TRACE PYTHON TEST PASS`（含 `test_trace_ui.py` 28 项：控件真被布局、超长/非 ASCII/空串被拦、预览与判据同源、四组泳道共享一根轴、一条记录 ≥3 px、只读寄存器有行、选中行真的被标出、指令表不被横向顶走、波形模式五组泳道 + 横轴单位是"拍"；`test_trace_ui_pixels.py` 4 项**像素级**：探针泳道总高 ≥80 px、每条泳道色块数与样本位数一致、光标落点 = 选中记录退休的那一拍、选中指令的寄存器行被框出） |
| 位流 | `scripts\run_trace85_pds.ps1` | `All Constraints Met` |
| 实板（命令行） | `scripts\program_board.ps1 -Config tr85` 后 `python python/trace_board.py --port COM11 --phase 0` | `TRACE BOARD PASS`（阶段 0 15/15、阶段 1 14/14 条判据） |
| 实板（**真走界面**） | `python python\trace_ui_board_check.py --port COM11 --text hello,rv --phase 0 --wave`（阶段 1 用 `--text ABC --phase 1`） | `TRACE UI BOARD CHECK PASS`（真的构造 pyUI、真的填输入框、真的点按钮；在**真实窗口尺寸**下再布一次版，断言四组泳道都在、可见记录数、寄存器行数；`--wave` 再跑一枪 0xAB，断言五组泳道 + 横轴单位是"拍" + 对齐交叉校验 `mismatch=0`。失败时把弹窗换成"记账"，不会挂死） |
| 一键演示 | `python python\mes50hp_validation_ui.py --page 2 --wave-text hello,rv` | 打开就停在第 2 页并自动跑一次组合采集（波形 + 指令流按拍对齐） |



### 6.11.14 离线回放：样本与镜像配对、来源徽标、两条入口（2026-10-28）

> 起因：用户看演示素材时报告"第 2 页热力图是写死的"。画图并不写死（四条泳道按记录现算），
> 但默认入口固定回放一份**过期**录包、页面上又没有任何来源标识，观感确实等同写死。
> 详见 `docs/debug_log.md` 2026-10-28。

**两条入口必须分开用**：

| 入口 | 落点 | 数据来源 | 用途 |
|---|---|---|---|
| `python/start_logic_analyzer.cmd`（交付包里 `启动逻辑分析仪.cmd`） | 第 ① 页八通道波形 | 板子实时采集 | 现场演示、录屏的"真采集"画面 |
| `python/start_logic_analyzer_offline.cmd`（交付包里 `离线演示.cmd`） | 第 ② 页 CPU 数据流 | `samples/trace_hello_rv.log` 回放 | 没有开发板时给人看第 ② 页长什么样 |

两个 `.cmd` 都自动探测 `pyUI.py` / `tools\pyUI.py`，仓库与交付包根目录通用。

**三条纪律**：

1. **样本与固件镜像是"一对"**：`python/samples/trace_hello_rv.log` 必须与
   `fpga/trace85/rtl/logic_analyzer_program.mem` 同源（当前 **15/15 PASS**）。
   重新生成镜像后必须重录样本或重新对齐，否则判据 `pc 与位流镜像同源` 会 100 条全错。
   配对哈希与自检命令写在 `python/samples/README.md`，并由
   `test_trace_ui.py::OfflineReplaySampleTests` 自动钉住。
2. **`sent_text` 取打点值，不取回包 `TRACE TEXT`**：后者是固件大写化**之后**的结果，
   拿它判据会稳定产生 2 条假 FAIL（"打点值等于发送的字符""大写字符计数"）。
3. **回放必须在屏幕上自证**：回放时第 ② 页顶栏显示「离线回放：<文件名> · 判据仅供参考」，
   判据日志标题写「===== 离线回放：… =====」，状态栏写「CPU 数据流 · 离线回放」；
   真采集一枪立刻撤标。**录像/截图里带这个徽标的画面不得当成"板子在跑"的证据。**

| 层 | 命令 | 判据 |
|---|---|---|
| 上位机（回放与徽标） | `python test_trace_ui.py` | 34 项 OK，其中 `OfflineReplaySampleTests` 3 项（sent 取打点、回包文本会误判、样本与镜像同源）+ `ReplayBannerTests` 3 项（徽标置、实采撤、payload 带来源） |
| 样本自检（无板） | 见 `python/samples/README.md` §2 | `True []`（15/15 PASS） |

## 7. 必须报告的量化指标

- Pipeline Core：CoreMark/MHz、Fmax、CoreMark/LUT、CPI、Stall/Flush Rate。
- Capture Engine：最高稳定采样频率、通道数、触发延迟、Raw 深度。
- 赛后若重新立项 RLE：另行报告典型/最坏压缩比、等效采样深度、额外 LUT/FF/BRAM 和 Fmax 影响；本届材料不报告压缩数据。
- SoC：纯 Core、基础 UART/GPIO、加入逻辑分析仪三种配置的 LUT/FF/BRAM/Fmax。
- 软硬件协同：CPU 轮询与硬件 Capture Engine 的最高无丢样频率和 CPU 占用对比。
- 数据链路：UART 有效吞吐、一次完整采集上传时间和上位机重建时间。

所有性能结论必须同时给出测试条件、编译参数、目标器件、时钟、输入模式、样本数量和 Before/After 数据。

## 8. G11 完成定义

### 当前实现映射（2026-09-15）

- `rtl/capture_engine.v`：8 通道 Raw、可调采样间隔、通道掩码、电平/上升沿/下降沿触发、环形 BRAM、触发前后计数、Overflow 和显式读指针。
- `rtl/logic_analyzer_mmio.v`：Application-MMIO 寄存器窗口；请求接受时锁存响应，支持随机背压且无重复 side effect。
- `rtl/application_mmio_mux.v`：性能计数器位于 Application `0x10002000..0x100020FF`，分析仪位于 `0x10002100..0x100021FF`，Core 源码不变。
- `fpga/logic_analyzer`：MES50HP P20/R8/R9 与 J8 隔行相邻脚对输入/输出的板级顶层与 `.fdc`；正式交互固件和 PDS bitstream 已生成。
- `rtl/logic_analyzer_pattern_gen.v`：软件可选 static、counter、UART 8N1、SPI mode 0，速率和数据运行时可改；发生器只驱动 J8，不在 FPGA 内回接 Capture Engine。
- `software/logic_analyzer`：13 字节带 XOR 校验配置协议、Arm/轮询/Raw 输出、UART/SPI 软件解析；`python/logic_analyzer.py` 与 `logic_analyzer_serial.py` 完成配置、重建、协议复核、VCD 和 JSON 证据。
- Capture Engine 的 `capture_count` 精确定义为实际导出的 `pre + trigger + post` 样本数；`trigger_index` 是 Raw 流的逻辑索引。容量不足时先保留触发样本和 post，再截断 pre。
- 已通过 Capture 独立边界测试、20 轮连续采集/每五轮 Reset、发生器独立测试、MMIO byte-enable、Application mux、交互式 board-top、软件 SoC 和 Python 六项测试。唯一最终配置（流水线 + BTB + UART/GPIO + 性能计数器 + 逻辑分析仪）在 PDS 50 MHz 下 All Constraints Met：setup WNS +2.661 ns、hold WHS +0.312 ns、3459 LUT、3129 FF、5.5 个 DRM18K 等效块。MES50HP 实体板 static、counter、UART、SPI 各 20 次，共 80/80 PASS。

### CPU 内部性能观测配置

Task 29 使用独立 CoreMark DebugCore bitstream 观察 CPU 内部事件，与本作品的 8 通道外部逻辑分析仪用途不同。`coremark_ila` 为单个 192-bit、512-sample 探针，覆盖退休 PC/instruction、寄存器写回、Store、stall/load-stall、branch/taken/flush、取指/数据请求握手和 reset。该诊断配置为 4416 LUT、4458 FF、39 DRM，50 MHz 下 setup WNS +5.453 ns、hold WNS +0.186 ns；正式 Task 28 计分 bitstream 不含 DebugCore，仍使用其独立资源与 Fmax 数据。Fabric Debugger 实测波形需在 MES50HP 连接后补录。

### UART 配置协议

正式固件上电发送 `LA_READY`。上位机收到提示后发送 13 字节包：`A5 mode data pattern_div_lo pattern_div_hi sample_div_lo sample_div_hi trigger_type trigger_mask trigger_value pre post checksum`。checksum 是前 12 字节 XOR。`trigger_type` 为 0 level、1 rise、2 fall。固件输出 `LA RAW count=<hex> trigger=<hex>`、Raw 数据、UART/SPI 解析计数、`LA_DONE`，最后再次发送 `LA_READY`。上位机必须等最后一个 `LA_READY` 后再发下一包，避免覆盖 UART RX 单字节邮箱。

### 当前量化结果

| 指标 | 当前值 | 证据边界 |
|---|---:|---|
| 通道 | 8 | 固定 MES50HP 配置 |
| Raw 深度 | 256 samples | Capture Engine parameter |
| 最大内部采样率 | 50 MS/s | `sample_div=0`，50 MHz 时钟；异步输入存在亚稳风险 |
| 触发延迟 | 0 个额外 sample tick | 命中样本同拍写入并成为 trigger sample |
| UART 线路速率 | 115200 bit/s | 8N1，有效字节上限 11520 B/s |
| 当前文本 Raw 负载 | 9 B/sample 左右 | 8 hex 字符加分隔符，256 samples 约 0.20 s 线路时间 |
| 自动连续压力 | 20/20 PASS | 每五轮插入 Reset，count/index 精确检查 |
| 实体 J8 回环 | 80/80 PASS | static/counter/UART/SPI 各 20 次；UART=`A5`、SPI=`3C` |
| PDS estimated Fmax | 57.6735 MHz | 唯一最终交互 bitstream；应用仍固定运行 50 MHz |

只有以下项目全部满足，Task 30/G11 才能标记完成：

1. P0 全部功能具有独立自动测试且全部 PASS；RLE 不属于本届 G11 范围。
2. 裸机 C 驱动、UART/SPI 解析、UART 传输和 Python 上位机形成可重复闭环。
3. 已知激励、随机激励、随机背压、Reset 和连续采集测试全部 PASS。
4. 三种 SoC 配置复用完全相同的 Pipeline Core，原完整 Regression 与 CoreMark 保持 PASS。
5. 应用 RTL 不含 CPU 内部信号，CPU Core 不含任何逻辑分析仪端口、地址、状态和协议逻辑。
6. 资源、时序、采样、吞吐和软硬件对比数据完整；本届不要求且不展示 RLE 压缩数据。
7. 现场演示脚本、故障恢复流程、3 分钟演示视频素材和答辩证据形成项目文件，不依赖历史聊天。
