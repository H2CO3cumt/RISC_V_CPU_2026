# 性能调优与频率-性能-资源数据（T0～T6）

> 最后更新：2026-09-17
> 权威命令：`scripts/run_fmax_sweep_rtl.ps1`（频率扫描）、`scripts/run_final_regression.ps1 -Quick`（回归）、
> `python/fmax_report.py` / `python/pds_paths.py` / `python/coremark_cpi_analysis.py`（数据提取）。
> 所有数字都注明来源阶段（RTL 仿真 / PDS 综合 / PDS 布局布线 / 实体板），不同阶段不得混用。

## 0. 结论速览

| 问题 | 结论 |
|---|---|
| 是否达到 70 MHz？ | **达到**。优化前后两版 RTL 在 70 MHz 约束下均 `All Constraints Met`，见 §2。 |
| 是否达到 80–85 MHz？ | **达到**。优化前最高 85.0 MHz（WNS +0.005 ns），优化后在 85 MHz 有 WNS +0.246 ns、在 80 MHz 有 WNS +0.145 ns；两版都在 90 MHz 约束下失败。 |
| 真实天花板在哪？ | 约 **89～90 MHz**（按 WNS 外推：优化前 1/(11.111−0.059) = 90.5 MHz，优化后 1/(11.111−0.148) = 89.7 MHz）。两版天花板相同，因为限制路径是流水线本体的寄存器堆→ALU→预测校验链，不是性能计数器。 |
| 提频率能不能提 Score？ | **不能**。`Score = Iterations/(Total_Time × Frequency)`，与 `CoreMark/MHz` 等价，是频率归一化的；提频率只服务于独立的「时钟频率」计分项。 |
| 本轮 RTL 改动的收益 | `rtl/perf_monitor.v` 事件打一拍：在 85 MHz 把 WNS 从 +0.005 ns 提到 **+0.246 ns**，让 85 MHz 从"零余量"变成"可用"；在 50 MHz 从 +1.805 到 +1.693（±0.1 ns 属布局波动）。CPI/CoreMark 不变（该改动不影响架构行为）。 |
| 下一步性价比最高的方向 | 数据事务握手流水化（把 `dstate` 的 REQ→RSP 两拍压成一拍），估计 CPI 可降约 0.4（约 −17%），但需要改动流水线访存时序，风险高于本轮改动；详见 `docs/coremark_cpi_analysis.md`。 |

## 1. 基准口径与可比性元数据

| 项 | 值 |
|---|---|
| 源码 git commit | `fd5bb75ec2d33f67bdf06f0a2a1fed23d25c1896`（本轮 RTL 改动未提交，改动内容见 `docs/rtl_changes.md`） |
| 优化前 `rtl/perf_monitor.v` SHA-256 | `9F5E0A06769DA0125C7CAC9DFD263038E480D2AAEC61298D088771F5662B25DC`（= git HEAD 内容） |
| 优化后 `rtl/perf_monitor.v` SHA-256 | `B9A41F8D23956422C531CA08C3C68F963635F40AD3441AE02C9B1A49346794FF` |
| 其余 24 个 `rtl/*.v` | 两版完全相同（扫描脚本逐文件比对 SHA-256 一致） |
| `fpga/task28_coremark/constraints/mes50hp_coremark.fdc` SHA-256 | `F535FD2475D77304AEA1BE7148E16AF5790089B15AAB446E08C6864C2E8BBB58`（优化前后共用，只改 `-period`） |
| 频率扫描 RTL 快照 | `tmp/fmax_sweep/before_rtl/`（优化前）、`tmp/fmax_sweep/after_rtl/`（优化后），各自附 `*_rtl_sha256.txt` |
| 器件/工具 | PGL50H-6IFBG484，PDS 2024.2-SP2-EN build 208883 |
| 固定流程 | `compile → synthesize(ads,opt2) → dev_map → place(-optimize_multi_corner_timing) → route → route_optimize(-fix_hold_violation) → report_timing → gen_bit_stream` |

> **可比性说明**：每次扫描都用**独立的隔离工程目录**（`tmp/fmax_sweep/<tag>_proj/f<freq>/`），
> 通过相对路径 `../../<tag>_rtl` 引用该 tag 专属的 RTL 快照，`clean -all` 从零重建，
> 因此不同频率点、不同 tag 之间不共享任何布局布线中间产物。

