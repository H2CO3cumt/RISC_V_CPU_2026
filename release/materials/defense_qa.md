# 答辩问答稿

## 为什么先做单周期 CPU

单周期 CPU 提供简单、稳定的架构参考。流水线与它运行同一程序后，自动比较 x1 至 x31、关键 RAM 和退休 trace。若结果不同，比较器报告第一条不一致提交以及具体字段，定位比只看最终状态更直接。

## 五级流水线如何处理数据冒险

EX 级优先使用 EX/MEM 结果，其次使用 MEM/WB 结果；x0、无效写回和出错响应不参与前递。Load 数据在 EX/MEM 阶段尚未可用，因此紧邻使用者触发 Load-Use Stall，冻结前端并向 ID/EX 注入 Bubble。数据事务整体等待期间，WB 值必须继续可前递，这一点有独立定向用例覆盖。

## 分支和跳转如何保证错误路径没有副作用

Branch、JAL 和 JALR 在 EX 级确定重定向。Redirect 冲刷 IF/ID 与 ID/EX 的错误路径指令。被冲刷指令不得进入 Store 请求、寄存器写回或退休 trace；已展示但尚未接受的取指请求按握手协议完成后丢弃其响应。

## Core 与外设如何解耦

`pipeline_cpu` 只暴露取指事务、数据事务、提交 trace 和通用性能事件。RAM、地址译码、UART、GPIO、逻辑分析仪和板级引脚都位于 Core 外。最终只交付一套完整配置，范围审计同时检查 Core 中不存在设备地址或设备专用端口。

## 为什么 CoreMark 数字分为仿真估算和实体实测

官方 CoreMark 在 fixed、random 和同步 FPGA memory model 下均通过官方 CRC（`Correct operation validated.`）。**实体板计分已经完成**，但要分清**用的是哪个位流、哪一套 ISA**：

**（1）RV32I 基线口径**——CoreMark 跑在**独立的 CoreMark 位流** `fpga/coremark/generate_bitstream/mes50hp_coremark_top.sbit`（SHA-256 `DC95F9D0…`）上，**不是**交付的那颗逻辑分析仪位流——因为 ILA/逻辑分析仪的资源不应混进 CoreMark 的面积与频率口径。该位流在 MES50HP 上实测 50 MHz Score **46.816**（21.360 s、1000 次迭代），`CoreMark/MHz ×1000` 为 **936**（即 0.936），CPI **1.508**，官方 CRC 校验 PASS。CoreMark 频点扫描随后已在实体板上补全：80 MHz Score **74.905**、85 MHz Score **79.587**、90 MHz Score **84.269**，四个频点的 `CoreMark/MHz` 都是 **0.936**、官方 CRC 全部 PASS；其中 **85 MHz 那一点与交付位流的工作时钟同频**，但它仍来自独立的 CoreMark 位流（`cm85`），不是交付的那颗逻辑分析仪位流。

**（2）RV32IM 增强口径（2026-10-14 新增，M 扩展）**——Core 实现了完整 M 扩展（`mul/mulh/mulhsu/mulhu/div/divu/rem/remu`），同一份 RTL、同一份程序、只把 `-march` 换成 `rv32im`。**两个频点都已实测**：独立位流 `fpga/coremark_im`（SHA-256 `BE7A4FF3…`）在 50 MHz 下 **Score 113.642**（17.599 s、**2000 次迭代**）、CPI 1.550；独立位流 `fpga/coremark_im_85m`（SHA-256 `EE8B6536…`，`All Constraints Met`，WNS +0.250 ns）在**与交付位流同频的 85 MHz**下 **Score 193.192**（**20.704 s、4000 次迭代**）、CPI 1.547。两个频点的 **`CoreMark/MHz` 都是 2.272**、`ticks/迭代` 都是 **439,975 拍**（逐位一致），官方 CRC 全过。相对 RV32I 基线（同频 85 MHz：79.587）是 **2.43×**；同频下 **CoreMark/LUT 也从 0.0218 提到 0.0460（2.11×）**。依据是"CoreMark 的矩阵段每迭代 10,575 次乘法全部走 libgcc 软件乘法、占约 60% 的退休指令"（板级 ILA 实测 84.3% 的提交落在 `__mulsi3`）。**两套 ISA 并列，rv32i 仍是默认与可比口径**；CoreMark 输出自带 `Compiler flags : -O2 -march=rv32im -mabi=ilp32` 一行可自证，说分数**必须写明是哪一套**。

