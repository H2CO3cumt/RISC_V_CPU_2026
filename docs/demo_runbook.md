# 现场演示 Runbook（分镜 + 一键命令）

> 用途：把"录演示视频/现场答辩"变成**一条条可以照着敲的命令**，每一段都有明确的
> 预期输出与 PASS 判据。录像本身需要人来按录制键，所以这里交付的是**分镜脚本 + 可执行流程**。
>
> 配套文件：`release/materials/video_script.md`（旁白稿）、
> `release/materials/live_demo_script.md`（现场走位）、
> `release/materials/field_recovery_card.md`（故障恢复卡）、
> `release/evidence/claims_map.md`（**每个数字的出处**——字幕只许用这里的数字）。
>
> 环境纪律：本机只有 Windows PowerShell 5.1。所有脚本一律用
> `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File <脚本>` 调用。
> **例外**：`export_final_submission.ps1` / `create_release_manifest.ps1` / `audit_release_package.ps1`
> 必须用 PowerShell 7（`pwsh.exe`）跑。

---

## 0. 演示前 60 秒自检（`preflight`，只读，可反复跑）

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\demo_preflight.ps1 -Port COM11
```

**预期输出（2026-10-10 实测）**：

```
OK   la85 DELIVERY         sha256=66A1E9A74A9C55CC...
OK   la50 fallback         sha256=0477DDA4B8D308B3...
OK   la80 pll               sha256=0388100A6D471402...
OK   cm50 coremark          sha256=DC95F9D087B7E29B...
OK   cm80 coremark          sha256=F0743756903BD557...
OK   ila debugcore          sha256=B6507CF177BAC2DF...
OK   python                 Python 3.13.15
OK   pyserial               v3.5
OK   gtkwave                D:\oss-cad-suite\bin\gtkwave.exe
OK   serial ports           COM11, COM15, COM16
OK   target COM11           present
OK   demo files             11 entries present
DEMO PREFLIGHT PASS warnings=0
```

- 该脚本**不下载位流、不打开串口**，所以可以在台上反复跑。
- 只要有一个 `FAIL` 就不要开始演示——先按 `field_recovery_card.md` 处理。
- **注意**：这里的位流哈希是"演示数字是用哪一版位流录的"的锁。任何位流被重打，
  必须同时更新本脚本顶部哈希和 `release/evidence/claims_map.md` 的对应行。
  （2026-09-30 发现本脚本有 3 个哈希过期，现场会必然 FAIL，已修正。）

---

## 1. 分镜表（共 6 段，每段一条命令）

| # | 段名 | 时长 | 一键命令 | 画面要点 | 旁白要点 |
|---|---|---|---|---|---|
| S0 | 开场 + 自检 | 0:00–0:20 | `demo_preflight.ps1 -Port COM11` | 板子、PDS 工程、`DEMO PREFLIGHT PASS` | 作品定位：RV32I 五级流水线 + 八通道逻辑分析仪 |
| S1 | 交付位流(85 MHz) + 逻辑分析仪闭环 | 0:20–0:55 | `program_board.ps1 -Config la85` → `run_logic_analyzer_board.ps1 -Port COM11` | J8 八根杜邦线、串口输出、`captures=100`、**镜像页上 `HELLO,RISC-V` 逐字符标注**、界面「采集源」切到 Core 内部观测点后波形换成流水线观测点 | Core 外置应用；统一 MMIO；四模式各 20 次 + 镜像 20 次；同一台仪器量自研 CPU |
| S2 | CoreMark 实板计分 | 0:55–1:25 | `program_board.ps1 -Config cm50` → `run_coremark_board.ps1 -Port COM11` | 串口滚动、`score_x1000=46816` | 官方 CRC PASS、21.36 s、CoreMark/MHz 0.936 |
| S3 | 板级中断（N1） | 1:25–1:50 | `run_timer_demo_board.ps1 -Port COM11` | **LED0 0.5 s 周期闪烁**、计数递增 | 机器模式 CSR/Trap；中断周期 250.3 ms |
| S4 | ILA 抓 Trap 进入/返回（N2） | 1:50–2:25 | `run_timer_demo_ila_pds.ps1` → `run_ila_trap_capture.ps1 -Mode capture …` | Fabric Debugger 波形、`ila_event_trap` 脉冲 | 192 位探针 × 512 样本；M-24 收口 |
| S5 | 收束 + 未完成项 | 2:25–3:00 | `show_capture.ps1` | 波形 + 回归 PASS | 止损记录、仍未做的断电压力 |

> 具体念什么以 `release/materials/video_script.md` 为准。
> **本 Runbook 只保证"命令和预期输出是对的"。**

---

## 2. 逐段命令与预期输出

### S1 逻辑分析仪现场闭环（交付位流）

```powershell
# 1) 下载交付位流
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\program_board.ps1 -Config la85
# 预期： PROGRAM PASS config=la85   （done bit is 1）
# 备用（主位流异常时）： -Config la50

