# RTL 变更说明（T3，逐改动记录）

> 最后更新：2026-09-17
> 基线 commit：`fd5bb75ec2d33f67bdf06f0a2a1fed23d25c1896`
> 配套数据：`docs/performance_tuning.md`（频率/资源/关键路径）、`docs/coremark_cpi_analysis.md`（CPI 归因）

本文件按「一次只动一块」的规则逐条记录本轮 RTL 改动。每条都包含：
改动文件 / 改动位置 / 改动前 / 改成什么 / **为什么改（引用具体数据）** / 量化收益 / 架构影响 / 验证方式 / 风险。

---

## 改动 1：`rtl/perf_monitor.v` —— 事件先打一拍再做累加（T3-1）

### 1.1 改动文件与位置

| 项 | 内容 |
|---|---|
| 文件 | `rtl/perf_monitor.v` |
| 位置 | 模块 `perf_monitor` 内部：新增 9 个事件暂存寄存器 `q_retire/q_stall/q_load_stall/q_branch/q_branch_taken/q_flush/q_predict/q_btb_hit/q_mispredict`，计数器 `if` 条件由 `event_*` 改为 `q_*` |
| 端口 | **未改**（10 个 `event_*` 输入、10 个 64-bit 计数输出、`clk/reset/clear/enable` 全部保持原样） |
| 行数 | 原 26 行 → 现 46 行（新增注释与暂存级） |

### 1.2 改动前

```verilog
always @(posedge clk) begin
  if(reset||clear)begin cycle_count<=0; ... end
  else if(enable)begin
   cycle_count<=cycle_count+1'b1;if(event_retire)instret_count<=instret_count+1'b1;
   if(event_stall)stall_count<=stall_count+1'b1;if(event_load_stall)load_stall_count<=load_stall_count+1'b1;
   if(event_branch)branch_count<=branch_count+1'b1;if(event_branch_taken)branch_taken_count<=branch_taken_count+1'b1;
   if(event_flush)flush_count<=flush_count+1'b1;
   if(event_predict)predict_count<=predict_count+1'b1;
   if(event_btb_hit)btb_hit_count<=btb_hit_count+1'b1;
   if(event_mispredict)mispredict_count<=mispredict_count+1'b1;
  end
end
```

### 1.3 改成什么

```verilog
// 事件暂存级：把 Core 侧的长组合事件分类结果先锁存，切断事件到计数器进位链的组合路径。
reg q_retire,q_stall,q_load_stall,q_branch,q_branch_taken,q_flush,q_predict,q_btb_hit,q_mispredict;
always @(posedge clk) begin
  if(reset||clear)begin q_retire<=0; ... q_mispredict<=0;end
  else if(enable)begin
   q_retire<=event_retire;q_stall<=event_stall;q_load_stall<=event_load_stall;
   q_branch<=event_branch;q_branch_taken<=event_branch_taken;q_flush<=event_flush;
   q_predict<=event_predict;q_btb_hit<=event_btb_hit;q_mispredict<=event_mispredict;
  end
end
always @(posedge clk) begin
  if(reset||clear)begin cycle_count<=0; ... end
  else if(enable)begin
   cycle_count<=cycle_count+1'b1;if(q_retire)instret_count<=instret_count+1'b1;
   ... if(q_flush)flush_count<=flush_count+1'b1; ...
  end
end
```

### 1.4 为什么改（依据）

**依据 1 — 关键路径数据（T2）**：50 MHz 约束、优化前的 `fpga/task28_coremark/report_timing/mes50hp_coremark_top.rtr` 中，
最差 10 条 setup 路径有 **8 条终点是 `perf/flush_count`**，前 3 名全是：

```
Startpoint : core/rf/regs/iGopDrm/CLKB
Endpoint   : perf/flush_count[62]/opit_0_A2Q21/CE
arrival 22.789 ns, Logic Levels: 26, 逻辑 8.381 ns(48.6%) / 走线 8.858 ns, slack +1.805 ns
```

同一路径的逐级构成（报告明细）：

