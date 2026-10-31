# S1：DDR3 板级冒烟证据（2026-09-30 补录）

> 本目录补齐了 `docs/handoff_next.md` 与 `release/HANDOFF.md` 里长期标注的缺口：
> **S1 的板级日志此前只存在于 `docs/ddr3_s1_survey.md` 的正文引用中**，
> `release/evidence/` 下没有独立证据文件。现在有了。

## 1. 位流（引用本证据时必须同时写明它）

| 项 | 值 |
|---|---|
| 工程 | `fpga/ddr3_smoke` |
| 位流 | `fpga/ddr3_smoke/generate_bitstream/mes50hp_ddr3_smoke_top.sbit` |
| SHA-256 | `FAEDF47618647C36FACBFF6DF0E5DE623F20ECD461FFA6997D724ABE93561B76` |
| 大小 | 2,101,696 B |
| 下载 | `scripts\program_board.ps1 -Config ddr3` → `PROGRAM PASS`、`The done bit is 1` |

## 2. 原始证据

| 文件 | 内容 |
|---|---|
| `board_run_20260930.log` | 本次复现的完整串口判定输出（2026-09-30，COM11 @ 115200 8N1，8 s 窗口） |

## 3. 本次复现结果（与 2026-09-29 首次通过一致）

```text
S1 DDR3 冒烟板级验收: COM11 @ 115200 8N1
  0x80 = 0x00011110  pll_lock=0 dll_lock=1 ddr_init_done=1 err_flag=0
  心跳采样 155 次，翻转 16 次（窗口 8 s）
  0x8B = err_cnt=0 main_state=3 wr_state=0 rd_state=2（15 次采样）

  [PASS] DLL 锁定
  [PASS] DDR3 初始化完成
  [PASS] 心跳在翻转（设计在运行）
  [PASS] 无校验错误标志 err_flag_led
  [PASS] BIST 错误计数全程为 0
  [PASS] BIST 状态机在推进
  [NOTE] pll_lock 状态位恒为 0（已知偏差，见 docstring）

S1 DDR3 SMOKE BOARD PASS
```

复现命令：

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\program_board.ps1 -Config ddr3
python python\ddr3_smoke_board.py --port COM11 --seconds 8
```

> 注意：`ddr3_smoke_board.py` 输出是 UTF-8，而 Windows PowerShell 5.1 控制台默认 GBK，
> 直接跑会看到乱码。**重定向到文件时先设 `$env:PYTHONIOENCODING='utf-8'`**，
> 否则存下来的证据文件不可读（本次已踩过）。

## 4. 这份证据**证明了什么**、**没证明什么**

**证明**：DDR3 控制器（`ipsxb_hmic_s`，HMIC_S 硬核）**在本板真正工作**——
初始化完成、DLL 锁定、BIST 状态机推进、BIST 错误计数全程为 0、心跳翻转。

**没有证明**（不得据此宣称）：

| 未证明的项 | 原因 |
|---|---|
| DDR3 **吞吐量 / 延迟** | `test_ddr` 例程只做 BIST 与状态寄存器，**没有任何性能测量** |
| DDR3 **已接入 CPU 存储路径** | 只做了板级连通性；S1 之后**没有**把 HMIC 后端接到 Core 的取指/数据路径 |
| Cache 在真实 DDR3 后端下的收益 | 从未测过（S3/S4 的止损是在**零等待 BRAM** 后端下得出的） |

**已知偏差（未消除，如实记录）**：`0x80` 的 bit0（`pll_lock` 状态位）持续为 0。
但同寄存器的 `dll_lock=1`、`ddr_init_done=1`、BIST 正常循环三者**不可能同时成立**，
且板上 LED1 实测常亮 ⇒ 判定**该状态位本身不可信**（极性/连线问题），不是"PLL 未锁定"。
**本项不计入通过判据。**

## 5. 与 2026-09-29 首次通过的差异（如实记录）

| 字段 | 2026-09-29 | 2026-09-30（本次） |
|---|---|---|
| `0x80` | `0x00001110`（文档记载） | `0x00011110` |
| `0x8B` 采样 | `main_state=4 wr_state=0 rd_state=2` | `main_state=3 wr_state=0 rd_state=2` |
| 心跳 | 155 次采样 / 翻转 16 次 | 155 次采样 / 翻转 16 次（一致） |
| BIST `err_cnt` | 全程 0 | 全程 0（一致） |
| 判定 | `S1 DDR3 SMOKE BOARD PASS` | `S1 DDR3 SMOKE BOARD PASS`（一致） |

`main_state` 是**运行时状态机的即时采样值**（不同采样时刻会落在不同状态），
不是固定常量；`wr_state` / `rd_state` 同理。**判定条件不看这几位是否等于某个定值，只看 BIST 是否推进、错误计数是否为 0。**

---

*本证据由 2026-09-30 上板补录。数字出处索引见 `release/evidence/claims_map.md` §7。*
