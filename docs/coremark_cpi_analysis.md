# CoreMark CPI 归因分析（T1 → T2 → T3）

> 数据源：板级实测 JSON（`release/evidence/coremark_board_cpi50m.json`、`coremark_board_cpi80m.json`）、
> T1 只读观测台（`scripts/run_cpi_attribution_tb.ps1`）、RTL 仿真日志（`scripts/run_coremark_pipeline_tb.ps1`）。
> 历史基线（改动前）：`release/evidence/coremark_board_opt50m_aligned.json`、`coremark_board_80m_aligned.json`。
> 自动生成部分由 `python/coremark_cpi_analysis.py` 产生；T1 归因与结论由 T2/T3 手工维护。

## 1. 口径说明（先对齐再归因）

本工程有两个容易混用的口径：

- **Score 口径**：CoreMark 用 `barebones_clock()` 读性能计数器 `cycle_count[31:0]`，`ticks = stop - start`，`Score = iterations × CLOCK_HZ / ticks`。
- **CPI 口径**：`CPI = cycle_count / instret_count`，分母是提交的指令数。
- `ticks`（CoreMark 计时窗口）< `cycle_count`（上电至今），因为 CoreMark 的计时窗口
  只覆盖 benchmark 主体；串口等待/回读与启动代码不计入 `ticks`，但计入 `cycle_count`。

本次板级实测口径对照（50 MHz，CPI 优化后）：

| 量 | 值 | 说明 |
|---|---:|---|
| ticks（Score 分子口径） | 1,109,848,679 | CoreMark 计时窗口内的周期数 |
| cycle_count（CPI 分母） | 1,112,164,751 | 同一次清零之后至今 |
| instret_count | 722,746,356 | 提交指令数 |
| iterations | 1,000 | CoreMark 迭代次数 |
| CPI = cycle/instret | 1.5388 | 全窗口 CPI |
| cycles/iteration | 1,112,164.8 | 每迭代周期数 |

窗口差 = cycle_count − ticks = 2,316,072（占 cycle_count 0.2%），来自启动代码、串口等待与回读。

## 2. T1：把「剩余 1134 拍」定位到取指握手（**本次优化的起点**）

### 2.1 方法是先建一个与实体板同源的观测台

历史上 RTL 仿真用的是 `tb/ram_adapter.v` / `tb/pipeline_imem_adapter.v`，
两者的 `req_ready` 策略与响应延迟和板上**不一致**（数据侧多一拍、取指侧允许交接当拍接收），
所以“仿真 CPI 2.37、板上 CPI 2.34”只能算巧合，不能用来归因。

T1 因此新建：

- `tb/cpi_board_memory_model.v`：与 `fpga/coremark/rtl/coremark_program_memory.v` 的
  `coremark_imem` / `coremark_dmem` **逐拍一致**的存储器行为模型（含 `ALLOW_HANDOFF` 开关）。
- `tb/tb_cpi_attribution.v`：**只读**观测台，不改被测 RTL、不改接口，只用分层引用采样
  `if_req/if_rsp/if_discard/dstate/mem_block/mem_done/exmem_*/id_advance/…` 并逐拍分类统计。
- 统计窗口与板上同口径：由 `start_time()` 写 `PERF_CONTROL` 产生的 `perf_clear` 脉冲界定。

**口径自证**：观测台窗口 CPI = **2.342**，实体板 = **2.3443**，相差 0.1% —— 归因结论可直接搬到板上。

### 2.2 第一个错误信号：取指通道一半的周期没有请求在场

| 证据（改动前，Predictor On，一次官方迭代） | 值 | 含义 |
|---|---:|---|
| 窗口 cycles / retired | 1,788,110 / 763,176 | CPI 2.342 |
| `i_req_valid` 为低的拍数 | **920,207（51.5%）** | 一半周期取指端口根本没有请求 |
| `i_req_valid && i_req_ready` 次数 | 844,672 | 每笔取指平均 2.12 拍 |
| IF/ID 写入次数（非 discard） | 766,004 | 每条指令平均 **2.334 拍**才取到 |
| 相邻 IF/ID 写入间隔直方图 | 间隔 1：**1 次**；间隔 2：**664,411 次（86.7%）** | 取指只能每两拍一条 |
| 数据阻塞 `mem_block` | 78,158 拍（4.4%） | 不是主因 |
| 访存阻塞期间取指响应被扣住 | 23,231 拍 | 放大效应存在但很小 |

### 2.3 根因：`pipeline_cpu.v` 在“请求被接受”的下一拍没有任何请求对外可见

