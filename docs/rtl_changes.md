# RTL 变更说明（T3，逐改动记录）

> 最后更新：2026-09-17（CPI 优化专项第二轮）
> RTL 优化提交：`284f736`（实体板验证与口径修正见 `ab7a117` / `fcda14c`）；改动前基线 commit：`fd5bb75ec2d33f67bdf06f0a2a1fed23d25c1896`
> CPI 优化专项（改动 2）基线：commit `b4760bd`，`rtl/pipeline_cpu.v` SHA-256 前 16 位 `8E8EB3A69B2EF45E`
> 配套数据：`docs/performance_tuning.md`（频率/资源/关键路径）、`docs/coremark_cpi_analysis.md`（CPI 归因）、`docs/debug_log.md`（T1 定位过程）

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

**依据 1 — 关键路径数据（T2）**：50 MHz 约束、优化前的 `fpga/coremark/report_timing/mes50hp_coremark_top.rtr` 中，
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

**依据 2 — `logic_analyzer` 是同一瓶颈**：同一份 RTL 的另一套配置（逻辑分析仪工程）最差路径
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
| 实体板 CoreMark 复测 | `cdt_cfg` 下载 + `python\coremark_serial.py COM11` | **PASS**：50 MHz 优化版 Score 29.559、ticks 1,691,496,677、33.829 s、CPI 2.3443，四个官方 CRC 全过；80 MHz PLL 版 Score 47.295、52.859 s、CPI 2.3445 |
| 实体板 J8 逻辑分析仪回环 | `scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` | 50 MHz 优化版与 80 MHz PLL 版**各 80/80 PASS** |

### 1.8 风险

| 风险 | 评估 | 缓解 |
|---|---|---|
| 事件计数时刻晚一拍 | 低。只影响"哪一拍 +1"，不影响总数与任一架构行为 | 定向 TB 覆盖 clear/disable；CoreMark 仿真 cycles/retired 逐字段不变 |
| 50/80 MHz 点 WNS 数值轻微下降 | 低。属 PDS 布局布线随机性（同一 RTL 重复构建实测差异约 ±0.3 ns） | 在 `docs/performance_tuning.md` 中如实列出，不宣称"整体提升" |
| 重复运行不可复现 | 中。同一 RTL 三次构建的 WNS 在两个频率点分别出现不同值 | 所有结论都在同一批扫描内比较，并记录 RTL/FDC SHA-256 |
| 实体板稳定性 | 低（已实测）。原担心 CTS 移除真实延迟路径会导致板上不稳定 | **已消除**：50 MHz 与 80 MHz PLL 两套位流在实体板跑完 CoreMark 全程（33.8 s / 52.9 s）、CRC 全过；J8 四模式各 20 轮 80/80 通过 |

---

## 改动 2：取指满速交接（`if_arm`）—— CPI 2.3443 → 1.5388（T2，本轮唯一 RTL 改动）

### 2.1 改动文件与位置

| 项 | 内容 |
|---|---|
| 文件 | `rtl/pipeline_cpu.v`（Core 内部取指握手） |
| 位置 | 新增 `reg if_arm` 与 `if_present/if_present_addr/if_present_pred_*`；改写 `i_req_valid`/`i_req_addr`；改写“请求被接受”分支；`ex_redirect` 分支新增冻结逻辑；`if(!if_req&&!ex_redirect)` 改为 `if(!if_req&&!if_arm&&!ex_redirect)` |
| 端口 | **未改**（`i_req_*`/`i_rsp_*`/`d_req_*`/`d_rsp_*`/`trace_*`/`event_*` 逐根不变） |
| 行数 | 127 → 145 |
| 配套（Core 之外，SoC 侧） | `scripts/generate_coremark_fpga_memory.ps1`、`scripts/generate_logic_analyzer_fpga_memory.ps1`：取指存储器 `req_ready` 由 `!rsp_valid` 改为 `!rsp_valid||rsp_ready`；重新生成 `fpga/coremark/rtl/coremark_program_memory.v`、`fpga/coremark_80m/rtl/*`、`fpga/logic_analyzer*/rtl/logic_analyzer_program_memory.v` |