## 2. T0/T4：频率扫描完整数据

### 2.1 优化前（Before，git HEAD 的 `perf_monitor.v`）

命令：

```powershell
& '<pwsh7>' -NoProfile -File scripts\run_fmax_sweep_rtl.ps1 -Tag before `
  -Periods '20.000,14.286,12.500,11.765,11.111' `
  -RtlSource 'D:\RISC_V_CPU_2026\tmp\fmax_sweep\baseline_src'
```

| 目标 MHz | 约束周期(ns) | All Met | setup WNS(ns) | TNS | 失败端点 | hold WHS(ns) | THS | 估算 Fmax(MHz) | LUT | FF | DRM18K | 最差路径终点 | 逻辑级数 |
|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
| 50.000 | 20.000 | MET | +1.805 | 0.000 | 0 | +0.276 | 0.000 | 54.9602 | 2707 | 2577 | 33.0 | `perf/flush_count[62]/CE` | 26 |
| 70.000 | 14.286 | MET | +1.058 | 0.000 | 0 | +0.317 | 0.000 | 75.5972 | 2851 | 2577 | 33.0 | `perf/flush_count[18]/CE` | 15 |
| 80.000 | 12.500 | MET | +0.588 | 0.000 | 0 | +0.311 | 0.000 | 83.9490 | 2929 | 2577 | 33.0 | `core/ifid_pc[6]/CE` | 11 |
| 85.000 | 11.765 | MET | **+0.005** | 0.000 | 0 | +0.317 | 0.000 | 85.0340 | 2922 | 2577 | 33.0 | `core/ifid_inst[5]/RS` | 13 |
| 90.000 | 11.111 | **VIOLATED** | **−0.059** | −0.268 | 18 | +0.302 | 0.000 | 89.5255 | 2924 | 2577 | 33.0 | `core/ifid_pc[1]/CE` | 14 |

### 2.2 优化后（After，事件打一拍的 `perf_monitor.v`）

| 目标 MHz | 约束周期(ns) | All Met | setup WNS(ns) | TNS | 失败端点 | hold WHS(ns) | THS | 估算 Fmax(MHz) | LUT | FF | DRM18K | 最差路径终点 | 逻辑级数 |
|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
| 50.000 | 20.000 | MET | +1.693 | 0.000 | 0 | +0.314 | 0.000 | 54.6239 | 2709 | 2585 | 33.0 | `core/fetch_pc[28]/CE` | 21 |
| 70.000 | 14.286 | MET | +1.035 | 0.000 | 0 | +0.319 | 0.000 | 75.4660 | 2823 | 2585 | 33.0 | `core/if_req_addr_reg[30]/CE` | 15 |
| 80.000 | 12.500 | MET | +0.145 | 0.000 | 0 | +0.312 | 0.000 | 80.9389 | 2913 | 2585 | 33.0 | `core/if_req_pred_target[8]/CE` | 12 |
| 85.000 | 11.765 | MET | **+0.246** | 0.000 | 0 | +0.316 | 0.000 | 86.8131 | 2924 | 2585 | 33.0 | `core/if_req_addr_reg[1]/CE` | 11 |
| 90.000 | 11.111 | **VIOLATED** | **−0.148** | −6.634 | 113 | +0.340 | 0.000 | 88.8178 | 2921 | 2585 | 33.0 | `core/idex_pred_target[19]/CE` | 11 |
| 100.000 | 10.000 | VIOLATED | −1.441 | −434.608 | 467 | +0.312 | 0.000 | 87.4049 | 2920 | 2585 | 33.0 | `core/ifid_inst[3]/RS` | 12 |
| 110.000 | 9.091 | VIOLATED | −2.382 | −821.139 | 486 | +0.317 | 0.000 | 87.1612 | 2965 | 2585 | 33.0 | `core/ifid_inst[3]/RS` | 12 |

### 2.3 三个必须讲清楚的点

1. **"估算 Fmax"不是天花板，只是"约束下反推值"。**
   PDS 在**满足给定约束**的前提下布线，然后反推 `Estimated Frequency`。约束松（20 ns）时工具没有动力压路径，
   所以 50 MHz 约束下报 54.96 MHz；把约束收紧到 85 MHz，同一份 RTL 报 85.03 MHz。
   **因此绝对不能用 50 MHz 约束下的估算 Fmax（57.67 / 54.96 MHz 之类）去宣称芯片上限。**
