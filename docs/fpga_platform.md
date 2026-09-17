# MES50HP FPGA 平台契约

> 最后更新：2026-09-10
> 决策状态：本届正式 FPGA 验证平台已切换为盘古 50（MES50HP）实体开发板；PDS/BRAM/JTAG 下载两次与 LED1 实体冒烟均完成，Task 10 / G2 PASS。SPI Flash 固化另行处理。
> 适用边界：本文只约束 Core 外部的 FPGA/板级顶层、约束、下载和上板验证，不得改变 CPU Core、ISA 或统一事务接口。

## 1. 冻结决策

- 本届 FPGA、Timing、UART、GPIO、CoreMark、PDS ILA 和最终应用证据均以 MES50HP 为目标平台。
- 旧在线实验箱 DUT（`PG2L200H-6FBB676`、S2/S3 子卡、27 MHz）不再作为正式验收平台；它的约束、bitstream、时序和上板结果均不得替代 MES50HP 验收。
- 不因板级工程尚未完成而阻塞 Task 2～9 的原理学习、RTL 模块和 Testbench；Task 10 必须完成 MES50HP 的真实可行性验证后才能通过 G2。

## 2. 已确认的硬件配置

以下项目均直接来自《盘古 50 开发板（MES50HP）硬件使用手册 V1.0》（2024-07-19，用户提供的本地 PDF）。

| 项目 | 已确认值 |
|---|---|
| FPGA 完整器件 | 紫光同创 Logos `PGL50H-6IFBG484` |
| FPGA 资源摘要 | 42,800 LUT6、64,200 FF、134 × 18 Kbit DRM、84 APM、4 路 HSSTLP |
| 系统时钟 | `FPGA_GCLK_50M`，50 MHz，管脚 `P20`；周期约束 20.000 ns |
| 备用通用时钟 | `FPGA_GCLK_27M`，27 MHz，管脚 `K21`；仅在板级顶层明确选择后使用 |
| 高速参考时钟 | 125 MHz 差分 HSST 参考时钟，`A10` / `B10`；不用于 CPU 系统时钟 |
| 约束格式 | PDS `.fdc`；本项目使用手册给出的管脚与电平建立约束 |
| UART | 板载 CP2102 USB-UART；实体板已验证 `UART0_RX=R8`、`UART0_TX=R9`，3.3 V I/O；波特率和帧格式由 SoC UART 配置 |
| 用户输入 | `KEY1..KEY8=K18,L15,J17,K16,J16,J19,H20,H17`；3.3 V I/O，低电平按下 |
| 用户输出 | `LED1..LED8=B2,A2,B3,A3,C5,A5,F7,F8`；3.3 V I/O，FPGA 输出高电平点亮 |
| 扩展 I/O | 40-pin J8，34 路 3.3 V I/O；Task 30 使用每隔一行的一组相邻管脚，便于八根跳线清晰布置 |

### 逻辑分析仪 P0 已选管脚

手册表 3-12 与表 3-13 已给出扩展口到 PGL50H 的完整映射。本项目固定以下 3.3 V 管脚，后续 `.fdc`、board wrapper 和实体接线均使用同一顺序：

| 用途 | 接口管脚 | 信号 | PGL50H 管脚 |
|---|---|---|---|
| `loopback_tx[0]` | J8-3 | `EX_IO_11N` | `AB13` |
| `capture_ch[0]` | J8-4 | `EX_IO_11P` | `Y13` |
| `loopback_tx[1]` | J8-7 | `EX_IO_10N` | `W11` |
| `capture_ch[1]` | J8-8 | `EX_IO_10P` | `V11` |
| `loopback_tx[2]` | J8-11 | `EX_IO_15N` | `Y10` |
| `capture_ch[2]` | J8-12 | `EX_IO_15P` | `W10` |
| `loopback_tx[3]` | J8-15 | `EX_IO_7N` | `Y12` |
| `capture_ch[3]` | J8-16 | `EX_IO_7P` | `W12` |
| `loopback_tx[4]` | J8-19 | `EX_IO_14N` | `U10` |
| `capture_ch[4]` | J8-20 | `EX_IO_14P` | `T10` |
| `loopback_tx[5]` | J8-23 | `EX_IO_17N` | `V9` |
| `capture_ch[5]` | J8-24 | `EX_IO_17P` | `U9` |
| `loopback_tx[6]` | J8-27 | `EX_IO_4N` | `W8` |
| `capture_ch[6]` | J8-28 | `EX_IO_4P` | `V7` |
| `loopback_tx[7]` | J8-31 | `EX_IO_5N` | `Y6` |
| `capture_ch[7]` | J8-32 | `EX_IO_5P` | `W6` |

物理回环只需在 J8 上短接：`3↔4`、`7↔8`、`11↔12`、`15↔16`、`19↔20`、`23↔24`、`27↔28`、`31↔32`，并使用 J8-1、J8-37 或 J8-38 共地。J8-2 为 5 V，J8-39/40 为 3.3 V 电源，绝不把电源脚接入 FPGA I/O。

### 核心板与底板连接纪律

- 核心板与底板使用定制 80-pin 母座，0.5 mm 间距，合高 4.5 mm。
- 核心板引脚编号必须逐一对应到底板连接器编号；信号、电源、GND 与 JTAG 网络必须按官方原理图连接，不得自行改变。
- `底板点位图1.pdf` 与配套图片仅用于核对底板机械布局、核心板位置与连接器方向；其本身不提供 FPGA 逻辑管脚映射，不能据此生成 `.fdc`。
- 若后续制作或修改底板，必须使用官方 PCB/原理图中固定的器件坐标和网络，不能移动、旋转或重排核心板相关封装。