### 2.2 改动前

```verilog
assign i_req_valid=if_req&&(!if_rsp||if_accept);
assign i_req_addr=if_req_addr_reg;
...
if(if_request_accept) begin
 if_req<=0;fetch_req_pc<=if_req_addr_reg;...;if_rsp<=1;
 if(if_req_discard||ex_redirect)begin if_discard<=1;if_req_discard<=0;end
 else fetch_pc<=if_req_pred_taken?if_req_pred_target:(if_req_addr_reg+4);
end
// 在旧事务等待响应期间预登记下一 PC；真正的 valid 仅在旧响应完成时放行。
if(!if_req&&!ex_redirect)begin if_req<=1;if_req_addr_reg<=fetch_pc;...;end
```

即：请求被接受的当拍 `if_req<=0`，下一拍**没有任何请求对外可见**；要到“响应被接收”那一拍的结尾
（`if(!if_req)` 分支）才重新登记 `if_req_addr_reg`，并再下一拍才开始展示。结果每笔取指固定占用
**2 拍**，且“旧响应接收 + 新请求接受”的交接永远无法发生。

### 2.3 改成什么

```verilog
// if_arm：刚接受完上一笔请求，本拍直接用已寄存的 fetch_pc 展示下一笔请求。
// 展示地址来自 fetch_pc 寄存器，不新增地址寄存级，因此 !ready 时地址仍然稳定。
wire if_present=if_req||if_arm;
wire [31:0] if_present_addr=if_req?if_req_addr_reg:fetch_pc;
wire if_present_pred_hit=if_req?if_req_pred_hit:predictor_hit;
wire if_present_pred_taken=if_req?if_req_pred_taken:predictor_taken;
wire [31:0] if_present_pred_target=if_req?if_req_pred_target:predictor_target;
assign i_req_valid=if_present&&(!if_rsp||if_accept);
assign i_req_addr=if_present_addr;
...
if(if_request_accept) begin
 if_req<=0;if_arm<=0;fetch_req_pc<=if_present_addr;fetch_req_pred_*<=if_present_pred_*;if_rsp<=1;
 if(if_req_discard||ex_redirect)begin if_discard<=1;if_req_discard<=0;end
 else begin
  fetch_pc<=if_present_pred_taken?if_present_pred_target:(if_present_addr+4);
  if_arm<=1;  // 接受当拍立刻武装下一笔请求
 end
end
// Redirect 当拍若请求正在展示但尚未被接收，必须先冻结成 if_req 再改 fetch_pc
if(if_arm&&!if_request_accept)begin if_req<=1;if_req_addr_reg<=fetch_pc;...;end
if(if_arm)if_arm<=0;
if(if_req||if_arm)if_req_discard<=1;
// 冷启动/Redirect 后重新登记
if(!if_req&&!if_arm&&!ex_redirect)begin if_req<=1;if_req_addr_reg<=fetch_pc;...;end
```

关键点：接受请求的那一拍就把**下一笔请求**的地址与预测登记好（`if_arm`），于是下一拍
（正是旧响应被接收的那一拍）新请求已经在场，可以在同一拍完成交接。稳态下 `if_arm` 恒为 1、
`if_req` 恒为 0，取指每拍一条。

**SoC 侧为什么必须一起改**：取指存储器原来的 `req_ready=!rsp_valid` 在“响应被接收”那一拍为 0，
即使 Core 把请求送到也拒收。改为 `!rsp_valid||rsp_ready` 后，交接当拍既接收响应也接收新请求；
`rsp_valid` 在该拍保持 1，`rsp_data` 同步换成新请求的数据，仍是单 outstanding 语义
（`docs/interfaces.md` §3 第 136 行本来就要求 IF 支持这种交接）。数据端口未改：`dstate` 已把
数据事务串行化，没有交接场景。

