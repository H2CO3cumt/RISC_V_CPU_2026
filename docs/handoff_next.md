# 接班执行清单（新窗口从这里开始）

> 生成时间：2026-09-29（第 2 版，纳入"2 路 I/D Cache + burst"分阶段计划）。
> 上一轮的完整过程记录在 `docs/progress.md` 与 `docs/debug_log.md`，
> 本文件只回答一个问题：**接下来做什么、怎么做、怎么算做完**。
>
> 新窗口的第一件事：读 `AGENTS.md` → `docs/progress.md` 顶部三节 → 本文件。
> 禁止把历史聊天当唯一依据；一切以工作区文件和可复现命令为准。

---

## 0. 一分钟状态快照（全部为已验证事实）

| 项 | 值 |
|---|---|
| 唯一主版本 RTL | `rtl/pipeline_cpu.v` = `B58496706686E37B`（A3：机器模式 CSR/Trap/MRET + 三根通用中断输入）——2026-09-29 N1 轮**未改动**，已复核 |
| 新增 Core 外部文件 | `rtl/csr_unit.v` = `5C7CF5C9C936EE38`、`rtl/timer_mmio.v` = `C8113935C658A6EE`、`rtl/soc_data_interconnect.v` = `7D7CA4F001A32D11` |
| 位流（当前批次，已含定时器） | `fpga/coremark` = `DC95F9D087B7E29B`、`fpga/logic_analyzer` = `BCAE040A3B96652B`、`fpga/coremark_80m` = `F0743756903BD557`；**另有演示用** `fpga/timer_demo` = `5E58B4217AB9591AF974C5B1897A287A007B7E7E219F122244E44A4958B7765B` |
| 自动回归 | `scripts\run_final_regression.ps1` → **ALL AUTOMATED FINAL REGRESSION PASS（28 项）** |
| Trap 契约矩阵 | `docs/trap_contract.md` §6：**23 条 PASS / 1 条部分（M-24）**；M-24 的"板级周期性中断演示"已于 2026-09-29 闭环，只剩 ILA |
| CoreMark（RTL 仿真） | 固定延迟 `cycles=1251724`（与 A1 逐位一致）、随机背压 `cycles=3004390` |
| **实板（当前位流）** | la50 下载 `PROGRAM PASS` + `done bit is 1`；J8 四模式各 20 次 **80/80 PASS**；cm50 下载 OK；CoreMark **21.360 s / score×1000 = 46816**；**tm50 定时器中断演示 PASS（50 条记录 / 45 个间隔 = 12_500_000 ± 65_536 拍）** |
| 时序 | 三个交付工程全部 `All Constraints Met`（50 MHz CoreMark WNS +2.676 ns、逻辑分析仪 +1.989 ns、80 MHz 工程 +1.608 ns）；演示工程 `fpga/timer_demo` 亦 `All Constraints Met`（WNS +2.638 ns）|
| 发布包 | `release/final_submission`（214 文件）+ `audit_release_package.ps1` = `PASS final_files=131 artifacts=3` |

**两个关键变化**：
1. 开发板与下载线已经正常（2026-09-29 实测），"JTAG 未枚举"的阻塞**已解除**；
2. **DDR3 路径被重新查证为可用**（上一版文档里"PDS 没有 DDR 控制器 IP"的结论是**查错关键词**造成的，
   Pango 的控制器叫 **HMIC** 不叫 ddr），细节与证据见 §3.3。

---

## 1. 全局纪律（先看，别踩）

1. **不要为了好看重构 RTL。** 现在 23/24 验收项是绿的；任何 RTL 改动都必须重跑 §4 的回归。
2. **Core 里不许出现设备名、设备地址、设备状态机**（`AGENTS.md` §8）。定时器、DDR 控制器、
   Cache 之外的地址译码一律在 Core 外。
3. **性能结论必须有 Before/After 且同镜像。** 没有可复现净收益就回退（`AGENTS.md` §9）。
4. **不要宣称高阶组整组完成**：M-24 仍是"部分"——板级中断演示已完成，但 ILA 抓 Trap 未做（见 §3.1、§3.2）。
5. **Cache / burst 已经"解冻"并纳入本届**（2026-09-29 用户批准）。
   `AGENTS.md` §1.14 已完成改写：I-Cache / D-Cache / burst / 外部 DDR3 由"本届不做"改为"本届要做"，
   并写明了不得放宽的边界（Cache 只在 Core 外部、`rtl/pipeline_cpu.v` 端口与事务语义不变、MMIO 恒 uncacheable、
   每步必须重跑 Trap 全部断言 + 最终回归 + CoreMark，退化即回退）。
   同步改写的文档共 7 个文件 9 处，由 `scripts/apply_scope_change.py` 精确落地（可 `--check` 复检）。
   **接下来按 §3.3 的 S1～S4 闸门推进，不要跳步。**
6. **AI / YOLO 依然不做**（`AGENTS.md` §1.14；依据见 §3.6）。
7. 未经用户同意不要扩大范围、不要回退用户已有改动。

### 环境坑（踩过的，别再踩）

- 本机只有 **Windows PowerShell 5.1**，`powershell.exe` 不在 PATH。统一这样调用：
  ```powershell
  & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\<脚本>.ps1
  ```
- **含中文的 `.ps1` 必须有 UTF-8 BOM**，否则 5.1 按 ANSI 解码会把注释变成乱码并报离奇的解析错误。
  用 `scripts\ensure_ps1_bom.ps1` 一键修复（**每次用工具改写含中文的脚本后都要跑一次**）。
- iverilog 的 **`-P name.VAL=字符串` 会静默失效且退出码仍为 0**。传字符串/宏一律用 `-D` 加转义引号
  （脚本里用 `$qs=[char]92+[char]34` 拼）。
- 需要"按行精确替换"时用 `scripts\apply_line_patches.ps1 -File <目标> -Patch <补丁文件>`：
  补丁格式是 `### anchor: <短子串>` + `### count: <替换行数>` + 新内容。
  锚点只写短子串，避免抄长串空格出错。**注意 count 数错会吃掉相邻行，改完要看一眼上下文。**
- PDS 的位流脚本会在构建后删除生成的 `impl.tcl`（git 里表现为删除，属正常）。

---

## 2. 想快速确认"现在还是好的"，跑这一组

```powershell
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_final_regression.ps1          # 28 项
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_trap_pipeline_tb.ps1          # 99 条 ×2 配置
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_irq_tb.ps1              # M-14 定时器端到端
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_trap_golden_judge.ps1         # M-21 独立判定器
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_logic_analyzer_fault_diag.ps1 # A6 故障诊断
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\audit_release_package.ps1         # 发布包审计
```

板上复现（当前位流，各约 1 分钟）：

```powershell
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\program_board.ps1 -Config la50
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\program_board.ps1 -Config cm50
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_coremark_board.ps1 -Port COM11
```

板级定时器中断演示（M-24 前半条，2026-09-29 已闭环）：

```powershell
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_board_top_tb.ps1   # 仿真两遍
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_pds.ps1            # 重建演示位流
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_board.ps1 -Port COM11
```

---

## 3. 下一步任务（严格按这个顺序，做完一个再开下一个）

### 3.1 【第 1 步】N1：板级裸机中断程序 —— M-24 的一半 ✅ **已完成（2026-09-29）**

**结论：已闭环。** 新增最小工程 `fpga/timer_demo`（+ `software/timer_demo`），Core 未改动
（`rtl/pipeline_cpu.v` SHA-256 前 16 位仍是 `B58496706686E37B`），已交付的
`fpga/logic_analyzer` 程序镜像与位流未被触碰。

**实测结果**：

| 项 | 值 |
|---|---|
| 位流 | `5E58B4217AB9591AF974C5B1897A287A007B7E7E219F122244E44A4958B7765B`，PDS `All Constraints Met`，WNS +2.638 ns，LUT 2902 / FF 2605 / DRM18K 3.0 |
| 仿真 | `scripts\run_timer_demo_board_top_tb.ps1` → 零延迟 **14/14 PASS**、随机背压 **13/13 PASS** |
| 解析器自检 | `python\tests\test_timer_demo_serial.py` → **20 项 PASS** |
| 下载 | `scripts\program_board.ps1 -Config tm50` → `PROGRAM PASS`、`done bit is 1` |
| 实板 | `scripts\run_timer_demo_board.ps1 -Port COM11` → **PASS**：50 条连续中断记录、45 个间隔全部 = 12_500_000 ± 65_536 拍 |
| 自计时周期 | 中位 **12_517_376 拍 = 250.35 ms**（mtime 硬件计数器给出，不依赖主机串口时钟）|
| LED | LED0（`B2`）每 0.25 s 翻转 → 0.5 s 整周期闪烁（需人眼/视频确认）|

