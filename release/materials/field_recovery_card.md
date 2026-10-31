# 现场恢复卡

## 固定条件

- 板卡：MES50HP，器件 `PGL50H-6IFBG484`
- 时钟：P20 板载晶振 50 MHz；**交付设计经片上 PLL 倍频到 85 MHz**（`50 MHz / IDIV 1 = PFD 50 MHz`，`× FDIV 17 = VCO 850 MHz`，`/ ODIV0 10 = 85.000 MHz`，整数分频）
- 串口：CP2102，115200 8N1，无流控，RX=R8，TX=R9
- Reset：默认内部上电复位；`REST` 用于重新加载配置
- 逻辑分析仪跳线：J8-3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32，并共地

## 第一步永远是自检

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\demo_preflight.ps1 -Port COM11
```

只读，不下载、不占串口，可反复跑。它核对关键位流 SHA-256、Python/pyserial、GTKWave、PDS 工具、串口和演示材料文件。
输出 `DEMO PREFLIGHT PASS warnings=0` 才算环境完好；否则先修自检报的那一项，不要盲目重下载。

## 五分钟恢复顺序

1. 断电，检查 USB-JTAG、独立 CP2102 数据线和跳线方向。
2. 上电，在 PDS Programmer 中确认器件型号。
3. 先跑上面的 `demo_preflight.ps1`，再做下面按目标的下载，并核对 `release/SHA256SUMS.txt`。
4. 关闭其他占用串口的软件，确认 COM 号与 115200 8N1。
5. 运行对应脚本；脚本未输出 PASS 时停止演示，保存原始日志。

## Bitstream 选择

演示只认 `scripts\program_board.ps1 -Config <名字>`，不要手点旧文件名。下载命令：

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\program_board.ps1 -Config la85
```

| 目标 | `-Config` | SHA-256 前 16 位 | 下载后应看到 |
|---|---|---|---|
| **交付位流（主下载）**：85 MHz PLL，流水线+BTB+CSR/Trap+UART/GPIO+性能计数+8 通道逻辑分析仪 | `la85` | `C017ED1019550273` | 串口输出 `LA_READY`，等待配置包；`run_logic_analyzer_board.ps1 -Port COM11` 跑 五模式各 20 次 |
| **已验证备用位流**：50 MHz（交付位流出问题时回退） | `la50` | `8102634A23ACB68B` | 同 `LA_READY`；功能已实测，仅作回退，不是主交付 |
| 逻辑分析仪 80 MHz PLL 变体 | `la80` | `0388100A6D471402` | 同 `LA_READY`；仅诊断用，不是交付位流 |
| 逻辑分析仪 90 MHz PLL | `la90` | `0315374E5FA60F49` | **不要用于演示**：PDS 时序过，但板上 SPI 模式固件挂死（须重下位流才能恢复）；只用于复现上界 |
| CoreMark 计分 50 MHz | `cm50` | `DC95F9D087B7E29B` | 上电后**等串口 `R` 才开跑**（脚本会自动发）；跑完输出官方 CRC PASS 与 score |
| CoreMark 80 MHz PLL | `cm80` | `F0743756903BD557` | 同样等 `R`；实体板 Score **74.905**，官方 CRC PASS |
| CoreMark 85 MHz PLL（与交付位流同频） | `cm85` | — | 同样等 `R`；实体板 Score **79.587**（RV32I），官方 CRC PASS |
| **CoreMark RV32IM 50 MHz（M 扩展）** | `cmim` | `BE7A4FF31F2214AC` | 同样等 `R`；实体板 Score **113.642**、CoreMark/MHz **2.272**、2000 迭代 17.599 s，官方 CRC PASS |
| **CoreMark RV32IM 85 MHz（M 扩展 + 交付时钟）** | `cmim85` | `EE8B65360B0B0718` | 同样等 `R`；实体板 Score **193.192**、CoreMark/MHz **2.272**、4000 迭代 20.704 s，官方 CRC PASS（WNS +0.250 ns） |
| CoreMark 90 MHz PLL（CPU 板级上界） | `cm90` | — | 同样等 `R`；实体板 Score **84.269**，官方 CRC PASS |
| CoreMark 95 MHz PLL | `cm95` | — | **时序违例、从未上板**，只留档，不要当成绩用 |
| CoreMark + DebugCore（ILA 波形） | `ila` | `B6507CF177BAC2DF` | Fabric Debugger 扫描到该核；CoreMark 仍等 `R` |
| 板级定时器中断演示（N1） | `tm50` | `5E58B4217AB9591A` | LED0（板上 LED1，`B2`）0.5 s 整周期闪烁；串口先出 `=`，再连续出现交替的十六进制计数与 LED 值 |
| 定时器中断 + DebugCore（N2，抓 Trap 进入/返回） | `tmila`（**必须加 `-UseDebugger`**） | `452EE532DAC8AB9A` | 同上 LED/串口现象，另可在 Fabric Debugger 抓 Trap 波形 |
| DDR3 冒烟（S1） | `ddr3` | `FAEDF47618647C36` | `led0..3 = {pll_lock, ddr_init_done, 心跳, err_flag}`（`B2,A2,B3,A3`）：正常时 `pll_lock`/`ddr_init_done` 常亮、心跳闪、err_flag 灭；串口 115200 读状态寄存器 |

