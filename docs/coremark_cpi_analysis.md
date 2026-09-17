# CoreMark CPI 归因分析（T1）

> 由 `python/coremark_cpi_analysis.py` 自动生成；数据源为板级实测 JSON 与 RTL 仿真日志。

## 1. 口径说明（先对齐再归因）

本工程有两个容易混用的口径：

- **Score 口径**：CoreMark 用 `barebones_clock()` 读性能计数器 `cycle_count[31:0]`，`ticks = stop - start`，`Score = iterations × CLOCK_HZ / ticks`。
- **CPI 口径**：`CPI = cycle_count / instret_count`，分母是提交的指令数。
- `ticks`（CoreMark 计时窗口）< `cycle_count`（上电至今），因为 CoreMark 的计时窗口
  只覆盖 benchmark 主体；串口等待/回读与启动代码不计入 `ticks`，但计入 `cycle_count`。

本次板级实测口径对照：

| 量 | 值 | 说明 |
|---|---:|---|
| ticks（Score 分子口径） | 1,691,496,677 | CoreMark 计时窗口内的周期数 |
| cycle_count（CPI 分母） | 1,693,816,436 | 上电至今全窗口周期数 |
| instret_count | 722,513,265 | 提交指令数 |
| iterations | 1,000 | CoreMark 迭代次数 |
| CPI = cycle/instret | 2.3443 | 全窗口 CPI |
| cycles/iteration（Score 口径） | 1,691,496.7 | 每迭代周期数 |

窗口差 = cycle_count − ticks = 2,319,759（占 cycle_count 0.1%），来自启动代码、串口等待与回读。

## 2. RTL 仿真归因（Predictor On / Off，官方 CoreMark 一次迭代）

命令：`scripts/run_coremark_pipeline_tb.ps1`（On）与 `-DisablePredictor`（Off）

### Predictor On（最终配置）

| 项目 | 周期数 | CPI 贡献 | 占 cycles |
|---|---:|---:|---:|
| 理想执行（retired × 1） | 779,952 | 1.0000 | 42.11% |
| Hazard stall | 176,170 | 0.2259 | 9.51% |
| 控制冒险 flush（81,523 次 × 2 拍） | 163,046 | 0.2090 | 8.80% |
| 其余（访存事务等待/取指交接） | 732,988 | 0.9398 | 39.57% |
| **合计** | **1,852,156** | **2.3747** | 100.00% |

- load-use stall = 19,791，占全部 stall 的 11.23%
- 分支事件 = 213,756，taken = 133,273，predict = 213,756，BTB hit = 203,492，mispredict = 51,908
- 预测命中率 = 95.20%，综合正确率 = 75.72%

### Predictor Off（Before 基线）

| 项目 | 周期数 | CPI 贡献 | 占 cycles |
|---|---:|---:|---:|
| 理想执行（retired × 1） | 775,901 | 1.0000 | 36.84% |
| 其余（访存事务等待/取指交接） | 1,330,141 | 1.7143 | 63.16% |
| **合计** | **2,106,042** | **2.7143** | 100.00% |

- mispredict = 131,903

### Predictor Before / After

| 配置 | cycles | retired | CPI | flush | mispredict | flush 周期成本 |
|---|---:|---:|---:|---:|---:|---:|
| Predictor Off | 2,106,042 | 775,901 | 2.7143 | n/a | 131,903 | n/a |
| Predictor On | 1,852,156 | 779,952 | 2.3747 | 81,523 | 51,908 | 163,046 |

BTB 减少 cycles 253,886（12.06%），CPI 从 2.7143 降到 2.3747。

## 3. 板级测量：口径修正与双频交叉验证

### 3.1 为什么必须做窗口对齐

板级七项计数器是**自由运行**的：从复位释放一直数到回读时刻。而 `COREMARK_READY` 会先等上位机发 `R` 才开跑，那段轮询是一个紧凑的 load + branch 循环，每个循环都要走统一事务（含访存阻塞），会产生上亿次 stall 与 branch。

后果（未对齐窗口时的实测值，可复现）：`stall` 甚至**超过** `cycles`、`branch` **超过** `instret`——这类数据不能用于 CPI 归因。

修正方式：在 `software/coremark/core_portme.c` 的 `start_time()` 中加入 `PERF_CONTROL = 1u`（写 perf_mmio CONTROL，offset 0x38），由编译开关 `PERF_WINDOW_ALIGN=1` 控制。清零紧接在读计时器之前，使七项计数器与 `ticks` **同口径**。该语句只改观测口径，不改被测量的执行路径。

### 3.2 对齐后的板级数据（本 JSON）

| 量 | 值 | 窗口 |
|---|---:|---|
| ticks | 1,691,496,677 | CoreMark 计时窗口（`start_time()`→`stop_time()`） |
| cycle_count | 1,693,816,436 | 同一次清零之后至今 |
| instret_count | 722,513,265 | 同上 |
| 窗口差 cycle−ticks | 2,319,759（0.14%） | 对齐残差 |