**复现命令（三条，按顺序）**：

```powershell
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_board_top_tb.ps1   # 仿真两遍
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_pds.ps1            # 重建位流
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_board.ps1 -Port COM11
```

**本轮踩到的坑（已写进 `docs/debug_log.md`，别再踩）**：

1. **字符表越界**：ISR 用"十六进制位"当下标查表，表里只有 `'0'..'9','='` 时，
   位值 `a`..`f` 会越界读进填充字 `0x0000006F`，串口打印出 `'o'`——很像 UART 出错，
   其实是表越界。表必须覆盖 0..15。
2. **重装 `mtimecmp` 必须在 ISR 最前面**：放在 UART 输出之后会被背压推迟，
   实测间隔变成 delta + 一个字节时间。修正后间隔 = delta + 6 拍、逐次完全相等。
3. **自计时字段不能太窄**：取 `mtime[15:4]` 时模只有 65536 拍 < delta，会绕 190 次；
   现在取 `mtime[27:16]`。
4. **`-march=rv32i` 的汇编器看不到 gcc `-D` 宏**，`.ifdef` 判断会静默失效；
   delta 只能有一个来源（Makefile 显式 `-DMTIMECMP_DELTA=`）。
5. **PowerShell 5.1 的两个坑**：`param()` 里的 `$(if ...)` 默认值可能报
   "Missing expression after ','"（注释里落单的反引号也会）；另外**不要用
   `Get-Content -Raw` + `Set-Content` 改含中文的源文件**，会把文件编码毁掉。
6. **Icarus 12 会静默忽略 `-P <tb>.<param>=...`**；要覆盖 Testbench 参数请用 `ifdef` + `-D`。
7. **主机串口会丢字节**：实测 12 秒里丢掉若干字节导致整体错位，20 秒里只收全 50/96 条记录。
   所以板级判据的**权威数字是自计时周期**（mtime 硬件计数器），墙钟只做量级核对；
   解析器用"相位搜索 + 自计时判别式"抗错位（`python/timer_demo_serial.py`）。

**本轮新发现、值得记一笔的环境事实**：2026-09-29 16:24 前后串口曾返回一大段错帧
（板子重配置期间线上持续低电平，主机把它收成连续的 `0x00`，20 秒收 230144 字节 =
115200/10 × 20）；重新下载位流后恢复正常，且**用已交付的 la50 位流验证过链路本身是好的**
（J8 四模式各 1 次全部 PASS）。下次遇到"串口全是垃圾"先怀疑这个，不要先去改 RTL。

### 3.2 【第 2 步】N2：ILA 抓 Trap 进入与返回 —— M-24 的另一半（**软件已就绪，卡在物理层下载线**）

**⚠️ 2026-09-30 更新（接手先看这段）**

原计划是"在 DebugCore 工程里把探针挂到 `pipeline_cpu` 的 `event_trap`/`event_trap_return`
与 `csr` 的 `mepc_q`/`mcause_q`"。**前半截做完了，后半截被工具链硬性挡回**：

- **PDS(Logos) 不允许层级引用子模块内部寄存器**：
  写 `core.csr.mepc_q` 会直接报
  `E: Verilog-4311: Reference to identifier 'mepc_q' of module instance 'csr' is not allowed.`（6 个全被拒）；
- 把 `mepc/mcause` 引到 Core 端口又违反 `AGENTS.md` §1.14（Core 端口不得改变）。

**所以诊断位流改用**：Core **既有**事件端口给"Trap 进入/返回"本身，
取指地址 `ia` 作佐证（看得到跳进陷入入口、返回后回原 PC），
`mcause/mepc` 的数值由固件串口记录（N1 已闭环）证明。
**材料里必须如实这样写，不得含糊成"ILA 看到了 mcause"。**

**已经做完的（本轮）**：