### 2.4 为什么改（依据，全部来自 T1 归因观测台）

T1 用只读观测 Testbench（`tb/tb_cpi_attribution.v` + `tb/cpi_board_memory_model.v`，
存储器时序与实体板 `coremark_imem`/`coremark_dmem` 逐拍一致，统计窗口与 `PERF_WINDOW_ALIGN=1` 一致）
测出（Predictor On，官方 CoreMark 一次迭代，窗口内）：

| 证据 | 改动前 | 含义 |
|---|---:|---|
| CPI | 2.342（实体板 2.3443，吻合 0.1%） | 仿真口径可信 |
| `i_req_valid` 连续为低的拍数 | 920,207 / 1,788,110 拍（51.5%） | 一半的周期取指通道根本没有请求在场 |
| IF/ID 写入次数 | 766,004 | 每次平均 **2.334 拍** |
| 相邻 IF/ID 写入间隔直方图 | 间隔 2 占 664,411 次（86.7%），间隔 1 只有 1 次 | 取指只能每两拍一条 |
| `2 × 写入次数` | 1,532,008 拍 = 总周期 85.7% | 其中超出理想执行的 **768,832 拍（43.0%）纯属取指串行化损失** |
| 数据访存阻塞 `mem_block` | 78,158 拍（4.4%） | 只占少数，且大多落在取指空洞里，几乎“免费” |

与板级口径核对：`cycles/1000 inst = 2344.3 = 理想 1000 + stall 106.4 + flush 103.3 + 剩余 1134.6`，
而“每 1000 条指令固定多花约 1000 拍”正好解释了这 1134.6 拍的主体。
因此 T2 的候选 1/3/4（store 提前退休、REQ→RSP 压缩、地址提前产生）都不是主要矛盾，
**唯一值得做的是恢复接口契约里写明的取指满速交接**。

### 2.5 量化收益（Before → After，实体板实测）

| 指标 | Before（50 MHz） | After（50 MHz） | 变化 | After（80 MHz PLL） |
|---|---:|---:|---:|---:|
| **Score** | 29.559 | **45.051** | **+52.4%** | **72.081** |
| **CoreMark/MHz x1000** | 591 | **901** | **+52.5%** | **901** |
| **CPI** | 2.3443 | **1.5388** | **−34.4%** | 1.5387 |
| ticks | 1,691,496,677 | 1,109,848,679 | −34.4% | 2,774,618,621（2500 iter） |
| 运行秒数 | 33.829 | 22.196 | −34.4% | 34.682 |
| cycle_count | 1,693,816,436 | 1,112,164,751 | −34.4% | 2,778,317,919 |
| instret_count | 722,513,265 | 722,746,356 | +0.03% | 1,805,613,110 |
| cycles / iteration | 1,693,816 | 1,112,165 | −34.4% | 1,111,327 |
| stall / cycles | 4.54% | 8.18% | 占比升高（见下） | 8.16% |
| flush / cycles | 4.41% | 6.71% | 占比升高 | 6.71% |
| branch / instret | 0.275 | 0.2747 | 不变 | 0.2747 |
| 官方 CRC | 全过，crcfinal `0xd340` | 全过，crcfinal `0xd340` | 一致 | 全过，crcfinal `0x5275` |

- **两个频率点归一化后逐项吻合**：CPI 1.5388 / 1.5387（0.006%）、cycles/iteration
  1,112,165 / 1,111,327（0.075%）、`CoreMark/MHz x1000` 均为 901 —— 性能与频率无关，互为交叉验证。
- `stall/cycles` 与 `flush/cycles` **占比升高不代表变差**：绝对拍数基本不变
  （stall/iteration 76,919 → 90,967，flush/iteration 74,697 → 74,613），分母变小了 34%。
  stall 绝对量上升是**真实的 load-use 冒险现在被正确检出**（见 2.8）。
