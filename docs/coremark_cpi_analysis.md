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
| cycle_count（CPI 分母） | 2,078,613,829 | 上电至今全窗口周期数 |
| instret_count | 914,907,729 | 提交指令数 |
| iterations | 1,000 | CoreMark 迭代次数 |
| CPI = cycle/instret | 2.2719 | 全窗口 CPI |
| cycles/iteration（Score 口径） | 1,691,496.7 | 每迭代周期数 |

窗口差 = cycle_count − ticks = 387,117,152（占 cycle_count 18.6%），来自启动代码、串口等待与回读。

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

## 3. 板级窗口校正

板级 `cycle_count / instret_count` 不能直接当 CoreMark 内核 CPI 用：三个计数的窗口并不相同。

| 量 | 值 | 窗口 |
|---|---:|---|
| ticks | 1,691,496,677 | 仅 CoreMark 计时窗口（`start_time()`→`stop_time()`） |
| cycle_count | 2,078,613,829 | 上电复位释放→回读时刻（含启动代码与串口等待） |
| instret_count | 914,907,729 | 同 cycle_count 窗口 |

CoreMark 计时窗口每迭代周期数 = ticks/iterations = 1,691,496.7 周期/迭代。

仿真侧同一指标是 1,852,156 周期/次执行，但两者**不是同一个工作量**：仿真镜像用 `ITERATIONS=1` 编译（CoreMark 的迭代循环被编译器优化掉，只跑一遍工作负载），板级镜像是 `ITERATIONS=1000` 的真实迭代循环，每轮迭代还要付出迭代管理、计时与运行上下文开销。

加上板级三个计数器窗口互不相同，**不能用板级 counter 反推 CoreMark 内核 CPI**，也不能把仿真单次执行的 CPI 直接当作板级 CPI 宣称。

板级计数器在本项目中的正确用途是：(1) 提供 Score 口径的 `ticks`；(2) 校验事件定义与量级；(3) 作为 ILA 波形的对齐基准。

**CPI 分解的权威数据是 RTL 仿真**（同一镜像、同一窗口、可逐周期核对），见第 2 节。

板级启动与交互开销（不计入 `ticks`，但计入 `cycle_count`）：387,117,152 周期，占 `cycle_count` 18.62%，来自启动代码、CoreMark 首次内存初始化、`COREMARK_READY` 串口等待与结果回读。

## 4. 可行动结论

以 RTL 仿真（官方 CoreMark 一次迭代、Predictor On）为准，CPI = 2.3747：

| 损失来源 | CPI 贡献 | 占 cycles | 可行动性 |
|---|---:|---:|---|
| Hazard stall | 0.2259 | 9.51% | 其中 load-use 只有 19,791（占 stall 11.23%），其余是访存阻塞——与下一行同源 |
| 控制冒险 flush | 0.2090 | 8.80% | 81,523 次跳转 × 2 拍；BTB 已把 mispredict 从 131,903 降到 51,908 |
| 访存事务等待 | 0.9398 | 39.57% | **最大单项**：每次数据访问固定多 2 拍握手，改为「请求即应答」可省 1 拍/次 |
| 理想执行 | 1.0000 | 42.11% | 不可压缩 |

访存相关合计 889,367 拍 = 48.02% cycles （1.1403 CPI）。按仿真 CoreMark 访存指令数估算，数据事务从 2 拍握手压到 1 拍可回收约一半该项，即 CPI 约 −0.4（约 −17%），这是当前性价比最高但需要改动流水线访存时序的候选；风险与工作量高于 perf 计数器打拍，因此本轮只作为下一轮建议，不在本轮引入。

## 5. 本轮已落地的优化与 CPI 关系

本轮 RTL 改动（`rtl/perf_monitor.v` 事件打一拍）**不改变任何架构行为**，因此 CPI / CoreMark 分数不变；它的收益全部体现在 Fmax（见 `docs/performance_tuning.md`）。
提 Score 必须降 CPI，提频率服务于独立的「时钟频率」计分项——两者收益来源不同。

## 6. 复现方式

```powershell
& '<pwsh7>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1
& '<pwsh7>' -NoProfile -File scripts\run_coremark_pipeline_tb.ps1 -DisablePredictor
D:\Python313\python.exe python\coremark_serial.py COM11 `
  --output release\evidence\coremark_uart.log --summary release\evidence\coremark_board.json
D:\Python313\python.exe python\coremark_cpi_analysis.py
```

