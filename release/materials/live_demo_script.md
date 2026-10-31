# 现场演示脚本（Live Demo Script）

> 版本：交付位流切换为 85 MHz 后校正
> 适用配置：`mes50hp_logic_analyzer_pll_top`（**主交付位流，85 MHz**，`C017ED10…`）与 `mes50hp_logic_analyzer_top`（50 MHz，**已验证备用位流**，`8102634A…`），以及 `mes50hp_coremark_top`（CoreMark 计分配置，`DC95F9D0…`）。
> 性质：**现场操作剧本**。本文不是项目完成度证据，也不替代 `docs/progress.md`。
> 口径纪律：实体板实测数据与 RTL 仿真数据分开陈述。板载**晶振**是 50 MHz，交付设计经片上 PLL 倍频到 **85 MHz** 运行（`50 MHz / IDIV 1 = PFD 50 MHz`、`× FDIV 17 = VCO 850 MHz`、`/ ODIV0 10 = 85.000 MHz`，整数分频）；**板级实测最高工作频率 = 85 MHz**（90 MHz 下逻辑分析仪应用的 SPI 模式固件挂死）；PDS 估算的 89.3841 MHz 只是工具估算，不是板上成绩；95 MHz 时序违例，从未上板。

---

## 0. 一句话定位（开场就说这句）

> 这块盘古 50 开发板里跑的 RV32I 五级流水线 CPU 是我用 Verilog 自己写的；CPU 外面挂了一个八通道多协议逻辑分析仪，它采到的 UART、SPI 波形由 CPU 上的裸机软件解成字节，再送到上位机显示和导出 VCD。

三个必须让评委记住的点：

1. **CPU 是真的**：RV32I **+ 完整 M 扩展（RV32IM）**、五级流水线、前递、Load-Use 暂停、分支冲刷、16 项 BTB，有单周期参考模型逐条比对；M 扩展把实体板 CoreMark/MHz 从 0.936 提到 **2.272**。
2. **应用是真的**：八根物理跳线闭环，现场改参数不用重新综合；**采集源还能切到 Core 内部**（MMIO 寄存器 18，同样不用重新综合），用自研仪器量自研 CPU 的总线与流水线行为。
3. **数字是真的**：官方 CoreMark 六个 CRC 全过，与交付位流同频的 85 MHz 实体板 Score **79.587**（RV32I）与 **193.192**（RV32IM，M 扩展），50 MHz 点 46.816 / 113.642；**CoreMark/MHz 0.936 → 2.272**，Before/After 全部可复现。

---

## 1. 演示前 30 分钟清单

### 1.1 硬件（缺一项就不要开始）

- [ ] MES50HP 开发板 + 配套电源
- [ ] USB-JTAG 下载线（下载位流）
- [ ] **独立 USB 数据线接板载 CP2102** —— 只有充电线时串口不会出现，这是历史上踩过的坑
- [ ] 8 根母-母杜邦线接 J8：`3↔4`、`7↔8`、`11↔12`、`15↔16`、`19↔20`、`23↔24`、`27↔28`、`31↔32`，并确认 J8 与板子共地
- [ ] 备用杜邦线 8 根（现场最常见故障就是某一根接触不良）
- [ ] 笔记本：PDS 2024.2-SP2 已装、位流全部在本地，**不依赖网络**

### 1.2 提前开好的窗口（不要现场找文件）

| 窗口 | 内容 |
|---|---|
| PowerShell | 工作目录 `D:\RISC_V_CPU_2026`，字号调大 |
| 上位机 | `python\start_logic_analyzer.cmd`（标题：MES50HP RISC-V 逻辑分析仪） |
| 资源管理器 | `release\evidence\` |
| PDF | `release\materials\technical_report.pdf`，翻到性能分析页 |
| 图片/表格 | CoreMark 成绩与 ILA 结论截图（断网、板坏时的兜底） |

### 1.3 T-15 分钟彩排（必须完整走一遍）

```powershell
# 1) 只读自检：位流哈希、串口、上位机依赖、GTKWave、下载器、材料
.\scripts\demo_preflight.ps1 -Port COM11

# 2) 下载交付位流（逻辑分析仪，85 MHz 主交付）
.\scripts\program_board.ps1 -Config la85

# 3) 采集一轮，确认板上正常
python python\logic_analyzer_serial.py COM11 --mode static --runs 1