| 事项 | 位置 |
|---|---|
| 探针段（`` `ifdef `` 保护，不改 N1 行为） | `fpga/timer_demo/rtl/mes50hp_timer_demo_top.v` |
| 诊断工程（顶层包装/配方/约束/README） | `fpga/timer_demo_ila/` |
| 构建脚本 | `scripts/run_timer_demo_ila_pds.ps1` |
| **位流（已构建成功，时序无违例）** | `fpga/timer_demo_ila/generate_bitstream/mes50hp_timer_demo_top.sbit`<br>`SHA256 452EE532DAC8AB9A86CDF9C6859892F7BA466EA035EF6A6C46FAAA9598248B74` |
| 抓取脚本（`discover` / `capture` 两种模式） | `scripts/run_ila_trap_capture.ps1` |
| 下载入口 | `scripts/program_board.ps1 -Config tmila -UseDebugger` |

**N1 未受影响（已核对）**：`fpga/timer_demo/generate_bitstream/…sbit` 仍是 **2026-09-29 16:21** 未重建；
`scripts\run_timer_demo_board_top_tb.ps1` 仍 **ALL PASS**（interrupts=12, uart_bytes=61）。

**✅ 2026-09-30 已闭环（N2 完成，M-24 = PASS）**

实板 ILA 已抓到 Trap 进入与返回，**两次抓取互相印证**：

| 抓取 | 触发 | 结果 |
|---|---|---|
| A | `ila_event_trap` 上升沿 | 该脉冲在**触发点（第 256 采样）**；同窗口另有 1 个 `trap_return`（第 251） |
| B | `ila_event_trap_return` 上升沿 | 该脉冲在**触发点**；另有 1 个 `trap`（第 261） |

两次都显示 **`trap` 恒在 `trap_return` 之后 5 个采样点**；`irq_timer` 全窗口为 1（原因 = 机器定时器中断）；
`illegal/misaligned/bus_error` 全 0。证据与位流哈希见 `fpga/timer_demo_ila/evidence/README.md`。

**本轮定位到的三个工具链坑（都已修进脚本，别再踩）**：
1. **`dbg_fla_power_init` 会静默废掉整个 Tcl 脚本**：本 IP 的 `INIT_ENABLE=false`（`.ipc` 第 53 行），
   该命令必然报 `Debugger-0006`；而手册写明**一条命令失败后后续命令不再执行，除非 `clean`**
   —— 现象是"什么都没发生"。脚本现已默认跳过它并补 `clean`。
2. **`-func` 的合法值要以工具自带 `-help` 为准**：`0~7` = `==,<>,>,>=,<,<=,In Range,Out of Range`
   —— 官方 PDF 示例里的 `-func 1` 是 `<>` 不是 `==`（'==' 是 **0**）。
3. **`-value` 不能写成 `-value { $v }`**：花括号会保留首尾空格，值串变成 `" XXX…R "` 直接被拒
   （`The value of trigger unit is illegal or out of range`）。裸传 `-value $v` 才被接受。

**（以下为闭环前的排查记录，保留备查）**

**🔴 当时的唯一阻塞：Pango 下载线不在 Windows 总线上（物理层，已用 D2XX 定案）**

09-29 成功那次日志里有 `Cable index 0:USB Cable II/fffffffffffffffe`；
现在 `The cable List :` **是空的**，`get_cable_paras` 耗时从 1.2 s 变成 26.1 s（像在超时重试）。

**已用 Pango 自带的 `ftd2xx64.dll` 直接查证（不要再重查这一层）**：

| 调用 | 结果 |
|---|---|
| `FT_GetLibraryVersion` | status=0（FT_OK），3.2.20 |
| `FT_CreateDeviceInfoList` / `FT_ListDevices` | status=0，**count = 2** ⇒ FTDI 栈正常 |
| `FT_ListDevices(BY_INDEX\|OPEN_BY_DESCRIPTION)` | **`Dual RS232-HS A`** / **`Dual RS232-HS B`** |

⇒ ① **不是**驱动/DLL 不匹配（虽然本机 FTDI 驱动 2.12.36.20 比 Pango 自带 2.12.28 新，但 D2XX 枚举正常）；
② **现在插着的 FT2232 是普通双串口模块**，描述不是 Pango 认线用的 `PANGO USB CABLE II`；
③ 所以 `Cable List` 为空是**正确行为**——**Pango 的线确实不在总线上**。

**第三轮再挖深一层（EEPROM 级）**：直接读那颗 FT2232 的 EEPROM
（`FT_Open` + `FT_EE_Read`，**只读**）返回 **status = 15 = `FT_EEPROM_NOT_PROGRAMMED`**
⇒ **它的 EEPROM 是空的**，所以描述只能是 FTDI 默认串、两个通道都退化成 VCP 串口。
而 `cdt_js.exe` 的符号里有 `cable_manager::CablePgUsb` / `PgUsbIIOperator` /
`CableProtocolJtag` / `CEC_DRIVER_NOT_FOUND`，且 Pango 安装目录**自带**
`driver\ftdibus.inf`、`ftdiport.inf`、`amd64\ftd2xx64.dll`
⇒ **Pango USB Cable II = FTDI FT2232 方案 + Pango 自己烧写的 EEPROM**，
认线靠 EEPROM 里的 `PANGO USB CABLE II`。
**⚠️ 不要用 `FT_EE_Program` 去猜着烧这颗 EEPROM**（写什么全靠猜、可能弄砖，且它可能根本不是 Pango 的线）；
这属于硬件层改动，必须用户明确授权后才谈。

**本轮无新增不可做项**：软件侧（位流/脚本/触发配置/金标准判据）已 100% 就绪，
**唯一待办就是让 Pango 的线出现在总线上**。

**要用户做的**：把 **Pango 的 USB Cable II 下载线**（独立 dongle + 排线接板子 JTAG 口）
**直接插主机 USB 口**（不过 hub）。插上后 Pango 工具应能读到 `PANGO USB CABLE II`。
**注意：不要认错线**——现在那块 "Dual RS232-HS" 不是它。

**⚠️ 另一条重要结论（别白花时间）**：objective 里允许的"或本项目逻辑分析仪"这条路
**同样绕不过这个阻塞**——逻辑分析仪的**回读**走 UART(CP2102) 没问题，
但**下载位流依然要 JTAG**。所以在线缆恢复之前，**任何板级证据都拿不到**，
不要在替代路线上下注。

**下一轮第一件事**：
1. 插对下载线（见上），确认 Pango 能读到 `PANGO USB CABLE II`；
2. `scripts\program_board.ps1 -Config tmila -UseDebugger`
3. `scripts\run_ila_trap_capture.ps1 -Mode discover`（**先拿通道名，不要凭猜**）
4. `scripts\run_ila_trap_capture.ps1 -Mode capture -TrigExpr ...`
   （判据见 `fpga/timer_demo_ila/README.md` 末节）


**原来那三条做法（保留作历史记录）**：

**现状**：只有 `scripts\run_coremark_ila_pds.ps1`（DebugCore 位流构建），**没有波形抓取脚本**；
`fpga/coremark_ila/` 是现成的 DebugCore 工程模板。

**做法**：
1. 在 DebugCore 工程里把探针挂到 `pipeline_cpu` 的 `event_trap`、`event_trap_return`
   与 `csr` 的 `mepc_q`/`mcause_q`，构建 ILB 位流；
2. 用 `cdt_dbg.exe` 走 `dbg_connect` / `dbg_scan_chain` / `dbg_program`，写一个**新的**
   `scripts\run_ila_trap_capture.ps1`：触发条件 = `event_trap` 上升沿 → 抓若干拍 → 导出波形。
   **Pango 的波形回读命令必须查 PDS 文档/`doc` 目录确认，不要凭猜写命令。**
   （✅ 已查证：见 `doc/Fabric_Debugger_User_Guide.pdf` 第 6 章，命令有 `dbg_fla_set_trig_cond` /
   `dbg_fla_run` / `dbg_fla_export_wf_data` 等。）
3. **止损**：波形回读搞不定就**如实记"ILA 部分未完成"**，不要拿仿真波形冒充实板 ILA。
   M-24 里"周期性中断可观测"由 N1 满足，"ILA 抓 Trap 进入/返回"可单独标未完成。


### 3.3 【第 3 步，主体工程】高阶项①：2 路 I/D Cache + burst（S1～S4，带闸门）

**为什么值得做**：官方高阶三项（`docs/competition_scoring.md` §2）是
①2 路组相联 I/D Cache + burst ②动态预测 + 完整异常/中断 ③边缘 AI。
本项目**第②项已做完**（23/24 验收 PASS + 实板 80/80 + CoreMark 21.36 s），
再拿下第①项就是"三项覆盖两项"，这是提升国赛几率最实在的一步。

**答辩主线（要讲清楚的一句话）**：
> 现在的后端是片上 BRAM，低延迟、单笔事务，Cache 挡在前面省不下周期，Off/On 也测不出差别。
> **一旦把代码/数据搬到板载 DDR3，没有 Cache 会慢很多倍；这时 2 路组相联 Cache + 突发行填充
> 才成为必需品**——Off/On 才是真实后端上的真实数字。这就是官方那项要的东西。

#### 已查证的可行性证据（**2026-09-29 已重新核对并修正，完整清单见 `docs/ddr3_s1_survey.md`**）

> ⚠️ **上一版本节指错了 IP 包**：`ips2l_hmic_s` 面向的是 **PG2L50H**（Kosmo2/Logos2），
> `ipsl_hmic_h` 只有 **PGL22G**。**PGL50H 对应的软核 HMIC 是 `ipsxb_hmic_s`**（family=Logos，
> device 列表含 PGL50H），模板名也不是 `..._484_x72` 而是 **`50h_ddr3_fbg484_b3_x32.fdc`**。

| 证据 | 路径 / 说明 |
|---|---|
| **PGL50H 的 HMIC 软核 IP（正确包）** | `D:\Pango\PDS_2024.2-SP2\ip\system_ip\ipsxb_hmic_s\ipsxb_hmic_eval\ipsxb_hmic_s\` |
| **匹配本板的约束模板**：`50h_ddr3_fbg484_b3_x32.fdc`（FBG484 + Bank 3 + **x32**，80 条管脚约束，DDR3 部分全部 1.5 V SSTL15） | 同上 `pnr\`（同目录还有 `_b1_x16`、`mbg484`、`mbg324` 等） |
| 例程：AXI BIST（PRBS15/31 + 写/读控制 + 读数据比对）+ **串口命令解析与回读** + DDR3 仿真模型 | 同上 `example_design\`（`rtl\test_ddr.v.xml`、`rtl\uart_ctrl_32bit\`、`bench\mem\ddr3.v`） |
| 工程文件清单 | 同上 `pnr\prj_filelist.f`、`ctrl_phy_ip_filelist.f`、`phy_only_ip_filelist.f` |
| 例程时钟（**与本国赛工程不同**）：`ref_clk=F14`、`free_clk=Y11`，都是 50 MHz / LVCMOS33；UART 用 `U16/V15` | 见 `50h_ddr3_fbg484_b3_x32.fdc`；跑通后需改回板载 CP2102 的 `R9/R8` |
| 板子侧：手册给出 PGL50H 的 DDR3 管脚分配，**Bank 3 固定 1.5 V** | `docs/fpga_platform.md` §4 |
| 资源余量：交付工程 4536 LUT / 3852 FF / 5.5 DRM18K；板卡 42,800 LUT6 / 64,200 FF / 134 DRM18K | 发布包 README |
| ⚠️ 参考实现未跑过的前置未知项：**板载 DDR3 位宽（x32/x16）**、**DDR3 参考时钟是否真有 F14** | 需用户查手册/看板子，见 `docs/ddr3_s1_survey.md` §4 |

#### S1 DDR3 打通（P3a 闸门，必须先单独做完）

> ✅ **S1 已完成（2026-09-29 晚）：`S1 DDR3 SMOKE BOARD PASS`。**
> 下面那段 ⛔ 记录的是当天早些时候"模板管脚对不上、停在下载之前"的状态，**已被后续工作推翻**，
> 保留它是为了记住"厂商模板不能用"这个教训。当前事实以
> **`fpga/ddr3_smoke/README.md` §5** 为准：
> - 管脚约束**全部按 MES50HP 官方手册表 2-4 重做**（71 端口，61×`HSTL15_I` + 10×`HSTL15D_I`；
>   注意不是 `SSTL15*`——照官方例程 `07_ddr3_test` 改的），并真的过了一遍
>   PDS `compile → synthesize → dev_map`（71/71 落到管脚上，0 error）；
> - IP 生成**已全程无 GUI 打通**（`scripts/run_ddr3_ip_generate.ps1`：ip_compiler → 改参数 → ip_generate），
>   `ref_clk`/`free_clk` 都接 **P20**；
> - 位流 `fpga/ddr3_smoke/generate_bitstream/mes50hp_ddr3_smoke_top.sbit`，
>   SHA-256 **`FAEDF47618647C36FACBFF6DF0E5DE623F20ECD461FFA6997D724ABE93561B76`**，
>   `All Constraints Met`（Setup WNS +0.367 ns / Hold WHS +0.044 ns，失败端点 0）；
> - 板级：`python python\ddr3_smoke_board.py --port COM11 --seconds 8` 读厂商例程状态寄存器，
>   `dll_lock=1`、`ddr_init_done=1`、BIST 正常循环、`err_cnt=0`。
> - **还没做**（见 `fpga/ddr3_smoke/README.md` §5.5）：例程只做 BIST 与状态寄存器，
>   **没有吞吐量/延迟数字**，也**没有把 DDR3 接成 Core 的真实后端**——那是 S2 及之后的事。

> ⛔ **2026-09-29 第 2 版更新（历史记录，勿再作为现状引用）：厂商模板的 DDR3 管脚与本板对不上，
> 当时停在下载之前。** 完整证据与"按手册重做的管脚表"见 **`docs/ddr3_s1_survey.md`**。要点：
> - `ipsxb_hmic_s` 里的 `50h_ddr3_fbg484_b3_x32.fdc` 与 **MES50HP 官方手册表 2-4** 逐脚比对，
>   **69 个 DDR3 信号里 65 个管脚不同**（模板 `mem_ck=F3`，手册 `F3=ddr3_addr[3]`；
>   模板 `mem_cs_n=C1`，手册 `C1=ddr3_reset_n`）；
> - 模板的 `ref_clk=F14`、`free_clk=Y11` 在本板**不是时钟源**：
>   F14 = 网口 1 RX_CLK、Y11 = J8 扩展口；板载 50 MHz 接 **P20**（用户已核对手册确认）；
> - 板载 DDR3 = **2 颗 `QN3B256M16H-16A::P`（兼容 Micron `MT41K256M16HA-125`），
>   总位宽 32 bit，Bank B3，DDR-VDDQ 1.5 V**（手册 §2.2.3 + 用户确认）；
> - 已产出**按手册重做**的映射与约束片段：`tmp/ddr3/pinmap_manual.json`、
>   `tmp/ddr3/ddr3_pins_from_manual.fdc`（71 端口，61×`SSTL15_I` + 10×`SSTL15D_I`，
>   自检 6 项全过：71/71 与手册一致、管脚无重复、与 3.3 V 外设无冲突、byte lane 分组与手册一致）；
> - **下一步**：等用户确认 "DDR3 `ref_clk` 与系统时钟共用 P20" 方案后，
>   复制例程到 `fpga/ddr3_smoke/`，换成手册管脚表、改时钟与 UART 分频，再综合/下载。
>   **在此之前不下载任何 DDR3 位流**（把 DDR3 CK 打到网口 RX_CLK 上既有损坏风险也必然不通）。

1. **先确认两件硬件事实**（`docs/ddr3_s1_survey.md` §1）：已由用户确认 —— 总位宽 **x32**、
   颗粒 **`MT41K256M16xx-15E` 兼容**、系统时钟 **P20**、F14/Y11 **不是时钟源**。
   仍需用户提供：**板载 27 MHz 单端晶振的管脚号**（若想用它做 `ref_clk`；否则默认用 P20）。
2. 复制 `ipsxb_hmic_s` 的 Example Design 到**新目录** `fpga/ddr3_smoke/`
   （`pnr\prj_filelist.f` 给出源文件清单；**不得改动任何交付工程**）。
3. 用 `tmp/ddr3/ddr3_pins_from_manual.fdc` **替换**厂商管脚表；`ref_clk`/`free_clk` 改接 P20；
   同步改例程 UART 分频并改到板载 `R9/R8`。
4. 综合 → 布局布线 → 位流 → 下载（`cdt_cfg`；DDR 工程占用 Bank 3 的 1.5 V，
   **不要与现有 3.3 V 约束混用**）。
5. 读串口 BIST 结果 → 记录**随机/连续访问延迟与吞吐**（"真实后端"的第一组数字，
   将来 Cache 的 Before/After 都要以它为基准）。
6. 仿真：例程自带 `ddr3.v` 模型；本机只有 iverilog，PHY 可能是加密/黑盒，
   **仿真跑不动就只做板上验证**并如实记录，不要伪造成"仿真通过"。
7. **闸门（硬性）**：时间盒 **2 个轮次**；例程在我们的板子上跑不通 → **停 S2～S4**，
   把时间转到 §3.4（材料）与 §3.5（Fmax）。
   > 补充：S1 本身**不需要**改 `AGENTS.md` §1.14——它只是"把 Core 外部的 DDR 控制器跑通并量数字"。
   > 但 **S2～S4 必须先由用户改写 §1.14**：用户 2026-09-29 的答复是**暂不改，等 S1 真跑通再决定**。

#### S2 行式突发接口

- 在 Core 与 DDR 适配器之间引入"一次请求 + 连拍"的**行传输**（建议 32 B = 8 拍）。
- **Core 侧端口保持不动**：`docs/interfaces.md` 的 `i_req_*`/`i_rsp_*`/`d_req_*`/`d_rsp_*`
  字段与单笔语义不改，突发只发生在 Core 之外的适配器↔DDR 之间。
- **量化证据**：同一个 32 B 行填充的**总线周期数**，逐字方案 vs 突发方案（这是"burst 优化"的定义）。
- **止损**：突发方案实测总线周期没有下降 → 停。

#### S3 2 路组相联 I-Cache（**已完成模块级验证；集成后触发止损，默认关闭**）

**已做**：`rtl/soc_icache_2way.v`（32 组 × 2 路 × 8 字/行 = 2 KB，round-robin 替换，
`CACHE_EN` Off 开关）+ `tb/tb_soc_icache_2way.v`（**26 项 PASS**）。
模块级量化（慢后端）：命中率 **87%**、下游请求 −87.5%、下游总线周期 **−70%**、
Core 等待周期 **−50%**。

**止损触发**：接进真实取指路径后（`tb/tb_coremark_pipeline.v` 的 `ENABLE_ICACHE`），
同一 TB / Core / 程序下 CoreMark **从 1,251,724 拍涨到 2,891,324 拍（慢 2.31 倍）**。

**根因**：`rtl/pipeline_cpu.v` 第 727–741 行的"响应接收 + 新请求接受同拍交接"优化，
让**零等待** BRAM 能每拍取一条；I-Cache 的命中响应是**寄存**的，
每次取指由 1 拍变 2 拍，**把顺序前端减半**。

**已按规则回退**：`ENABLE_ICACHE` 与 `CACHE_EN` **默认都是 0**；**未重新出版本**。
模块与独立 TB 保留但不接入交付工程。

**下一轮该做什么（重要）**：S3 要真正兑现，必须先解决**共同的 1 拍问题**——
把命中路径做成**组合**（零气泡）。本会话试过但**未调通**（握手时序反复出错、TB 超时），
过程记入 `docs/debug_log.md`。要点提示，避免重走弯路：

1. 命中数据在"请求被接受后"仍可组合读出，所以 `rsp_valid` **不能**只在判定那一拍有效——
   必须有一个**粘滞标志**把它保持到 `rsp_ready` 真正握手完成（含 IDLE 拍就完成的情形）；
2. 状态机**不要**让"是否进下一状态"依赖被自己驱动的 `rsp_valid`，否则会互锁（实测状态机不推进）；
3. `req_ready` 与 `rsp_valid` 不能同拍都拉高（那等于"请求被接受的同时旧响应还在"），
   否则 Core 的前端交接会算错。

**另一条更省事的路线**：先把后端换成**真实慢存储**（S1 已经跑通的 DDR3），
Cache 的收益就不依赖零气泡了——模块级 −70% 的总线周期正是在慢后端下测出来的。

#### S4 2 路组相联 D-Cache（**模块已完成并通过独立验收；集成级 CoreMark 未做**）

**参数**：2 路 × 32 组 × 32 B = 2 KB，写穿 + 写缓冲，带 `CACHE_EN` Off 开关。

**已完成**：`rtl/soc_dcache_2way.v` + `tb/tb_soc_dcache_2way.v`（**19 项 PASS**），
四项必做功能全部验证：

- **写穿 + 写缓冲**（明确不做写回）：写命中按 `wstrb` 就地合并 + 写穿下游；
  写未命中不分配；单条目写缓冲，占满时让 Core 等；
- **MMIO 强制绕行**：`> CACHEABLE_LAST_ADDR`（默认 `0x0000_FFFF`）不查表/不分配/不更新，
  用"写 MMIO 再读回"验证副作用未被缓存；
- **Store→Load 转发**：写缓冲未落盘字节按 `wstrb` 覆盖读回值（命中与直连两条来源都覆盖）；
- 字节写按 `wstrb` 逐字节合并；另覆盖行填充、2 路冲突仍命中、复位重填、越界 error。

**量化（必须连同前提一起引用）**：

| 后端 | 配置 | 下游读请求 | 下游总线周期 |
|---|---|---|---|
| 慢（读首拍 4 拍） | Off | 32 | 192 |
| 慢 | **On**（命中率 90%） | **3（−90%）** | **39（−79%）** |
| **零等待** | Off（对照） | 32 | 64 |

**⚠️ 未做的事**：**没有做 D-Cache 的集成级 CoreMark Off/On**。
曾尝试（`tb/dcache_coremark_adapter.v` + TB 的 `ENABLE_DCACHE`/`DATA_SLOW_LATENCY`），
**仍卡在开机第一条分支**（`pc=00000018 retired=7`）。关键排除：
`ENABLE_DCACHE=0` 时 `cycles=1,251,724 / retired=786,925` 与加入之前**逐位一致** ⇒ 基线未受损。
所以 S4 的收益是**模型级证据**，**"端到端净收益"仍未证明**——引用时不得省略这句。

**🔴 2026-09-29 第七轮更新（最重要的现状，接手先看这段）**

上一段写的"卡在开机第一条分支"的两个根因**都已经查清并修掉了**，
但**又暴露出更靠前的一个问题**，所以 **S4 仍未闭环，D-Cache 必须保持不接入**。
细节见 `docs/debug_log.md` 第七轮与 `docs/progress.md` 的 S4 第七轮小节。摘要：

1. **已修**：`tb/tb_coremark_pipeline.v` 原来把 D-Cache 与 `soc_data_interconnect`
   **并联**接在同一组 Core 端口网上 ⇒ `dr/dsv/drd/de` 四根网**双驱动 → 全变 `x`** ⇒
   永久冻结。已改为**串联**（新增一套 `x_*` 网：`Core → D-Cache → 互连`）。
2. **已修**：D-Cache 的 **MMIO（uncacheable）直连读通路**两处缺陷——
   直连读的锁存位置错（`word_q` 用了行内偏移，而直连读只发一个字）、
   适配器无视 `m_rd_len` 永远取满 8 个字（对 MMIO 越界读）。
   补丁：`python scripts\fix_dcache_mmio_bypass.py`（含 `--check`）。
3. **已撤回的两个错误根因**：第五轮"`D_IDLE→D_RSP` 非法跃迁"、第六轮"拒收=丢请求"
   **都不成立**（`pipeline_cpu.v` L876-879 表明 Core 会把请求一直举到被接受）。
   第六轮那个结论来自当时 TB 的**不忠实模型**，现已改为忠实模型并通过 8/8。
4. **🔴 仍未解决（下一轮第一件事）**：接好线、修完 MMIO 之后，集成能**跑完** CoreMark，
   但**输出被破坏**。第八轮用新增的 `-CacheEnD` 开关把问题拆成两级，结论**收窄到一条**：

   | 配置 | cycles | retired | bytes | UART 内容判据 |
   |---|---|---|---|---|
   | 完全旁路（交付基线） | 1,251,724 | 786,925 | **655** | PASS |
   | D-Cache 在路径 + **全直连**（`-CacheEnD 0`） | 1,628,578 | 774,251 | **655** | **PASS** |
   | D-Cache 在路径 + **真缓存**（`-CacheEnD 1`） | 1,341,508 | 771,724 | **607** | **输出被破坏** |

   - ✅ **直连（MMIO）通路已经是正确的**（`bytes=655` 与基线一致、内容判据全过）：
     D-Cache 可以安全地"挂在数据路径上但不缓存"。
   - 🔴 **坏的是可缓存读**：UART 日志逐字对比显示 `[0]crcfinal : 0xe714` 整行被吃成 1 个字符
     `c`、`CoreMark score x1000` 整行消失，而三处 CRC 与 `Correct operation validated.` **都是对的**。
     `.rodata`（`0x8000~0xBFFF`，见 `software/coremark/link.ld` 的 DROM）
     **落在 `CACHEABLE_LAST_ADDR=0xFFFF` 之内 ⇒ 是可缓存区**，
     所以是**可缓存读返回错数据**把 `printf` 的格式串读坏了。
   - **所以下一轮只查可缓存读通路**：优先给 `tb/tb_soc_dcache_2way.v` 加**逐字全比对** harness
     （填已知数据 → 顺序读整行 → 乱序读同一行 → 跨行读 → 每字比对；现有 19 项只看了几十个点，
     "模块 PASS 但集成烂"本身就是覆盖不足的直接证据），
     重点核对 `hit_word` 选路、行填充落点（`victim` + `fill_idx`）、
     以及第七轮改过的条件赋值 `word_q <= pend_cacheable ? addr[4:2] : 0` 有没有把**可缓存**路径带偏。

   **两个已排除的假线索，别再查**：①`0x10002000` 的 MMIO 读两边不同（那是 `perf_mmio` 的
   性能计数器，本来就随周期变）；②"UART 丢字符"（丢的是整段文本而非零星字符，不符合 overrun 特征）。

   **📌 顺带一个必须记住的前提事实**：**"只把 D-Cache 串进数据路径、一次都不缓存"就要多花
   +30.1% 周期**（1,251,724 → 1,628,578）。也就是说这套直通实现对着片上 BRAM 这种零等待后端
   是**纯亏损**，Cache 只有在后端足够慢（DDR3 那类）时才有机会回本（与 S3 结论一致）。
   引用 S4 收益时必须把这条一起说。

**当前安全配置（交付口径）**：`ENABLE_DCACHE=0`（TB 的 generate 直接把数据路径旁路，
基线 `cycles=1,251,724 retired=786,925 bytes=655` 逐位未变）。
**不要**只用 `CACHE_EN_D=0` 来代替它——它功能上已经正确，但会白白多花 30% 周期。

---

**✅ 2026-09-29 第九轮：S4 已闭环（根因找到、修好、功能验证通过、止损判定完成）**

上面第 4 条那个"🔴 仍未解决"**已经解决**，保留在上文只作为排查过程的记录。

**根因**：`rtl/soc_dcache_2way.v` 的 `S_RFIL` 里 **数据阵列写入缺 `cacheable_q` 门控**
（而 `tag/valid` 更新**有**门控）。于是**不可缓存（MMIO 直连）读**不改 tag/valid，
却把外设寄存器的值写进了数据阵列 —— 三笔错读全在 **set 0 / word 0**、全返回 `0x00000002`
（UART 状态寄存器值），而 `0x10000004` 算出来恰好就是 set 0 / word 0：
那条合法行 **tag 命中、数据却已被悄悄改掉**。
**修法是一行门控**，补丁：`python scripts\fix_dcache_bypass_data_array.py`（含 `--check`）；
另一处 MMIO 直连缺陷的补丁是 `python scripts\fix_dcache_mmio_bypass.py`。

**为什么三轮都没找到**：模块级 TB 的存储模型只有 **2048 字（0x0~0x1FFF）**，
而 CoreMark 数据在 **0x8000~0xFFFF** ⇒ 模块级 TB **根本寻址不到出问题的区间**。
第九轮真正一击命中的动作是**影子内存逐笔比对**（见 `docs/debug_log.md` 第九轮 §1）。

**修完的验证（全 PASS）**：

| 检查 | 结果 |
|---|---|
| 影子内存逐笔比对（真缓存） | **零笔错读** |
| UART 日志逐行对比（基线 vs D-Cache） | **只有计时/性能行不同**；所有 CRC、`Correct operation validated.`、`COREMARK_DONE` **逐字相同** |
| P3 套件 / s4i / s4d | 14·26·19 / 15 / 8 **PASS** |
| Trap 契约 / 最终回归 | 99/99 / **ALL AUTOMATED FINAL REGRESSION PASS** |
| CoreMark 基线 | `cycles=1251724 retired=786925 bytes=655` 逐位未变 |

**S4 止损判定（这是最终口径）**：

| 配置 | cycles | vs 基线 |
|---|---|---|
| 基线（无 D-Cache） | 1,251,724 | — |
| **D-Cache On（零等待 BRAM 后端）** | **1,348,302** | **+7.7%（净亏）** |

⇒ **S4 触发 §3.3 的「Off-On 无净收益」止损条件**：**功能已正确**，
但在本工程当前的零等待 BRAM 后端下**没有净收益**，因此
**D-Cache 保持默认关闭（`ENABLE_DCACHE=0`），不得宣称端到端收益。**
与 S3 同源：**Cache 的收益完全取决于后端有多慢**；只有把后端换成 DDR3 那类慢存储，
Cache 才有机会回本 —— 那属于"下一步的大工程"，不在本届已批准范围内自动展开。

**若将来要把 Cache 真正用起来，建议的前置顺序**（不要跳步）：
1. 先把 **DDR3/HMIC 行突发后端**真正接到 SoC 数据/取指路径（S1 只证明了板级连通）；
2. 用**同一个后端**跑 Cache Off/On（现在是拿零等待 BRAM 比，Cache 必输，比了也没意义）；
3. 后端够慢之后，再回头解决 S3 的"零气泡命中"问题（否则每次命中仍多花 1 拍）。

**⚠️ 一个不能引用的测量（留档，避免以后误用）**：
第九轮试过"同后端 Off/On"（两边都用 `slow_ram_adapter` + 读延迟 4，只差 `CACHE_EN_D`），
得到 Off = 5,000,000 拍超时、On = 1,217,422 拍。**这组数字不可引用**：
在 `DATA_SLOW_LATENCY=4` 下**纯直连配置（`CACHE_EN_D=0`）也报影子不符**，
说明该慢后端**模型的写延迟**让影子与存储模型对不上（模型问题，不是 Cache 问题），
且 On@4 的 `bytes=628 ≠ 655`，输出本身不完整。
要做可信的端到端慢后端对比，**前提是先把 DDR3/HMIC 真后端接进 SoC**。


**第三～四轮的实际进展（已从"猜"推进到"具体信号"）**：

- 新建独立 trace TB `tb/tb_dcache_adapter_solo.v`，用 `scripts\run_p3_sim.ps1 -Suite s4i` 单独跑；
- **查清并修掉协议不匹配**（前两轮死锁的根因）：Cache 的 `m_rd_valid` **只举一拍**，
  被 ready 接受后立刻撤下、之后只等 `m_beat_valid` 送数据；适配器以为它一直举着
  → **两边都以为对方在推进 → 死锁**。修法：适配器自己先把整行取进行缓冲再喂给 Cache；
- **适配器现在 15/15 全 PASS**（`P3 S4I: PASS (TEST PASS=15)`）。
  上一轮那次失败是 TB 没等写缓冲排空就发起行填充，**不是适配器逻辑错**；
- **CoreMark 集成的死锁已定位到具体信号**（`-DTRACE_DCACHE` + 新增诊断计数
  `stat_rsp_accepted`）：`acc` 从 0 变 1 说明 **Cache 以为响应已被 Core 收走并清掉了
  `rsp_valid`**，而 Core 侧 `dsv` 从头到尾没有效过（某一拍甚至是 `X`），
  `dstate` 永远停在 `D_RSP` ⇒ **两侧对"响应是否已交接"判断不一致**。
  已排除：多驱动、写缓冲未排空、适配器取行、Cache 模块、基线（均已核对）。

**下一轮该做的：强烈建议改走"对接 DDR3 行突发后端"，不要再修这个适配器。**

第五轮用**边沿触发**追踪（只在信号变化时打印）拿到决定性证据：

```text
[165000] dstate 0->1   (D_IDLE -> D_REQ)   st=0 acc=0
[175000] dstate 1->2   (D_REQ  -> D_RSP)   st=1 acc=0
[185000] dsv 0->X  dsr 1->1  dstate 0->2   st=6 acc=0   ← 非法跃迁 + dsv 为 X
[195000] dsv X->0  dsr 1->1  dstate 0->2   st=5 acc=1   ← Cache 以为握手完成
...（永久停住）
```

- **Core 出现了 `D_IDLE → D_RSP` 的跃迁**。而 `rtl/pipeline_cpu.v` 只有 4 个 `dstate` 驱动点
  （第 815/878/881/919 行），正常路径只能 `D_IDLE→D_REQ→D_RSP→D_IDLE`，**这一跳不可能正常出现**；
  `pipeline_cpu.v` 的 SHA-256 仍是 `B58496706686E37B`，未改过。
- 死锁期间 Core 侧条件**全部满足**（`exmem_valid=1`、`exmem_access=1`、`ls_misaligned=0`、
  `dstate==D_RSP`、`dsr=1`），而 `dsv` 只在 `st=6` 那一拍出现且为 `X`；
  同时 Cache 的 `acc` 却数到 1 ⇒ **两侧对"响应是否已交接"记账不一致**。

**建议改走 DDR3 后端的三条理由**：

1. **这层适配器本来就是测试用替代品**：它只是"用单笔互操作模拟一个行后端"。
   真硬件里 D-Cache 的下游应当是 **DDR3 控制器/HMIC 的行突发接口**（S1 已跑通）。
   **直接对接它，这层适配器不需要存在，死锁也就不存在。**
2. **性价比**：本会话已在"单笔互连 vs 行 Cache"的接口转换上耗了四轮
   （协议不匹配 → 行缓冲 → 握手记账 → 状态跃迁），每次都是一个新的、更深的接口假设；
   换后端是**把这个转换整体删掉**。
3. **科学价值更高**：换后端拿到的 Off/On 是**真实慢后端上的端到端数字**，
   直接满足 S4 的量化要求，也顺便解决 S3"零气泡才不会亏"的前提。

#### 前置契约改动（**先做，否则违反项目规则**）

1. ✅ **已完成（2026-09-29）** `AGENTS.md` §1.14 已由用户批准改写：I-Cache / D-Cache / burst / 外部 DDR3
   由"本届不做"改为"本届要做"，并写明执行顺序（S1→S2→S3→S4）、不得放宽的边界与"退化即回退"要求；
   §4 路线图、§8 解耦条款、§9 范围冻结三处引用一并同步。其余 7 个文档 9 处旧表述由
   `scripts/apply_scope_change.py` 精确落地。
2. ⏳ `docs/interfaces.md`：Core 端口不变，但要在 Core **外部**记录新的"行/突发适配器契约"（S2 时补）。
3. ⏳ `docs/architecture.md` 增加"存储层次（行式突发 + 2 路组相联 Cache）"一节（S2 时补）。
4. ⏳ `docs/roadmap.md` 的 Gate 补 P3 阶段与验收条件（S2 时补）。

#### 总止损线与降级方案

- **止损**：S1 打不通 → 停；突发无周期收益 → 停；Off/On 无净收益 → 回退；
  时序违例 → 回退；任何 trap / CoreMark / 应用回归退化 → 回退到最近的通过版本。
- **降级方案**：DDR3 打不通时，把行式突发实现在**片上 BRAM 后端**（宽 BRAM + 多拍），
  仍可交付 2 路 I/D Cache 与 Off/On 数字；但按清单口径**只能算原型，不能宣称完成官方整组**。

### 3.4 【第 4 步】N3：把参赛材料收口到"当前批次" ✅ **已完成（2026-09-30）**

1. **录视频** → 交付为**可执行流程**（录像需要人按录制键，Agent 无法代办）：
   新增 **`docs/demo_runbook.md`**，6 段分镜，每段**一条命令 + 预期输出 + PASS 判据**；
   并修正 `release/materials/video_script.md`（见第 3 点的两个批次问题）。
2. **数字批次对齐** → 新增 **`release/evidence/claims_map.md`**
   （数字 ↔ 证据文件 ↔ 位流 SHA-256，含第 12 节「未宣称清单」）。
   同时修正 `release/HANDOFF.md`（停在 09-17 快照）与交付包 README。
   ⚠️ 交付包 README 由 `scripts/export_final_submission.ps1` 的 `$readme` here-string **重新生成**，
   且该脚本会**清空整个 `release/final_submission/`** ⇒ 改生成物是白改，**必须改脚本里的模板**。
   模板里 markdown 行内代码要用**双反引号**`` `` ``；PowerShell 双引号 here-string 里 `` `r `` 会被当回车，
   把 `release/...` 吃成 `elease/...`（本轮踩到并已修）。
