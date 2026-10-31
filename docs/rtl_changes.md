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

## 改动 3：M 扩展（RV32IM）—— 新增 `rtl/mdu.v`，CoreMark/MHz 0.936 → 2.272（2026-10-14）

### 3.1 改动文件与位置

| 项 | 内容 |
|---|---|
| 新文件 | `rtl/mdu.v`（乘除法单元，三段流水乘法 + 32 拍迭代除法） |
| `rtl/decoder.v` | 新增 `mdu_en` / `mdu_op[2:0]` 两个输出；`funct7=0000001` 的整组 R-Type 由"非法"改为合法（`mdu_op` 直接取 `funct3`）。**不受 `ENABLE_SYSTEM` 影响**：两个 CPU 都按 RV32IM 译码 |
| `rtl/pipeline_cpu.v` | 新增 ID/EX 的 `idex_mdu_en/idex_mdu_op`；`ex_result` 增加 mdu 分支；新增 `mdu_block` 停顿与 `idex_to_exmem`/`mdu_ack` 握手；新增 `exmem_retired` 退休标记；`mem_done` 与 `event_misaligned`/`event_bus_error`/`mem_access_error_now` 相应调整 |
| `rtl/single_cycle_cpu.v` | 同一套 M 扩展（Reference Model 必须与流水线同 ISA，否则等价性比较在任何用到乘除法的程序上直接失效）；新增 `mdu_busy` 等待状态 |
| 端口 | **Core 对外端口一根未改**（`docs/interfaces.md` §293～299 的契约不变） |

### 3.2 为什么做

`third_party/coremark/core_matrix.c` 每次迭代固定 10,575 次乘法（N=15），全部走 libgcc
`__mulsi3` 的移位加循环；反汇编实测循环体 6 条指令、平均 7.94 次循环迭代/次乘法
（B 矩阵 225 个值里只有 6 个负数）。板级 ILA 窗口实测 84.3% 的提交落在该循环里。
按指令数折算：**约 47 万条 / 每迭代 778,037 条 ≈ 60% 的指令花在软件乘法上**。

### 3.3 量化收益（实体板实测，同一位流口径）

| 指标 | RV32I（`cm50`，1000 迭代） | **RV32IM（`cmim`，2000 迭代）** | 变化 |
|---|---:|---:|---:|
| **CoreMark Score @50 MHz** | 46.816 | **113.642** | **2.43×** |
| **CoreMark Score @85 MHz（与交付同频）** | 79.587（`cm85`） | **193.192**（`cmim85`，4000 迭代） | **2.43×** |
| **CoreMark/MHz ×1000** | 936 | **2272**（50 与 85 MHz 两点一致） | **2.43×** |
| ticks / 迭代 | 1,068,007 | 439,975（两个频点逐位一致） | −58.8% |
| 每次迭代指令数 | 778,037 | 362,131 | −53.5% |
| CPI | 1.494 | 1.550（50 MHz）/ 1.547（85 MHz） | +3.7% |
| 迭代次数 / 运行时间 | 1000 / 21.36 s | 2000 / 17.60 s（50 MHz）· 4000 / 20.70 s（85 MHz） | 均 ≥10 s ✓ |
| 官方 CRC | 全过 | **全过**（两个频点） | ✓ |
| CoreMark/LUT（85 MHz 同源同频） | 0.0190（79.587÷4198，`cm85r`） | **0.0460**（193.192÷4198） | **2.43×** |
| RTL 仿真 `cycles`（同 TB/程序） | 1,251,724 | 594,792 | −52.5% |

证据：`release/evidence/coremark_uart_im.log` + `coremark_board_im.json`（50 MHz 点）、
`release/evidence/coremark_uart_cmim85_20261014.log` + `coremark_board_cmim85_20261014.json`（85 MHz 点，与交付同频）、
`release/evidence/board/run01/`（RV32I 基线）。**引用时必须写明哪一套 ISA 与哪个频点**——
CoreMark 输出里自带 `Compiler flags : -O2 -march=rv32im -mabi=ilp32` 一行可自证；