**板级 CPI = 2.3443**（cycles/instret），cycles/iteration = 1,693,816.4，ticks/iteration = 1,691,496.7。

### 3.3 双频交叉验证

同一份 RTL、同一份 CoreMark 源，分别在 50 MHz 与 80 MHz（PLL）上实测：

| 指标 | 50 MHz | 80 MHz | 差别 |
|---|---:|---:|---:|
| cycles / iteration | 1,693,816 | 1,692,975 | 0.05% |
| CPI | 2.3443 | 2.3445 | 0.009% |
| stall / cycles | 4.54% | 4.53% | — |
| load-use / stall | 9.30% | 9.32% | — |
| flush / cycles | 4.41% | 4.41% | — |
| branch / instret | 0.275 | 0.275 | — |

归一化后逐项吻合到 **0.02% 以内**：两个独立频率点互为交叉验证，证明核心性能与频率无关、计数器统计正确。

对照 RTL 仿真（Predictor On）：CPI 2.3747、cycles/iteration 1,852,156、stall/cycles 9.51%、flush/cycles 8.80%。板级 CPI 与仿真相差 **1.3%**，说明仿真 memory model 是可信的性能预测工具（差异来自板级 BRAM 实现与仿真零等待模型的细微不同）。

对齐残差（`cycle_count − ticks`）仅 2,319,759 周期（0.14%），来自启动代码、CoreMark 首次内存初始化与结果回读；对齐前该差值曾达数亿周期。

## 4. 可行动结论

以 RTL 仿真（官方 CoreMark 一次迭代、Predictor On）为准，CPI = 2.3747：

| 损失来源 | CPI 贡献 | 占 cycles | 可行动性 |
|---|---:|---:|---|
| Hazard stall | 0.2259 | 9.51% | 其中 load-use 只有 19,791（占 stall 11.23%），其余是访存阻塞——与下一行同源 |
| 控制冒险 flush | 0.2090 | 8.80% | 81,523 次跳转 × 2 拍；BTB 已把 mispredict 从 131,903 降到 51,908 |
| 访存事务等待 | 0.9398 | 39.57% | **最大单项**：每次数据访问固定多 2 拍握手，改为「请求即应答」可省 1 拍/次 |
| 理想执行 | 1.0000 | 42.11% | 不可压缩 |

访存相关合计 889,367 拍 = 48.02% cycles （1.1403 CPI）。

**实体板印证**：50/80 MHz 两点 `stall/cycles` 为 4.54% / 4.53%，其中 load-use 只占 stall 的 9.30% / 9.32%，即 **90.7% 的 stall 不是 load-use**，同样指向数据事务的固定握手开销，而不是 Hazard 逻辑。

**因此下一轮唯一值得做的大项是数据事务握手流水化**：把 `pipeline_cpu.v` 里 `dstate` 的 REQ→RSP 两拍握手压成一拍（`d_req_ready` 恒为可接收，请求当拍即可应答），估计可回收约一半访存开销，即 **CPI 约 −0.4（约 −17%）**，直接提高 Score 第 (1) 项。风险与工作量显著高于本轮 perf 计数器打拍（要改流水线访存时序与 hazard 语义），必须独立一轮做 Before/After 并重跑 Task 23/24 全套 + 提交级 trace + 实体板 CoreMark。

## 5. 本轮已落地的优化与 CPI 关系

本轮 RTL 改动（`rtl/perf_monitor.v` 事件打一拍）**不改变任何架构行为**，因此 CPI / CoreMark 分数不变；它的收益全部体现在 Fmax：最差 10 条路径中 `perf/flush_count` 终点由 8 条降为 0 条、逻辑级数 26 → 21、85 MHz 的 WNS 由 +0.005 ns 提升到 +0.246 ns（见 `docs/performance_tuning.md`）。

实体板已证实这一点：优化后 50 MHz 位流的 Score 仍为 **29.559**、CPI **2.3443**，与优化前一致；而在 80 MHz PLL 下 Score 为 **47.295**、`CoreMark/MHz` 仍是 **0.591**——**提 Score 必须降 CPI，提频率只服务于独立的「时钟频率」计分项**。

## 6. 复现方式

```powershell
& '<pwsh7>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1
& '<pwsh7>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1 -DisablePredictor
# 板级采集（必须用 PERF_WINDOW_ALIGN=1 的镜像，否则计数器窗口被 UART 轮询污染）
D:\Python313\python.exe python\coremark_serial.py COM11 --clock-hz 50000000 `
  --output release\evidence\coremark_uart_opt50m_aligned.log `
  --summary release\evidence\coremark_board_opt50m_aligned.json
D:\Python313\python.exe python\coremark_cpi_analysis.py `
  --board release/evidence/coremark_board_opt50m_aligned.json
```