3. **重跑发布链** → **必须用 PowerShell 7**（`pwsh.exe`，本机在 Codex runtime 下；5.1 不行）：
   ```powershell
   pwsh -NoProfile -File scripts\export_final_submission.ps1   # FINAL SUBMISSION EXPORT PASS files=214
   pwsh -NoProfile -File scripts\create_release_manifest.ps1   # RELEASE MANIFEST PASS files=2260
   pwsh -NoProfile -File scripts\audit_release_package.ps1     # RELEASE PACKAGE AUDIT PASS final_files=131 artifacts=3
   ```

**本轮修掉的现场级缺陷（重要）**：`scripts/demo_preflight.ps1` 里 5 个位流哈希有 **3 个过期**
（`la50` / `cm50` / `cm80`），**现场演示前自检必然 FAIL**。现已修正并实跑
`DEMO PREFLIGHT PASS warnings=0`。该文件顶部已加注释：**改位流必须同步改这里和 `claims_map.md`**。

**查证中发现的两个批次问题（后续必须处理）**：

1. **80 MHz 没有当前批次结果**：`release/evidence/coremark_board_cm80.json`（Score 72.081）是 **09-17** 的测量，
   而 `fpga/coremark_80m` 位流已于 **09-28 22:26 重打**（`F0743756…`），新版**未上板复测**。
   视频稿已删除 80 MHz 分数。**要补：用 `-Config cm80` 重测一次。**
