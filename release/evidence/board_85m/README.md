# 板级实测最高工作频率：**85 MHz**（2026-09-30）

> ⚠️ **2026-09-30 后续更新：交付配置已切换。** 本文写于切换之前，文中"交付位流 = `BCAE040A…`（50 MHz）"
> 的表述**已过期**。现在的交付主位流是 **85 MHz PLL 版**（`F7DFD321…`，工程 `fpga/logic_analyzer_85m`），
> 50 MHz 版（`BCAE040A…`）改为**已验证备用位流**随包提供。
> 本文其余内容（波形、对比、上界结论）**不受影响**，因为那些结论与"哪一颗是交付位流"无关。

> 这份证据回答赛题选题一 · 四 · 1 · (2) 的那条：
> **「时钟频率：在满足时钟约束的前提下，处理器能达到的最高工作频率」**。
>
> 在此之前，材料里能拿出来的只有 **PDS 时序分析的估算值**（89.2538 MHz）和
> **板级实测过的 80 MHz**（`fpga/*_80m` PLL 变体）。现在有了 **板级实测的 85 MHz**。

## 1. 做法：PLL 变体，改一个整数

板载晶振（`P20`）固定 50 MHz，所以"板上更高频率"只能靠 **PLL 倍频**。
`fpga/coremark_80m/rtl/pll_80m.v` 里写明了现成方案，85 MHz 只需改一个整数：

| | 80 MHz（已有） | **85 MHz（本次新增）** |
|---|---|---|
| `STATIC_RATIOI`（IDIV） | 1 → PFD 50 MHz | 1 → PFD 50 MHz |
| `STATIC_RATIOF`（FDIV） | **16** → VCO 800 MHz | **17** → VCO **850 MHz** |
| `STATIC_RATIO0`（ODIV0） | 10 | 10 |
| 输出 | 80.000 MHz | **85.000 MHz（精确整数，无小数误差）** |
| `STATIC_DUTY0` | 5（50% 占空比） | 5（50% 占空比） |

VCO 850 MHz 落在 PGL50H Logos PLL 的允许范围 **600~1250 MHz** 内。
UART 分频随之改为 `85e6/115200 = 737`（实际 115332 baud，**+0.115%**，远在容差内）。

## 2. 两个位流（都是新建工程，不改任何 CPU/SoC 逻辑）

| 用途 | 工程 | 位流 SHA-256 | PDS 时序 |
|---|---|---|---|
| 逻辑分析仪 | `fpga/logic_analyzer_85m` | `F7DFD321250787B4FD71B18D85CF8F3E59309AFB3CE6383079CF4525BBA33AF8` | **All Constraints Met**；请求 85.0000 MHz / 估算 **90.0766 MHz** / slack **+0.663 ns** |
| CoreMark 计分 | `fpga/coremark_85m` | `751C692B8780E3F05BD6D86E8E0F8BA34A83AFE899E5DA86FE7474C49CA970E9` | **All Constraints Met**；请求 85.0000 MHz / 估算 **88.2637 MHz** / slack **+0.435 ns** |

PDS 自己在时序报告里把生成时钟推导为：

```
clk_50m|u_pll/u_pll_85m/CLKOUT0_Inferred   11.7647 ns   Generated (clk_50m)
  Requested Frequency: 85.0000 MHz   Estimated: 90.0766 MHz   Slack: +0.663
```

⇒ **不是"我们声称 85 MHz"，是 PDS 从 PLL 参数推导并确认了 85.0000 MHz。**

**构建命令**（可复现）：
```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_logic_analyzer_85m_pds.ps1
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File scripts\run_coremark_85m_pds.ps1
```

> ⚠️ **镜像生成有一个坑，别踩**：`generate_coremark_80m_memory.ps1` 会先把自己的镜像写进
> **`fpga/coremark/rtl/`（50 MHz 交付工程）** 再拷出去。用 `-ClockHz 85000000` 调它
> **会覆盖交付的 50 MHz CoreMark 镜像**。本次专门写了
> `scripts/generate_coremark_85m_memory.ps1`，直接把 `-OutputFile`/`-MemoryDirectory`
> 指向 `fpga/coremark_85m/rtl`，全程不碰 `fpga/coremark/rtl/`。
> 事后已核对：50 MHz 的四份镜像哈希**未变**。

## 3. 板级实测结果

### 3.1 CoreMark（85 MHz 计分位流）

板子自己打印的原始数据（`release/evidence/coremark_uart_cm85_20260930.log`）：