交付位流（`mes50hp_riscv_logic_analyzer.sbit`，SHA-256 `C017ED10…003FAA4F`）顶层是 `mes50hp_logic_analyzer_pll_top`，工作时钟 **85 MHz**（板载晶振 50 MHz 经片上 PLL：PFD 50 MHz、× FDIV 17 = VCO 850 MHz、/ ODIV0 10 = 85.000 MHz），85 MHz 约束下 All Constraints Met；本批（10-14）重建后时序与资源以 `release/evidence/automated_metrics.json` 与 `claims_map.md` 为准。50 MHz 版本（`mes50hp_logic_analyzer_top`，SHA-256 `8102634A…3986B012`）是**已验证备用位流**，只在主交付版本出问题时回退。RTL 仿真用于说明架构趋势和官方 CRC，不作为实体成绩。

> **引用纪律**：任何实体分数都必须同时说明它来自**哪颗位流**与**哪一套 ISA**。把 CoreMark 的 Score/CPI 说成"交付位流的成绩"是错的；把备用 50 MHz 位流的数字说成交付口径同样是错的；把 2.272（rv32im）说成"rv32i 的成绩"也是错的。

## 为什么交付的位流跑在 85 MHz

因为"最高工作频率"这一计分项要由**实际递交的 bitstream 自己举证**：如果报告宣称一个交付件并没有跑到的频率，等于把估算当成绩。所以逻辑分析仪应用在实体板上把 PLL 逐级上推实测：85 MHz 下五模式各 20 次 **100/100 PASS**（2026-10-14 复测）；更早批次另有 3 轮 soak 各 80 次、累计 320 次连续采集零失败；90 MHz 下 PDS 时序虽然收敛，但逻辑分析仪应用的 SPI 模式固件挂死（须重下位流才能恢复），因此应用级上界记为 85 MHz，交付位流就构建在 85 MHz。PDS 估算的 89.3841 MHz 只是工具估算、不是板上实测；95 MHz 版本 PDS 时序违例，从未上板。明细见 `release/evidence/fmax_ceiling/README.md`。

交付包同时带一份 50 MHz 已验证备用位流（`bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit`），这也正好满足 `docs/roadmap.md` Task 35 的验收条目："主版本失败时能切换已验证备用版本，不使用未验证临时代码"。

## CPI 1.508 的主要来源是什么

同步片上存储模型、取指与数据事务等待、Load-Use 相关和控制流冲刷共同增加周期。**实体板实测**（50 MHz 单点，CoreMark 位流 `DC95F9D0…`）：1000 次迭代 1,279,896,248 cycles、848,491,425 条退休指令，对应 CPI **1.508**。板级性能计数器给出的分项（折算到每 1000 条退休指令）是：理想 **1000** + stall **206.0** + flush **75.6** + 剩余取指与事务开销 **约 226.8**，合计 **1508.4**（原始计数：stalls 174,789,140、load-stalls 63,079,449、flushes 64,153,920、branches 240,477,872、taken 165,302,707）。性能计数器同时记录 stall、load stall、branch、taken 和 flush 五项事件，便于在 ILA 中对照关键循环。CPI 的最大单项优化来自取指满速交接（`if_arm`），把 CPI 从早期批次的 2.3443（该值未登记，仅作趋势参考）降到 **1.508**；当前剩余的最大单项空间是数据事务握手流水化，RTL 仿真（Predictor On 固定延迟）CPI 1.5907 中访存事务等待仍是主要构成。

## PDS ILA 和作品逻辑分析仪有什么区别

PDS DebugCore 观察 CPU 内部退休、流水控制和握手信号，用于性能诊断。作品逻辑分析仪是 Core 外部 MMIO 外设，采集板外八路数字信号并由 RISC-V 软件解析 UART/SPI。二者的对象、资源配置与演示目标不同。

## 附：必须张口就对的数字

