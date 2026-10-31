# M 扩展乘法：并行部分积优化（MUL_LAT 3 → 2）

> 日期：2026-10-19　改动文件：`rtl/mdu.v`（算法主体）、`rtl/pipeline_cpu.v`（参数透传）
> 相关：`docs/rtl_changes.md` 改动 4、`docs/debug_log.md`（两个坑）、`docs/coremark_cpi_analysis.md` §8（T4 归因）
> 一句话：把乘法的"两级串联 16x32 部分积"改成"四路并联 16x16 + 窄位宽加法树"，
> 乘法在 EX 的占用从 3 拍降到 2 拍，CoreMark 周期 **−1.571%**，同时 LUT **−46**、85 MHz 时序仍 `All Constraints Met`。

---

## 1. 动机：T4 归因给出的第二个可动项

`docs/coremark_cpi_analysis.md` §8.1 把 rv32im @85 MHz 的周期拆开后，
仅次于"理想执行"和"数据口阻塞"的就是 **MDU 冻结 ≈4.5%**；
§8.4 的优先级是 `Fmax 85→90 > **MDU 去阻塞** > store 提前退休 > 非阻塞 load`
——本改动就是其中排第二的那一项，且是其中**唯一不需要碰取指/预测/提交时序**的。

改之前的实测（rv32im，一次官方迭代，RTL 仿真）：
`mdu_block = 24,307 拍 / 604,288 拍 = 4.02%`。

## 2. 算法本身

一个 32×32 乘法，不论怎么实现，最终都是四个 16×16 部分积按权重相加：

```text
a = a_hi*2^16 + a_lo        b = b_hi*2^16 + b_lo
a*b = pp00 + (pp01 + pp10)*2^16 + pp11*2^32
      pp00 = a_lo*b_lo   pp01 = a_lo*b_hi
      pp10 = a_hi*b_lo   pp11 = a_hi*b_hi
```

- **旧实现（MUL_LAT=3）**：用两级**串联**的 16×32 部分积（`a_lo*b`、`a_hi*b`），
  两级 APM 串在一条链上，所以必须多花一拍把它们分别寄存 —— 乘法挡 **2 拍**。
- **新实现（MUL_LAT=2）**：四个 16×16 做成**并联**，每路只有 1 层 APM；
  加法按 16 位分块，只用 17/33 位加法器，并把"低位进位"做成两个候选值再二选一，
  使最高位加法与最低位加法处在**同一级** —— 乘法挡 **1 拍**。
- **APM 用量不变**：4 个 16×16 = 4 个 APM，与原来两个 16×32 相同（实测都是 APM=4）。

加法结构（`mdu.v` 的 `cross_p/mid_p/hid0_p/hid1_p`）：

```text
cross  = pp01 + pp10                 （33 位）
mid    = pp00[31:16] + cross[15:0]   （17 位，mid[16] 是进位）
hid0   = pp11 + cross[32:16]         （33 位）
hid1   = hid0 + 1
全积   = {mid[16] ? hid1[31:0] : hid0[31:0], mid[15:0], pp00[15:0]}
```

有符号/无符号共四种语义仍然只需要**一个**无符号全积加两处符号修正
（`signed_hi = unsigned_hi − (a<0 ? b : 0) − (b<0 ? a : 0)`），这部分逻辑未改。

## 3. 三种配置的 Before / After

`MUL_LAT` 是 `rtl/mdu.v` 的参数（`pipeline_cpu` 用 `MDU_MUL_LAT` 透传），
三种取值都是**同一条算法、不同存储方式**，结果必须完全相同：

| MUL_LAT | 结构 | 乘法占用 EX |
|---|---|---|
| 3 | 两级串联 16×32 部分积（旧基线） | 3 拍（挡 2 拍） |
| **2** | **四路并联 16×16 + 窄位宽加法树（当前默认）** | **2 拍（挡 1 拍）** |
| 1 | 全组合，不进状态机 | 1 拍（挡 0 拍） |

### 3.1 RTL 仿真（rv32im、`-O2`、predictor on、无 Cache、官方 CoreMark 一次迭代）

| MUL_LAT | cycles | Δ cycles | mdu_block | ticks（CoreMark 窗口） | **instret** | CoreMark/MHz |
|---|---:|---:|---:|---:|---:|---:|
| 3 | 604,288 | — | 24,307 | 508,850 | **0x51327 = 333,095** | 1.965 |
| **2** | **594,792** | **−9,496（−1.571%）** | 14,810 | **499,454（−1.85%）** | **0x51327 = 333,095** | **2.002（+1.88%）** |
| 1 | 585,294 | −18,994（−3.143%） | 5,313 | 490,058（−3.69%） | **0x51327 = 333,095** | 2.040（+3.82%） |