2. **两版 RTL 的真实天花板相同，约 89～90 MHz。**
   优化前 90 MHz 失败（WNS −0.059，18 个失败端点），优化后 90 MHz 也失败（WNS −0.148）。
   两版的 `All Constraints Met` 上界都在 85～90 MHz 之间，最差路径终点是
   `core/rf/regs/iGopDrm` →（ALU / 预测目标比较）→ `core/*_pc` / `core/*_pred_target`，
   属于流水线本体，不是性能计数器。
3. **优化改动的实际作用域**：把 `perf/flush_count` 从最差路径列表里**彻底移除**——
   50 MHz 约束下 Before 最差 10 条中有 8 条终点是 `perf/flush_count`（26 级逻辑，arrival 22.789 ns），
   After 最差 10 条中 `perf` 终点为 **0 条**，最差路径变成 `core/fetch_pc`（21 级，arrival 22.901 ns）。
   净效果是在 85 MHz 把 WNS 从 +0.005 ns 提到 +0.246 ns，把"零余量"变成"可用余量"。

### 2.4 频率-性能-资源总表（当前状态）

| 版本 | 目标频率 | All Met | WNS(ns) | WHS(ns) | LUT(综合) | FF(综合) | DRM18K | CoreMark | Score(CoreMark/MHz×1000) | CPI | CoreMark/LUT |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 基线 50 MHz（Before） | 50 MHz | MET | +1.805 | +0.276 | 2707 | 2577 | 33.0 | 29.559 | 591 | 2.2719 | 0.01092 |
| 基线 85 MHz（Before） | 85 MHz | MET | +0.005 | +0.317 | 2922 | 2577 | 33.0 | 未上板 | 591（预期不变） | 2.2719（预期不变） | 0.01080 |
| 优化 50 MHz（After，正式工程已重建） | 50 MHz | MET | +1.693 | +0.314 | 2709 | 2585 | 33.0 | 待实体板复测 | 591（预期不变） | 2.2719（预期不变） | 0.01089 |
| 优化 80 MHz + PLL（After） | 80 MHz | MET | +0.721 | +0.312 | 3003 | 2593 | 33.0 | 待实体板复测 | 591（预期不变） | 2.2719（预期不变） | 0.00984 |
| 优化 85 MHz（After） | 85 MHz | MET | +0.246 | +0.316 | 2924 | 2585 | 33.0 | 未上板 | — | — | — |
| 逻辑分析仪 50 MHz（After，正式工程已重建） | 50 MHz | MET | +2.257 | +0.319 | 3458 | 3137 | 5.5 | 不适用 | 不适用 | 不适用 | 不适用 |
| 逻辑分析仪 80 MHz + PLL（After） | 80 MHz | MET | +0.652 | +0.312 | 3781 | 3143 | 5.5 | 不适用 | 不适用 | 不适用 | 不适用 |

说明：
- LUT/FF 都是**综合统计**（`synthesize/run.log` 的 `Total LUTs` / `Total Registers`），DRM 为 `Total DRM18Ks`；布局布线后的实现数另存，两者不混用。
- CoreMark 分数的实测值 `29.559` / CPI `2.2719` 来自 50 MHz 基线实体板（`release/evidence/coremark_board.json`）；本轮 RTL 改动不改变架构行为，因此 Score/CPI 预期不变，**但 After 的实体板复测因 JTAG 下载线未连接尚未完成**（见 §5）。
- `CoreMark/LUT` 用 Score ÷ 综合 LUT 计算。

## 3. T2：关键路径批量提取

命令：

```powershell
D:\Python313\python.exe python\pds_paths.py --report <报告.rtr> --top 10 --out <输出.md>
```

### 3.1 优化前 50 MHz 约束（`fpga/task28_coremark/report_timing/*.rtr`，26 级，WNS +1.805）