# 3b) 双源各抓一枪：确认「采集源」下拉框两条路都通（Core 源报文是 16 字节 0xA8）
python python\logic_analyzer_serial.py COM11 --mode core --runs 1 --output release\evidence\demo_core

# 4) 打开波形，确认 GTKWave 能显示八条通道
.\scripts\show_capture.ps1
```

彩排结束后**再下载一次 `la85`**，让固件回到上电后的 `LA_READY` 等待状态。
若彩排中出现"板子一个字节都不输出"，说明有一枪的触发条件从未命中把固件停住了 ——
按板上 `REST` 或重下 `la85`，然后**把触发改成电平触发**再继续（见 §6 与
`docs/application_logic_analyzer.md` §6.10.7）。

> 脚本执行策略：如果报 `running scripts is disabled on this system`，改用
> `powershell -ExecutionPolicy Bypass -File scripts\demo_preflight.ps1 -Port COM11`。
> **这个必须提前解决，不要在现场改系统策略。**

---

## 2. 三档时间线

| 时间 | 场景 | 内容 |
|---|---|---|
| **3 分钟** | 巡场 / 初评 | 第 1 幕定位 + 第 2 幕动作 1～5（板子已下载好） |
| **8 分钟** | 推荐主用 | 第 1～5 幕全走，CoreMark 用 50 MHz 位流 `cm50`（85 MHz 点用 `cm85`） |
| **15 分钟** | 决赛 / 深度问询 | 8 分钟版 + ILA 波形展开 + 回归现场跑 + 架构图详讲 |

时间不够时的取舍顺序：**先砍回归演示 → 再砍 ILA 讲解 → 再砍 DDR3/中断加演 → 绝不砍应用闭环（第 2 幕）**。

---

## 3. 逐幕脚本

### 第 1 幕　定位（0:00–0:40）

**动作**：手指标签和开发板，手不要碰键盘。

**口播**：

> 这是盘古 50 开发板，FPGA 里是我自己写的 RV32I 处理器，经典五级流水线：取指、译码、执行、访存、写回。数据相关在 EX 级用前递解决，Load-Use 插一个气泡，分支和跳转确认后冲刷错误路径，另外挂了一张 16 项的直接映射 BTB 做动态预测。
> 板子上除了 CPU 还有 UART、GPIO 和一个八通道逻辑分析仪。**逻辑分析仪不是 CPU 内部的模块**，它是 CPU 外面的一个 MMIO 外设，CPU 只发统一的取指和数据访问事务，所以换外设不用动流水线。

**给非本方向评委的备用比方**：

> CPU 像一个只会按地址读写信箱的办事员，逻辑分析仪是外面的一台仪器。办事员不需要认识仪器，只要按地址读写信箱 —— 所以仪器换了，办事员不用重训。
> （这个比方不准确的地方：事务并不是"写信箱"那么便宜，外设变慢时 CPU 要真的停下来等，这个等待是流水线 stall 的主要来源之一。）

---

### 第 2 幕　应用实机闭环（0:40–3:00）★ 主戏

#### 动作 1　指 J8 的八根跳线（10 秒）

**口播**：

> 这八根线，一头接 FPGA 的输出脚，另一头接它自己的输入脚。信号从芯片出来、走物理线、再回到芯片被采回来 —— **不是 FPGA 内部假回环**。用物理回环才能证明输入通道、电平和时序都是真的。

#### 动作 2　上位机采集四种模式（40 秒）

点击「采集四种模式并生成 VCD」，`Runs/模式` 保持 `1`。

预期画面：逐行出现 `LOGIC ANALYZER BOARD RUN n/n PASS`，最后 `LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`（五模式 × 20 轮就是验收口径）。

**口播**：

> 上位机通过串口发一个 13 字节、带 XOR 校验的配置包，CPU 上的裸机软件把它写进逻辑分析仪的 MMIO 寄存器：模式、数据、速率、触发类型、触发通道、触发值、触发前和触发后采样数。FPGA 采满 256 个样本，软件读回来、解析协议、再从 UART 发上来。
> 现在这四种：static 是固定电平，用来确认八条通道的映射；counter 是连续计数，确认八条通道都在动；UART 和 SPI 是软件从采样点里把字节解出来，和期望值直接比对。

#### 动作 3　现场改参数（40 秒）★ 可重构的证据

```powershell
python python\logic_analyzer_serial.py COM11 --mode uart --value 0x5A --runs 1 --output release\evidence\demo_uart
python python\logic_analyzer_serial.py COM11 --mode spi  --value 0xC3 --runs 1 --output release\evidence\demo_spi
```

**口播**：

> 我把 UART 的测试字节从默认的 A5 改成 5A，SPI 从 3C 改成 C3 —— **没有重新综合，只发了一包配置**。工具会把解出来的字节和期望值比对，两个新值都过，说明波形、速率、触发条件都是软件现场决定的。

#### 动作 4　看真实波形（40 秒）

```powershell
.\scripts\show_capture.ps1 -Vcd release\evidence\demo_uart\uart_00.vcd
```

（该脚本会自动插入 `capture.ch0..ch7` 并缩放到全窗口。）

**口播**：

> 这是八条通道的原始采样，深度 2048 点。触发配在通道 0 的下降沿，触发点由刚才那一包配置里的 pre/post。UART 的起始位、8 位数据、停止位在波形上可以直接看出来。

若一键打开失败，**不要在现场排障**，手工操作：GTKWave 左侧 SST 面板展开 `capture`，选中 `ch0`～`ch7` 后点 Insert，再按 Zoom Fit。

#### 动作 5　把同一台仪器接到自研 CPU 上（40 秒）★ 双源切换

在界面上把**「采集源」**从 `J8 外部 8 路` 改成 `Core 内部观测点`（模式选 `core` 也行：选中后采集源会自动跟着切），点一次采集。

事件日志里出现（`[14]` 字节 = 1 说明源写入生效）：

```text
[core] 报文 a80000000000000140004000bf070110 · 采集源=Core 内部观测点 ...
LOGIC ANALYZER BOARD RUN 1/1 PASS mode=core view=core samples=1987 trigger=3
```

**口播**：

> 刚才八根线量的是回环，现在把同一台仪器的八路探头切到 CPU 内部 —— 只写一个 MMIO 寄存器，**不重新综合、不换位流**。八路分别是取指请求/接受/响应、访存请求/接受、流水线暂停、控制流冲刷和指令提交。
> 这一窗 1987 拍全速采样里有 1187 条提交，窗口 IPC 大约是 0.597；停顿占 39.5%，主因就是软件乘法留下的乘法器缺失 —— 这个数就是我们后来做 M 扩展的起点，做完之后 CoreMark/MHz 从 0.936 变成 2.272。

**给非本方向评委的备用比方**：

> 同一台示波器，探头原来夹在测试回环上，现在夹到 CPU 的引脚上。仪器没换，被测对象换了，而且换的时候不用停机。
> （这个比方不准确的地方：CPU 内部信号是有限的八路观测点，不是"想夹哪儿就夹哪儿"，加观测点要改板级顶层。）

#### 动作 6　稳定性（可选，30 秒）

```powershell
.\scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20
```

**口播**：五模式各 20 轮，一共 **100/100** 通过 —— 这是本批 85 MHz 交付位流的验收成绩。同一颗位流更早批次另外做过 3 轮 soak、每轮 80 次，累计 **320 次连续采集零失败**，这就是连续采集的稳定性证据（`release\evidence\logic_analyzer_board_85m_soak\`）。

---

### 第 3 幕　CoreMark 实体成绩（3:00–5:00）

#### 动作 1　换位流（下载的 30 秒用来讲架构）

```powershell
.\scripts\program_board.ps1 -Config cm50
```

下载期间**口播**（评委在等，正好讲）：

> 换位流大概要半分钟，我顺便说下正确性怎么保证的。我先做了一版单周期 CPU，把它当作参考模型冻结下来；五级流水线做出来以后，同一个程序分别在两个 CPU 上跑，按退休顺序逐条比对 PC、指令、寄存器写回和内存写入，出现差异就报第一条不一致，不是只比最后结果。现在覆盖 RV32I 定向测试、上游 RV32UI 测试、真实 GCC 程序、随机背压和 Reset，一共 20 个自动化入口。

#### 动作 2　跑 CoreMark（21 秒）

```powershell
python python\coremark_serial.py COM11
```

脚本每秒发一次 `R` 启动，运行 21.36 秒后输出：

```text
COREMARK BOARD PASS port=COM11 clock_hz=50000000 ticks=1068006999 seconds=21.360 score_x1000=46816
```

**口播**：

> 这是官方 CoreMark v1.0 源码，用 `-march=rv32i -mabi=ilp32` 编的裸机程序，50 MHz 跑了 21.36 秒 —— 官方要求不低于 10 秒，我们满足。四个官方 CRC 全部通过，输出 `Correct operation validated.`。
> 关键数字：50 MHz 这一点的 CoreMark/MHz 是 0.936，CPI 1.508。
> 另外，与交付位流同频的 85 MHz CoreMark 位流 `cm85` 也已经在实体板上跑完：Score **79.587**、CoreMark/MHz 同样是 0.936、官方 CRC PASS —— 也就是说交付件的 85 MHz 工作频率是有配套计分点支撑的。80 MHz 和 90 MHz 的测点分别是 74.905 和 84.269。
> 补充一句口径：`Score` 等于 `Iterations /(运行时间 × 频率)`，本质就是 CoreMark/MHz，是频率归一化的；提频率只服务于"最高工作频率"这一个计分项，要提 Score 必须降 CPI。

---

### 第 4 幕　为什么快：性能归因（5:00–6:30）

**画面**：`release\evidence\ila_coremark\` 与报告里的 CPI 归因表。

**口播**：

> 我们不只是报一个好数字，而是把瓶颈找出来了。
> 我用 PDS 的 Fabric Debugger 在板上抓了 512 拍的内部波形，看到取指请求在大量周期里是空的 —— 取指每两拍才能发一条。根因在取指请求的交接：旧响应被接收的那一拍，新请求还没有登记。
> 改法是在接受请求的当拍就把下一笔请求武装好。改完之后实体板 CPI 1.508、Score 46.816 —— 这是同一块板子上改完之后的实测结果。
> 另外，在 CoreMark ILA 抓取的 512 拍窗口里，84.3% 的提交指令落在 libgcc 的软件乘法 `__mulsi3` —— 这就是取指满速之后剩下的最大单项。**这一条本批已经做完**：我们给 Core 加了完整 M 扩展（`rtl/mdu.v`），同一份 RTL、同一份程序，只把 `-march` 换成 `rv32im`：实体板 50 MHz 的 Score 从 46.816 提到 **113.642**，**与交付时钟同频的 85 MHz 上从 79.587 提到 193.192**，CoreMark/MHz 从 0.936 提到 **2.272**，正好 2.43 倍；同源同频下 CoreMark/LUT 也从 0.0190 提到 0.0460（同样是 2.43 倍，因为面积不随程序变）。

---

### 第 5 幕　正确性与收尾（6:30–8:00）

```powershell
.\scripts\run_final_regression.ps1 -Quick
```

约 1～2 分钟；时间紧时直接展示预跑日志（`ALL AUTOMATED FINAL REGRESSION PASS`）。

**口播**：

> 单周期版本是参考模型。流水线每一次退休都和它逐条比对，出现差异直接报第一条不一致。现在全部自动化入口通过。

**收尾一句话**：

> RISC-V 多协议逻辑分析仪 —— 一颗可验证的自研处理器，加上一个软件可重构的采集与协议解析闭环。

---

## 4. 数字口径卡（照着说，不要凭记忆）

### 4.1 实体板实测（权威，可以说）

| 项目 | 数值 | 证据位置 |
|---|---|---|
| CoreMark @85 MHz PLL（**与交付位流同频**） | **Score 79.587**、CoreMark/MHz **936**、官方 CRC PASS（位流 `cm85`） | `release/evidence/fmax_ceiling/README.md` |
| CoreMark @50 MHz | **Score 46.816**、CPI **1.508**、21.360 s、ticks 1,068,006,999、四个官方 CRC 全过 | `release/evidence/coremark_board.json` |
| CoreMark @80 MHz PLL | **Score 74.905**、CoreMark/MHz **936**、官方 CRC PASS | `release/evidence/fmax_ceiling/README.md` |
| CoreMark @90 MHz PLL（CPU 板级上界） | **Score 84.269**、CoreMark/MHz **936**、官方 CRC PASS；仅 CPU+最小 SoC，**不代表逻辑分析仪应用能跑 90 MHz** | `release/evidence/fmax_ceiling/README.md` |
| **CoreMark @50 MHz（RV32IM，M 扩展）** | **Score 113.642**、**CoreMark/MHz 2272**、CPI 1.550、17.599 s、**2000 迭代**、官方 CRC 全过（位流 `cmim`） | `release/evidence/coremark_board_im.json` + `coremark_uart_im.log` |
| **CoreMark @85 MHz（RV32IM，与交付同频）** | **Score 193.192**、**CoreMark/MHz 2272**、CPI 1.547、20.704 s、**4000 迭代**、官方 CRC 全过（位流 `cmim85`，WNS +0.250 ns） | `release/evidence/coremark_board_cmim85_20261014.json` + `coremark_uart_cmim85_20261014.log` |
| CoreMark/MHz ×1000 | RV32I **936**（50／80／85／90 MHz 四个频点一致）／ RV32IM **2272**（50 MHz）——**两套 ISA 并列，引用必须写明** | `release/evidence/fmax_ceiling/README.md`、`coremark_board_im.json` |
| **逻辑分析仪 Core 探针（双源可选）** | 2048 点全速窗口：**1187 条提交 / 1987 拍 ⇒ 窗口 IPC ≈0.597**、停顿 **785 拍（39.5%）**、4 次冲刷；flush/stall 两组触发各 3 次全 PASS | `release/evidence/core_probe_board/` |
| 逻辑分析仪实体回环（85 MHz 交付位流） | **100/100 PASS**（五模式 × 20 轮，本批 10-14 复测）；更早批次另有 3 轮 soak × 80、累计 320 次零失败（旧位流口径） | `release/evidence/logic_analyzer_board_85m/`、`release/evidence/logic_analyzer_board_85m_soak/` |
| 逻辑分析仪实体回环（50 MHz 备用位流） | 五模式 × 1 冒烟 PASS（2026-10-14 重建后验证），仅作回退用 | `release/evidence/logic_analyzer_board_final/` |
| PDS ILA 实测窗口（2026-09-17 批次） | 512 拍、**IPC 0.635 / CPI 1.575**；84.3% 提交落在 `__mulsi3`；44 次 flush | `release/evidence/ila_coremark/` |

### 4.2 综合与时序（PDS 结果，必须说明是工具报告）

| 项目 | 数值 |
|---|---|
| 主交付配置（`la85` 位流 `C017ED10…003FAA4F`，85 MHz PLL 顶层 `mes50hp_logic_analyzer_pll_top`） | **4995 LUT、3908 FF、6.0 个 DRM18K**、setup WNS **+0.577 ns**、hold WHS **+0.304 ns**、估算 Fmax **89.3841 MHz**，85 MHz 约束下 All Constraints Met |
| 已验证备用配置（`la50` 位流 `8102634A…3986B012`，50 MHz 顶层 `mes50hp_logic_analyzer_top`） | **4704 LUT、3903 FF、6.0 个 DRM18K**、setup WNS **+2.217 ns**、hold WHS **+0.315 ns**、估算 Fmax **（见 50 MHz 位流构建报告）** —— 只在主交付出问题时回退，不进入交付口径 |
| CoreMark 50 MHz 位流 | All Constraints Met |
| CoreMark 80 MHz PLL（2026-09-17 旧批次，已被取代） | WNS +0.667 / WHS +0.312 ns，估算 Fmax 84.51 MHz |
| 关键路径/上界实测 | 逻辑分析仪应用板级上界 **85 MHz**（90 MHz 下 SPI 模式固件挂死）；CoreMark 配置板级上界 **90 MHz**（Score 84.269）；95 MHz PDS 时序违例、**从未上板** |

### 4.3 RTL 仿真（必须说"仿真"，不得说成板上成绩）

| 项目 | 数值 |
|---|---|
| CoreMark Predictor On | cycles 1,251,724、CPI **1.5907**、BTB hit 221,615、mispredict 69,120 |
| CoreMark Predictor Off | cycles 1,604,264、CPI **2.0670** → On 减少 **21.98%** |

### 4.4 绝对不要说的三句

1. ❌ "实体板 CPI 2.6682 / CoreMark/MHz 0.520 / Fmax 68.2594 MHz" —— 那是早期 RTL 仿真估算，已被实体实测取代。`release/materials/defense_qa.md` 已同步为实体口径，背诵时以该文件的"必须张口就对的数字"表为准。
2. ❌ "交付件跑在 50 MHz" / "85 MHz 只是约束扫描点、没上过板" —— 交付位流 `C017ED10…` 就是 **85 MHz** 构建（板载 50 MHz 晶振经片上 PLL 倍频），85 MHz 下五模式 **100/100**（本批复测）；50 MHz 的 `8102634A…` 是**已验证备用**位流，不能再当交付口径。
   ❌ 反过来也不能说"PDS 估算 Fmax 89.3841 MHz，所以板子跑 90 MHz" —— 89.3841 MHz 只是**工具估算**；**板级实测最高工作频率是 85 MHz**。90 MHz 只有 CoreMark 配置能跑（Score 84.269），逻辑分析仪应用在 90 MHz 的 SPI 模式**固件挂死**；95 MHz 时序违例、从未上板。
3. ❌ "做了压缩 / RLE"、"支持 16 通道" —— 这两项才是本届冻结项，说了就是虚报。⚠️ 但"有 Cache"、"有完整异常中断"要分清楚：Cache、突发传输和外部 DDR3 本届**做了**（S1～S4 都执行过），机器模式 CSR/Trap/MRET 和定时器中断也**已实现并进入交付位流**，所以不能说它们不在范围；**不能说**的是"Cache 带来了加速" —— I/D-Cache 已按止损条件默认关闭，交付配置和上面的 CoreMark 分数都不含 Cache。

---

## 5. 追问速答

1. **CPU 是你自己写的吗？**
   RTL 是我自己写的，从单周期到五级流水线。测试平台、自动化回归和对比脚本由 AI 助手协助完成，这也是为什么我能给出每个模块的 PASS 数和失败定位方法。

2. **为什么先做单周期？**
   单周期是参考模型。流水线一旦和它在最终状态、提交 trace 上有差异，我能立刻定位到哪一条指令第几个周期出错，而不是靠肉眼猜。

3. **数据冒险怎么处理？**
   EX 级前递，覆盖一级和二级相关，包括双源和同 rd 优先级；Load-Use 无法前递时插一个气泡；EX 级之前的写回值在访存等待期间会保持，避免转发到旧值。

4. **分支怎么处理？**
   预测命中就继续，未命中在确认拍冲刷错误路径；JAL/JALR 也走同一条 redirect 通道。16 项 BTB 配 2-bit 饱和计数器，仿真里 On 比 Off 减少 21.98% 周期。

5. **为什么交付配置里没有 Cache？**
   Cache 和突发传输不是"没做"，而是**做了、量过、按止损关掉了**。2026-09-29 批准纳入本届，按 S1 打通 DDR3 → S2 行式突发 → S3 2 路组相联 I-Cache → S4 2 路组相联 D-Cache 的顺序推进：S2 通过，总线周期从 48 拍降到 30 拍，降了 37.5%；S3 的 I-Cache 把周期从 1,251,724 拉到 2,891,324，S4 的 D-Cache 拉到 1,348,302，反而慢 7.7%。所以按事先定好的止损条件，两个 Cache 都默认关闭。结论不是"做不出来"，而是**片上 BRAM 的访问延迟本来就比一次 Cache 命中还短**，后端还是 BRAM 的时候 Cache 不可能有净收益，要等真正的 DDR3/HMIC 后端接进存储路径才可能翻盘。AI/YOLO、RLE 这些仍然不在本届范围。

6. **性能数字怎么保证不是编的？**
   每个数字都对应一个可复现入口和一份原始日志：`release/evidence/` 下有串口原始输出、JSON、VCD，位流有 SHA-256 清单。CoreMark 用官方源码和官方 CRC。

7. **你们的逻辑分析仪和 PDS 的 ILA 有什么区别？**
   PDS ILA 是用来分析我 CPU 内部流水线的调试工具，只在诊断位流里，不占计分配置的资源。作品里的逻辑分析仪是 CPU 外面的一个 MMIO 外设，是交付功能本身，测的是外部信号。

8. **采样率多少？**
   内部最高采样率与系统时钟同频（`sample_div=0`，交付位流是 85 MHz 工作时钟），八通道、2048 点原始缓存；异步输入在这个速率下存在亚稳风险，所以正式演示用的是可软件配置的分频。

9. **为什么跑 85 MHz？**
   板子上的晶振是 50 MHz，交付设计过片上 PLL 倍频：`50 MHz / IDIV 1 = PFD 50 MHz`、`× FDIV 17 = VCO 850 MHz`、`/ ODIV0 10 = 85.000 MHz`，是精确的整数分频。我们把 PLL 逐级上推做板级实测：85 MHz 下五模式 **100/100** 通过、另有 3 轮 soak 共累计 320 次连续采集零失败；90 MHz 的 CoreMark 位流能跑完（Score 84.269），但逻辑分析仪应用在 90 MHz 的 SPI 模式固件挂死，所以应用级上界记为 85 MHz，交付位流就构建在 85 MHz。PDS 对交付配置的估算 Fmax 是 89.3841 MHz —— 那是工具估算，不当作板上成绩；95 MHz 的版本 PDS 时序已经违例，从没上过板。

10. **最难的地方是什么？**
    找 CPI 的根因。一开始怀疑访存，做了归因观测台之后发现瓶颈在取指串行化上，改动只有一行条件，但定位花的时间远多于修改。

11. **代码规范怎么保证？**
    所有核心模块都有独立 Testbench 和 PASS/FAIL 输出，改动后必须重跑回归；Core/SoC 边界写在接口文档里，外设专用逻辑不得进入 CPU 顶层。

12. **如果还有时间做什么？**
    硬件乘法器（消掉 `__mulsi3` 的开销）、正确预测的跳转不再重定向（约 7.7% 周期）、以及赛后研究的采集数据无损压缩。这些都在文档里写明了范围和预期收益。

---

## 6. 故障分级处置

| 级别 | 现象 | 处置 | 耗时 |
|---|---|---|---|
| 一级 | 上位机找不到串口 | 重新插拔 CP2102 数据线 → 刷新串口 → 只选含 `Silicon Labs/CP210x` 的项 | 30 秒 |
| 一级 | 一直等不到 `LA_READY`，且报错里是 `bytes=0`（板子一个字节都不输出） | **触发条件没出现把固件停住了**：按板上 `REST` 重新加载（或重下 `la85`），恢复后先用 `static`（电平触发）确认链路 | 1 分钟 |
| 一级 | 一直等不到 `LA_READY`，但报错里有字节数 | 确认下载的是 `la85` 交付位流；若仍异常切回已验证备用 `la50`；按板子 `REST` 重新加载 | 1 分钟 |
| 二级 | static 过、UART/SPI 失败 | 检查八组 J8 脚对是否接牢，换备用杜邦线 | 2 分钟 |
| 二级 | CoreMark 无输出 | 重新下载 `cm50`；确认串口参数 115200 8N1 | 2 分钟 |
| 三级 | 板子完全不响应 | **切证据模式**：用本地日志、JSON、VCD、ILA 波形截图和报告继续讲，不再动板子 | 立即 |

**铁律**：任何时候都不在评委面前改 RTL、改代码、重新综合。完整处置见 `release/materials/field_recovery_card.md`。

---

## 7. 演示后留存

- 现场每一轮的串口原始日志、JSON、VCD 都保存到独立目录，**失败记录也保留**，不要覆盖。
- 记录使用的位流 SHA-256（`.\scripts\demo_preflight.ps1` 会打印）。
- 如果现场换了参数（新数据值、新触发条件），把这些值记下来，便于复现。
- 现场发现的问题写入 `docs/debug_log.md`，材料层面的问题写入 `docs/progress.md`。

---

## 附：现场命令集中卡（可直接复制）

```powershell
# 自检
.\scripts\demo_preflight.ps1 -Port COM11

