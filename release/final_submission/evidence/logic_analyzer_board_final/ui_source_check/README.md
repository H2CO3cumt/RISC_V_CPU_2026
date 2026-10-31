# 采集源（双源可选）界面与验收证据

本目录是"采集源双源可选"功能**接进两个上位机界面之后**的实板复测记录
（2026-10-14，用户指出"功能做出来了但界面上没改"后补做；RTL / 固件 / 位流均未改动，
交付位流仍是 `C017ED10…`）。

## 1. pyUI 真路径：四种「模式 × 采集源」组合

命令（`python/ui_source_board_check.py` 驱动的是界面自己的 `_run_logic_analyzer()`，不是重写的采集脚本）：

```powershell
scripts\run_ui_source_board.ps1 -Port COM11
# = python python/ui_source_board_check.py COM11  +  python 逻辑分析仪演示.py --selftest COM11
# 两段日志直接刷新到本目录：pyui_board_check.log / singlefile_selftest.log
```

| 组合 | 报文长度 | 命令码 | `[14]` 采集源 | 解释方式 (view) | 结果 |
|---|---:|---|---|---|---|
| `core` 模式 + Core 源（默认） | 16 | 0xA8 | 1 | `core` | PASS（1987 点，触发 3） |
| `uart` 模式 + Core 源 | 16 | 0xA8 | 1 | `core` | PASS（1984 点） |
| `uart` 模式 + J8 源（默认） | 13 | 0xA5 | — | `uart` | PASS（207 点，触发 15，解出 A5） |
| `core` 预设 + J8 源 | 13 | 0xA5 | — | `raw` | PASS（256 点，电平触发） |

末行：`UI BOARD CHECK PASS`。完整输出见 `pyui_board_check.log`。

> 后两种组合在修 `capture_view` 之前是**假失败**：uart+Core 被按 UART 帧解码报
> `UART decode mismatch`；core+J8 的 ch6 上升沿在 J8 源下永不出现而超时。
> 判据规则见 `docs/application_logic_analyzer.md` §6.10.5。

## 2. 单文件界面（自包含演示器）六模式

```powershell
python 逻辑分析仪演示.py --selftest COM11   # → singlefile_selftest.log（也可由上面那个 ps1 一起跑）
```

`全部通过`；Core 源读数：提交 1187 拍、取指请求在场 1198 拍、停顿 785 拍、
冲刷 4 次、窗口 IPC 0.597（读数区按 `view=core` 改成这几个计数，不再是协议读数）。

## 3. 板级验收入口新增的 Core 源开关

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_logic_analyzer_board.ps1 `
  -Port COM11 -RunsPerMode 1 -IncludeCoreSource -CoreRuns 3 -Output results\la_board_include_core
```

```text
LOGIC ANALYZER BOARD RUN 1/1 PASS mode=static  view=static
LOGIC ANALYZER BOARD RUN 1/1 PASS mode=counter view=counter
LOGIC ANALYZER BOARD RUN 1/1 PASS mode=uart    view=uart   samples=207 trigger=15
LOGIC ANALYZER BOARD RUN 1/1 PASS mode=spi     view=spi    samples=85  trigger=4
LOGIC ANALYZER BOARD RUN 1/1 PASS mode=mirror  view=mirror samples=2048 trigger=0
LOGIC ANALYZER BOARD RUN 1/3 PASS mode=core    view=core   samples=1987 trigger=3
LOGIC ANALYZER BOARD RUN 2/3 PASS mode=core    view=core   samples=1987 trigger=3
LOGIC ANALYZER BOARD RUN 3/3 PASS mode=core    view=core   samples=1987 trigger=3
LOGIC ANALYZER CORE SOURCE PASS captures=3 source=core_probe
LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=8 mirror_text=HELLO,RISC-V
```

`-IncludeCoreSource` 是**加跑**：不加开关时脚本仍打印原来的
`captures=100`（五模式 ×20），既有 100/100 验收口径与证据不变。

## 4. 已知限制（同批记录）

触发条件永不出现时，固件会停在无超时的采集完成轮询上（`logic_analyzer.c` 第 189 行），
串口不再响应，**只能按板上 `REST` 或重下同一位流恢复**；实板复现一次后重下 `la85` 恢复。
识别方法与现场纪律见 `docs/application_logic_analyzer.md` §6.10.7 与
`release/materials/field_recovery_card.md`。本轮未改固件（改它要重建位流、作废全部哈希）。