```verilog
if(if_request_accept) begin
 if_req<=0; ...; if_rsp<=1; ...          // 接受当拍清掉 if_req
end
if(!if_req&&!ex_redirect)begin if_req<=1;if_req_addr_reg<=fetch_pc;...;end  // 要等到下一拍结尾才重新登记
```

于是时序固定成：T 拍发请求 → T+1 拍**空**（无请求）→ T+2 拍发下一笔请求……
“旧响应接收 + 新请求接受”的交接永远无法发生。同时实体板取指存储器
`assign req_ready=!rsp_valid` 在“响应被接收”那一拍也恰好是 0，两边一起把取指钉在 2 拍/条。

**严格对账**（每 1000 条指令，板级口径）：

```text
cycles 2344.3 = 理想 1000（42.7%） + stall 106.4 + flush 103.3 + 剩余 1134.6（48.4%）
```

观测台把“剩余 1134.6”拆开：`2 × 766,004 = 1,532,008 拍（占窗口 85.7%）`是取指串行化底座，
其中超出理想执行的 **768,832 拍（43.0%）纯属取指每两拍一条的损失**；
`mem_block` 只占 78,158 拍，而且大多正好落在取指空洞里（每笔访存 1 拍阻塞）。

**结论**：T2 候选里的「store 提前退休」「REQ→RSP 压一拍」「访存地址提前产生」都不是主要矛盾；
唯一值得做的是**恢复 `docs/interfaces.md` §3 已经写明的取指满速交接**。

### 2.4 T2 实施（一轮一块）

| 块 | 内容 | 单独收益（观测台） |
|---|---|---:|
| A. SoC 侧取指 ready 策略 | `req_ready` 由 `!rsp_valid` 改为 `!rsp_valid||rsp_ready`（交接当拍可接收新请求） | 2.342 → 2.321（−0.9%，单独无用） |
| B. Core 侧 `if_arm` | 接受请求当拍立即武装下一笔请求（详见 `docs/rtl_changes.md` 改动 2） | 2.321 → **1.550（−33%）** |

A 单独做**几乎没有收益**，这正好证明瓶颈在 Core 而不在存储器——两者必须一起改才有效，
因此按同一个逻辑改动记录、分别给出证据。

### 2.5 T1 观测台 Before / After（同源窗口）

| 指标 | 改动前 | 改动后 | 变化 |
|---|---:|---:|---:|
| 窗口 cycles | 1,788,110 | **1,191,965** | −33.3% |
| retired | 763,176 | 768,610 | +0.7% |
| CPI | 2.342 | **1.550** | −33.8% |
| `i_req_valid` 为低的拍数 | 920,207（51.5%） | 187,749（15.8%） | — |
| IF/ID 写入次数 | 766,004 | 847,146 | +10.6% |
| 相邻写入间隔 = 1 | 1 | **692,507（81.7%）** | 满速取指 |
| 间隔 = 2 | 664,411 | 46,850 | — |
| 间隔 = 3 | 23,077 | 28,004 | — |
| 间隔 = 4 | 2,827 | 77,179 | Redirect 重取 |
| 间隔 = 5 | 75,534 | 2,606 | — |
| `mem_block` 拍数 | 78,158 | 79,960 | 与访存次数 1:1 |
| d_req 接受（load/store） | 78,159 | 79,961（64,283 / 15,677） | 每笔访存正好 1 拍阻塞 |
| redirect | 78,515 | 78,535 | 不变 |
| load-use stall | 7,156 | **30,504** | 真实冒险现在被正确检出 |
| `exmem_busy` | 78,158 | 79,960 | — |

**逐笔取指代价的严格分解**（间隔直方图与总周期精确相等）：

| 项 | 改动前 | 改动后 |
|---|---:|---:|
| 窗口 cycles | 1,788,110 | 1,191,965 |
| 理想（retired × 1） | 763,176 | 768,610 |
| 取指串行化底座（每笔取指 N 拍，N=2→1） | 1,532,008 | 847,146 |
| 其中超出理想的部分 | **768,832（43.0%）** | **78,536（6.6%）** |
| 额外间隔（stall / Redirect 重取） | 256,103（14.3%） | 344,819（28.9%） |
| 对账 | 1,788,110 ✓ | 1,191,965 ✓ |

即：**取指串行化损失被压掉了 90%**，代价是额外间隔（Redirect 重取与数据阻塞）
在总周期中的占比从 14.3% 升到 28.9% —— 它们从“藏在取指空洞里”变成“真实花钱”。

## 3. RTL 仿真归因（Predictor On / Off，官方 CoreMark 一次迭代）