| # | 起点 | 终点 | 逻辑级数 | 逻辑(ns/%) | 走线(ns) | slack(ns) | 归属 |
|---:|---|---|---:|---:|---:|---:|---|
| 1 | `core/rf/regs/iGopDrm/CLKB` | `perf/flush_count[62]/opit_0_A2Q21/CE` | 26 | 8.381/48.6% | 8.858 | +1.805 | **perf** |
| 2 | 同上 | `perf/flush_count[63]/opit_0_AQ_perm/CE` | 26 | 8.381/48.6% | 8.858 | +1.805 | **perf** |
| 3 | 同上 | `perf/flush_count[58]/opit_0_A2Q21/CE` | 25 | 8.197/48.1% | 8.858 | +1.989 | **perf** |
| 4–8 | `gpio_out_reg[*]` / `uart0_rx` | `perf/flush_count[62]/CE` | 26 | 6.482/53.6% | 5.622 | +7.141 | **perf** |
| 9 | `por_count[4]` | `uart/u_uart_rx/rx_r1/LRS` | 2 | 0.928/15.8% | 4.930 | +13.721 | uart |
| 10 | `por_count[4]` | `uart/u_uart_tx/cnt_baud[14]/RS` | 9 | 1.957/51.8% | 1.818 | +15.557 | uart |

**最差 10 条中有 8 条终点在 `perf/`，前 3 名全部是 `perf/flush_count`。** 该路径的构成（来自报告逐级明细）：

```
core/rf/regs/iGopDrm tco 2.286
  → 转发/操作数选择 (core/idex_a → srca0 → ex_a, fanout=13)
  → core/exalu 加法链
  → core/ex_result (fanout=18)
  → core/N161.eq_0..eq_14  （16 级进位链做 32-bit 相等比较）
  → core/N164 → perf_mispredict (fanout=7)
  → core/N172 → perf_flush (fanout=46)
  → perf/flush_count[24..60] （10 级 CECO 进位链，1.84 ns）
```

### 3.2 优化后 50 MHz 约束（21 级，WNS +1.693）

| # | 起点 | 终点 | 逻辑级数 | 逻辑(ns/%) | 走线(ns) | slack(ns) | 归属 |
|---:|---|---|---:|---:|---:|---:|---|
| 1–3 | `core/rf/regs/iGopDrm/CLKB` | `core/fetch_pc[28,29,22]/opit_0_L5Q_perm/CE` | 21 | 7.866/45.0% | 9.608 | +1.693 | core |
| 4–8 | `gpio_out_reg[*]` / `uart0_rx` | `core/fetch_pc[28]/CE` | 21 | 6.025/48.7% | 6.342 | +6.988 | core |
| 9 | `por_count[2]` | `uart/u_uart_rx/rx_r1/LRS` | 2 | 0.966/24.7% | 2.942 | +15.794 | uart |
| 10 | `por_count[2]` | `uart/u_uart_tx/cnt_baud[14]/RS` | 5 | 1.407/43.7% | 1.814 | +16.131 | uart |

**`perf/` 终点从 8 条降到 0 条；逻辑级数从 26 降到 21；逻辑延迟从 8.381 ns 降到 7.866 ns。**

### 3.3 优化后 85 MHz 约束（WNS +0.246，最差路径）

```
core/rf/regs/iGopDrm/CLKB  →  core/if_req_addr_reg[1]/opit_0/CE
11 级逻辑, arrival 16.243 ns, 逻辑 5.547 ns (51.3%) / 走线 5.269 ns
```

### 3.4 优化后 90 MHz 约束（WNS −0.148，首个失败点）

```
core/rf/regs/iGopDrm/CLKB  →  core/idex_pred_target[19]/opit_0/CE
11 级逻辑, arrival 15.983 ns, 逻辑 5.723 ns (54.2%) / 走线 4.833 ns
```

**还差多少**：90 MHz 周期 11.111 ns，最差路径需要 11.111+0.148 = 11.259 ns，即**还需要再砍 0.148 ns**才能让 90 MHz 通过；
按当前实现 89.7 MHz 是上限。要真正上 100 MHz 需要 10 ns 周期，最差路径要从 15.983 ns 砍到 10 ns 以下，
**必须动流水线本体（寄存器堆→ALU 段再分级），不是计数器级优化能解决的**。

### 3.5 hold 路径

| 版本/频率 | 最差 hold 路径 | 逻辑级数 | WHS(ns) | THS |
|---|---|---:|---:|---:|
| 优化前 50 MHz | `core/ifid_pc[0]` → `core/idex_pc[0]` | 0（纯走线） | +0.276 | 0.000 |
| 优化后 50 MHz | `core/ifid_pred_target[15]` → `core/idex_pred_target[15]` | 0 | +0.314 | 0.000 |
| 优化后 85 MHz | `core/ifid_pred_target[*]` → `core/idex_pred_target[*]` | 0 | +0.316 | 0.000 |
| 优化后 90 MHz | — | — | +0.340 | 0.000 |