```
core/rf/regs/iGopDrm tco 2.286
  → 转发/操作数选择（core/idex_a → core/srca0 → core/ex_a, fanout=13）
  → core/exalu 加法链（GTP_LUT5CARRY）
  → core/ex_result（fanout=18）
  → core/N161.eq_0 .. eq_14   （16 级进位链做 32-bit 相等比较）
  → core/N164 → perf_mispredict（fanout=7）
  → core/N172 → perf_flush（fanout=46）
  → perf/flush_count[24..60] （10 级 CECO 进位链，1.84 ns）
```

**路径尾部「事件分类 → 计数器进位链」约 2～3 ns 纯属观测逻辑**：先锁一拍后，
组合路径从「事件分类 + 计数器进位链」变成「只走计数器进位链」，等于把这段组合深度整段砍掉。

**依据 2 — `task30_logic_analyzer` 是同一瓶颈**：同一份 RTL 的另一套配置（逻辑分析仪工程）最差路径
起点/终点与上完全一致，25 级逻辑、arrival 21.933 ns、slack +2.661 ns。
说明这是**所有配置的公共瓶颈**，不是某个顶层的偶然产物。

**依据 3 — 该路径与架构无关**：`perf_flush` / `perf_mispredict` 在 `rtl/pipeline_cpu.v` 第 93 行只驱动
`event_flush` / `event_mispredict` 两个**只读输出端口**。全工程检索确认它们的唯一消费者是
`perf_monitor`（以及 Testbench 的 `$display`），**不参与 IF/ID/EX/MEM/WB、Hazard、Forwarding、提交或任何架构状态**。

### 1.5 量化收益（Before → After）

| 频率约束 | 指标 | Before | After | 变化 |
|---:|---|---:|---:|---|
| 50 MHz | setup WNS | +1.805 ns | +1.693 ns | −0.112 ns（在 ±0.3 ns 布局波动内） |
| 50 MHz | 最差路径终点 | `perf/flush_count[62]` | `core/fetch_pc[28]` | **瓶颈从 perf 移到 core** |
| 50 MHz | 最差路径逻辑级数 | 26 | 21 | **−5 级** |
| 50 MHz | 最差路径逻辑延迟 | 8.381 ns | 7.866 ns | **−0.515 ns** |
| 50 MHz | 最差 10 条中 `perf/` 终点数 | 8 | **0** | 完全消除 |
| 70 MHz | setup WNS | +1.058 ns | +1.035 ns | −0.023 ns |
| 80 MHz | setup WNS | +0.588 ns | +0.145 ns | −0.443 ns |
| **85 MHz** | **setup WNS** | **+0.005 ns（零余量）** | **+0.246 ns** | **+0.241 ns，从"零余量"变成"可用余量"** |
| 90 MHz | 结果 | VIOLATED，18 失败端点 | VIOLATED | 两版天花板相同（约 89～90 MHz） |
| 综合资源（50 MHz 点） | LUT / FF | 2707 / 2577 | 2709 / 2585 | +2 LUT / +8 FF（9 个事件寄存器） |

**诚实结论**：这次改动**没有抬高约 89～90 MHz 的整体天花板**——因为天花板由流水线本体
（`core/rf/regs` → ALU → 预测目标比较 → `core/*_pc`）决定，而不是计数器。
它的真实价值是：**移除了一个跨配置存在的结构性瓶颈**，把 85 MHz 从 WNS +0.005 ns（零余量、不可用）
变成 +0.246 ns（可用），并让 80 MHz 有 +0.145 ns 余量。同时它是零架构风险的改动。

### 1.6 对架构的影响

| 项 | 结论 |
|---|---|
| Core/SoC 边界（`docs/interfaces.md`） | **不影响**。`perf_monitor` 本来就在 Core 之外，端口未变 |
| `pipeline_cpu` 接口 | **未改**，一行未动 |
| Reference Model | **不影响**。不改任何架构状态 |
| 提交级 trace | **不影响**。`trace_*` 端口与语义不变 |
| 事件定义语义 | 计数时刻整体晚一拍（事件经一级寄存）；计数器总数在同一轮运行内不变 |
| 唯一可观测差异 | `clear` 那一拍被暂存级吸收的事件不计数；运行期统计（百万级）可忽略 |