2. **平台里有 10 份不同批次的板级 CoreMark JSON**，混用会出错。当前有效的是
   `release/evidence/coremark_board.json`（09-29：Score **46.816**、CM/MHz **0.936**、CPI **1.508**、`ticks=1068006999`）。
   `release/evidence/ila_coremark/`（09-17 批次）用的是整段 CPI **1.5388**，
   "窗口 1.575 vs 整段 1.5388 差 2.3%"只在**同批次内**成立；换成 1.508 就变成 4.5%。**两个数不得混用。**

**仍未完成（如实标注，勿用仿真替代）**：
**三轮断电一致性 —— 用户 2026-09-30 明确决定不做**（`run01` 只做了重下载，**没有真断电**；
详见 `release/evidence/board/README.md`，记的是"用户决定不做"，**不是"已完成"也不是"不适用"**）；
80 MHz 逻辑分析仪回环；DDR3 接入 CPU 存储路径；N4 的 89.25 MHz 候选位流上板验证。

> ✅ **2026-09-30 上板会话已补掉两项**（此前长期挂在"未完成"里）：
> ① **80 MHz PLL CoreMark 首次按当前批次实测** —— Score **74.905**、CoreMark/MHz **0.936**、CRC PASS，
> 证据 `release/evidence/coremark_board_cm80_20260930.json`；
> ② **S1 DDR3 板级证据独立落盘** —— `release/evidence/ddr3_smoke_board/`，并复现 `S1 DDR3 SMOKE BOARD PASS`。
> 另外交付位流 `la50` 重新上板复核 **80/80 PASS**。
>
> ⚠️ **读数纪律**：板级 **CPI 有窗口敏感性**（同一颗位流实测 1.494 与 1.508，
> 而 `ticks`/Score/`flushes` 逐位相同）⇒ **CPI 只能写 ≈1.50**；
> `run_coremark_board.ps1` 的 `clock_hz` 恒为 50 MHz ⇒ 跑 80 MHz 位流时它打印的 `seconds` 是错的
> （真实 33.375 s，不是 53.400 s）。CoreMark 分数来自 **CoreMark 专用位流**，
> 不是交付的逻辑分析仪位流。