### 最小板级约束

Task 10 的最小冒烟工程只能先约束 `FPGA_GCLK_50M=P20` 和一个已确认输出（推荐 `LED1=B2` 或 `UART0_TX=R9`）。顶层端口名必须与 `.fdc` 对象一致。未实际使用的接口不得为“预留”而加入顶层或约束。

## 3. Reset 契约

- 默认使用顶层内部上电复位，`USE_EXTERNAL_RESET=0`。
- 手册表 2-8 将底板 `REST` 映射到核心板 J4 Pin14，电平为 3.3 V；该信号经延时复位芯片连接 PGL50H 专用 `RSTN`，用于重新加载固件，不作为普通用户 I/O 写入 `.fdc`。
- CPU 默认继续使用可验证的内部上电复位。若后续需要人工 CPU 复位，优先从已确认的 `KEY1..KEY8` 中分配一个用户按键，并在 board wrapper 内同步与消抖；不把重新加载固件的 `REST` 当作 Core Reset。
- Reset 选择和同步逻辑属于 board wrapper/SoC 顶层，不得引入 CPU Core。Reset 后不得残留有效存储事务、MMIO side effect 或 UART 发送状态。

## 4. I/O 与电平规则

- 8 个用户按键低有效；8 个用户 LED 高有效。SoC 内部逻辑优先使用语义清晰的高有效信号，极性转换集中于 MES50HP board wrapper。
- 40-pin 扩展口与 PMOD 的通用 I/O 使用 3.3 V；手册明确警告 I/O 不得直接接 5 V 设备。
- 手册已给出时钟、UART、按键、LED、J8、PMOD、DDR3、QSPI、以太网、SFP、PCIe、HDMI、EEPROM 和 SD Card 的 PGL50H 管脚分配及相应电平。项目只将实际使用的 P0 信号写入 RTL 与 `.fdc`，不把未使用接口加入顶层。

## 5. `.fdc` 约束纪律

- 约束文件计划位置：`fpga/constraints/mes50hp_pgl50h.fdc`。
- `FPGA_GCLK_50M=P20` 应建立 50 MHz、20.000 ns 时钟约束；如明确选择 27 MHz 时钟，必须改用 `K21` 与 37.037 ns，二者不得同时作为同一 SoC 的系统时钟。
- `.fdc` 不允许出现 TODO 管脚、旧 PG2L200H 管脚、示例板管脚或臆测管脚。
- 本届实际使用的系统时钟、UART、按键、LED、J8 与 PMOD 均按手册的 3.3 V 电平使用 `LVCMOS33`；不得把 J4 中固定为 1.5 V 的 Bank 3/DDR3 管脚当作 3.3 V GPIO。

## 6. 分层与构建策略

```text
CPU Core（板卡无关）
        |
统一 instruction/data/commit/perf 接口
        |
SoC：RAM + MMIO + UART/GPIO/应用外设
        |
MES50HP board wrapper
  - 50 MHz clock
  - internal/external Reset select
  - key/LED polarity normalization
  - CP2102 UART and extension ports
        |
mes50hp_pgl50h.fdc
```

本地流程固定为“RTL/Testbench Regression -> PDS 目标工程综合/实现/Timing -> MES50HP 下载与 UART/LED 验收”。上板测试应由 UART 输出明确的 `TEST ... PASS/FAIL`，LED 只作为辅助观察证据。

## 7. Gate 状态与验收

### D3 平台决策：PASS

- 正式目标已切换为 MES50HP，并已确认器件、50 MHz 系统时钟、CP2102 UART、按键/LED 极性与主要管脚。
- 旧在线 DUT 不再是正式验收路径。

### Task 10 / G2：PASS

已完成并实测：

1. PDS 项目创建、综合报告和器件选择均复核为 `PGL50H-6IFBG484`；已通过板载 JTAG 下载 bitstream。
2. 50 MHz 时钟约束被 PDS 正确识别，且无未约束时钟。
3. 内部上电复位两次 JTAG 配置均启动通过；当前 SPI Flash 尚未固化，但不影响临时 FPGA 配置冒烟。
4. BRAM 读写延迟、初始化格式、资源推断和严重警告已完成审计；`GTP_DRM36K_E1` 映射已确认。
5. MES50HP `LED1=B2` 两次实体冒烟均常亮，表示 BRAM 自检和板级约束具备重复性。
6. 首次 SPI Flash 扫描虽报错，但 Flash 固化是持久化下载路径，不是本次 Task 10 临时 JTAG/BRAM Gate 的前置条件。

### Task 27 / G9：正式上板

- 在 MES50HP 上完成 Reset、程序执行、GPIO、UART、性能计数器和 PDS ILA 验收。
- 保存 bitstream、PDS 报告、测试镜像、板卡接线与日志的对应关系。

### Task 30 / G11：应用平台风险

8 路输入和 8 路激励输出已冻结为 J8 的八组隔行相邻脚对（3/4 至 31/32），全部为 3.3 V I/O；内部 pattern loopback 不能单独替代 `docs/application_logic_analyzer.md` 规定的 8 通道物理闭环验收。