hold 在所有频率点都为正且 THS=0，**没有为 hold 做任何妥协**（`route_optimize -fix_hold_violation` 已在内）。

## 4. T1：CPI 分解与瓶颈归因（摘要）

完整内容见 `docs/coremark_cpi_analysis.md`。以 RTL 仿真（官方 CoreMark，Predictor On，同一镜像同一窗口）为准：

| 损失来源 | CPI 贡献 | 占 cycles | 可行动性 |
|---|---:|---:|---|
| 理想执行（retired × 1） | 1.0000 | 42.11% | 不可压缩 |
| Hazard stall | 0.2259 | 9.51% | 其中 load-use 仅 19,791（占 stall 11.23%），其余是访存阻塞 |
| 控制冒险 flush（81,523 次 × 2 拍） | 0.2090 | 8.80% | BTB 已把 mispredict 从 131,903 降到 51,908 |
| **访存事务等待** | **0.9398** | **39.57%** | **最大单项**；数据访问固定多 2 拍握手 |
| 合计 | 2.3747 | 100% | — |

**可行动结论**：访存相关（stall + 事务等待）合计约 **48% 的周期、1.14 CPI**。
把数据事务的 `dstate` REQ→RSP 两拍握手压成一拍（请求当拍即可应答，因为 `d_req_ready` 恒为可接收）
估计可回收约一半，即 **CPI 约 −0.4（约 −17%）**——这是当前 Score 提升空间最大的单项。
它需要改动 `pipeline_cpu.v` 的访存时序与对应 hazard 语义，风险显著高于本轮的计数器打拍，
因此本轮**不做**，作为下一轮明确建议。

板级口径提醒：`cycle_count / instret_count`（2.2719）**不能**当 CoreMark 内核 CPI ——
`ticks` 只覆盖 CoreMark 计时窗口，而 `cycle_count` 覆盖上电至今，两者相差 387,117,152 周期（18.6%），
其中包含启动代码、首次内存初始化和 `COREMARK_READY` 串口等待。

## 5. T5：高频实体板验证（PLL）

### 5.1 PLL 方案

P20 是 50 MHz 固定晶振，>50 MHz 必须倍频。PGL50H（Logos）PLL 约束：IDIV/FDIV/ODIV 为整数，
PFD 5～320 MHz，VCO 600～1250 MHz，输出 ≤625 MHz。因此**无法精确产生 85/90 MHz**，
但**可以精确产生 80 MHz 和 70 MHz**：

| 目标 | IDIV | FDIV | ODIV0 | PFD | VCO | 实际输出 |
|---|---:|---:|---:|---:|---:|---:|
| 80 MHz | 1 | 16 | 10 | 50 MHz | 800 MHz | **80.000 MHz**（DUTY0=5 → 50%） |
| 70 MHz | 1 | 14 | 10 | 50 MHz | 700 MHz | 70.000 MHz |

实施：
- `fpga/task28_coremark_80m/rtl/pll_80m.v`：直接例化原语 `GTP_PLL_E3`（与 PDS 自带例子 `PGL25G_lvds4to1/ip/pll_tx` 同源），
  **不引入外部 IP 文件依赖**，配方只依赖仓库内源码。PLL 完全位于 Core 之外（board wrapper 层）。
- `fpga/task28_coremark_80m/rtl/mes50hp_coremark_pll_top.v`：CoreMark 80 MHz 顶层，逻辑与 50 MHz 版一致，只换时钟与波特率常数。
- `fpga/task30_logic_analyzer_80m/rtl/mes50hp_logic_analyzer_pll_top.v`：逻辑分析仪 80 MHz 顶层，内部例化**未修改**的
  `mes50hp_logic_analyzer_top`，只把 `clk_50m` 端口接 80 MHz 并传入 `UART_BAUD_CYCLES`。
- 复位：先等 `pll_locked`，再用 POR 计数器释放；`USE_EXTERNAL_RESET=0` 的内部上电复位契约保持不变。
- **UART 波特率重算**：80e6/115200 = 694.44 → 取 694 → 实际 115274 baud（−0.064%，在 UART 容差内）；
  70 MHz 时为 607 → 115238 baud。

### 5.2 80 MHz PLL 设计时序与资源（PDS 布局布线，`All Constraints Met`）