```text
Total ticks      : 2670014377
Total time (secs): 31
Iterations/Sec   : 80
Iterations       : 2500
CoreMark score x1000 : 79587
CoreMark/MHz x1000  : 936
crcfinal         : 0x5275
Correct operation validated.
```

| 项 | 值 |
|---|---|
| 迭代 | 2500 |
| ticks | 2,670,014,377 |
| 真实耗时 | `ticks/85e6` = **31.412 s** |
| **CoreMark 分数** | **79.587** |
| **CoreMark/MHz** | **0.936** |
| CPI | 1.510 |
| 官方 CRC | `0x5275`，**PASS** |

证据：`release/evidence/coremark_board_cm85_20260930.json`。

**三频点自洽性（这是这份证据可信的核心）**：

| 频率 | Score | CoreMark/MHz | ticks |
|---|---|---|---|
| 50 MHz | 46.816 | **0.936** | 1,068,006,999 |
| 80 MHz | 74.905 | **0.936** | 2,670,014,377 |
| **85 MHz** | **79.587** | **0.936** | 2,670,014,377 |

- `79.587 × 80/85 = **74.905**` —— 与 80 MHz 的实测值**完全相同**；
- `79.587 × 50/85 = **46.816**` —— 与 50 MHz 的实测值**完全相同**；
- 三点 `CoreMark/MHz` 都是 **0.936**（该指标与频率无关，三点一致说明口径正确）。

### 3.2 逻辑分析仪（85 MHz 位流）

`scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20`
→ **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80`**（四模式各 20/20）。

证据：`release/evidence/logic_analyzer_board_85m/`。

### 3.3 50 MHz 回归（确认改动没破坏交付配置）

用修改后的默认采集窗口在交付位流 `la50` 上重跑 → **80/80 PASS**。
证据：`release/evidence/logic_analyzer_board_recheck_20260930/`。

## 4. 过程中修掉的一个真实 bug（值得单独记）

**85 MHz 第一次跑 UART 模式时 FAIL 了**（`errors=1`）。排查结论：**不是 85 MHz 硬件问题，是测试工具的两个缺陷**：

1. **`python/logic_analyzer.py` 的 `decode_uart`**：把"窗口里第一个下降沿"当成帧起始，
   且不管 stop 位是否有效都固定前跳 10 个比特。窗口相位一偏，第一个下降沿就落在数据位内部
   ⇒ 解出 0 字节 + 记一个**假的** framing error。
   已改为：stop 位无效时只前进 1 个采样点继续找真正的起始位。
2. **`python/logic_analyzer_serial.py` 的 UART 采集窗口**：`pattern_div=433 / sample_div=26`
   ⇒ 每比特 16.65 个采样点，一帧 10 bit = **166.5 个采样点**，而 Raw 深度上限 256。
   旧窗口（`pre=16/post=220`，共 237）只给帧起始留 70.5 点余量，**恰好在 50/80 MHz 上能过、在 85 MHz 上过不了**。
   已把默认改为 `pre=64/post=191`（窗口前移），三频率都能稳定框住整帧。
   同时给 CLI 加了 `--pre/--post` 便于诊断。

**证据**：修复前 85 MHz 的波形与 50 MHz **游程结构完全相同**（`32/48/64`，都是 16 的倍数），
只是窗口整体晚了 32 个采样点 —— 硬件没问题。

## 5. 如实边界

1. **85 MHz 是板级实测的**（PLL 锁定、CPU 跑完 CoreMark 并通过官方 CRC、逻辑分析仪四模式 80/80），
   这一点比 PDS 估算值强。
2. **89.2538 MHz 仍然是 PDS 估算值**，不是实测。两者不要混写：
   - **实测最高工作频率 = 85.000 MHz**（本文件）
   - **PDS 估算 Fmax（收紧约束候选）= 89.2538 MHz**（`release/artifacts/fmax_tuning_2026-09-30/`）
3. **≥90 MHz 没有测**。PDS 对 85 MHz 的估算可达 88.26 / 90.08 MHz，但**没有**做 90 MHz 约束或 90 MHz PLL。
4. ~~交付位流没有变~~ → **已变更**：85 MHz 变体（本文件的位流）**已于同日被采纳为交付主位流**；
   50 MHz 版 `BCAE040A…` 改为已验证备用位流。89 MHz 候选仍**不是**交付入口。
5. 85 MHz 变体**只做了逻辑分析仪四模式 + CoreMark**，**没有**做 N1 定时器中断 / N2 ILA 抓 Trap
   / S1 DDR3 这些其它板级项目 —— 那些仍以 50 MHz 交付配置的证据为准。

---

*本证据由 2026-09-30 上板验证建立。数字出处索引见 `release/evidence/claims_map.md`。*