> ⚠️ 85 MHz 那一点是 2026-10-14 追加构建的（`fpga/coremark_im_85m`，源文件取自 `fpga/coremark_85m`，
> 只换程序镜像）。补它的原因：原来的 RV32IM 工程 `.fdc` 写死 50 MHz、而 80/85/90 MHz 的计分工程
> 建在 M 扩展之前从未重建，于是"与交付同频的 M 扩展分数"这一栏是空的——
> **是没建过，不是跑不了**（带 M 的 85 MHz 构建 `All Constraints Met`，WNS +0.250 ns）。

### 3.4 三个真 bug（都由证据定位，不是猜的）

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 背靠背两条除法指令中，第二条沿用第一条的结果（`rem` 返回了商） | 状态机只在 `run` 落下时才回 IDLE，而连续两条同类指令之间 `run` 从不落下 | 新增 `ack` 输入：流水线在"该指令被锁进 EX/MEM"那一拍给出消费脉冲，`S_DONE` 依 `ack \|\| !run` 回 IDLE |
| 2 | CoreMark rv32im 跑到 306,637 条后整机死锁（停在一条 `lbu` 上） | 访存指令的"完成"由握手定义（`dstate` D_RSP→D_IDLE 只发生一次），而 MEM→WB 原来与"ID/EX 换入 EX/MEM"同拍原子发生。除法停顿把两者拆开后，`mem_done` 在握手结束那一刻落下，`mem_block` 永久为 1 | 新增 `exmem_retired` 标记：MEM→WB 只允许每条 EX/MEM 记录退休一次，`mem_done` 在退休后保持为 1，MEM 级因此可以与 EX 级解耦排空 |
| 3 | 50 MHz 下 WNS 从 +2.676 ns 掉到 +0.234 ns；85 MHz 直接违例 −3.268 ns | 一拍组合 32×32 乘法被综合成 **4 级串联 APM**，端点 `mdu_unit/N25_m1..m4/gopapm → exmem_alu` | 分两段流水：先把 32×32 拆成两个 **16×32** 部分积分别寄存（串联链缩到 2 级 APM），第二段做"移位相加 + 符号修正"；每条乘法 3 拍。50 MHz WNS 回到 +1.841 ns，85 MHz `All Constraints Met` |

### 3.5 端口与语义边界

- Core 对外**端口未变**，M 扩展完全在 Core 内部（这是 ISA 扩展，不是外设）。
- 单周期 Reference 与流水线**必须同 ISA**：这一条写在 `rtl/decoder.v` 顶部注释里。
- `scripts/check_coremark_elf.ps1` 双向校验：rv32i 镜像必须"一条 M 指令都没有"，
  rv32im 镜像必须"真的有 M 指令且 ELF 属性是 `rv32i2p1_m2p0...`"。
- 新增/更新测试：`tb/tb_mdu.v`（46 项，含乘除全部边界、除零、溢出、背靠背、取消）、
  `tb/tb_pipeline_m_ext.v`（流水线 vs 单周期，55 条提交 trace + x1~x31 + RAM + 手算常量 + 除法停顿精确 34 拍）、
  `tb/tb_decoder.v` 的 M 编码用例（8 条 + 两条反例）。

### 3.6 风险

| 风险 | 评估 | 缓解 |
|---|---|---|
| 乘法器进关键路径 | **已实测并已修**（见 §3.4 第 3 条） | 两段流水；50 MHz +1.841 ns、85 MHz All Met |
| 除法停顿 34 拍被误当成死锁 | 低。`tb_pipeline_m_ext.v` 逐条断言"每笔除法正好占 EX 34 拍" | 断言随回归常跑 |
| 引用分数时混用两套 ISA | **中**（这正是 `claims_map` §12 记录过的那类风险） | 两个位流、两份证据文件、CoreMark 输出自带 `-march` 一行 |

---

## 改动 4：逻辑分析仪采集源双源可选（Core 外部，2026-10-14）