| 设计 | 顶层 | 输入时钟约束 | PLL 输出（工具推断） | setup WNS | hold WHS | 失败端点 | LUT | FF | DRM18K | bitstream SHA-256 |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---|
| CoreMark 80 MHz | `mes50hp_coremark_pll_top` | 20.000 ns | `clk_50m\|u_pll/u_pll_80m/CLKOUT0_Inferred` 12.5000 ns | **+0.721** | +0.312 | 0 | 3003 | 2593 | 33.0 | `3BF90440BDC9D2AB463B5D9E389107F846FB1A1A2972D81E03DA9070CC23948F` |
| 逻辑分析仪 80 MHz | `mes50hp_logic_analyzer_pll_top` | 20.000 ns | 同上 | **+0.652** | +0.312 | 0 | 3781 | 3143 | 5.5 | `261D3989AC2D3EC686B9C740B42E988A96175B8534BE5F494D66573A1A54D898` |

工具把 PLL 输出识别为生成时钟 `...CLKOUT0_Inferred`，周期 12.5000 ns = 80 MHz，与设计意图一致；
输入时钟端口只有 1 个负载（PLL），CPU/SoC 全部在 80 MHz 域。

### 5.3 RTL 级验证（已完成）

`scripts/run_task30_pll80_board_top_tb.ps1`（Icarus，`tb/pll_80m_model.v` 提供 `GTP_PLL_E3` 行为模型）：

```
PLL80 LOCK PASS
PLL80 FREQ PASS period_ps=12400 freq=80.6452 MHz
PLL80 UART PASS bytes=13
PLL80 CAPTURE PASS count=9
ALL TASK30 PLL80 BOARD TOP TEST PASS
```

覆盖：PLL 锁定握手与输出频点、80 MHz 域 UART 分频 694 无帧错误、板级固件 `LA_READY` 前缀、
Capture Engine 在 80 MHz 下 `pre/trigger/post` 精确计数（count=9、trigger_index=4）、GPIO=0x5A、回环=0x01。

### 5.4 实体板验证状态：**未完成（阻塞）**

**阻塞原因**：本轮执行期间，开发板的 Pango JTAG 下载线未连接到本机。
设备枚举只有 CP2102 UART 桥：

```
Silicon Labs CP210x USB to UART Bridge (COM11)   USB\VID_10C4&PID_EA60\0001
```

没有 Pango 下载器（`cdt_js`/`cdt_cfg` 连接后 `cfg_scan_chain` 无响应、超时）。
因此以下两项**无法完成，也不在本文件中宣称**：

- 优化后 50 MHz / 80 MHz 位流的实体板下载与 CoreMark 复测；
- PLL 在实体板上的锁定、80 MHz 稳定性与 UART 实际波特率验证。

**恢复验证的步骤**（接上下载线后）：

```powershell
# 1) 启动 JTAG 服务（若未运行）
Start-Process 'D:\Pango\PDS_2024.2-SP2\bin\cdt_js.exe' -ArgumentList '-work_dir','D:\RISC_V_CPU_2026\tmp','-port','65420'
# 2) 下载 80 MHz CoreMark 位流
D:\Pango\PDS_2024.2-SP2\bin\cdt_cfg.exe -file D:\RISC_V_CPU_2026\tmp\program_coremark_80m.tcl -work_dir D:\RISC_V_CPU_2026\tmp
# 3) 采集（注意 --clock-hz 必须与位流时钟一致）
D:\Python313\python.exe python\coremark_serial.py COM11 --clock-hz 80000000 `
  --output release\evidence\coremark_uart_80m.log --summary release\evidence\coremark_board_80m.json