| 指标 | 数值 | 口径 |
|---|---|---|
| CoreMark Score | **79.587 @85 MHz**（与交付位流同频）；另 46.816 @50 MHz、74.905 @80 MHz、84.269 @90 MHz | 实体板实测，均来自**独立 CoreMark 位流**（RV32I） |
| **CoreMark Score（RV32IM）** | **193.192 @85 MHz**（`cmim85`，4000 迭代、20.704 s，**与交付位流同频**）／ **113.642 @50 MHz**（`cmim`，2000 迭代、17.599 s） | 实体板实测，独立 CoreMark 位流 `EE8B6536…` / `BE7A4FF3…`，**与上面一行不是同一套 ISA** |
| CoreMark/MHz ×1000 | **936**（RV32I，50／80／85／90 MHz 四个频点一致）／ **2272**（RV32IM，**50 与 85 MHz 两点一致**，**2.43×**） | 实体板实测；两套 ISA 并列，引用必须写明 |
| CoreMark/LUT（85 MHz **同源同频**） | **0.0460**（RV32IM 193.192÷4198 LUT） vs **0.0190**（RV32I 79.587÷4198 LUT）⇒ **2.43×**（两颗位流 LUT/FF/WNS 逐项相同，面积不随程序变） | 分母 = 各自计分位流 PnR 后的**整机** LUT；rv32i 用当前 RTL 重建的 `cm85r` 才同源 |
| CPI | ≈1.50（RV32I @50 MHz，窗口敏感 1.494–1.508）／ 1.550（RV32IM @50 MHz）／ 1.547（RV32IM @85 MHz） | 实体板实测（CoreMark 位流） |
| 官方 CRC | 校验 PASS（RV32I 四个频点 + RV32IM 两个频点全部 PASS） | 实体板实测 |
| 最高工作频率（板级实测） | **85 MHz** | PLL 逐级上推实测：85 MHz 五模式 100/100；90 MHz 的 LA 配置 SPI 模式固件挂死，故应用上界 85 MHz（`release/evidence/fmax_ceiling/README.md`） |
| 实体板上板频率 | **85 MHz** | 板载晶振 50 MHz，经片上 PLL 倍频到 85 MHz（交付位流即 85 MHz 构建） |
| 最终资源 | 交付位流与 CoreMark 位的 LUT/FF/DRM 见 `release/evidence/automated_metrics.json`（本批 10-14 重建后的值） | 85 MHz 交付位流综合统计 |
| 最终 bitstream | `C017ED10…003FAA4F`（85 MHz 主下载）/ `8102634A…3986B012`（50 MHz 已验证备用） | 交付包 `bitstream/` 两份，哈希一致 |
| 逻辑分析仪 | 8 通道、Raw **2048** 点、85 MHz **五模式 100/100**；**采集源双源可选**（J8 外部 / Core 内部观测点，MMIO 寄存器 18） | Capture Engine + J8 实测；Core 探针 6 次采集 PASS |

> 四个最容易说错的地方：① PDS 估算 Fmax 89.3841 MHz 只是工具估算，**板级实测最高工作频率是 85 MHz**；90 MHz 只有 CoreMark 配置能跑（84.269），逻辑分析仪应用的 SPI 模式在 90 MHz 挂死，95 MHz 时序违例、从未上板，三者不可混写；② 说 Score 必须带频率，且必须说明来自独立的 CoreMark 位流（85 MHz 点用 `cm85`），不可说成"交付位流的成绩"；③ RTL 仿真值与实体实测值不可互换（仿真 Predictor On 1.5907、Predictor Off 2.0670，实体 50 MHz 用 1.508）；④ **必须说明是哪一套 ISA**：rv32i 是 0.936（可比基线），rv32im 是 2.272（M 扩展增强口径），两个数并列、不可混写，也不可把 2.272 说成"基线的成绩"。

## 为什么正式 CoreMark bitstream 不含 DebugCore

DebugCore 消耗额外逻辑和存储资源，也可能改变关键路径。项目把**计分配置**与**诊断配置**分开：交付与资源/Fmax 口径只用主交付 bitstream `mes50hp_riscv_logic_analyzer.sbit`（85 MHz，资源与时序见 `release/evidence/automated_metrics.json`）；交付包里另有一份 50 MHz 的已验证备用位流 `mes50hp_riscv_logic_analyzer_50m_fallback.sbit`，它只在主交付版本出问题时回退，其 4704 LUT / 3903 FF / 6.0 DRM18K、估算 Fmax （见 50 MHz 位流构建报告） 不进入交付口径；抓内部波形时另建带 DebugCore 的诊断位流，其资源与时序数字同样不并入交付口径。这样几套数字不会互相污染。

## 逻辑分析仪为什么选择 Raw 而没有实现 RLE

本届优先保证 RV32I、流水线、CoreMark、Timing 和实体闭环的正确性与可复现性。Raw 模式已经覆盖 8 通道、前后触发、**2048** 点缓存、UART/SPI/镜像软件解析和 VCD。RLE 会增加编码、溢出和解码验证范围，因此冻结为赛后研究，不进入本届发布。

## 为什么实现 BTB 但不宣称完成高级控制逻辑

