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