| 项 | 内容 |
|---|---|
| `rtl/logic_analyzer_mmio.v` | 新增输入 `probe_channels[7:0]` 与寄存器 18（`src_sel`）；`active_channels` **寄存一拍**再进采集引擎（理由见下） |
| 板级顶层（la50 / la80 / la85 / la90） | 新增 `core_probe`：8 根 Core 已有冻结输出（`i_req_valid`/`i_req_ready`/`i_rsp_valid`/`d_req_valid`/`d_req_ready`/`event_stall`/`event_flush`/`trace_valid`），**再打一拍**后接 `probe_channels` |
| `software/logic_analyzer/logic_analyzer.c` | 新增 `LA_SRC` 定义与 **0xA8** 命令（16 字节，pre/post 各 16 位，[14]=采集源）；0xA5/0xA7 路径明确回写 `LA_SRC=0` |
| 上位机 | `python/logic_analyzer_serial.py` 新增 `source`/`core` 模式/`CORE_PROBE_NAMES`；`python/core_probe_board.py` 板级验收；`python/test_logic_analyzer_serial.py` 新增 5 项 |
| 端口 | 采集引擎、Pattern Generator、MMIO 对外契约不变；**J8 外部通路只多了"寄存一拍"** |

**为什么 `active_channels` 必须寄存一拍**：spi 模式的 `sample_div=0` 让采集引擎每拍采样，
是四种模式里最吃时序的一条路径。源选择 MUX 直接串在 `channels → 引擎` 之间时，
85 MHz 下余量被吃光，**实测症状是"SPI 模式一发配置包固件就永久卡死，之后连 static 也无响应"**
（与 2026-09-30 在 90 MHz 上记录的完全一致）。寄存之后引擎输入来自寄存器，
这条路径比加功能之前更短；代价是采样点整体晚 1 个系统时钟，对所有判据无影响。

**同一类问题的第二处**：Core 的事件信号是组合逻辑，直接接到采集引擎会让
"Core 事件逻辑 → `capture_count` 使能"成为最差路径（85 MHz 实测 Endpoint
`analyzer/cap/capture_count[3]/CE`、Slack −0.980 ns）。在板级顶层给探针打一拍即可，
且**只影响探针，不影响 J8 通路**。

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

---

## 改动 3（2026-10-18）：返回地址栈 RAS —— **已实现、已上板、默认关闭**

### 3.1 动机

BTB 每个 PC 只存**一个** target，而同一个 `ret` 会被多个调用点共享。
CoreMark（rv32i）静态统计：`ret` 49 处 / `call` 158 处 / `jmp` 110 处 /
条件分支 295 处（合计 619 条控制流，占 3417 条静态指令的 18.1%）。
RAS 记的是整条返回路径的栈，不是"上次去了哪儿"。

### 3.2 改动内容（全部可开关，默认 `ENABLE_RAS = 0`）

| 文件 | 改动 |
|---|---|
| `rtl/ras.v` | **新增**：参数化深度的返回地址栈（环形指针 + 计数饱和；空栈 pop 不回绕；溢出覆盖最老项） |
| `tb/tb_ras.v` | **新增**：27 条断言，深度 8/4/2/1 全部 PASS（含随机黄金模型比对） |
| `scripts/run_ras_tb.ps1` | **新增**：一次跑四个深度 |
| `rtl/pipeline_cpu.v` | 新增 `ENABLE_RAS` / `RAS_DEPTH` 参数；`id_advance` 提前声明；新增 `btb_is_ret[15:0]` 位图（与 BTB 同索引同更新点）；`predictor_target_eff` 在 ret 命中且栈非空时改用 `ras_top` |
| `tb/tb_coremark_pipeline.v` | 新增 `ENABLE_RAS` 参数并透传 |
| `scripts/run_coremark_pipeline_tb.ps1` | 新增 `$env:ENABLE_RAS` 开关（默认 0） |
| 24 个 `scripts/run_*.ps1` | 源文件列表补 `rtl/ras.v` |
| `fpga/coremark_ras_85m/` | **新增**独立工程（rsa.v 已加入 recipe），用于 RAS=1 的板级对照，不覆盖交付工程 |

判定规则（RISC-V 没有专职 call/ret，只能看寄存器号）：
`call = dec_jmp && rd==x1` → push `ifid_pc+4`；
`ret = dec_jalr && rd==x0 && rs1==x1` → pop。
更新点放在 **ID 级、按序**（`id_advance` 门控），被重定向冲刷的指令不会污染栈。