# 2) J8 四模式各 20 次物理回环 + 镜像抓取 20 次
#    -Output 必须显式写成交付证据目录：脚本默认值是 release/evidence/logic_analyzer_board，
#    而第 3 步要看的页面在 _85m 下；不写 -Output 会把证据写到另一个目录，第 3 步就打不开。
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 -ClockHz 85000000 -Output release\evidence\logic_analyzer_board_85m
# 预期： LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100 mirror_text=HELLO,RISC-V
# （50 MHz 备用位流要加 -ClockHz 50000000；默认按交付位流的 85 MHz 算采样分频）
# 采完把页面重建一遍（模板升级后必须做，否则交付页面比模板当代）：
#   scripts\logic_analyzer_capture.ps1 -FromCaptures release\evidence\logic_analyzer_board_85m -Modes static,counter,uart,spi,mirror
#   预期： LOGIC ANALYZER WAVEFORM REBUILD PASS pages=5

# 2b) 采集源切到 Core 内部观测点（可选加跑，不改上面的 100/100 口径）
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 1 -IncludeCoreSource -CoreRuns 3 -Output results\la_board_include_core
# 预期： LOGIC ANALYZER CORE SOURCE PASS captures=3 source=core_probe
#        LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=8
# 界面口径同样可切：两个上位机的「采集源」下拉框（J8 外部 8 路 / Core 内部观测点）。
# 想看界面上切源是否真的通，跑这一条（两段日志直接刷新进交付证据目录）：
#   scripts\run_ui_source_board.ps1 -Port COM11
#   预期： UI BOARD CHECK PASS + 单文件界面「全部通过」
#   证据： release/evidence/logic_analyzer_board_85m/ui_source_check/README.md

# 3) 镜像演示的关键一眼：页面上的整句标注
#    打开 release/evidence/logic_analyzer_board_85m/mirror/mirror_00.html
#    预期： 2048 个采样点、ch7 = PC_TX、每帧上方标 'H' 0x48 … 'V' 0x56、
#           状态栏出现 报文 "HELLO,RISC-V"、底部 BYTE0 起逐帧序号
#    这一张图的含义：被测信号就是上位机**自己刚发出去的那句话**，
#    波形是板上真采的，字符是上位机从波形里解回来的。
```

J8 接线（八根杜邦线，隔行相邻脚对）：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。
奇数脚为激励输出，偶数脚为采集输入。**第 8 对（31↔32）现在是被测的外部信号通道**：
板级顶层把 CP2102 的 `uart0_rx` 镜像到 J8-31，逻辑分析仪抓 J8-32（ch7）。

**现场可做的变量改动**（证明"可重构"不是背稿）：

- 改字符串：`run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 3 -MirrorText "RISC-V 2026"`，
  或直接 `python python\logic_analyzer_serial.py COM11 --mode mirror --text "HELLO,2026" --runs 1`；
  波形上的字符标注会**跟着变**，不用重新综合。
- 改 `-RunsPerMode` 或模式后重跑，触发位置与解析字节应随之改变。
- **在上位机面板上当场改**（2026-10-10 新增，规格见 `docs/application_logic_analyzer.md` §6.9）：
  双击 `启动逻辑分析仪.cmd` → 勾「使用面板参数」→ 改时基、触发方式、触发通道、电平或 `pre`/`post`
  → 点「按面板参数采集当前模式」。面板下方实时显示"每比特几个采样点、窗口多少点"，
  改错的值当场变红并说明原因；每一轮的**报文十六进制**会打进日志，事后可逐字节复现这一枪。
  两点注意：勾了面板**只采当前选中的那个模式**（参数是按模式各一套的）；
  镜像模式下除 `post` 以外的旋钮会被自动禁用（固件里它们被重新定义或写死）。
- **不要用 `-Oneshot`**：它发的 0xA6 前缀在当前交付固件上不存在，
  现在会在**打开串口之前**直接报错（旧行为是干等到超时，默认 70 s）。

### S2 CoreMark 实板计分

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\program_board.ps1 -Config cm50
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_coremark_board.ps1 -Port COM11
# 预期： COREMARK PHYSICAL BOARD ACCEPTANCE PASS
#       并刷新 release/evidence/coremark_board.json
```

