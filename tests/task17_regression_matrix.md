# Task 17 Formal Regression Matrix

> 状态：通过。所有必测项已接入正式入口并连续两次 PASS。

> 正式运行：2026-09-13，完整入口连续两次均为 14 passed、0 failed。`single_cycle_stable` 标签尚待创建。

## 运行方式

```powershell
./scripts/run_task17_regression.ps1
```

默认模式会完成所有彼此独立的 suite，再汇总 PASS/FAIL；任一失败时总入口以非零退出。调试单一根因时可加 `-FailFast`，在首个失败处停止。

## 已接入入口的 suite

| Suite | 现有脚本 | 主要验收 |
|---|---|---|
| RV32I 与候选 trace | `run_task13_regression.ps1` | Task 12 指令/上游 RV32UI，候选提交级 trace，两次运行一致性 |
| GCC 程序 | `run_task14_regression.ps1` | `c_smoke`、`array_control` 的启动、函数、循环、`.data`/`.bss` |
| Core 事务 | `run_task15_data_interface_tb.ps1` | 固定/随机背压、请求字段稳定、唯一响应 |
| 互连与 RAM-only SoC | `run_task15_interconnect_tb.ps1`、`run_task15_core_interconnect_tb.ps1` | 地址译码、未映射响应、外部 RAM 和未修改 Core 的端到端执行 |
| UART/GPIO 独测 | `run_uart_*_tb.ps1`、`run_gpio_mmio_tb.ps1` | UART TX/RX、邮箱/状态、GPIO 和写副作用唯一性 |
| 外设互连与端到端 SoC | `run_task16_peripheral_interconnect_tb.ps1`、`run_task16_soc_harness_tb.ps1` | UART/GPIO MMIO 事务；GCC 镜像输出 GPIO=`0xAA` 和 `Hello RISC-V!` |
| 独立 SoC 配置与性能导出 | `run_task17_soc_config_tb.ps1` | RAM+GPIO、RAM+UART 分别复用未修改 Core；导出提交记录、`x1`～`x31`、RAM、外设结果与 CPI，并连续两次逐记录一致 |

## 冻结前缺口（已关闭）

1. RAM+UART、RAM+GPIO 独立端到端配置均复用未修改 `single_cycle_cpu.v`，并通过 state/performance/trace golden。
2. 系统 trace 已固化；`rd_data` 与 Store `mem_data` 篡改均通过字段级首差自检。
3. Task 14 `c_smoke`、`array_control` 已作为 `gcc_evidence_golden` suite 接入总入口。
4. 扩展后的总入口连续两次均为 14 passed、0 failed。

## 冻结判定

仅当本矩阵所有必测项 PASS、缺口全部关闭，并在 `docs/progress.md` 记录测试镜像、工具版本、结果与已知限制后，才允许创建可恢复的 `single_cycle_stable` 标签或等价识别版本，并进入 Task 18。