# 下载
.\scripts\program_board.ps1 -Config la85     # 逻辑分析仪 85 MHz（主交付位流）
.\scripts\program_board.ps1 -Config la50     # 逻辑分析仪 50 MHz（已验证备用，主版本失败时回退）
.\scripts\program_board.ps1 -Config cm50     # CoreMark 50 MHz
.\scripts\program_board.ps1 -Config cm85     # CoreMark 85 MHz（与交付位流同频，RV32I Score 79.587）
.\scripts\program_board.ps1 -Config cmim85   # CoreMark 85 MHz RV32IM（M 扩展，与交付同频，Score 193.192）
.\scripts\program_board.ps1 -Config cmim     # CoreMark 50 MHz RV32IM（Score 113.642）
.\scripts\program_board.ps1 -Config cm90     # CoreMark 90 MHz（CPU 板级上界，Score 84.269）
.\scripts\program_board.ps1 -Config ila      # CoreMark + DebugCore（仅诊断）

# 应用闭环
python python\logic_analyzer_serial.py COM11 --mode uart --value 0x5A --runs 1 --output release\evidence\demo_uart
python python\logic_analyzer_serial.py COM11 --mode spi  --value 0xC3 --runs 1 --output release\evidence\demo_spi
.\scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20
.\scripts\show_capture.ps1

# CoreMark
python python\coremark_serial.py COM11

# 回归
.\scripts\run_final_regression.ps1 -Quick
```