最终版本实现了 16 项直接映射 BTB 与 2-bit 饱和计数器，并用 Predictor Off/On、别名替换、错误恢复和 CoreMark 数据验证。**RTL 仿真对比**（同一 CoreMark 镜像）：Predictor Off 1,604,264 cycles / CPI 2.0670，Predictor On 1,251,724 cycles / CPI 1.5907，周期减少 **21.98%**；Predictor On 统计 221,615 次 BTB 命中、69,120 次误预测。官方高级控制逻辑还要求完整异常/中断，因此本项目只陈述“实现动态分支预测”，不把 BTB 单项包装成完整高级控制逻辑；机器模式 CSR/Trap/MRET 与定时器中断已经实现，并包含在交付位流中。Cache、burst 与外部 DDR3 已于 2026-09-29 纳入本届范围，S1～S4 全部执行完毕：burst 通过，I-Cache 与 D-Cache 均已建成并实测，随后按止损条件默认关闭——片上 BRAM 的访问延迟本来就优于 Cache 命中延迟，只有等真实 DDR3/HMIC 后端接入后 Cache 才可能翻盘。

## 为什么加 M 扩展，跑分变化怎么解释

**为什么要加**：RV32I 没有硬件乘法器，CoreMark 的矩阵段每迭代固定 **10,575 次乘法**全部走 libgcc 的
移位加 `__mulsi3`（反汇编实测：循环体 6 条指令、平均 7.94 次循环迭代/次乘法）；板级 ILA 的 512 拍窗口里
**84.3% 的提交落在该循环**。按指令数折算，**约 60% 的退休指令花在软件乘法上**——这是"取指已满速"之后
剩下的最大单项，也是 CoreMark 在 RV32I 上"算得多、跑得慢"的结构性原因。

**改了什么**：新增 `rtl/mdu.v`——乘法三段流水（锁操作数 → 两个 16×32 部分积寄存 → 移位相加 + 符号修正，
覆盖 `mul/mulh/mulhsu/mulhu`），除法 32 拍恢复余数法（`div/divu/rem/remu`）。单周期 Reference Model
同步实现（否则两 CPU 的架构状态一致性比较在任何用到乘除法的程序上直接失效）。**Core 对外端口一根未改**
（这是 ISA 扩展，不是外设）。

**数字怎么解释**：同一份 RTL、同一份程序，只把 `-march` 从 `rv32i` 换成 `rv32im`——
实体板 50 MHz **Score 46.816 → 113.642**、85 MHz（交付时钟）**79.587 → 193.192**，
**CoreMark/MHz 0.936 → 2.272（2.43×）**，每迭代周期数 −58.8%，指令数 −53.5%
（CPI 从 ≈1.50 微升到 ≈1.55，因为省下来的指令本来就"便宜"；85 MHz 点实测 1.547）。
同频（85 MHz）下 **CoreMark/LUT 从 0.0190 提到 0.0460（2.43×）**；三颗位流的 LUT/FF/WNS 逐项相同，
面积不随程序变，涨的全是分数。另外，用当前 RTL 重建的 rv32i 位流跑出 `ticks = 2,670,014,377`，
与 M 扩展之前的归档位流**逐位相同**——这就是"M 扩展没有扰动 RV32I"的直接证据。
**两套 ISA 并列，rv32i 仍是默认与可比口径**；CoreMark 输出自带 `Compiler flags` 一行可自证。

**一条必须主动讲清的工程取舍**：乘法器一开始写成"一拍组合 32×32"，PDS 把它综合成 **4 级串联 APM**，
85 MHz 直接违例（Slack −3.268 ns）。改成两段流水后 85 MHz `All Constraints Met`，
代价是每条乘法多 2 拍（Score 从 116.122 降到 113.642，−2.2%）——**先保时序与正确性，再谈分数**。

## 逻辑分析仪的"采集源双源可选"是什么

原来的被测对象是**它自己**（板上发生器 → J8 回环 → 采自己发出去的波形），这只能证明"仪器能采能解"。
本批让同一台仪器去采**自研 CPU 的总线与流水线行为**：8 根探针全部是 Core **已有的冻结观测输出**
（`i_req_valid`/`i_req_ready`/`i_rsp_valid`/`d_req_valid`/`d_req_ready`/`event_stall`/`event_flush`/`trace_valid`），
由 **MMIO 寄存器 18** 切换（0 = J8 外部、1 = Core 内部），**不需要重新综合**；新增 **0xA8** 命令承载 16 位
pre/post 与源选择，老命令 0xA5/0xA7 逐字节不变。

