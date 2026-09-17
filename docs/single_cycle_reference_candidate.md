# Single-Cycle Reference Candidate

> 版本：`single_cycle_reference_candidate`
> 建立日期：2026-09-12
> 状态：Task 13 候选基线；不是 `single_cycle_stable`。

## 目的

本候选版本以 Task 12 已通过的 `rtl/single_cycle_cpu.v` 为基础，为后续 GCC/SoC Regression 和五级流水线逐条退休比较提供可重复的架构状态与提交级观察结果。它不改变 RV32I 执行语义，也不代表 Task 17 的正式冻结版本。

## Architectural state

- `PC`。
- Register File 的 `x1` 至 `x31`；`x0` 固定为 0，不作为可写架构状态。
- 测试指定的 DMEM word。

组合 ALU 信号、译码控制线和未来流水线级间寄存器都属于内部实现状态，不参与等价比较。

## Commit trace contract

每个非 Reset 单周期都退休当前 `PC` 的一条指令，输出：

| 字段 | 含义 |
|---|---|
| `trace_valid` | 非 Reset 时为 1；Reset 时为 0。未来流水线的 Bubble/Flush 必须为 0。 |
| `trace_pc` / `trace_instruction` | 退休指令的 PC 与机器码。 |
| `trace_rd_we` / `trace_rd_addr` / `trace_rd_data` | 实际架构寄存器写回。写 `x0` 不计为写回。 |
| `trace_mem_we` / `trace_mem_addr` / `trace_mem_data` / `trace_mem_wstrb` | 实际 Store：原始字节地址、按 byte lane 对齐的写数据及字节写使能。 |

不具备对应副作用的字段固定为 0。Branch、Jump、合法 `FENCE` 与非法/未支持指令同样退休；错误路径上的流水线指令不得退休。

## 当前自动验证

运行：

```powershell
.\scripts\run_single_cycle_reference_trace_tb.ps1
```

该测试运行两份相同候选实例，检查 Task 11 固定程序的 10 条提交记录（算术、Load、Store、Branch、JAL），比较 `x1`～`x31`、指定 DMEM，并演示篡改一项 `rd_data` 会被识别为首条不一致字段。

## 已知限制

- 当前 trace 验证使用固定行为级 IMEM/DMEM 与 Task 11 程序；GCC、统一事务接口、MMIO、UART/GPIO 和正式全量 Regression 属于 Task 14～17。
- 单周期 Core 的逐根统一事务端口将在 Task 15 评审后冻结。
- 只有 Task 17 正式 Regression 全部通过后，才允许冻结为 `single_cycle_stable`。