命令：`scripts/run_coremark_pipeline_tb.ps1`（On）与 `-DisablePredictor`（Off）

| 配置 | cycles | retired | CPI | stall | load-use | flush | mispredict |
|---|---:|---:|---:|---:|---:|---:|---:|
| Predictor On（改动前） | 1,852,156 | 779,952 | 2.3747 | 176,170 | 19,791 | 81,523 | 51,908 |
| **Predictor On（改动后）** | **1,295,932** | 783,550 | **1.6539** | 186,129 | 28,489 | 81,562 | 51,947 |
| Predictor Off（改动前） | 2,106,042 | 775,901 | 2.7143 | n/a | n/a | n/a | 131,903 |
| **Predictor Off（改动后）** | **1,604,264** | 776,138 | **2.0670** | n/a | n/a | n/a | 132,127 |

- On：cycles −30.0%，CPI −30.4%；Off：cycles −23.8%，CPI −23.8%。
- BTB 收益（On 相对 Off）由 253,886 拍缩小到 308,332 拍，但**两条基线都整体下移**：
  BTB 是在更快的基线之上继续省周期。
- 该仿真用的是 `pipeline_imem_adapter` / `ram_adapter`（非板级同源），
  因此其 CPI 略高于板级 1.5388；板级同源口径见 §2.5 与 §4。

## 4. 板级测量：双频交叉验证

### 4.1 为什么必须做窗口对齐

板级七项计数器是**自由运行**的：从复位释放一直数到回读时刻。而 `COREMARK_READY` 会先等上位机发 `R` 才开跑，那段轮询是一个紧凑的 load + branch 循环，每个循环都要走统一事务（含访存阻塞），会产生上亿次 stall 与 branch。

后果（未对齐窗口时的实测值，可复现）：`stall` 甚至**超过** `cycles`、`branch` **超过** `instret`——这类数据不能用于 CPI 归因。

修正方式：在 `software/coremark/core_portme.c` 的 `start_time()` 中加入 `PERF_CONTROL = 1u`（写 perf_mmio CONTROL，offset 0x38），由编译开关 `PERF_WINDOW_ALIGN=1` 控制。清零紧接在读计时器之前，使七项计数器与 `ticks` **同口径**。该语句只改观测口径，不改被测量的执行路径。

### 4.2 板级 Before / After（实体板实测）

| 指标 | 改动前 50 MHz | **改动后 50 MHz** | 改动后 80 MHz PLL |
|---|---:|---:|---:|
| Score | 29.559 | **45.051** | **72.081** |
| CoreMark/MHz x1000 | 591 | **901** | **901** |
| CPI | 2.3443 | **1.5388** | **1.5387** |
| ticks | 1,691,496,677 | 1,109,848,679 | 2,774,618,621（2500 iter） |
| cycle_count | 1,693,816,436 | 1,112,164,751 | 2,778,317,919 |
| instret_count | 722,513,265 | 722,746,356 | 1,805,613,110 |
| cycles / iteration | 1,693,816 | 1,112,165 | 1,111,327 |
| 运行秒数 | 33.829 | 22.196 | 34.682 |
| stall / cycles | 4.54% | 8.18% | 8.16% |
| load-use / stall | 9.30% | 23.27% | 23.18% |
| flush / cycles | 4.41% | 6.71% | 6.71% |
| branch / instret | 0.275 | 0.2747 | 0.2747 |
| 官方 CRC | 全过 `0xd340` | 全过 `0xd340` | 全过 `0x5275` |

### 4.3 板级 CPI 分解（每 1000 条指令，计数器占用口径）

```text
改动前：2344.3 = 理想 1000（42.7%） + stall 106.4（4.5%） + flush 103.3（4.4%） + 剩余 1134.6（48.4%）
改动后：1538.8 = 理想 1000（65.0%） + stall 125.9（8.2%） + flush 103.2（6.7%） + 剩余  309.7（20.1%）
```

- 「剩余」由 1134.6 掉到 309.7（−72.7%），正是 §2 定位到的取指串行化损失，**归因闭环**。
- 注意这是**事件当拍的占用**口径，不是“每次事件的代价”：
  flush 74,613 次/迭代各花约 3 拍，真实代价约 20% cycles（见 §2.5 的额外间隔 344,819 拍）。
- `stall/cycles` 与 `flush/cycles` 占比升高只因分母变小；stall 的绝对量上升
  （76,919 → 90,967 拍/迭代）是真实 load-use 冒险现在被正确检出（见 `docs/rtl_changes.md` §2.8）。

### 4.4 双频交叉验证