### 3.3 Before / After（实测，非估算）

| 口径 | RAS=0 | RAS=1 | 变化 |
|---|---:|---:|---:|
| RTL 仿真 cycles，**rv32i** | 1,251,724 | 1,226,872 | **−1.99%** |
| RTL 仿真 cycles，**rv32im** | 604,288 | 603,090 | **−0.20%** |
| **实体板 ticks**，rv32im @85 MHz（4000 迭代） | 1,759,901,953 | 1,755,563,957 | **−0.25%** |
| **实体板 Score** | 193.192 | **193.669** | +0.25% |
| CoreMark/MHz | 2.272 | **2.278** | +0.26% |
| **LUT** | **4198** | **4308** | **+2.62%** |
| **CoreMark/LUT** | **0.04602** | **0.04496** | **−2.30%** |
| FF | 3361 | 3640 | +279 |
| 路由后 WNS（85 MHz） | +0.250 ns | +0.117 ns | 余量变小 |

板级证据：`release/evidence/coremark_uart_ras85_20261018.log`、
`release/evidence/coremark_board_ras85_20261018.json`（四 CRC 全过、
`Correct operation validated.`、`-march=rv32im` 自证、20.653 s ≥ 10 s）。

### 3.4 结论：**功能正确，但净收益为负，默认关闭**

1. **仿真与实体板完全吻合**：rv32im 仿真 −0.20% vs 实体板 −0.25%。
   早期看到的 −1.99% 是 **rv32i** 口径——rv32i 下每次乘法都要调 `__mulsi3`
   （84.3% 的提交落在里面），call/ret 对极多，RAS 才有大收益；
   rv32im 把乘法变成单条指令后这些调用整个消失。
   **引用 RAS 收益必须写明 ISA，不得把 rv32i 的 −2% 说成 rv32im 的成绩。**
2. **面积代价（+110 LUT，+2.62%）大于分数收益（+0.25%）**，因此
   CoreMark/LUT 反而掉了 2.3%。这是"小面积改动换小分数"的典型亏本交易。
   深度扫描（4/8/16）周期数完全相同，减小深度也省不下足够的 LUT。
3. 时序余量从 +0.250 ns 降到 +0.117 ns（85 MHz 仍 Met）：RAS 栈顶到
   `fetch_pc` 多了一级 mux，落在原本就紧的预测链上。
4. 按 `AGENTS.md` §9「功能正确性或时序稳定性下降时应优先恢复正确性」，
   **默认值保持 `ENABLE_RAS = 0`，交付位流与既有证据口径不变**；
   机制、Testbench 与板级 Before/After 全部留档，便于将来在
   "面积更宽松 / 面积不计分"的场合直接打开。

### 3.5 复现

```powershell
# 模块自测（深度 8/4/2/1）
& '<pwsh5>' -NoProfile -File scripts\run_ras_tb.ps1

# 仿真 Before/After（rv32i 与 rv32im 各跑一遍）
$env:ENABLE_RAS=0; & '<pwsh5>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1 -March rv32im
$env:ENABLE_RAS=1; & '<pwsh5>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1 -March rv32im

# 板级 Before/After（RAS 位流在独立工程里，不动交付工程）
cd fpga\coremark_ras_85m; & 'D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe' -file pds_recipe.tcl -project_name coremark_ras_85m_generated
& '<pwsh5>' -NoProfile -File scripts\program_board.ps1 -BitstreamPath fpga\coremark_ras_85m\generate_bitstream\mes50hp_coremark_pll_top.sbit
& '<pwsh5>' -NoProfile -File scripts\run_coremark_board.ps1 -Port COM11 -ClockHz 85000000 -TimeoutSeconds 180
```

---

## 改动 4（2026-10-19）：`rtl/mdu.v` —— 乘法并行部分积，`MUL_LAT` 3 → 2

> 完整记录（算法、三方对照、关键路径、复现命令）在 **`docs/mdu_parallel_partial_product.md`**，
> 本节只保留"改动清单 + 结论"以便与改动 1～3 并列。

### 4.1 改动文件