- `cm50` 位流**上电后要等串口发 `R` 才启动**，用 `run_coremark_board.ps1` 会自动发。
- 实测数字：`ticks=1068006999`、`seconds=21.360`、`score_x1000=46816`、`cpi_x1000=1508`、
  `validation=PASS`。**运行 21.36 秒，满足赛题"不少于 10 秒"。**
- 跑完约 21 秒，**录像时不要剪掉等待**，这正是"实板真跑"的证据。

### S3 板级裸机中断（N1 / M-24 前半）

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_board.ps1 -Port COM11
# 默认 -Seconds 12；脚本自己下载 tm50 位流、抓串口、判定 PASS/FAIL
```

**要拍的画面（两个证据缺一不可）**：
1. **LED0 固定 0.5 s 亮灭周期**（人眼证据，脚本无法自动"看"LED）；
2. 串口输出：中断计数逐次递增、LED 位交替、周期落在容差内。

实测（`release/evidence/timer_demo_board/timer_demo_board.json`）：
12 次中断、计数序列 `890123456789`、LED 序列 `010101010101`、
自计时周期中位数 **12,517,376 拍 = 250.348 ms**（预期 250.0 ms）。

**如果评审问"为什么不是精确 250.000 ms"**：ISR 内阻塞式 UART 打印期间 `mtimecmp` 未重载，
造成每次约 +17.4k 拍的固定叠加；固件已改为"先重载再打印"，容差按 65536 拍判定。
这是**已定位的设计取舍**，不是未知误差。

### S4 ILA 抓 Trap 进入/返回（N2 / M-24 后半）

```powershell
# 1) 重建带 DebugCore 的位流（必须用 Fabric Debugger 通道下载，JTAG 链被 Hub 接管）
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_ila_pds.ps1

# 2) 先确认下载线在
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\check_jtag_cable.ps1

# 3) 抓 Trap 进入（bit0 上升沿）：Binary 值，除最低位为 R 外全部 X
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_ila_trap_capture.ps1 -Mode capture -TrigUnit 0 -TrigFunc 0 -TrigRadix 0 -TrigValue <192位模式>

# 4) 抓 Trap 返回（bit1 上升沿）
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_ila_trap_capture.ps1 -Mode capture -TrigUnit 0 -TrigFunc 0 -TrigRadix 0 -TrigValue <192位模式>
```

**预期结果**：

| 抓取 | 触发 | trap 样本号 | return 样本号 |
|---|---|---|---|
| A | `ila_event_trap` | **256**（= 触发点） | 251 |
| B | `ila_event_trap_return` | 261 | **256**（= 触发点） |

两次互为正/反向触发；`irq_timer` 全程 512 样本为 1；
illegal / misaligned / bus_error 全程为 0。
`event_trap` 与 `event_trap_return` **各产生恰好一个脉冲**（不是毛刺）。
证据：`fpga/timer_demo_ila/evidence/A_trap_enter/`、`B_trap_return/`。

**必须如实说的三条边界**（说了才加分，藏了会被问死）：
1. 探针上**没有** `mcause` / `mepc` 的**数值**——PDS 拒绝跨层引用（`Verilog-4311`），
   Core 端口已冻结。这两个数值由**固件 UART 记录**证明（S3），不是 ILA 证明的。
2. trap 与 return 间隔恰好 **5 个样本**是可复现的观测，
   但本轮**没有**把它换算成周期（ILA 采样间隔未标定），也**没有**因果解释。
   **不许**把"5 样本"说成"5 个周期"。
3. 触发值和 `-func`/`-radix` 的合法值以工具 `-help` 为准，
   **不要照抄官方 PDF 示例**（PDF 写 `-func 1`，实际 1 是 `<>` 不是 `==`）。

### S5 收束：波形展示与止损

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\show_capture.ps1
# 不带 -Vcd 时自动挑 release/evidence 下最新的 .vcd，八通道已插好、时间轴已缩放
```