```

验收判据：官方四个 CRC 全过 + `Correct operation validated.` + 运行 ≥10 秒 + `All Constraints Met`。

## 6. 频率点必录数据清单（本文件覆盖情况）

| 项 | 覆盖情况 |
|---|---|
| A 时序闭合（周期/WNS/TNS/失败端点/WHS/THS/All Met/估算 Fmax/报告路径） | ✅ §2，报告在 `tmp/fmax_sweep/<tag>_proj/f*/report_timing/` |
| B 资源（LUT/FF/DRM18K，注明综合阶段） | ✅ §2、§2.4（均为综合统计） |
| C CoreMark 实测（score/ticks/iterations/秒数/CPI/四 CRC/七计数器） | ⚠ 仅 50 MHz 基线有实体数据（`release/evidence/coremark_board.json`）；After 待复测 |
| D 关键路径（起点/终点/逻辑级数/逻辑与走线占比） | ✅ §3 |
| E 可比性元数据（commit/FDC 哈希/bitstream SHA-256/镜像一致性） | ✅ §1、§5.2 |

## 7. 桌面入口最终状态（收尾交付 10.1）

所有编号快捷方式都已用脚本创建/刷新，并逐个 `Test-Path` 校验目标存在。

| 桌面入口 | 目标 | 状态 |
|---|---|---|
| `1_FPGA工程_最新.lnk` | `fpga\task30_logic_analyzer\task30_generated.pds`（**优化后 RTL 重建**，WNS +2.257 ns） | 已刷新，目标存在 |
| `2_最终位流_下载用.lnk` | `release\artifacts\fmax_tuning_2026-09-17\la_50m_optimized.sbit`（逻辑分析仪 50 MHz 优化版） | **已替换**，目标存在 |
| `3_逻辑分析仪上位机.lnk` | `release\final_submission\启动逻辑分析仪.cmd` | 路径不变，保留 |
| `4_逻辑分析仪使用说明.lnk` | `docs\logic_analyzer_quick_start.md` | 路径不变，保留 |
| `5_采集波形_80组VCD.lnk` | `release\evidence\logic_analyzer_board_final` | 路径不变，保留 |
| `6_最终交付包.lnk` | `release\final_submission` | 路径不变，保留（见下方说明） |
| `7_项目仓库.lnk` | `D:\RISC_V_CPU_2026` | 路径不变，保留 |
| `8_测CoreMark分数.cmd` | 自动找 CP210x 串口并采集 50 MHz CoreMark | **保留且仍可用**（未改动该文件，避免破坏其 GBK 编码） |
| `11_新会话指令.md.lnk` | `docs\next_session_instruction.md` | 路径不变，保留 |
| `12_性能调优记录.lnk` | `docs\performance_tuning.md` | **新增**，目标存在 |
| `13_RTL变更说明.lnk` | `docs\rtl_changes.md` | **新增**，目标存在 |
| `14_CoreMark_80MHz_PLL位流.lnk` | `release\artifacts\fmax_tuning_2026-09-17\coremark_80m_pll.sbit` | **新增**，目标存在（待实体验证） |
| `15_逻辑分析仪_80MHz_PLL位流.lnk` | `release\artifacts\fmax_tuning_2026-09-17\la_80m_pll.sbit` | **新增**，目标存在（待实体验证） |
| `16_测CoreMark_80MHz.cmd` | `python\coremark_serial.py <PORT> --clock-hz 80000000` | **新增** |

桌面散落的 CoreMark 位流：

| 文件 | SHA-256（前 16 位） | 说明 |
|---|---|---|
| `coremark_baseline_50m.sbit` | `92638DAF8C73F632` | **旧 `coremark_btb.sbit` 已按要求改名存档**（50 MHz 基线；全 64 位 `92638DAF8C73F63214CB1C42DEBC17B8E4B7E4FAF42C1C132084F022EDABF5A7`） |
| `coremark_optimized_50m.sbit` | `9F42B8F9720D7047` | 优化后 50 MHz 位流（WNS +1.693 ns） |
| `coremark_pll_80m.sbit` | `3BF90440BDC9D2AB` | 80 MHz PLL 位流（WNS +0.721 ns，待实体验证） |

**关于 `6_最终交付包.lnk`（重要，未静默处理）**：`release/final_submission` 顶层的位流与 `SHA256SUMS.txt`
仍是**调优前**版本（`2C09E690…`），清单因此保持自洽。本轮调优后的位流以**并存的新交付物**形式归档在
`release/artifacts/fmax_tuning_2026-09-17/`（同时保留调优前位流的存档副本 `la_50m_pre_tuning_ARCHIVE.sbit`），
**没有静默改写发布清单**。把调优后位流提升为正式发布版本必须按顺序执行（且必须用 pwsh 7）：

```powershell
& '<pwsh7>' -NoProfile -File scripts\export_final_submission.ps1
& '<pwsh7>' -NoProfile -File scripts\create_release_manifest.ps1
& '<pwsh7>' -NoProfile -File scripts\audit_release_package.ps1
```

## 8. 复现步骤

```powershell
# 频率扫描（隔离目录，不污染正式产物）
& '<pwsh7>' -NoProfile -File scripts\run_fmax_sweep_rtl.ps1 -Tag after `
  -Periods '20.000,14.286,12.500,11.765,11.111,10.000,9.091' `
  -RtlSource 'D:\RISC_V_CPU_2026\rtl'