| 指标 | 50 MHz | 80 MHz | 差别 |
|---|---:|---:|---:|
| cycles / iteration | 1,112,165 | 1,111,327 | 0.075% |
| CPI | 1.5388 | 1.5387 | 0.006% |
| stall / cycles | 8.18% | 8.16% | — |
| load-use / stall | 23.27% | 23.18% | — |
| flush / cycles | 6.71% | 6.71% | — |
| branch / instret | 0.2747 | 0.2747 | — |
| CoreMark/MHz x1000 | 901 | 901 | 0% |

两个独立频率点归一化后逐项吻合到 0.08% 以内：核心性能与频率无关、计数器统计正确。

## 5. 可行动结论：还能再压多少、卡在哪

以板级 50 MHz 为准，CPI = 1.5388。剩余可压缩空间与门槛：

| 损失来源 | 板级规模（每迭代） | 占 cycles | 可行动性 |
|---|---:|---:|---|
| 理想执行 | 722,746 拍 | 65.0% | 不可压缩（每指令至少 1 拍） |
| 正确预测的跳转仍被 Redirect | 约 28,500 次 × 3 拍 ≈ 85,500 拍 | ≈ 7.7% | **候选 A，收益最大**：`ex_redirect` 对 `idex_jump` 无条件成立 |
| 数据访问固定 1 拍阻塞 | 79,960 拍 | 7.2% | 候选 B：需把 `mem_block` 与取指重叠，改动 hazard/提交时序，风险高 |
| load-use 气泡 | 已含在 stall 90,967 拍内（23%） | 1.9% | 需要 MEM→EX 转发或 1 拍前递，属流水线主体改造 |
| control-mispredict | 50,022 次 × 3 拍 ≈ 150,000 拍 | 13.5% | 需要更大/更准的预测器（16 项 BTB 已饱和），属增强项 |

**下一轮建议**：候选 A（“BTB 对 jump 恒 taken” + “正确预测不 Redirect”），
预期 CPI 1.5388 → 约 1.42、Score 45.05 → 约 48.8。理由、前置条件与风险见
`docs/rtl_changes.md`「下一轮候选」。

**当前门槛**：90 MHz 以上的瓶颈已回到流水线本体
（`core/rf/regs` → ALU → 预测校验 → `core/*_pc`），不是本次改动的取指链
（取指链在 80 MHz 仍有 +0.667 ns 余量）。CPI 侧的门槛则是“每指令取指 1 拍 + 每指令提交 1 拍”
这条硬底，以及 3 拍/次的 Redirect 代价。

## 6. 历史结论（改动 1：`perf_monitor.v` 事件打一拍）

`rtl/perf_monitor.v` 事件打一拍**不改变任何架构行为**，因此 CPI / CoreMark 分数不变；
它的收益全部体现在 Fmax：最差 10 条路径中 `perf/flush_count` 终点由 8 条降为 0 条、
逻辑级数 26 → 21、85 MHz 的 WNS 由 +0.005 ns 提升到 +0.246 ns（见 `docs/performance_tuning.md`）。
实体板也已证实：该改动前后 50 MHz 位流的 Score 均为 **29.559**、CPI 均为 **2.3443**。
**提 Score 必须降 CPI，提频率只服务于独立的「时钟频率」计分项。**

## 7. 复现方式

```powershell
# T1 归因观测台（与实体板同源存储器时序；-AllowHandoff 为改动后配置）
& '<pwsh7>' -NoProfile -File scripts\run_cpi_attribution_tb.ps1 -AllowHandoff
& '<pwsh7>' -NoProfile -File scripts\run_cpi_attribution_tb.ps1          # 改动前配置（无交接）

# 官方 CoreMark RTL 仿真（Predictor On / Off）
& '<pwsh7>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1
& '<pwsh7>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1 -DisablePredictor

# 板级同源存储器模型的官方 CRC 自检
& '<pwsh7>' -NoProfile -File scripts\run_coremark_fpga_tb.ps1

# 板级采集（必须用 PERF_WINDOW_ALIGN=1 的镜像，否则计数器窗口被 UART 轮询污染）
D:\Python313\python.exe python\coremark_serial.py COM11 --clock-hz 50000000 `
  --output release\evidence\coremark_uart_cpi50m.log `
  --summary release\evidence\coremark_board_cpi50m.json
D:\Python313\python.exe python\coremark_cpi_analysis.py `
  --board release/evidence/coremark_board_cpi50m.json
