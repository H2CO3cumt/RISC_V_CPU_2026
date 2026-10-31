# M-24 / N2 板级 ILA 证据：Trap 进入与返回

本目录是 **M-24（板级周期性中断 + ILA 抓 Trap 进入/返回）** 的实板证据。
判据与 `../golden_trace.txt`（仿真金标准）一一对应。

## 位流与硬件

| 项 | 值 |
|---|---|
| 位流 | `../generate_bitstream/mes50hp_timer_demo_top.sbit`（2,101,696 B） |
| 位流 SHA-256 | `452EE532DAC8AB9A86CDF9C6859892F7BA466EA035EF6A6C46FAAA9598248B74` |
| 下载线 | **PANGO USB CABLE II**（`dbg_scan_chain` 日志：`PANGO USB CABLE II cable driver: D2XX DLL`） |
| 器件 | `IDCODE = 0x00521899`（PGL50H-6IFBG484） |
| 采样 | 512 采样点，单窗口，触发位置 `-position 256` |

**注**：本证据**不需要** JTAG 之外的任何东西；固件的 250 ms 周期中断记录由 CP2102 串口（COM11）另行验证（见 `docs/progress.md` 的 N1 记录）。

## 复现命令（三步）

```powershell
# 1) 构建位流（PDS）
powershell -File scripts\run_timer_demo_ila_pds.ps1
# 2) 下载（板上位流带 DebugCore，必须走 Fabric Debugger）
powershell -File scripts\program_board.ps1 -Config tmila -UseDebugger
# 3A) 触发在 Trap 进入（ila_event_trap = 探针 bit0 上升沿）
powershell -File scripts\run_ila_trap_capture.ps1 -Mode capture
# 3B) 触发在 Trap 返回（ila_event_trap_return = bit1 上升沿）
$tv = ('X' * 190) + 'R' + 'X'
powershell -File scripts\run_ila_trap_capture.ps1 -Mode capture -TrigValue $tv
```

抓取脚本会导出 **vcd + txt** 两种格式，并把它们放在 `tmp/ila/`；
下面两份是本目录固化的副本。

## 证据 A：触发在 **Trap 进入**（`ila_event_trap` 上升沿）

- `A_trap_enter/waveform.txt` — 76,439 B，SHA-256 `A7FAB1B198B3008D1B02EFE80EDFD787EF0622AC2E0DFA9EF597B9213297A71D`
- `A_trap_enter/waveform.vcd` — 7,374 B，SHA-256 `E9EC8F47521D163EFAF96EF28FB6680719AAC4B27330FEF950FDC4D052A4B7EA`

| 通道 | 结果 |
|---|---|
| `ila_event_trap`（bit0） | **恰有 1 个脉冲，位于第 256 采样点 —— 正是 `-position 256` 触发点** |
| `ila_event_trap_return`（bit1） | 1 个脉冲，第 251 采样点 |
| `irq_timer`（bit6） | 全窗口为 1（原因 = 机器定时器中断） |
| `ila_event_illegal` / `misaligned` / `bus_error` | **全 0**（没有被误触发的异常） |
| `perf_retire`（bit7） | 12 个脉冲 |

## 证据 B：触发在 **Trap 返回**（`ila_event_trap_return` 上升沿）

- `B_trap_return/waveform.txt` — 76,454 B，SHA-256 `80F384A38B4DF507DE5615736894193EC2B56FA06239B5BC7C60333C265E1F45`
- `B_trap_return/waveform.vcd` — 7,374 B，SHA-256 `8BCDBC60270E9C241542C6DEC4B5F5ABE558F6496DA971E238EDA89BBD2C467D`

| 通道 | 结果 |
|---|---|
| `ila_event_trap_return`（bit1） | **恰有 1 个脉冲，位于第 256 采样点（触发点）** |
| `ila_event_trap`（bit0） | 1 个脉冲，第 261 采样点 |
| `irq_timer` | 全窗口为 1 |
| illegal / misaligned / bus_error | 全 0 |

## 结论（判据 C1~C5）

| # | 判据 | 结果 |
|---|---|---|
| C1 | 出现 `ila_event_trap` 脉冲 | **PASS**（A/B 两次各 1 个，位置与触发设置一致） |
| C2 | 出现 `ila_event_trap_return` 脉冲 | **PASS**（两次各 1 个） |
| C3 | 进入时 `irq_timer` = 1（原因 = 定时器中断） | **PASS**（全窗口为 1） |
| C4 | 无非法/非对齐/总线错误型 Trap 混入 | **PASS**（三路事件全 0） |
| C5 | 事件关系可复现 | **PASS**：两次抓取互相印证 —— **`trap` 恒在 `trap_return` 之后 5 个采样点**（A：251→256，B：256→261） |

**⇒ M-24 的"ILA 抓 Trap 进入与返回"由上述两次实板抓取满足。**

## 如实记录的边界（不得含糊）

1. **`mcause` / `mepc` 的数值不在探针里**（PDS 拒绝层级引用 `core.csr.mepc_q`，
   而改 Core 端口又违反 `AGENTS.md` §1.14）。本证据用 Core **既有**事件端口给出
   "Trap 进入/返回"本身，并用 `irq_timer` 证明原因；`mcause`/`mepc` 的数值由固件的
   串口记录（N1 的 50 条周期中断记录）证明。
2. `trap` 在 `trap_return` 之后 5 个采样点这一关系是**实测可复现**的；
   采样间隔本身（1 采样 = 多少 `clk_50m` 拍）尚未用独立手段标定，
   因此**不把它换算成"多少拍"**。
3. 单窗口 512 采样远短于一次 ISR（仿真约 3.5 万拍），所以
   "进入→返回"跨窗口不可见；这正是**分开抓两次**（A/B）的原因。

## 数据格式说明（供他人复核）

- `waveform.txt`：**纯数值表，无表头**；512 行 × 68 列，一行一个采样点，一列一个通道；
  列顺序按 FIC 的通道顺序（`mes50hp_timer_demo_top.fic` 的 `triggerChannel`）：
  `0..7` = 8 个单比特事件，随后是 4 条 32 位总线（`ia`/`idata`/`da`/`drd`）等。
- `waveform.vcd`：标准波形格式，带信号名（`$var wire 1 n0 ila_event_trap $end` …），
  可用 GTKWave 打开。
  **注意工具的一个瑕疵**：4 条 32 位总线共用同一个标识码 `n8`，所以 VCD 里
  `ia`/`idata`/`da`/`drd` 无法区分 —— **要按总线复核时请用 `.txt`**。
- 复核脚本：`tmp/ila/verify_capture.py`（按列核对 C1~C5）。