**这一段的加分点是把止损讲清楚**（评委最吃这套）：

| 项 | 结论 | 数字 |
|---|---|---|
| S2 行式突发 | **PASS** | 总线周期 48 → 30（−37.5%） |
| S3 2 路组相联 I-Cache | **止损触发 → 默认关闭** | cycles 1,251,724 → 2,891,324（2.31× 变慢） |
| S4 2 路组相联 D-Cache | **止损触发 → 默认关闭** | 1,251,724 → 1,348,302（+7.7%） |
| S1 DDR3 | 板级打通，**未接入 CPU 存储路径** | `S1 DDR3 SMOKE BOARD PASS` |

架构结论：片上 BRAM 的访问延迟**已经优于** Cache 命中延迟，
所以 Cache 在"后端仍是 BRAM"时**不可能**有净收益；
必须等真实 DDR3/HMIC 后端接入后才可能翻盘。**这是本轮最有价值的结论，不是失败。**

---

## 3. 现场故障恢复

| 现象 | 先查 | 处理 |
|---|---|---|
| `preflight` 报位流 SHA 不匹配 | 是不是手改过位流 | 不要演示；先核对 `claims_map.md` |
| `program_board.ps1` 报 `Configuration-0009` | JTAG 链被 DebugCore Hub 接管 | 该用 `-Config tmila -UseDebugger` 走 Fabric Debugger |
| 串口无输出 | COM 口号、波特率 | `preflight -Port COMx`；`-Baud 115200` |
| `Cable List` 为空 | USB 线、驱动 | `check_jtag_cable.ps1`；换 USB 口 |
| ILA 抓不到触发 | 触发值与 `-func` 语义 | 以 `dbg_fla_set_trig_unit -help` 为准，不要照抄 PDF |
| 演示中途板子需要重启 | — | 断电 5 s → 重新上电 → 重新下载同一位流 → 重跑该段命令 |

**原则：现场失败不剪掉错误提示。** 按恢复卡重新连接、下载并复测，
比"一次成功"更能证明工程可控。

---

## 4. 仍未完成、录像时必须如实处理的项

1. **三轮断电压力复测**：`run01` **已做**（重新下载 = Reset 等价，LA 80/80 + CoreMark `ticks=1068006999`），
   但**没有真的断过电**；`run02` / `run03` 未做，**用户 2026-09-30 明确决定不做**。
   记录见 `release/evidence/board/README.md`（记的是"用户决定不做"，不是"已完成"）。
   流程见 `docs/reproduction.md`「Reset 与断电重复」。
2. ~~S1 DDR3 的板级日志尚未落成 `release/evidence/` 下的独立目录~~ → **已补**：
   `release/evidence/ddr3_smoke_board/`（2026-09-30 落盘并复现 `S1 DDR3 SMOKE BOARD PASS`）。
   DDR3 是唯一不满足的条目。
3. **演示视频本身**（本文件是拍摄依据，不是已完成素材）。
4. **PPT 版本未对齐**：用户 2026-09-30 明确要求不重新生成 PPT，
   因此它仍是 09-16 版，**既不含 85 MHz 交付口径、也带着更早的旧数字与错误范围表述**。
   这是当前材料里**唯一已知不一致**的文件 —— 要用它必须重新生成
   （生成器 `scripts/generate_defense_deck.mjs` 的数字与范围句已改对）。

**未宣称（字幕里不许出现）**：DDR3 吞吐量/延迟数字、板上 89.25 MHz、
Cache 的 Off/On 净收益、Trap↔return 的"5 样本"因果解释。完整清单见
`release/evidence/claims_map.md` §12。

---

## 5. 录像后：材料一致性收口

```powershell
# 必须用 PowerShell 7
pwsh -NoProfile -File scripts\export_final_submission.ps1
pwsh -NoProfile -File scripts\create_release_manifest.ps1
pwsh -NoProfile -File scripts\audit_release_package.ps1
```

注意 `export_final_submission.ps1` 会**重新生成** `release/final_submission/README.md`
并**清空**该目录，所以任何 README 修改都必须改**脚本里的模板**（`$readme` here-string），
改生成物是白改。

---

*本 Runbook 由 N3 材料收口任务建立（2026-09-30）。命令行或预期输出变化时请同步更新本文件。*