### 1.7 验证方式

| 验证 | 命令 | 结果 |
|---|---|---|
| 全套回归（20 个入口） | `scripts\run_final_regression.ps1 -Quick` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 性能计数器定向测试（含 clear/disable） | `run_perf_monitor_tb.ps1` | 13/13 PASS（`clear cycle`/`clear instret`/`disabled hold` 均 PASS） |
| 性能计数器 MMIO | `run_perf_mmio_tb.ps1` | 8/8 PASS |
| 官方 CoreMark RTL 仿真 | `run_coremark_pipeline_tb.ps1` | `cycles=1852156 retired=779952`，官方 CRC 全过，**与改动前逐字段一致** |
| 时序（50/70/80/85/90 MHz 五点） | `scripts\run_fmax_sweep_rtl.ps1 -Tag after` | 85 MHz `All Constraints Met`，90 MHz 起 VIOLATED |
| 实体板 CoreMark 复测 | 需 JTAG 下载线 | **未完成**（下载线未连接，见 `docs/performance_tuning.md` §5.4） |

### 1.8 风险

| 风险 | 评估 | 缓解 |
|---|---|---|
| 事件计数时刻晚一拍 | 低。只影响"哪一拍 +1"，不影响总数与任一架构行为 | 定向 TB 覆盖 clear/disable；CoreMark 仿真 cycles/retired 逐字段不变 |
| 50/80 MHz 点 WNS 数值轻微下降 | 低。属 PDS 布局布线随机性（同一 RTL 重复构建实测差异约 ±0.3 ns） | 在 `docs/performance_tuning.md` 中如实列出，不宣称"整体提升" |
| 重复运行不可复现 | 中。同一 RTL 三次构建的 WNS 分别为 +0.145 / +1.693（50 MHz 点）等不同值 | 所有结论都在同一批扫描内比较，并记录 RTL/FDC SHA-256 |
| 实体板未验证 | **中高**。CTS 移除了真实延迟路径，工具时序通过不等于板上稳定 | **必须**在接上下载线后重跑 `run_final_regression.ps1 -Quick` + 实体 CoreMark；未完成前不宣称板上可用 |

---

## 本轮未做的候选（有数据支撑，但风险/工作量更高）

以下候选**都给出了依据**，但按"一次只动一块 + 每轮都要上板实测"的规则，
本轮只落地了改动 1，其余留作下一轮明确建议。

### 候选 2：数据事务握手流水化（**收益最大**）

| 项 | 内容 |
|---|---|
| 位置 | `rtl/pipeline_cpu.v`：`dstate`（`D_IDLE/D_REQ/D_RSP`）与 `mem_done` / `mem_block` 时序 |
| 现状 | 每次数据访问固定 2 拍握手：`D_REQ`（发请求）→ `D_RSP`（收响应）→ 才 `mem_done` |
| 依据 | T1 CPI 归因：访存相关（stall + 事务等待）合计 **约 48% cycles、1.14 CPI**，是最大单项；load-use 只占 stall 的 11.23%，其余都是访存阻塞 |
| 预期收益 | 若把 REQ→RSP 压成"请求当拍即可应答"（`d_req_ready` 恒为可接收），每次数据访问省 1 拍；按访存指令占比估计 **CPI 约 −0.4（约 −17%）**，直接提高 Score 第 (1) 项 |
| 风险 | **高**。直接改动流水线访存时序、Hazard 与提交语义；必须重跑 Task 23/24 全套 + 提交级 trace 对比 + 实体板 CoreMark |
| 建议 | 作为下一轮唯一改动，独立一轮 Before/After |

### 候选 3：`N161.eq_*` 32-bit 相等比较树化