**实测读数**（2048 点全速窗口，触发 ch6 冲刷沿 / ch5 停顿沿各 3 次全 PASS）：窗口内 **1187 条提交 / 1987 拍
⇒ 窗口 IPC ≈0.597**，其中 **785 拍是停顿（39.5%）**，窗口内 4 次控制流冲刷。也就是说，
"用自研仪器量自研 CPU"这条链已经在真板上跑通，与 PDS ILA 的结论互为印证。

**评委追问"现场怎么切"**：两个上位机（主力的 pyUI 与自包含的 `逻辑分析仪演示.py`）面板上都有
**「采集源」下拉框**，选 `Core 内部观测点` 即发 16 字节 `0xA8` 包，切回 `J8 外部 8 路` 即回到 13 字节老命令，
**不重新下载位流**。切换后判据、通道名和波形页标注都跟着换（按**采集源**而不是按模式选）：
Core 源下读数区报提交/停顿/冲刷/窗口 IPC，不再报"每比特采样点/波特率"这类对流水线信号无意义的协议读数。
实板四组"模式 × 采集源"组合全 PASS，证据 `release/evidence/logic_analyzer_board_85m/ui_source_check/`。

**也要主动说明的一条已知限制**：如果某一枪的**触发条件永远不出现**，固件会停在无超时的采集完成轮询上，
串口不再响应，**只能按板上 `REST` 或重下同一位流恢复**（本轮实板复现一次）。上位机会在"一个字节都没收到"时
直接提示这一点；调试触发优先用电平触发。详见 `docs/application_logic_analyzer.md` §6.10.7。

## 当前还缺哪些证据

自动化回归、最终 PDS 构建、实体板 CoreMark 计分和 J8 物理回环都已完成。交付位流 `C017ED10…003FAA4F`（85 MHz）已下载到 MES50HP（`DONE=1`），J8 static、counter、UART、SPI、镜像五模式各连续 20 次，共 **100/100** 实体采集 PASS（本批 10-14 复测；更早批次另有 3 轮 soak 各 80 次、累计 320 次零失败，属旧位流口径）；UART 20 次均解码 `A5` 且无帧错误，SPI 20 次均解码 `3C`。CoreMark 实体成绩为与交付同频的 85 MHz Score **79.587**（RV32I），另有 46.816 @50 MHz（21.360 s）、74.905 @80 MHz、84.269 @90 MHz，CoreMark/MHz 均为 0.936；**RV32IM 增强口径另计**：**85 MHz（与交付同频）Score 193.192、CoreMark/MHz 2.272（4000 迭代 20.704 s，官方 CRC 全过，位流 `EE8B6536…`，WNS +0.250 ns）**；50 MHz Score **113.642**、CoreMark/MHz **2.272**（2000 迭代 17.599 s）。2026-10-14 本批又补齐六项：① 逻辑分析仪五模式 ×20 = **100/100 实体板验收 PASS**；② **采集源双源可选**（J8 外部 / Core 内部观测点）板级 6 次采集 PASS，窗口 IPC ≈0.597、停顿占 39.5%；③ RV32IM 实体跑分（上句）；④ 最终回归与发布链全部重跑通过（`ALL AUTOMATED FINAL REGRESSION PASS`、`AUDIT PASS final_files=299`）；⑤ 同日晚把**采集源开关接进两个上位机界面**并把判据改为按采集源选（实板四组"模式 × 采集源"全 PASS，见 `ui_source_check/`）；⑥ **新打并实测 RV32IM 的 85 MHz 计分位流**（`cmim85`，补齐"与交付同频的 M 扩展分数"这一栏）。2026-09-30 又补齐了三项：① N1 实体板裸机定时器中断演示（12 次中断，自计时期中位数 12,517,376 拍 = 250.348 ms）；② N2 用 ILA 抓到 Trap 进入/返回波形，据此收口 M-24（Trap 契约 M-01…M-24 全部 PASS，99/99 断言通过）；③ Task 29 的 CoreMark 关键循环 ILA 波形（512 样本 PDS DebugCore 探针窗口，IPC 0.635 / CPI 1.575，属 2026-09-17 批次）。仍**未**完成、应当如实说明的有两项：**三轮断电压力复测**和**最终视频素材**；此外 95 MHz 的 PLL 配置因 PDS 时序违例从未上板，材料不宣称该频点。这些都无需修改 CPU、外设 RTL、软件协议或 J8 约束。
