# 板级轮次证据（Reset / 重下载一致性）

> ⚠️ **2026-09-30 后续更新：交付配置已切换。** 本文写于切换之前，文中"交付位流 = `BCAE040A…`（50 MHz）"
> 的表述**已过期**。现在的交付主位流是 **85 MHz PLL 版**（`F7DFD321…`，工程 `fpga/logic_analyzer_85m`），
> 50 MHz 版（`BCAE040A…`）改为**已验证备用位流**随包提供。
> 本文其余内容（波形、对比、上界结论）**不受影响**，因为那些结论与"哪一颗是交付位流"无关。

## 当前状态：**只有 1 轮**，三轮一致性 **未做（用户 2026-09-30 决定不做）**

`docs/roadmap.md` 任务 35 的验收标准里有一条：
「**多次断电、Reset 和重新连接串口后演示结果一致**」，通过条件要求
`competition_final` 前完成三轮（`docs/reproduction.md`「Reset 与断电重复」）。

**2026-09-30 用户明确表示"不用三轮一致性，我感觉没意义"**，因此本项**不再执行**。

> ⚠️ **这条要如实记为"用户决定不做"，不能记成"已完成"或"不适用"。**
> 将来若有人问"三轮断电压力做了吗"，答案是：**没做，是用户主动放弃的**。
> 如果最终提交需要这一条，必须重新跑 `scripts\run_board_rounds.ps1`。

## run01：已完成的那一轮（2026-09-30，**重新下载 = Reset 等价**）

| 项 | 值 |
|---|---|
| 轮次 | 1 |
| 复位方式 | `re-download (reset-equivalent, FPGA reconfigured)` |
| **有没有真的断电** | **没有。脚本无法替人断电。** |
| 端口 | COM11 @ 115200 8N1 |
| 逻辑分析仪 | 当时的交付位流 la50（`BCAE040A…`，**现已改为备用位流**），J8 四模式各 20 次 = **80/80 PASS** |
| CoreMark | 计分位流 cm50（`DC95F9D0…`），`ticks=1068006999`、Score **46.816**、`crcfinal=0xd340`、1000 迭代、CRC **PASS** |
| 证据文件 | 164 个（`logic_analyzer/` 四模式各 41 个）+ 6 个日志/summary |

**这一轮的价值**：它证明**重新下载后结果与 2026-09-29 完全一致**——
CoreMark `ticks` 与 Score 两次运行**逐位相同**（1068006999 / 46816）。

**它不能证明**：断电冷启动后的一致性（没有断电）。

## 复现 / 若要补做三轮

```powershell
# 单轮（重新下载 = Reset 等价）
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_board_rounds.ps1 -Port COM11 -Round 1 -RunsPerMode 20

# 带真实断电的三轮：脚本会在每轮之间暂停，让你有时间断电；
# 你确实断过电的那一轮请加 -PowerCycled，否则 summary 会如实记成"未验证断电"。
# （同一轮里不要既不加 -PowerCycled 又对外宣称断过电。）
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_board_rounds.ps1 -Port COM11 -Round all -RunsPerMode 20 -PauseSeconds 120 -PowerCycled
```

比对逻辑：读取 `run01`~`run03` 里所有已存在的 `summary.json`，
要求各轮 `la_pass` 全为真、且 CoreMark 的 `ticks` / `crcfinal` / `iterations` **完全一致**，
全过才打印 `BOARD ROUND CONSISTENCY PASS`。

## 附带发现：板级 CPI 有"窗口敏感性"（写进材料时必须知道）

同一颗 cm50 位流两次运行（2026-09-29 与 2026-09-30 run01）：

| 字段 | 09-29 | 09-30 run01 | 是否一致 |
|---|---|---|---|
| `ticks` | 1068006999 | 1068006999 | **一致** |
| `score_x1000` | 46816 | 46816 | **一致** |
| `flushes` | 64153920 | 64153920 | **一致** |
| `iterations` | 1000 | 1000 | **一致** |
| `cycles` | 1279896248 | 1162472298 | 不同 |
| `instret` | 848491425 | 778037055 | 不同 |
| `branches` | 240477872 | 216993082 | 不同 |
| `stalls` | 174789140 | 127819560 | 不同 |
| `load_stalls` | 63079449 | 39594659 | 不同 |
| `taken` | 165302707 | 141817917 | 不同 |
| `cpi_x1000` | **1508** | **1494** | 不同 |

**怎么解读**：`ticks` 与 `flushes` 逐位相同 ⇒ **程序执行完全一致**；
差异只出现在**性能计数器**的聚合量上 ⇒ 是计数器**统计窗口**的边界口径问题
（固件用 `PERF_CONTROL` 的 clear 脉冲把计数器窗口对齐到 CoreMark 计时窗口，
见 `software/coremark/core_portme.c` 的 `PERF_WINDOW_ALIGN`）。

**因此**：

- **CoreMark 的 Score / ticks 可以照写**，它们完全可复现；
- **板级 CPI 不能写成 `1.508` 这种四位精度**，应写成 **≈1.50（实测 1.494–1.508，窗口敏感）**。
  材料里凡出现"CPI 1.508"的地方都要按这个口径表述。

---

*本节由 2026-09-30 上板复现建立。数字出处索引见 `release/evidence/claims_map.md`。*