- 时序（PDS 重综合，四点全部 `All Constraints Met`）：
  50 MHz CoreMark WNS **+2.349 ns**；80 MHz CoreMark WNS **+0.667 ns**（估计 Fmax 84.51 MHz，
  优于改动前 `docs/performance_tuning.md` 记录的 +0.145 ns）；50 MHz 逻辑分析仪 WNS +2.812 ns；
  80 MHz 逻辑分析仪 WNS **+0.789 ns**（估计 Fmax 85.39 MHz）。
  新增的“下一取指 PC → BTB 查询 → `if_req_pred_*`”组合链确实成为 80 MHz 最差路径
  （`core/memwb_pc[3] → core/fetch_pc[2]`），但仍有 +0.667 ns 余量。

### 2.6 对架构的影响

| 项 | 结论 |
|---|---|
| Core/SoC 边界（`docs/interfaces.md`） | **不越界**。改动只在 Core 内部的取指握手；存储器 ready 策略改动在 Core 外的 adapter |
| `pipeline_cpu` 接口 | **未改** |
| 单 outstanding 事务语义 | **保持**。`*_ready` 策略保证“未完成响应在场时下游不接受新请求”，任意时刻仍只有一笔未完成事务 |
| “valid 且 !ready 时字段稳定” | **保持**。`if_arm` 的展示地址直接来自 `fetch_pc` 寄存器；Redirect 当拍先冻结成 `if_req_addr_reg` 再改 `fetch_pc` |
| 错误路径事务 | **保持**。Redirect 仍把在场/在途请求标记为 discard，等待其正常握手并丢弃响应，不撤回 `valid` |
| 提交级 trace | **语义不变**。`trace_valid` 仍表示一条指令架构提交；空泡/被 Flush 的指令不产生提交事件 |
| Reference Model 等价性 | **继续 PASS**（Task 17/24 全套 + 提交级 trace 逐条比对） |
| 事件定义 | **语义不变**（`event_stall`/`event_flush` 的定义未改，只是发生次数变了） |

### 2.7 验证方式

| 验证 | 命令 | 结果 |
|---|---|---|
| 全套回归（20 个入口） | `scripts\run_final_regression.ps1 -Quick` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 官方 CoreMark RTL 仿真（Predictor On） | `scripts\run_coremark_pipeline_tb.ps1` | PASS，cycles 1,852,156 → **1,295,932**，CPI 2.3747 → 1.6539，CRC 全过 |
| 官方 CoreMark RTL 仿真（Predictor Off） | `... -DisablePredictor` | PASS，cycles 2,106,042 → **1,604,264**，CPI 2.7143 → 2.0670 |
| 板级同源存储器模型 | `scripts\run_coremark_fpga_tb.ps1` | PASS，cycles 1,221,446，官方四 CRC 全过 |
| T1 归因观测台 | `scripts\run_cpi_attribution_tb.ps1 -AllowHandoff` | 窗口内 CPI 2.342 → **1.550**，IF/ID 间隔=1 占比 0% → **81.7%** |
| 实体板 CoreMark 50 MHz | `cdt_cfg` 下载 + `coremark_serial.py COM11 --clock-hz 50000000` | PASS，Score **45.051**、22.196 s、crcfinal `0xd340`、`Correct operation validated.` |
| 实体板 CoreMark 80 MHz PLL | 同上，`--clock-hz 80000000`，2500 迭代 | PASS，Score **72.081**、34.682 s、crcfinal `0x5275` |
| 实体板 J8 逻辑分析仪回环 | `scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` | 见 `docs/progress.md`（50/80 MHz 两配置各 80/80） |

### 2.8 必须说明的一处测试期望更新（不是放宽，而是纠正）

`scripts/run_pipeline_load_use_tb.ps1` 的 `EXPECT_LOAD_STALL` 由 **3 改为 4**。依据：