**本轮顺带发现并修掉的"旧批次"材料（此前从未被检查过）**：`release/materials/` 下 5 个文件
整体停留在 2026-09-16～09-23 快照，其中 `defense_qa.md` / `live_demo_script.md` 各 20+ 处数字错误、
`field_recovery_card.md` 的位流表整体是遗留文件名、**两份生成器（技术报告与 PPT）都把
"Cache/burst/完整异常中断/外部 DDR 不在本届范围"写进了正文**（与 §1.14 直接矛盾）。
现已全部修正，并**真正重新生成了 docx / pdf / pptx 且逐项验证了产物内容**。
重生成工具链有三个坑（`RUNTIME_NODE_MODULES`、`.codex-finalizer` 旧收据、目标 pptx 必须先删），
完整记录见 `docs/progress.md` §5.1。

### 3.5 【可选】N4：把 Fmax 往上推 ✅ **已完成（2026-09-30）**

在**同一份 RTL**（`pipeline_cpu.v` = `B58496706686E37B`）上收紧约束重跑 PDS，四个约束点全部 All Met：

| 约束周期 | 目标 | 估算 Fmax | WNS | LUT | FF |
|---|---|---|---|---|---|
| 20.000 ns | 50 MHz（交付值） | 55.5216 MHz | +1.989 | 4536 | 3852 |
| 13.333 ns | 75 MHz | 80.0897 MHz | +0.847 | 4805 | 3858 |
| 12.500 ns | 80 MHz | 85.2370 MHz | +0.768 | 4814 | 3858 |
| 11.765 ns | 85 MHz | **89.2538 MHz** | +0.561 | 4794 | 3858 |

