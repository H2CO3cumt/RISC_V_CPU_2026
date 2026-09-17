# 性能基线与证据边界

`run_performance_report.ps1` 从真实 GCC Pipeline 的 `perf.actual` 生成 CPI、stall、load-stall 和 flush 表。`run_release_evidence.ps1` 从正式 PDS 报告、bitstream 和官方 CoreMark RTL 仿真日志生成 `release/evidence/automated_metrics.{json,md}`，避免手工抄数。

当前可自动追溯的 Task 28 配置为 RV32I/ILP32、GCC 15.2.0、`-O2`、2K performance seeds、静态 BRAM。同步 FPGA memory model 的一迭代官方 CRC 仿真为 1,923,077 ticks、CPI 2.6682、CoreMark/MHz 0.520000。按 50 MHz 线性换算为 26.0000 CoreMark，正式 1000 次镜像的计时区间约 38.46154 秒，满足不少于 10 秒的配置要求。该换算属于经过 RTL 验证的板级预期值，在实体板串口日志产生前不得表述为实测成绩。

Task 28 PDS 2024.2-SP2 报告：setup WNS +5.350 ns、慢角 hold +0.313 ns、估算 Fmax 68.2594 MHz、2438 LUT、1333 FF、33 DRM；正式交互式 bitstream SHA-256 为 `3204B46D8B447BB8206A914FA4A7CFBE6560144CE15DF6DD2A9C8A96884A3581`。正式镜像上电等待串口 `R` 后开始计时，避免串口连接时间污染成绩。

## 分支预测 Before / After（2026-09-16）

使用同一 RV32I CoreMark 一次迭代镜像、固定零等待行为存储模型完成 Predictor Off/On 对比，两次均通过官方 CRC：

| 配置 | cycles | retired | CPI | BTB hit | misprediction |
|---|---:|---:|---:|---:|---:|
| Predictor Off | 2,106,042 | 775,901 | 2.7143 | 0 | 131,903 |
| Predictor On | 1,852,156 | 779,952 | 2.3747 | 203,492 | 51,908 |

Predictor On 减少 253,886 cycles，即 12.06%；共解析 213,756 条条件分支，BTB 命中率约 95.20%，方向/目标综合预测正确率约 75.72%。退休条数的轻微差异来自 CoreMark 打印的计时数值不同，官方 CRC 与最终功能结果一致。以上均为 RTL 仿真 Before/After。唯一最终 PDS 配置为 3459 LUT、3129 FF、5.5 个 DRM18K 等效块，50 MHz setup WNS +2.661 ns、hold WHS +0.312 ns、估算 Fmax 57.6735 MHz；实体板 CoreMark 仍只接受真实串口日志。