| 文件 | 改动 |
|---|---|
| `rtl/mdu.v` | 新增参数 `MUL_LAT`（3/2/1，默认 **2**）；乘法由"两级串联 16x32 部分积"改为"四路并联 16x16 + 窄位宽（17/33 位）加法树 + 推测进位选择"；除法通路**一行未改** |
| `rtl/pipeline_cpu.v` | 新增参数 `MDU_MUL_LAT`（默认 2）并透传给 `mdu`；`mdu` 例化改为 `mdu #(.MUL_LAT(MDU_MUL_LAT))`；注释里"乘法 2 拍"的旧说法改为引用参数 |
| `tb/tb_mdu.v` | 由"写死 3 拍"改为按 `MUL_LAT` 判定时序（`-DMUL_LAT=n`），46 项手算用例三种模式共用同一组期望值 |
| `tb/tb_pipeline_m_ext.v` | 新增 `MUL_LAT_CFG` 参数并透传（默认 2） |
| `tb/tb_coremark_pipeline.v` | 新增 `MDU_MUL_LAT` 参数并透传（默认 2） |
| `scripts/run_mdu_tb.ps1` / `run_pipeline_m_ext_tb.ps1` / `run_coremark_pipeline_tb.ps1` | 新增 `-MulLat` / `$env:MDU_MUL_LAT` 开关（默认 2），Before/After 靠它切换 |
| `fpga/coremark_mul{1,2,3}_85m/` | **新增**三个对照工程（同一份镜像与约束，唯一变量 `MUL_LAT`），互不覆盖、不动交付工程 |

### 4.2 结论（实测）

| 项 | MUL_LAT=3（旧） | MUL_LAT=2（新默认） | 变化 |
|---|---:|---:|---:|
| 仿真 cycles（rv32im 一次迭代） | 604,288 | **594,792** | **−1.571%** |
| 仿真 `mdu_block` | 24,307 | **14,810** | −9,497（= 每迭代乘法条数） |
| 仿真 CoreMark/MHz | 1.965 | **2.002** | **+1.88%** |
| 仿真 `instret` | 333,095 | 333,095 | **不变** |
| LUT / FF（85 MHz PnR） | 4185 / 3361 | **4139 / 3324** | **−46 / −37** |
| 路由后 WNS（85 MHz） | +0.281 ns | **+0.115 ns** | −0.166 ns，仍 `All Constraints Met` |
| 估算 Fmax | 87.0800 MHz | **85.8391 MHz** | — |
| **板级 ticks（4000 迭代）** | 1,759,901,953 | **1,722,317,953** | **−2.135%** |
| **板级 Score / CoreMark/MHz** | 193.192 / 2.272 | **197.408 / 2.322** | **+2.183% / +2.20%** |

- `instret` 与四行官方 CRC 三种配置完全相同 ⇒ **纯延迟改动，架构不变**。
- `ΔScore/ΔArea` 判据：分数 +1.88%、面积 −1.10%，**同向为正**。
- **MUL_LAT=1 实测违例**（WNS −4.471 ns / 61.59 MHz）：关键路径在
  `core/rf/regs → 前递 MUX → 一级 APM` 就已 12.189 ns，超过 85 MHz 的 11.7647 ns 周期
  ⇒ 85 MHz 下不存在"乘法输入直连前递操作数"的结构，`M_IDLE` 那一拍是必需的。
- **板级已验证**（2026-10-19，MES50HP/COM11，两颗位流分别上板）：
  Score **193.192 → 197.408（+2.183%）**、ticks −2.135%、`crcfinal 0x65c5` 两次相同、
  `flush_count` 两次逐位相同；且**仿真与实板的每迭代 ticks 收益都是 9,396 拍**。
  证据 `release/evidence/coremark_board_mul{3,2}_85m_20261019.json`。
  上板后板子已恢复交付位流 `la85`。
- **交付逻辑分析仪位流（la85）未重打**：`release/` 内既有位流与哈希未动。
- **CPI 不得引用**：两次采集用默认 `PERF_WINDOW_ALIGN=0` 镜像，`cycle/instret/stall/branch`
  含启动与等待 `R` 的轮询，两次不可比。