- **交叉验证**：20 ns 那组复现出的 `est 55.5216 / WNS 1.989 / LUT 4536 / FF 3852` 与
  `release/evidence/automated_metrics.json` 的 `final` **逐个数字一致** ⇒ 扫描用的确是交付批次 RTL。
- **产物**：`release/artifacts/fmax_tuning_2026-09-30/`（3 份候选 `.sbit` + `_timing.rtr` + `sweep_summary.csv` + `rtl_sha256.txt`）。
- **止损未触发**：N4 后 Trap 99/99 PASS、CoreMark `cycles=1251724 retired=786925 bytes=655` 逐位未变、
  `run_final_regression.ps1` ALL PASS。
- **如实边界**：交付位流**未替换**；候选 `.sbit` **未上板**；候选哈希不同源于**构建目录不同导致布局种子不同**，
  非设计不同；**89.25 MHz 是 PDS 估算值**，板载时钟固定 50 MHz ⇒ "Fmax 提升"指**时序余量变宽**，
  不是板上跑得更快；**≥90 MHz 未测**。

**下一步可选**：① 补三轮断电压力（用户已表示不做）；② 若要把 85 MHz 变体或 89 MHz 候选**提升为交付位流**，
必须先重跑全部板级证据并更新所有哈希登记点（现在它们**只是**证据，不是交付入口）。

### 3.5.1 ✅ **已完成（2026-09-30）：85 MHz PLL 变体 —— 把"最高工作频率"变成板级实测**

赛题指南选题一 · 四 · 1 · (2) 要的是「**时钟频率**：在满足时钟约束的前提下，处理器能达到的最高工作频率」。
在此之前只有 **PDS 估算**（89.2538 MHz）和 **板级实测 80 MHz**。
板载晶振固定 50 MHz ⇒ 更高频率只能靠 **PLL 倍频**。