- 测试程序 `tb/data/load_use.mem` 含 **4 组相邻 load-use**
  （0x08→0x0c、0x10→0x14、0x18→0x1c、0x24→0x28）。
- 旧值 3 是“取指每两拍一条”时代的历史标定：当时取指空洞恰好插在 0x24→0x28 之间，
  让这对相邻指令在流水线里天然相隔两级，既不构成 load-use、也不需要停顿。
- 满速取指后该组恢复为真正的相邻 load-use。逐事件探针输出（`docs/debug_log.md` 有完整记录）：
  `LOADUSE cyc=27 ex_load_pc=00000024 id_pc=00000028 id_inst=00708433`，共 4 次。
- 同一测试的**提交级 trace 与最终 architectural state 对比全部 PASS**，
  即停顿次数变化只影响周期数，不影响功能正确性。

### 2.9 风险

| 风险 | 评估 | 缓解 |
|---|---|---|
| 前端组合链变长影响 Fmax | **中**，已实测：80 MHz WNS +0.667 ns、80 MHz 逻辑分析仪 +0.789 ns，仍 `All Constraints Met` | 四个配置全部重综合并记录 WNS；已列入 `docs/performance_tuning.md` |
| BTB 预测提前一拍查询 | 低。预测查询地址改成“组合下一 PC”，比原来早一拍；若该拍恰好有同一表项的更新，可能多一次 mispredict（自纠正） | 实测 mispredict 51,908 → 51,947（+0.08%），可忽略 |
| 取指变快后更多指令进入错误路径被丢弃 | 低，已量化：窗口内 discard 78,669 → 157,070，但总周期仍下降 33% | 板级 CRC 全过、trace 等价性 PASS |
| 数据端口未改，仍固定占 1 拍阻塞 | 低。取指变快后数据阻塞的相对代价上升（见 §4 的下一轮候选） | 作为下一轮候选单独评估 |

---

## 下一轮候选（CPI 专项，有数据支撑，本轮未做）

### 候选 A：正确预测的跳转不再 Redirect（**当前收益最大**）

| 项 | 内容 |
|---|---|
| 位置 | `rtl/pipeline_cpu.v`：`ex_redirect=(idex_valid&&!mem_block)&&(idex_jump||branch_mispredict)` |
| 现状 | `idex_jump` **无条件**触发 Redirect，即使 BTB 已经预测正确、前端本来就在正确路径上；此时 Redirect 把 IF/ID、ID/EX 与在途请求全部丢弃再重取，纯属浪费 |
| 依据 | T1 观测台（改动后窗口）：redirect 78,535 次、mispredict 仅 50,022 次 → **约 28,500 次是“预测正确的跳转”**；每次 Redirect 使相邻 IF/ID 写入间隔由 1 变 4，即多花 3 拍 |
| 预期收益 | 约 28,500 × 3 = 85,500 拍/迭代 ≈ **cycles 的 7.7%**；CPI 1.5388 → 约 1.42，Score 45.05 → 约 48.8 |
| 追加前置条件 | BTB 对 jump 的训练目前用 `update_taken=branch_taken`，而 `branch_unit` 对 JAL/JALR 的 funct3 没有意义 → 计数器可能长期停在“不跳”。要拿到全部收益需同时把 jump 训练改成恒 taken |
| 风险 | 中。改动控制冒险语义，须重跑 branch predictor / control hazard / trace 全套 + 实体板复测 |
| 建议 | 作为独立一轮，先做“BTB 对 jump 恒 taken”，再做“正确预测不 Redirect”，分两次 Before/After |

### 候选 B：数据访问阻塞与取指重叠