```

---

## 8. T4 归因（2026-10-18）：把 `event_stall` 拆成 mem_block 与 mdu_block

### 8.1 为什么必须拆

历轮优化都集中在**控制流前端**（取指交接、分支预测、RAS），但板级计数器显示
前端相关只剩 8.29%。rv32im @85 MHz 4000 迭代（`coremark_board_cmim85_20261014.json`）：

| 项 | 周期 | 占 cycles | 每 1000 条指令 |
|---|---:|---:|---:|
| 理想 | 1,352,157,282 | 64.63% | 1000.0 |
| **stall 合计** | 566,381,894 | **27.07%** | 418.9 |
| 　load-use | 149,296,483 | 7.14% | 110.4 |
| **　mem_block / mdu_block** | **417,085,411** | **19.94%** | **308.5** |
| flush | 43,406,274 | 2.07% | 32.1 |
| 其余（前端/重填） | 130,218,825 | 6.22% | 96.3 |

`event_stall = front_hold = mem_block || mdu_block || load_use`，
`event_load_stall = load_use && !mem_block`，两者相减得到 `mem_block || mdu_block`，
但**这一项内部没有拆分**，而它是仅次于"理想执行"的最大单项。

### 8.2 拆分方法（零 RTL 改动、零端口改动）

`docs/interfaces.md` §6.1 冻结了 `pipeline_cpu` 的观测端口，因此**不新增端口**，
改为在 `tb/tb_coremark_pipeline.v` 里用**层次引用**采样 Core 内部信号：

```verilog
if (core.mem_block)                                           c_memblk <= c_memblk + 1;
if (core.mdu_block)                                           c_mdublk <= c_mdublk + 1;
if (core.d_req_valid && core.d_req_ready)                      c_dxact  <= c_dxact  + 1;
if (core.d_req_valid && core.d_req_ready && core.d_req_write)  c_store  <= c_store  + 1;
if (core.load_use)                                            c_loaduse<= c_loaduse+ 1;
if (core.front_hold)                                          c_stall  <= c_stall  + 1;
```

**关键口径**：`mem_block` 的每笔拍数与存储器模型有关——
板上 `coremark_dmem.req_ready = !rsp_valid`（每笔 **1 拍**），
而仿真 `tb/ram_adapter.v` 默认 `RANDOM_DELAY=1`（实测每笔约 **1.89 拍**）。
所以**向板级折算必须用 `data_xact` × 1 拍**，不能直接乘 `c_memblk`。

### 8.3 实测（rv32im，1 次迭代，`-O2`）

```text
ATTR cycles=604288 retired=340119 mem_block=157954 mdu_block=24307
     data_xact=83552 store=17351 load_use=32854 stall=212251
```

`mdu_block` 与存储器模型无关（纯 Core 内部），可直接按比例折算。
按板级测得的 `mem||mdu = 417.09M` 与仿真内部分摊比例（mdu 占 22.5%）拆分：

| 来源 | 板级周期（估） | 占全部 cycles | 可行动性 |
|---|---:|---:|---|
| **load 阻塞** | ≈256M（占 mem 的 79.2%） | **≈12.2%** | 需非阻塞 load（scoreboard / 延迟写回），**风险最高** |
| load-use 气泡 | 149.3M（实测） | **7.14%** | MEM→EX 前递，但会加长 ALU 关键路径，**与 Fmax 冲突** |
| **MDU 冻结** | ≈94M | **≈4.5%** | 乘法流水化 / 除法基数-4，改动封闭、不碰前端 |
| **store 阻塞** | ≈67M（占 mem 的 20.8%） | **≈3.2%** | store 提前退休（请求被接受即退休），中风险 |
| flush | 43.4M | 2.07% | 已在 A1 优化过 |
| 其余（前端） | 130.2M | 6.22% | FIFO 实测 0、RAS 实测 0.25%，已证明不值得再投入 |

### 8.4 结论与优先级修正

1. **数据口（load+store）是最大单项 ≈15.4%**，其中 load 占 79%。
   代价最低的是 **store 提前退休 ≈3.2%**；load 那 12.2% 必须靠非阻塞 load，
   属"重新设计访存/提交时序"，建议最后做。
2. **MDU 只有 ≈4.5%**，比按静态指令数估计的低得多；改动封闭，作中风险项。
3. **load-use 7.14%** 需 MEM→EX 前递，会加长 ALU 关键路径，与 85→90 MHz
   直接冲突，**不建议在 Fmax 之前做**。
4. 前端已无余量（FIFO 0%、RAS 0.25% 且 LUT +2.62% 使 CoreMark/LUT −2.30%）。

**由此修正 §5 的旧建议**，新优先级：
`Fmax 85→90` > `MDU 去阻塞` > `store 提前退休` > `非阻塞 load`；
`load-use 前递` 推迟到 Fmax 稳定之后再评估。