**做法：只改一个整数。** `STATIC_RATIOF` 16 → **17**（VCO 800 → **850 MHz**），`ODIV0` 仍 10
⇒ **85.000 MHz 精确整数频率**。VCO 850 MHz 在 PGL50H 允许范围 600~1250 MHz 内。

| 用途 | 工程 | 位流 SHA-256 | PDS |
|---|---|---|---|
| 逻辑分析仪 | `fpga/logic_analyzer_85m` | `F7DFD321250787B4FD71B18D85CF8F3E59309AFB3CE6383079CF4525BBA33AF8` | All Met；请求 85.0000 / 估算 **90.0766** MHz / slack +0.663 ns |
| CoreMark | `fpga/coremark_85m` | `751C692B8780E3F05BD6D86E8E0F8BA34A83AFE899E5DA86FE7474C49CA970E9` | All Met；请求 85.0000 / 估算 **88.2637** MHz / slack +0.435 ns |

**板级实测**：CoreMark **Score 79.587 / CoreMark-MHz 0.936 / CRC PASS / 31.412 s**；
逻辑分析仪 **四模式 80/80 PASS**（`release/evidence/logic_analyzer_board_85m/`）。

**三频点自洽**：`79.587 × 80/85 = 74.905`、`× 50/85 = 46.816`，与 80/50 MHz 实测**完全相同**；
三点 `CoreMark/MHz` 都是 **0.936**。

**构建入口**：`scripts\run_logic_analyzer_85m_pds.ps1`、`scripts\run_coremark_85m_pds.ps1`；
上板 `program_board.ps1 -Config la85` / `-Config cm85`。

**⚠️ 两个坑（都已修，别再踩）**：

1. **`generate_coremark_80m_memory.ps1` 会污染 50 MHz 交付镜像** —— 它先把自己的镜像写进
   `fpga/coremark/rtl/` 再拷出去。用 `-ClockHz 85000000` 调它会覆盖交付的 50 MHz CoreMark 镜像。
   本次专门写了 `generate_coremark_85m_memory.ps1` 直接输出到 85m 目录。
2. **UART 采集窗口 + 解码器的两个 bug**（`python/logic_analyzer.py`、`logic_analyzer_serial.py`）：
   `decode_uart` 把窗口第一个下降沿当帧起始、`pattern_div=433/sample_div=26` ⇒ 一帧 166.5 个采样点
   而旧窗口只留 70.5 点余量 —— **恰好在 50/80 MHz 能过、85 MHz 过不了**。
   已修（解码器 + 默认窗口 `pre=64/post=191`），三频率都稳定，50 MHz 回归 80/80 未退化。

**口径**：**板级实测最高工作频率 = 85.000 MHz**；**89.2538 MHz 仍是 PDS 估算**，两者不得混写；
**≥90 MHz 未测**；交付位流**仍是** `BCAE040A…`。

### 3.6 【明确不要做】AI / YOLO（高阶项③）

事实依据：`AGENTS.md` §1.14 明确排除；`docs/advanced_tasks_ai_checklist.md` 自己写的
"没有现成的模型、摄像头/传感器、存储控制器和推理演示链；纯软件识别或单个乘加器无法算完成"；
P4c 还要求实板端到端闭环。用户若要做，需先改 §1.14 并准备输入设备与模型。

---

## 4. 改了什么就必须重跑什么

| 改动位置 | 必须重跑 |
|---|---|
| `rtl/pipeline_cpu.v`、`rtl/csr_unit.v`、`rtl/decoder.v` | `run_pipeline_regression.ps1`、`run_trap_pipeline_tb.ps1`、`run_trap_golden_judge.ps1`、`run_csr_unit_tb.ps1`、`run_coremark_pipeline_tb.ps1`（两种延迟）、`run_final_regression.ps1` |
| `rtl/timer_mmio.v`、`rtl/soc_data_interconnect.v` | `run_timer_irq_tb.ps1`、`run_mes50hp_pipeline_soc_tb.ps1`、`run_logic_analyzer_*_tb.ps1`、`run_final_regression.ps1`、三个 PDS 重建 |
| **新增 Cache / 突发适配器（S2～S4）** | 上面全部 + **Cache On 下的 trap 99 条** + CoreMark Off/On 同镜像 + 板上 J8 四模式 + DDR 工程自己的 BIST |
| `tb/*`、`scripts/*` | 对应 TB/回归 + `run_final_regression.ps1` |
| 任何 RTL | 三个 PDS 工程重建（`run_coremark_pds.ps1`、`run_logic_analyzer_pds.ps1`、`run_coremark_80m_pds.ps1`）+ 刷新 `release/artifacts` + 重新导出/审计 |
| 材料/发布 | `export_final_submission.ps1` + `audit_release_package.ps1` |

**注意**：PDS 的 WNS 会随布放种子波动（同一份 RTL 两次构建实测差过约 1 ns）。
引用时序必须连同"哪一次构建"一起说明，不要跨次比较 WNS。

---

## 5. 关键文件索引

| 用途 | 位置 |
|---|---|
| 项目总规则 / 范围纪律 | `AGENTS.md`（§1.13/1.14 决定高阶任务与明确不做的项） |
| Trap 契约与验收矩阵 | `docs/trap_contract.md`（§6 矩阵、§6.4 M-14、文末结论段） |
| 进度与每轮证据 | `docs/progress.md`（顶部"A7 发布收口"→"A6 故障诊断"→"实板闭环"→"A3 轮次"） |
| 踩过的坑 | `docs/debug_log.md` |
| Core/SoC 边界与地址窗口 | `docs/interfaces.md`（§3.2 含 TIMER 的完整窗口表） |
| Trap 数据通路设计 | `docs/architecture.md` §5.4 |
| 逻辑分析仪应用 + A6 现场步骤 | `docs/application_logic_analyzer.md` §6.5 |
| 进阶任务包与止损条件 | `docs/advanced_task_plan_qa.md`（A0–A7；"时间紧张时优先 A0~A3、A6、A7"） |
| 官方评分映射 | `docs/competition_scoring.md`（§2 高阶三项、§3 得分主线） |
| **DDR3 / HMIC 软核 IP + 50h 约束 + 例程** | `D:\Pango\PDS_2024.2-SP2\ip\system_ip\ips2l_hmic_s\ips2l_hmic_eval\ips2l_hmic_s\` |
| **DDR3 / HMIC 硬核 IP + 例程** | `D:\Pango\PDS_2024.2-SP2\ip\system_ip\ipsl_hmic_h\ipsl_hmic_h_eval\ipsl_hmic_h\` |
| 板级下载 | `scripts/program_board.ps1`（`-Config la50|la80|cm50|cm80|ila`，必要时 `-UseDebugger`） |

---

## 6. 交回格式（每完成一个任务都按这个写）

1. **改了什么、为什么**：文件清单 + 设计取舍；
2. **怎么证明**：实际命令、PASS/FAIL、首个失败点、未覆盖项；
3. **值不值得保留**：同镜像 Before/After（仿真 / 综合估算 / 时序 / 实板分开写）；
4. **能否进入下一包**：逐项对照止损条件；失败就保留日志并回退到最近的通过版本。

## 7. 给用户的一句话摘要（可直接复述）

> 高阶任务②（动态预测 + 完整异常/中断）已经做完并验证：契约 24 条里 23 条 PASS、回归 28 项全绿、
> 实板也重新验证过（J8 四模式 80/80、CoreMark 实板 21.36 秒）；
> **板级周期性中断演示（M-24 的前半条）已于 2026-09-29 闭环**：新建最小工程 `fpga/timer_demo`
> （Core 一字未改），板上实测 50 条连续中断记录、45 个间隔全部等于 12_500_000 ± 65_536 拍、
> LED0 每 0.25 s 翻转一次；只剩 **ILA 抓 Trap 进入/返回** 没做。
> 高阶任务①（2 路 I/D Cache + burst）经复查**可行**：PDS 里带着匹配 PGL50H-484 的 DDR3 约束模板
> （`50h_ddr3_484_x72.fdc`）与厂商例程，路线是"先打通 DDR3 → 行式突发 → I-Cache → D-Cache"，
> 每步都有止损线和实板 Before/After。