> CoreMark **RV32I** 四个实体测点的 `CoreMark/MHz` 都是 **0.936**、官方 CRC 全部 PASS：`cm50` 46.816、`cm80` 74.905、`cm85` **79.587**（与交付的 85 MHz 同频）、`cm90` 84.269。表中标 `—` 的三项是频点扫描配置，现场不下载、不用核对哈希。

> `release/board_validation/bitstreams/` 下的 `pipeline_soc.sbit`、`coremark_stable.sbit`、`coremark_debug_ila.sbit`、`logic_analyzer_p0.sbit` 是**开发阶段历史件**，按 `release/HANDOFF.md` 不属于交付入口，也不需要选择——演示一律用上表。

## CoreMark 无输出

1. 确认下载的是 `cm50` 位流，即 `fpga/coremark/generate_bitstream/mes50hp_coremark_top.sbit`，SHA-256 前 16 位 `DC95F9D087B7E29B`。
2. 重新插拔独立 CP2102 数据线并重开串口。
3. 该位流**上电后不自己开跑**：等待 READY 后发送大写 `R`；用 `run_coremark_board.ps1` 会自动发送。
4. 仍无输出时按 `REST` 重新加载；不要改 RTL 或串口参数。

交付 CoreMark 口径按频点与 ISA 分：与交付位流同频的 85 MHz 测点有两颗——`cm85`（**RV32I**）score **79.587**、`cmim85`（**RV32IM，M 扩展**）score **193.192**，CoreMark/MHz 分别是 `0.936` / **`2.272`**，官方 CRC 均 PASS；50 MHz 点是 `cm50`（rv32i）ticks `1068006999`、score `46.816`、CoreMark/MHz `0.936`、21.360 s 与 `cmim`（rv32im）score **113.642**、CoreMark/MHz **2.272**。**每个数都必须带频率与 ISA**，不许混说。

## 下载报 `Configuration-0009`

1. 这说明板上当前位流含 DebugCore，JTAG 链被 Jtag Hub 接管，普通 `cdt_cfg` 必然失败——**不是板子坏了**。
2. 直接在命令末尾加 `-UseDebugger` 重下，例如 `-Config tmila -UseDebugger`；`tmila` 不加这个开关一定报此错。
3. 切回 `la85`、`la50` 或 `cm50` 时可不加该开关。

## Fabric Debugger 无波形

1. 确认下载的是 `ila`（CoreMark + DebugCore）或 `tmila`（Trap 抓取）位流；`tmila` 需加 `-UseDebugger` 下载。
2. 重新扫描 JTAG 链并选择对应 DebugCore 核。
3. 先用 bit 0 的退休事件触发；需要控制流证据时再用 bit 174/176。
4. 仍无法采集时保存界面与日志，切回正式演示（交付位流 `la85` 的应用闭环，或 CoreMark `cm50`），不声称 ILA 已实测。

## 逻辑分析仪超时或解析错误

1. 确认下载的是交付位流 `la85`（`C017ED10…`）；若 `la85` 复现异常，切回已验证备用位流 `la50`（`8102634A…`）再测。再逐位检查 J8 的 8 组隔行相邻脚对（3↔4 至 31↔32），确认 GND 共地；不要使用 J8-2（5V）。
2. 等待 `LA_READY` 后再发送下一配置包。
3. 先运行 static，再运行 counter，最后运行 UART/SPI。
4. 重新下载同一 bitstream 后复测；不要临时改采样深度、触发协议或固件。

### 串口一个字节都不再输出（触发条件永不出现 ⇒ 固件停住）

