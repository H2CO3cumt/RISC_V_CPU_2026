# N4 候选位流板级验证（2026-09-30）

> ⚠️ **2026-09-30 后续更新：交付配置已切换。** 本文写于切换之前，文中"交付位流 = `BCAE040A…`（50 MHz）"
> 的表述**已过期**。现在的交付主位流是 **85 MHz PLL 版**（`F7DFD321…`，工程 `fpga/logic_analyzer_85m`），
> 50 MHz 版（`BCAE040A…`）改为**已验证备用位流**随包提供。
> 本文其余内容（波形、对比、上界结论）**不受影响**，因为那些结论与"哪一颗是交付位流"无关。

## 一句话结论

**11.765 ns 约束的候选位流（估算 Fmax 89.2538 MHz）在 MES50HP 上功能正常，
J8 四模式 80/80 PASS，且与交付位流的采集结果逐字节相同。**

> ⚠️ **但这不等于"板上跑到了 89.25 MHz"。** 板载系统时钟固定 50 MHz，
> 这颗位流在板上仍然跑 50 MHz。**本验证证明的是"这版更紧约束的布局布线功能正确"，
> 不是"实测到了更高频率"。** 见第 4 节。

## 1. 被测位流

| 项 | 值 |
|---|---|
| 文件 | `release/artifacts/fmax_tuning_2026-09-30/la_85m_constraint11p765ns.sbit` |
| SHA-256 | `702EFAD1BA11A94858392DC775C3AE864963850E706B6779253A8FA6C813AA9E` |
| 约束 | 11.765 ns（85 MHz 目标），**All Constraints Met**，setup WNS **+0.561 ns** |
| PDS 估算 Fmax | **89.2538 MHz** |
| 资源 | 4794 LUT / 3858 FF / 5.5 DRM18K |
| RTL | `pipeline_cpu.v` = `B58496706686E37B`，**与工作区当前文件逐字节相同** |

## 2. 板级结果

**下载**：`scripts\program_board.ps1 -BitstreamPath release\artifacts\fmax_tuning_2026-09-30\la_85m_constraint11p765ns.sbit`
→ `PROGRAM PASS config=custom`、`The done bit is 1`。

**验收**：`scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20`
→ **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80`**
（static / counter / uart / spi 各 20/20）。

证据目录：`release/evidence/fmax_candidate_board/la_85m_constraint11p765ns/`
（164 个采集文件 + 四份 `summary.json`）。

## 3. 与交付位流的等价性（这是本验证最有价值的部分）

把候选位流与**当时的交付位流**（`BCAE040A…`，50 MHz 约束版；**现已改为备用位流**）在同一套四模式下的采集结果对比：

| 模式 | `summary.json` |
|---|---|
| static | **逐字节相同** |
| counter | **逐字节相同** |
| uart | **逐字节相同** |
| spi | **逐字节相同** |

原始日志抽样（`static_00.log`，两者**完全一致**）：

```text
LA RAW count=00000005 trigger=00000000
000000A5 000000A5 000000A5 000000A5 000000A5
UART:00000000 SPI:00000000
LA_DONE
LA_READY
```

⇒ **收紧约束只改变了 PDS 的布局布线目标，没有改变任何功能行为。**
这印证了 `release/artifacts/fmax_tuning_2026-09-30/README.md` 的"纯优化"说法。

## 4. 这份证据**不能**支撑的说法（必须写清楚）

| 不能宣称 | 原因 |
|---|---|
| "板上跑到 89.25 MHz" | 板载晶振固定 **50 MHz**；`89.2538 MHz` 是 **PDS 时序分析的估算值** |
| "实测最高工作频率 89.25 MHz" | 同上。真正的板级实测频率需要 **PLL 变体**（见第 5 节） |
| "可以把交付位流换成这一版" | 换之前必须补：实板 CoreMark（本候选是逻辑分析仪顶层，不跑 CoreMark）+ 重跑 `export_final_submission.ps1` / `audit_release_package.ps1` + 更新全部哈希登记点 |

**指南第 (2) 项"时钟频率：在满足时钟约束的前提下，处理器能达到的最高工作频率"目前的口径是**：

- **板级实测过的最高频率：80 MHz**（`fpga/logic_analyzer_80m` 与 `fpga/coremark_80m` 两个 PLL 变体，
  后者 2026-09-30 实测 CoreMark `ticks=2670014377` / 33.375 s / Score 74.905）；
- 89.25 MHz 是 **PDS 估算**，不是实测。

## 5. 要拿到"实测的更高频率"，唯一的路是 PLL 变体

`fpga/logic_analyzer_80m/rtl/mes50hp_logic_analyzer_pll_top.v` 里写明了现成的频率方案：

```text
50 MHz / IDIV 1 = PFD 50 MHz
PFD × FDIV 16 = VCO 800 MHz
VCO / ODIV0 10 = 80.000 MHz
```

**要上 85 MHz，改一个整数即可**：`FDIV 17 → VCO 850 MHz`，`ODIV0 10 → 85.000 MHz`（精确值，无小数误差）。
另外需同步：UART 分频（80 MHz 用的是 `80e6/115200 = 694`）、`.fdc` 里的时钟周期约束（12.5 ns → 11.765 ns）。

**可行性依据**：N4 扫描已证明同一份 RTL 在 11.765 ns 约束下 **All Met、WNS +0.561 ns**，
即 85 MHz 在时序预算之内。**但这需要新建工程并重跑 PDS，属于新增交付物，需用户确认后再做。**

---

*本证据由 2026-09-30 上板验证建立。数字出处索引见 `release/evidence/claims_map.md`。*