| 项 | 内容 |
|---|---|
| 位置 | `rtl/pipeline_cpu.v` 第 59–61 行 `branch_mispredict` 中的 `idex_pred_target != ex_target` |
| 现状 | PDS 实现为 16 级进位链（`core/N161.eq_0..eq_14`，每级 0.058 ns，合计约 1.0 ns） |
| 依据 | §3.1 路径明细中该段占据路径中段 |
| 预期收益 | 改成比较树（或先比较低 2 位）理论上可再省 0.5～0.8 ns；对 90 MHz 缺口（0.148 ns）可能有帮助 |
| 风险 | 中。改动预测校验逻辑，需重跑 branch predictor / control hazard / trace 回归 |

### 候选 4：寄存器堆读出 → 转发 → ALU 段再分级

| 项 | 内容 |
|---|---|
| 位置 | `rtl/regfile.v`（DRM 推断）与 `rtl/pipeline_cpu.v` 的 `srca0/srcb0/ex_a/ex_b` → `alu` |
| 依据 | §3.3/§3.4：85/90 MHz 的最差路径全是 `core/rf/regs/iGopDrm/CLKB → core/*`，DRM `tco` 约 2.3 ns、逻辑 5.5～5.7 ns、走线 4.8～5.3 ns |
| 预期收益 | 这是 90 MHz 以上的**唯一**门槛。要上 100 MHz 必须把 15.983 ns 砍到 10 ns 以下，只能靠这一段的再分级（例如 EX 阶段拆两级） |
| 风险 | **高**。会改变流水线级数与所有 Hazard/Flush/提交时序，属于"重新设计流水线主体"，与"不顺手大重构"规则冲突 |
| 建议 | 本届不做；若要冲 100 MHz，需要单独立项并重新验证全部 Gate |

### 候选 5：hold 路径（`ifid_pc → idex_pc`，0 级逻辑纯走线）

| 项 | 内容 |
|---|---|
| 依据 | §3.5：优化前最差 hold 为 `core/ifid_pc[0] → core/idex_pc[0]`，0 级逻辑，WHS +0.276 ns |
| 现状 | 优化后该路径已不在最差列表；所有频率点 WHS≥+0.276 ns、THS=0 |
| 结论 | **不需要动**。`route_optimize -fix_hold_violation` 已覆盖；不为它牺牲 setup |

---

## 附：新增文件清单（本非 RTL 部分）

| 文件 | 用途 |
|---|---|
| `fpga/task28_coremark_80m/rtl/pll_80m.v` | PLL 原语 `GTP_PLL_E3` 例化（50 MHz → 80 MHz），Core 之外 |
| `fpga/task28_coremark_80m/rtl/mes50hp_coremark_pll_top.v` | CoreMark 80 MHz 顶层 |
| `fpga/task28_coremark_80m/pds_recipe.tcl`、`constraints/mes50hp_coremark_80m.fdc` | 80 MHz 工程配方与约束 |
| `fpga/task30_logic_analyzer_80m/rtl/mes50hp_logic_analyzer_pll_top.v` | 逻辑分析仪 80 MHz 顶层（内部例化未改动的 50 MHz 顶层） |
| `fpga/task30_logic_analyzer_80m/pds_recipe.tcl`、`constraints/mes50hp_logic_analyzer_80m.fdc` | 80 MHz 工程配方与约束 |
| `tb/pll_80m_model.v` | `GTP_PLL_E3` 行为模型（仅供 Icarus 仿真，不参与综合） |
| `tb/tb_task30_pll80_board_top.v`、`scripts/run_task30_pll80_board_top_tb.ps1` | 80 MHz PLL 顶层 RTL 闭环测试 |
| `scripts/run_fmax_sweep_rtl.ps1` | 可复现的频率扫描（隔离目录 + RTL 哈希记录） |
| `scripts/run_fmax_sweep.ps1`、`scripts/run_fmax_sweep_extra.ps1` | T0 首轮扫描用的脚本（保留为过程记录） |
| `python/fmax_report.py`、`python/pds_paths.py`、`python/coremark_cpi_analysis.py` | 时序/路径/CPI 数据自动提取 |
| `scripts/extract_timing_paths.ps1` | 早期 PowerShell 版路径提取（已被 `pds_paths.py` 取代，保留参考） |