**等价性判据（比 cycles 更重要）**：

1. **`instret` 三方逐位相同**（333,095）—— 退休指令数不变，架构不变。
2. CoreMark 输出的四行 CRC（`crclist 0xe714` / `crcmatrix 0x1fd7` / `crcstate 0x8e3a` /
   `crcfinal 0xe714`）与 `Correct operation validated.` 三方完全一致。
3. `branch / taken / flush / load` 计数三方完全相同，只有周期类计数变化。
4. `tb/tb_mdu.v` 46 项手算用例 × 三种 MUL_LAT 全 PASS；
   `tb/tb_pipeline_m_ext.v` 对单周期 Reference 的提交级 trace、`x1~x31`、RAM 三方全一致。

**收益归因**（严格对账）：`mdu_block` 三个配置是 24,307 / 14,810 / 5,313，
相邻差都恰好是 **9,497** —— 即每迭代 **9,497 条乘法**；
剩下 5,313 拍是除法（三配置相同，除法通路一行未动）。
每条乘法省 1 拍 ⇒ −9,496 拍/迭代，与实测 cycles 差值逐位对上。

### 3.2 PDS 综合/布局布线（85 MHz，同一份 RTL/约束/镜像，唯一变量 MUL_LAT）

三颗位流都在 `fpga/coremark_mul*_85m/`，**同一配方**（含 `rtl/ras.v`），
每个配置连跑 3 次，时序数字**逐位相同**（这套流程是确定性的，不是碰运气）：

| MUL_LAT | WNS | 估算 Fmax | LUT | FF | DRM | APM | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|
| 3 | +0.281 ns | 87.0800 MHz | 4185 | 3361 | 33 | 4 | All Constraints Met |
| **2** | **+0.115 ns** | **85.8391 MHz** | **4139** | **3324** | 34 | 4 | **All Constraints Met** |
| 1 | **−4.471 ns** | 61.5916 MHz | 4016 | 3257 | 33 | 4 | **Some Constraints Violated → 拒绝** |

### 3.3 ΔScore / ΔArea 判据（`docs/progress.md` 2026-10-18 定的门槛）

| 项 | 值 |
|---|---|
| ΔScore（CoreMark/MHz，仿真口径） | **+1.88%** |
| ΔLUT | **−46（−1.10%）** |
| ΔCoreMark/LUT | **≈ +3.0%** |
| ΔWNS @85 MHz | −0.166 ns（+0.281 → +0.115），仍 Met |
| 判据 `ΔScore/ΔArea > 1` | **满足**（分数涨、面积还降了） |

这是继 `-O3` 之后第二个"分数与面积同向"的改动。

## 4. 为什么 MUL_LAT=1 不可行 —— 这是一道硬墙，已实测

MUL_LAT=1 意味着乘法器直接吃"前递后的操作数"、当拍出结果。实测关键路径：

```text
core/rf/regs ──► core/mdu_unit/N14/gopapm/PO[0]        累计 12.189 ns   ← 单级 APM 从寄存器堆/前递 MUX 出发
              ──► core/mdu_unit/N8/gopapm/P[1]         累计 14.000 ns   ← PDS 用 APM 的加法入口做 cross
              ──► core/mdu_unit/mid_p_1/gateop_A2/Cout 累计 15.100 ns   ← 进位链
              ──► core/exmem_alu[*]                    累计 16.236 ns   ⇒ 85 MHz（11.7647 ns）差 4.471 ns
```

**关键数字是第一个 12.189 ns**：光是"寄存器堆 → 前递 MUX → 一级 APM"就已经超过整个 85 MHz 周期。
也就是说 85 MHz 下不存在"乘法输入直接接前递操作数"的结构，
**必须先有一拍把操作数锁进寄存器** —— 这正是旧实现 `M_IDLE` 那一拍存在的原因，
不是冗余设计。因此 MUL_LAT=1 保留为对照/证据，不进入任何配置。

> 教训：这条路径的第一版还是**两条 64 位行波进位链串联**（PDS 把 64 位三元相加实现成
> `CLMA../COUT × N`），WNS −2.947 ns；改成 17/33 位窄加法器后降到 −4.471 ns 的原因不同
> —— 此时瓶颈已经从"加法树"转移到"rf → APM"这一段本身。详见 `docs/debug_log.md`。

## 5. 板级实测（2026-10-19，MES50HP / COM11 / 85 MHz PLL）

**已上板**：把两颗位流分别下载后跑官方 CoreMark 4000 迭代（≥10 s 要求满足），
Before/After 是**同一套源文件、同一个频点、同一份程序镜像**，唯一变量就是 `MUL_LAT`。