| 项 | 内容 |
|---|---|
| 位置 | `rtl/pipeline_cpu.v`：`mem_block` 冻结整条前端 |
| 现状 | 板级数据事务固定占 1 拍阻塞（79,960 拍/迭代），这 1 拍同时冻结 IF/ID 与 ID/EX |
| 依据 | 改动后取指已满速，`mem_block` 不再能“藏”在取指空洞里：窗口内 `hold_rsp`（阻塞期间响应被扣住）由 23,231 升到 79,960 |
| 预期收益 | 上界约 8 万拍/迭代 ≈ 7%，但需要“请求保持 + 响应交接”式改造 |
| 风险 | 高（改 hazard 与提交时序） |

### 候选 2（旧）：数据事务握手流水化 —— **已被 T1 证伪，作废**

原预期「CPI −0.4（约 −17%）」基于“每次数据访问固定多 2 拍握手”的猜测。T1 实测显示
板级数据事务本来就只有 1 拍阻塞（`memblk` 78,158 拍 = 78,158 次访存 × 1 拍），
且当时大多落在取指空洞里几乎免费。该候选作废，记录保留以便回溯。

---

## 上一轮未做的候选（保留记录）

以下候选**都给出了依据**，但按"一次只动一块 + 每轮都要上板实测"的规则，
上一轮只落地了改动 1，其余留作记录。

### 候选 2（旧记录）：数据事务握手流水化（**收益最大**）

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
| `fpga/coremark_80m/rtl/pll_80m.v` | PLL 原语 `GTP_PLL_E3` 例化（50 MHz → 80 MHz），Core 之外 |
| `fpga/coremark_80m/rtl/mes50hp_coremark_pll_top.v` | CoreMark 80 MHz 顶层 |
| `fpga/coremark_80m/pds_recipe.tcl`、`constraints/mes50hp_coremark_80m.fdc` | 80 MHz 工程配方与约束 |
| `fpga/logic_analyzer_80m/rtl/mes50hp_logic_analyzer_pll_top.v` | 逻辑分析仪 80 MHz 顶层（内部例化未改动的 50 MHz 顶层） |
| `fpga/logic_analyzer_80m/pds_recipe.tcl`、`constraints/mes50hp_logic_analyzer_80m.fdc` | 80 MHz 工程配方与约束 |
| `tb/pll_80m_model.v` | `GTP_PLL_E3` 行为模型（仅供 Icarus 仿真，不参与综合） |
| `tb/tb_logic_analyzer_pll80_board_top.v`、`scripts/run_logic_analyzer_pll80_board_top_tb.ps1` | 80 MHz PLL 顶层 RTL 闭环测试 |
| `scripts/run_fmax_sweep_rtl.ps1` | 可复现的频率扫描（隔离目录 + RTL 哈希记录） |
| `scripts/run_fmax_sweep.ps1`、`scripts/run_fmax_sweep_extra.ps1` | T0 首轮扫描用的脚本（保留为过程记录） |
| `python/fmax_report.py`、`python/pds_paths.py`、`python/coremark_cpi_analysis.py` | 时序/路径/CPI 数据自动提取 |
| `scripts/extract_timing_paths.ps1` | 早期 PowerShell 版路径提取（已被 `pds_paths.py` 取代，保留参考） |

## 附：CPI 专项（改动 2）新增文件

| 文件 | 用途 |
|---|---|
| `tb/cpi_board_memory_model.v` | 与实体板 `coremark_imem`/`coremark_dmem` 逐拍一致的只读观测存储器模型（含 `ALLOW_HANDOFF` 开关） |
| `tb/tb_cpi_attribution.v` | T1 只读观测台：逐拍分类统计取指/访存/阻塞，输出周期直方图与逐 PC 直方图 |
| `scripts/run_cpi_attribution_tb.ps1` | T1 观测台运行入口（`-AllowHandoff` / `-DisablePredictor`） |
| `python/cpi_attribution_report.py` | 逐 PC 直方图排序 + 关联 `coremark.dis` 给出指令文本 |
| `tmp/cpi/cycle_trace-*.log` | 窗口前 120 拍逐拍信号证据（`i_req_valid`/`i_rsp_valid`/`if_req`/`if_arm`/`mem_block`…） |