**判据**：报错里出现"`bytes=0`"或"板子完全没有输出"，板子对任何报文都无反应。
**原因**：固件 Arm 之后是无超时轮询采集完成位（`software/logic_analyzer/logic_analyzer.c` 第 189 行），
若这一枪的触发永远不会命中（例如在 J8 源下等一个没接信号的引脚上升沿），固件就停在那里，
串口不再读也不再写。**这是已知限制，不是板子坏了，也无法用报文救回来。**

1. 按板上 `REST` 重新加载；或在开发机上 `scripts\program_board.ps1 -Config la85` 重下同一位流。
2. 恢复后先跑 static（电平触发、上电即命中）确认链路，再跑 counter，最后才跑协议模式。
3. 调试触发时优先用**电平触发**；用边沿触发前先确认那个通道上真的有信号。
4. 证据与复现：`docs/application_logic_analyzer.md` §6.10.7。


## 证据保存与三轮断电复测

- 每轮保存 UART 原始日志、JSON、VCD、PDS/Fabric Debugger 截图和 bitstream SHA-256。
- 下载核对用 `release/SHA256SUMS.txt`（已含 85 MHz 交付位流 `C017ED10…`）；交付包 `release/final_submission/bitstream/` 里两份都要核：`mes50hp_riscv_logic_analyzer.sbit`（85 MHz 主下载，`C017ED10…`）与 `mes50hp_riscv_logic_analyzer_50m_fallback.sbit`（50 MHz 已验证备用，`8102634A…`）；交付包整体核对用 `release/final_submission/SHA256SUMS.txt`（按包内清单逐条核对）。
- **三轮断电压力测试：`run01` 已做但未断电，`run02`/`run03` 未做（用户已决定不做）**。
  `release/evidence/board/run01` 存在（重新下载 = Reset 等价：LA 80/80 + CoreMark `ticks=1068006999`），
  但**没有真的断过电**，`run02`/`run03` 没有。下面只是待办步骤，**不得当成已完成结果**：
  断电 5 s → 上电 → 下载同一个 SHA-256 的位流 → 跑对应板级脚本；三轮分别写入 `release/evidence/board/run01`、`run02`、`run03`。
- 失败结果保留，修复后另建新一轮目录，不覆盖原记录。

## 一页参考数字

- 交付配置 `la85`（85 MHz PLL）：setup WNS **+0.577 ns**（2026-10-14 重建批次），估算 Fmax **89.3841 MHz**，**4995 LUT / 3908 FF / 6.0 DRM18K**，85 MHz 约束下 All Constraints Met；板级时钟 **85 MHz**（板载晶振 50 MHz 经片上 PLL 倍频）。
- 已验证备用配置 `la50`（50 MHz）：setup WNS **+2.217 ns**（2026-10-14 重建批次），估算 Fmax **55.7338 MHz**，**4704 LUT / 3903 FF / 6.0 DRM18K**。只在 `la85` 出问题时用于回退，不当作交付数字。
- CoreMark 计分位流（都不是交付位流，只用于计分）：`cm50`（rv32i 50 MHz，46.816）、`cm85`（rv32i 85 MHz，79.587，09-30 旧 RTL）、**`cm85r`（rv32i 85 MHz，当前 RTL 重建的同源对照点：Score 也是 79.587、ticks 逐位相同，4198 LUT / WNS +0.250 ns）**、**`cmim85`（rv32im 85 MHz，193.192，4198 LUT / 3361 FF / WNS +0.250 ns）**、`cmim`（rv32im 50 MHz，113.642）。**同源同频（85 MHz）下 CoreMark/LUT = 0.0190 → 0.0460，即 2.43×**（旧稿写的 2.11× 是拿不带乘法器的 rv32i 位流当分母，跨 RTL 修订，已更正）。
- 逻辑分析仪板级闭环（85 MHz 交付位流）：五模式各 20 次 **100/100 PASS**（2026-10-14 复测）；**采集源双源可选**（J8 外部 / Core 内部观测点）6 次采集 PASS，窗口 IPC ≈0.597、停顿占 39.5%；更早批次另有 3 轮 soak 各 80 次、累计 **320 次连续采集零失败**，证据 `release/evidence/logic_analyzer_board_85m/`、`release/evidence/logic_analyzer_board_85m_soak/`。
- 应用级上界：逻辑分析仪应用在 90 MHz 的 SPI 模式固件挂死，所以应用上界记为 **85 MHz**；PDS 估算的 89.3841 MHz 只是估算值；95 MHz 时序违例、从未上板。明细见 `release/evidence/fmax_ceiling/README.md`。
- 需要现场再抓一份 Trap 证据时：`scripts\run_trap_pipeline_tb.ps1` → `ALL TRAP PIPELINE TEST PASS`（99/99）。