| 项 | MUL_LAT=3（基线位流） | **MUL_LAT=2（改后位流）** | 变化 |
|---|---:|---:|---:|
| **总 ticks** | 1,759,901,953 | **1,722,317,953** | **−37,584,000（−2.135%）** |
| **每迭代 ticks** | 439,975.5 | **430,579.5** | **−9,396** |
| **CoreMark 分数** | 193.192 | **197.408** | **+4.216（+2.183%）** |
| **CoreMark/MHz** | 2.272 | **2.322** | **+2.20%** |
| 耗时 | 20.704 s | **20.262 s** | −0.442 s |
| 官方 CRC（`crcfinal`） | 0x65c5 | **0x65c5** | 相同 |
| `flush_count` | 43,406,274 | 43,406,274 | **逐位相同** |
| 位流 SHA-256 | `C7C41A33…DF11DF1E` | `18F35C77…62949FEF` | — |
| 证据 | `release/evidence/coremark_board_mul3_85m_20261019.json` | `release/evidence/coremark_board_mul2_85m_20261019.json` | — |
| 串口原始日志 | `release/evidence/coremark_uart_mul3_85m_20261019.log` | `release/evidence/coremark_uart_mul2_85m_20261019.log` | — |

**两个决定性的自洽点**：

1. **基线位流复现了归档值**：`ticks = 1,759,901,953` 与 2026-10-14 归档的 `cmim85`
   （`coremark_board_cmim85_20261014.json`）**逐位相同** ⇒ 当前源码树（含 `ras.v` 入配方但
   `ENABLE_RAS=0`）没有改变基线行为。
2. **仿真与实板的收益逐拍吻合**：仿真 CoreMark 窗口 ticks 508,850 → 499,454，
   差 **9,396** 拍/迭代；实板 (1,759,901,953 − 1,722,317,953) ÷ 4000 = **9,396** 拍/迭代。
   两者**完全相同**，说明省的这 9,396 拍确实全部来自乘法（每迭代 9,497 条乘法中的 9,396 条
   落在计时窗口内，其余在窗口外）。

> ⚠️ **口径纪律**：这两次采集用的是默认 `PERF_WINDOW_ALIGN=0` 的镜像，性能计数器**自由运行**，
> 因此 PERF 行里的 `cycle / instret / stall / branch` 含启动与等待 `R` 的轮询，**两次采集不可比**
> （mul3 的 `instret` 明显偏大就是这个原因），`cpi_x1000` 也随之失真。
> 可引用的只有 `ticks / Score / CoreMark/MHz / CRC / flush`（`flush` 在两次采集中逐位相同，
> 因为轮询循环不产生误预测冲刷）。要做 CPI 归因必须换 `PERF_WINDOW_ALIGN=1` 的镜像（见
> `docs/coremark_cpi_analysis.md` §4.1）。

**上板后已恢复交付位流** `la85`（`C017ED10195502…3FAA4F`，与 `claims_map` §1 一致）。

## 6. 复现命令

```powershell
# 模块自测（三种 MUL_LAT × 46 项手算）
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_mdu_tb.ps1 -MulLat 3
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_mdu_tb.ps1 -MulLat 2
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_mdu_tb.ps1 -MulLat 1

# 流水线 vs 单周期 Reference（trace / x1~x31 / RAM）
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_pipeline_m_ext_tb.ps1 -MulLat 2

# CoreMark 仿真 Before/After
$env:MDU_MUL_LAT=3; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_coremark_pipeline_tb.ps1 -March rv32im
$env:MDU_MUL_LAT=2; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_coremark_pipeline_tb.ps1 -March rv32im

# PDS 位流（三个对照工程，互不覆盖）
cd fpga\coremark_mul2_85m
$env:PANGO_LICENSE_FILE='D:\Downloads\new_pds_60452e195a32.lic'
D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe -file pds_recipe.tcl -project_name coremark_mul2_85m_generated
```

三个实验工程：

| 工程 | MUL_LAT | 用途 |
|---|---:|---|
| `fpga/coremark_mul3_85m/` | 3 | **同配方**重建的基线（Before） |
| `fpga/coremark_mul2_85m/` | 2 | 当前默认配置的位流（After，已过时序、**未上板**） |
| `fpga/coremark_mul1_85m/` | 1 | 违例证据（记录 Fmax 硬墙） |

> ⚠️ 三个工程都由 `fpga/coremark_im_85m` 复制而来，并在配方里补了 `rtl/ras.v`
> （归档配方缺这一行，直接重建会报 `Verilog-4072: 'ras' is referenced to undefined module`）。
> 因此**基线数字只能引用 `coremark_mul3_85m` 这次同配方重建的结果**，
> 不得引用归档 `coremark_im_85m` 的 4198 LUT / +0.250 ns（那是另一套源文件集）。