D:\Python313\python.exe python\fmax_report.py --tag after --out tmp\fmax_after.md

# 后仿/回归（每次 RTL 改动后必须跑）
& '<pwsh7>' -NoProfile -File scripts\run_final_regression.ps1 -Quick

# 80 MHz PLL 顶层 RTL 闭环
& '<pwsh7>' -NoProfile -File scripts\run_task30_pll80_board_top_tb.ps1

# 80 MHz 位流构建
& '<pwsh7>' -NoProfile -Command "cd fpga\task28_coremark_80m; & 'D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe' -file pds_recipe.tcl -project_name coremark_80m"
& '<pwsh7>' -NoProfile -Command "cd fpga\task30_logic_analyzer_80m; & 'D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe' -file pds_recipe.tcl -project_name la80m"

# 从已有扫描目录重新提取时序汇总（无需重跑 PDS）
D:\Python313\python.exe python\fmax_summary.py --proj-root tmp/fmax_sweep/after_proj --tag after
D:\Python313\python.exe python\fmax_summary.py --proj-root tmp/fmax_sweep/before_proj --tag before
```

## 9. 最终回答（必答项）

**是否达到 70 MHz？** 达到。优化前后两版 RTL 在 70 MHz 约束下均为 `All Constraints Met`、0 失败端点
（优化前 WNS +1.058 ns，优化后 +1.035 ns）。

**是否达到 80–85 MHz？** 达到。
- 80 MHz：优化前 WNS +0.588 ns，优化后 +0.145 ns；并有精确 80.000 MHz 的 PLL 工程，
  CoreMark 配置 WNS +0.721 ns、逻辑分析仪配置 WNS +0.652 ns，均 `All Constraints Met`、0 失败端点。
- 85 MHz：优化前 WNS **+0.005 ns**（零余量，能过但不可用），优化后 **+0.246 ns**。
- 90 MHz 起失败（优化前 WNS −0.059 ns / 18 失败端点；优化后 −0.148 ns / 113 失败端点）。

**若未达到更高频率，卡在哪条路径、还差多少 ns？**
卡在流水线本体的**寄存器堆读出 → 转发/操作数选择 → ALU → 分支预测目标比较 → 写回 `core/*_pc` / `core/*_pred_target`** 这一段：

| 频率 | 最差路径 | 逻辑级数 | arrival | 逻辑/走线占比 | slack |
|---:|---|---:|---:|---|---:|
| 85 MHz | `core/rf/regs/iGopDrm/CLKB` → `core/if_req_addr_reg[1]/CE` | 11 | 16.243 ns | 5.547 ns(51.3%) / 5.269 ns | +0.246 ns |
| 90 MHz | `core/rf/regs/iGopDrm/CLKB` → `core/idex_pred_target[19]/CE` | 11 | 15.983 ns | 5.723 ns(54.2%) / 4.833 ns | −0.148 ns |

- 要让 **90 MHz** 通过，还需要再砍 **0.148 ns**；
- 要上 **100 MHz**（10 ns 周期），最差路径必须从约 16.0 ns 砍到 10 ns 以下，**必须动流水线本体的分级**
  （例如把 EX 段拆成两级），不是计数器级优化能解决的。

**下一步建议**（按性价比排序）：
1. **数据事务握手流水化**：按 CPI 归因，访存相关占约 48% cycles，把 `dstate` 的 REQ→RSP 两拍压成一拍
   估计可降 CPI 约 0.4（约 −17%），直接提高 Score 第 (1) 项。工作量与风险最高，需独立一轮。
2. **补齐实体板验证**（当前被 JTAG 下载线缺失阻塞）：调优后 50 MHz / 80 MHz 位流的 CoreMark 复测与
   PLL 实体验证，见 §5.4。
3. **`N161.eq_*` 相等比较树化**：理论上再省 0.5～0.8 ns，可能让 90 MHz 通过；风险中等。
4. **寄存器堆→ALU 段再分级**：真正突破 90 MHz 的唯一途径；属"重新设计流水线主体"，本届不做。
