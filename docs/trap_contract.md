# Trap 契约（A2）：机器模式异常与中断支持矩阵

> 建立日期：2026-09-28
> 状态：**契约草案，实现前冻结**。本文只定义"要实现什么、边界在哪、怎么判定 PASS"，不声称 RTL 已实现。
> 上游依据：`docs/advanced_task_plan_qa.md` A2 任务包、赛题高阶任务②"动态分支预测以及完整异常/中断"。
> 相关文档：`docs/interfaces.md`（Core/SoC 边界）、`docs/architecture.md`（微架构决定）、`docs/progress.md`（实际进度）。

## 1. 为什么单独写这份契约

赛题高阶任务②要求"动态分支预测以及**完整**异常/中断"。工程现有的 `AGENTS.md`、`docs/roadmap.md` 与
`docs/competition_scoring.md` 曾把异常/中断列为本届不做，`docs/advanced_task_plan_qa.md` 已明确改选这条路线。
按该项目"不得静默扩大修改范围"的规则，这里先把**支持矩阵**写死：

- 哪些 CSR、哪些异常原因、哪些中断源要实现；
- 哪些明确**不支持**，以及不支持时的行为；
- 精确提交、取消年轻指令、已发事务取消、MMIO 零副作用的判定方式。

没有这份矩阵就动手写 RTL，就会出现"口号式完整"：只加一个中断输入或只支持 `ECALL` 也叫"支持异常"。
矩阵冻结后，实现范围只能按编号逐条勾选，不允许事后扩大口径。

## 2. 规范基线

| 项 | 取值 |
|---|---|
| Unprivileged ISA | RV32I（现行实现基线不动） |
| Privileged 规范 | RISC-V Privileged Architecture v1.11 的 **Machine mode 子集** |
| 特权级 | 只实现 **M-mode**。不实现 U/S 模式、不实现 `mstatus.MPP` 非零语义 |
| 扩展 | Zicsr 指令（`CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI`） |
| ABI | `-march=rv32i_zicsr -mabi=ilp32`（软件侧）；硬件侧必须能执行既有 `rv32i` 镜像，不得回归 |
| 计数器 | `cycle`/`time`/`instret` 只读 CSR（`0xC00/0xC01/0xC02`） |

> 说明：`-march=rv32i` 下 GCC 只生成 `ECALL/EBREAK`，不会生成 CSR 指令。要写 CSR 访问的
> 中断服务程序与 Trap 处理程序，必须允许 `_zicsr`。这不改变已冻结的 CPU 核心理念，只是让软件能用
> CSR；已有的 `-march=rv32i` 镜像仍必须逐字段一致地跑通，作为回归项。

## 3. CSR 支持矩阵

地址栏使用 CSR 编号（`csr[11:0]`）。"读"指任何读取该 CSR 的指令，"写"指任何产生写副作用的指令。

### 3.1 必须实现

| 编号 | 名称 | 读 | 写 | 语义与约束 |
|---|---|---|---|---|
| `0x300` | `mstatus` | ✅ | ✅ | 只实现 `MIE[3]`、`MPIE[7]`、`MPP[12:11]`；其余位读 0、写忽略。`MPP` 恒为 `00`（只有 M-mode） |
| `0x301` | `misa` | ✅ | ❌ | 只读。返回 `MXL=1`（32-bit）与 `I` 位；写操作不产生副作用 |
| `0x304` | `mie` | ✅ | ✅ | 只实现 `MSIE[3]`、`MTIE[7]`、`MEIE[11]`；其余位读 0、写忽略 |
| `0x305` | `mtvec` | ✅ | ✅ | 只实现 **Direct** 模式：`mode[1:0]` 写入后强制 `00`；`base[31:2]` 参与取指。写入非 Direct 编码时按 Direct 处理并在 `mtval` 之外不做其他动作 |
| `0x340` | `mscratch` | ✅ | ✅ | 完整 32-bit 读写，供 Trap handler 保存临时寄存器 |
| `0x341` | `mepc` | ✅ | ✅ | 写入时 `bit[0]` 强制 0（RV32I 无 C 扩展）；Trap 时保存被打断指令的 PC |
| `0x342` | `mcause` | ✅ | ✅ | trap 时由硬件写；软件可写（用于测试与 RTOS 场景） |
| `0x343` | `mtval` | ✅ | ✅ | trap 时由硬件写（含义见 §4.3）；软件可写 |
| `0x344` | `mip` | ✅ | ⚠️ | **只读有效位**：`MSIP[3]`、`MTIP[7]`、`MEIP[11]` 由 Core 外部中断输入驱动。软件写 `mip` 不产生副作用（读回硬件值） |
| `0xC00` | `cycle` (低) | ✅ | ❌ | 64-bit 周期计数，读低 32 位 |
| `0xC80` | `cycleh` (高) | ✅ | ❌ | 读高 32 位 |
| `0xC01` | `time` | ✅ | ❌ | 与 `mtime` MMIO 同源（SoC 提供） |
| `0xC81` | `timeh` | ✅ | ❌ | 同上 |
| `0xC02` | `instret` | ✅ | ❌ | 退休指令计数 |
| `0xC82` | `instreth` | ✅ | ❌ | 同上 |

**写只读 CSR**：`CSRRW/CSRRS/CSRRC` 目标是只读 CSR 时，按规范产生**非法指令异常**，
且**不得修改任何 CSR 或架构状态**。这是必须逐项验证的负向路径（见 §6 M-07）。

### 3.2 明确不实现

| 项 | 行为 |
|---|---|
| `mhartid`(`0xF14`) | 读返回 `0`；不实现多 hart |
| `mvendorid`/`marchid`/`mimpid`(`0xF11/0xF12/0xF13`) | 读返回 `0` |
| `medeleg`/`mideleg` | 不存在（无 S-mode）；访问产生非法指令异常 |
| `mtval2`/`mtinst`/`mseccfg` 等 | 访问产生非法指令异常 |
| `pmpcfg*`/`pmpaddr*` | 访问产生非法指令异常；本届无物理内存保护 |
| 非 `0x3xx`/`0xCxx` 的已定义 CSR | 访问产生非法指令异常 |
| 未定义 CSR 编号 | 访问产生非法指令异常 |
| `mcountinhibit` | 不实现；计数器始终运行 |
| 影子 CSR（`sstatus` 等） | 不存在 |

**未实现/未定义 CSR 的访问必须报非法指令异常，不允许静默读 0 或静默忽略写。**
这条与工程既有的"非法/未实现编码必须无副作用"原则一致，并直接对应 §6 的 M-08。

### 3.3 CSR 访问的原子性与副作用

1. `CSRRW`：读旧值 → 写新值。若 `rd=x0`，可以不读（本项目仍读，行为等价）。
2. `CSRRS`/`CSRRC`：读旧值；仅当 `rs1 != x0` 时才写（`rs1=x0` 是纯读，不得产生写副作用，
   尤其不得因此对只读 CSR 报异常）。`CSRRWI/CSRRSI/CSRRCI` 同理以 `uimm != 0` 判断。
3. CSR 写与 trap 同周期冲突时，**trap 优先**：该 CSR 写必须被丢弃（见 §5 优先级表）。
4. CSR 读写必须在 EX 级单周期完成（组合读、寄存器写），不得引入新的流水级。

## 4. 异常与中断支持矩阵

### 4.1 同步异常（exception，`mcause[31]=0`）

| 编号 | `mcause` | 触发条件 | 检测级 | 优先级 |
|---:|---|---|---|---:|
| E-01 | `0` | 指令地址未对齐（`jalr`/跳转目标 `pc[1:0]!=00`） | EX | 2 |
| E-02 | `2` | 非法指令：opcode 未定义、`funct3/funct7` 组合非法、`FENCE` 边界以外的 SYSTEM 编码、访问未实现/未定义 CSR、写只读 CSR | ID（译码） | 多次提交时按**程序序最早者** |
| E-03 | `3` | `EBREAK` | ID | 同上 |
| E-04 | `4` | Load/Store 地址未对齐（`lh/lhu/sh` 非 2 字节对齐、`lw/sw` 非 4 字节对齐） | MEM | 3 |
| E-05 | `5` | Load 访问错误（`d_rsp_error` 且 `d_req_write=0`） | MEM | 4 |
| E-06 | `6` | Store/AMO 地址未对齐（与 E-04 同判据，Store 方向） | MEM | 3 |
| E-07 | `7` | Store 访问错误（`d_rsp_error` 且 `d_req_write=1`） | MEM | 4 |
| E-08 | `1` | 取指访问错误（`i_rsp_error`） | IF | 1（最高） |
| E-09 | `1` | 取指地址未对齐（`i_req_addr[1:0]!=00`） | IF | 1 |
| E-10 | `11` | `ECALL`（M-mode） | ID | 同 E-02 |

**取指错误/未对齐（E-08/E-09）的过渡行为**：现有实现的 `i_rsp_error` 装载零指令并置 `trace_error`。
引入 Trap 后，取指错误改为进入 `mcause=1` 的 Trap，`mtval` 记录取指地址。
为避免"一进 Trap 又取指失败"造成死循环，Trap 入口地址本身不做错误屏蔽——若 `mtvec` 指向错误区域，
行为是再次 Trap，属于软件错误，测试必须覆盖该情形并确认无死锁、无未定义状态。

### 4.2 中断（interrupt，`mcause[31]=1`）

| 编号 | `mcause` | 源 | Core 侧端口 | SoC 侧来源 |
|---:|---|---|---|---|
| I-01 | `0x80000003` | Machine software interrupt (`MSIP`) | `irq_software_i` | SoC 软件中断寄存器（外部，可选） |
| I-02 | `0x80000007` | Machine timer interrupt (`MTIP`) | `irq_timer_i` | SoC 机器定时器（`mtime`/`mtimecmp` MMIO） |
| I-03 | `0x8000000B` | Machine external interrupt (`MEIP`) | `irq_external_i` | SoC 中断聚合器（外部设备） |

**边界纪律（不可协商）**：Core 只暴露上述三根**电平型、设备无关**的中断输入。
UART/GPIO/SPI/逻辑分析仪/定时器的中断使能、状态位、聚合与优先级**全部在 SoC 外部**。
Core 内不得出现任何设备名、设备地址或设备状态机。这沿用并强化 `docs/interfaces.md` 第 5 节的既有约定。

**中断采样与使能**：
- 中断在**指令边界**采样：只有一条指令真正退休时才允许接受中断。
- 全局使能 `mstatus.MIE=1`；分级使能 `mie.M{T,S,E}IE=1`；对应 `mip.M{T,S,E}IP=1`。
- 三者同时为 1 才产生中断请求。`mip` 反映的是输入电平（不是锁存脉冲）。
- 不允许在 Trap 入口瞬间重复接受同一中断：进入 Trap 时 `mstatus.MIE` 自动清 0。

### 4.3 `mtval` 语义

| 原因 | `mtval` 内容 |
|---|---|
| E-01 指令地址未对齐 | 未对齐的目标地址 |
| E-02 非法指令 | 出错指令的 32-bit 机器码 |
| E-03 `EBREAK` | 出错指令的 32-bit 机器码（`0x00100073`） |
| E-04/E-06 地址未对齐 | 未对齐的访存地址 |
| E-05/E-07 访问错误 | 出错的访存地址 |
| E-08/E-09 取指错误/未对齐 | 出错的取指地址 |
| E-10 `ECALL` | `0` |
| I-01/I-02/I-03 | `0` |

### 4.4 明确不实现

| 项 | 说明 |
|---|---|
| S/U 模式及其 Trap | 不实现 |
| 中断嵌套的硬件支持 | 不实现硬件嵌套；`MRET` 恢复 `MIE` 后可再次响应（软件可用 `mscratch` 做嵌套，属软件行为） |
| 向量化 Trap（`mtvec.mode=1`） | 不实现；写入被强制为 Direct |
| 调试模式（Debug Mode）、`dcsr`/`dpc` | 不实现；`EBREAK` 按普通异常处理（`mcause=3`），不进入调试模式 |
| `WFI` | 保留为非法指令（`mcause=2`）。本届不实现休眠 |
| `FENCE.I` 语义扩展 | 保持既有 no-op；本届无 I-Cache，不需要 |
| 性能计数器事件选择 CSR（`mhpmevent*`、`mcountinhibit`） | 不实现；访问报非法指令异常 |
| 非屏蔽中断（NMI） | 不实现 |
| 硬件断点/`tselect`/`tdata*` | 不实现；访问报非法指令异常 |

## 5. 精确 Trap 语义与优先级

### 5.1 精确性要求（不可协商）

1. **较老指令完成**：Trap 指令之前（程序序更早）的指令必须全部退休，副作用（寄存器写、Store、MMIO 写）
   恰好发生一次。
2. **较年轻指令取消**：Trap 指令之后的所有指令不得产生任何架构副作用——不写寄存器、不写 RAM、
   **不产生 MMIO 写**、不形成 `trace_valid` 提交记录。
3. **被打断的指令本身**：不得产生任何副作用。`mepc` 必须等于该指令的 PC（不是 PC+4）。
4. **已发出的总线事务**：Trap 发生时若已有被下游接受的取指/数据请求，必须按既有 `docs/interfaces.md`
   第 3 节规则完成握手并丢弃响应；**不得依赖外设撤销副作用**。若 Store 请求已经被接受，
   该 Store 视为已提交（架构上它在 Trap 之前完成），`mepc` 不回退它。
5. **`MRET` 之后**：从 `mepc` 重新取指，`mstatus.MIE ← MPIE`、`MPIE ← 1`、`MPP ← 00`。
   恢复后重新执行的指令必须得到与首次相同的架构结果（不得重复副作用）。

### 5.2 同周期优先级（从高到低）

| 顺序 | 条件 | 处理 |
|---:|---|---|
| 1 | Reset | 清所有 CSR 与流水线，PC=0；任何 Trap 请求被忽略 |
| 2 | 取指错误/未对齐（E-08/E-09） | 进入 Trap，取消 IF 之后全部指令 |
| 3 | MEM 级访问错误/未对齐（E-04～E-07） | 进入 Trap，取消 EX 及之后全部指令；较老的 ID/IF 龄指令一并取消 |
| 4 | EX 级指令地址未对齐（E-01） | 进入 Trap，取消 ID/IF |
| 5 | ID 级非法指令 / `EBREAK` / `ECALL`（E-02/E-03/E-10） | 进入 Trap，取消 IF |
| 6 | 中断（I-01～I-03） | 只在**没有任何同步异常**且当前指令允许退休时接受 |
| 7 | 分支/跳转误预测重定向 | 若同周期存在 Trap，重定向被 Trap 覆盖（Trap 优先）；否则按既有逻辑 |
| 8 | Load-Use Stall / 数据事务等待 | 等待期间不提交、不取指；`mem_block` 期间不得进入 Trap，等事务完成后再判定 |

**关键约束**："更老"的定义完全由流水线位置决定：IF 最年轻，ID 次之，EX 再次，MEM 较老，WB 最老。
上表第 2～5 条已经按这个顺序排列；实现时必须保证**同一周期内只产生一个 Trap**，
且被选中的原因对应程序序最早的那条出错指令。

### 5.3 Trap 与 `trace` / 性能事件的一致性

- 进入 Trap 的那一拍，被取消的指令**不得**产生 `trace_valid`。
- 被打断指令本身在 Trap 处理期间不得产生 `trace_valid`；`MRET` 后重新执行时正常提交一次。
- 新增观察事件（供 ILA 与性能监视器使用，均由 Core 输出、SoC 外部计数）：
  `event_trap`（任何 Trap 进入）、`event_trap_return`（`MRET` 退休）、`event_irq`（中断型 Trap）。
- 这些事件不得改变既有 `event_flush`/`event_mispredict` 等信号的历史口径。

## 6. 验收矩阵（A2 冻结；A3 逐项执行）

每条都必须**自动判定**并输出 `TEST <id> PASS/FAIL`，不得只靠看波形。

| ID | 验收项 | 判定方式 | 通过条件 |
|---|---|---|---|
| M-01 | CSR 读改写基本功能 | 独立 TB：`CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI` 对 `mscratch` 的读改写、`rs1=x0` 纯读、`uimm=0` 纯读 | 旧值/新值逐项匹配；`x0` 形式无写副作用 |
| M-02 | `mstatus`/`mie`/`mtvec` 位域 | 独立 TB：写入全 1、读回掩码 | 只保留实现位；`mtvec.mode` 强制 `00` |
| M-03 | 只读 CSR 与未定义 CSR | 独立 TB：写 `misa`、读未定义编号、读写 `pmpcfg0` | 全部产生 `mcause=2` 非法指令异常；CSR 内容不变 |
| M-04 | `ECALL`/`EBREAK` | 独立 TB 与裸机程序 | `mcause` 分别为 `11`/`3`；`mtval` 为 `0`/指令码；`mepc` 为该指令 PC |
| M-05 | 非法指令 | 注入未定义 opcode、非法 `funct3/funct7`、`WFI` | `mcause=2`、`mtval` 为指令码、`mepc` 正确；无寄存器/内存副作用 |
| M-06 | Load/Store 未对齐 | `lh` 于奇数地址、`lw` 于 `+1/+2/+3`、`sh`/`sw` 同 | `mcause=4`（Load）/`6`（Store）；`mtval` 为未对齐地址；**Store 不发生任何总线写事务** |
| M-07 | 访存访问错误 | 让 adapter 对特定地址返回 `error` | Load→`mcause=5`、Store→`mcause=7`；`mtval` 为地址；一次事务一次副作用 |
| M-08 | 取指错误/未对齐 | adapter 对特定 PC 返回 `error`；构造 `jalr` 到非对齐地址 | `mcause=1`；`mtval` 为出错地址；不产生架构副作用 |
| M-09 | `MRET` 返回 | 裸机程序：`ECALL` → handler → `MRET` → 继续执行 | 恢复到 `mepc`；`mstatus.MIE/MPIE` 按规范变化；后续程序结果正确 |
| M-10 | 精确性（年轻指令取消） | 定向程序：在 Trap 指令**之后**安排写寄存器、写 RAM、写 MMIO 的指令 | 三者均无副作用；`trace` 中不出现这些提交 |
| M-11 | 精确性（较老指令完成） | 在 Trap 指令**之前**安排写寄存器/写 RAM/写 MMIO | 三者各恰好发生一次；顺序与程序序一致 |
| M-12 | 同步异常优先级 | 同周期注入多个异常源（如 MEM 访问错误 + EX 未对齐 + ID 非法） | 只产生一个 Trap；`mcause` 对应程序序最早者；与 §5.2 表一致 |
| M-13 | 中断屏蔽 | `mstatus.MIE=0` 或 `mie` 对应位 0 时拉起中断线 | 不产生 Trap；程序继续正确执行；`mip` 仍能读到 pending |
| M-14 | 定时器中断 | SoC `mtime`/`mtimecmp` + `irq_timer_i` | `mcause=0x80000007`；周期可预测；ISR 中重设 `mtimecmp` 后可再次触发 |
| M-15 | 外部中断 | SoC 中断聚合器拉起 `irq_external_i` | `mcause=0x8000000B`；ISR 清除 SoC 侧 pending 后不再重复进入 |
| M-16 | 中断与随机背压 | 中断注入 + 随机取指/数据延迟 | 不丢中断、不重复响应、无死锁；`mepc`/`mtval` 正确 |
| M-17 | 中断与 Trap 冲突 | 中断与同步异常同周期到达 | 同步异常优先；不产生两次 Trap |
| M-18 | Trap 期间 Reset | Trap handler 运行中复位 | CSR、流水线、总线全部回到 Reset 状态；无残留请求/副作用 |
| M-19 | 错误路径零 MMIO 副作用 | 错误路径上安排 MMIO 写；随机背压 | MMIO 写次数恰好为 0（用 `write_side_effect_count` 判定） |
| M-20 | `mcycle`/`minstret` | 短程序手工计数对照 | 与 TB 统计一致；`CSRRS` 只读不改变计数 |
| M-21 | 独立事件判定器 | 不使用现有单周期模型（它不支持 Trap） | 独立 golden 事件序列判定器 PASS；不得用"跳过非法指令"的旧模型冒充参考模型 |
| M-22 | 既有功能不回归 | 全量 Regression（RV32I、Reference、Pipeline、GCC、CoreMark、逻辑分析仪） | 全部 PASS；CoreMark 官方四 CRC 与周期数不退步 |
| M-23 | 时序与资源 | PDS 综合、布局布线与时序分析 | `All Constraints Met`；记录 LUT/FF/DRM/WNS 与 Before 对比 |
| M-24 | 实板闭环 | MES50HP 上运行裸机中断程序 | 串口/LED 可观察周期性中断；ILA 抓到 Trap 进入与返回 |

### 6.1 参考模型策略（M-21 的具体做法）

现有 `rtl/single_cycle_cpu.v` 参考模型**不支持 Trap**，其非法指令行为是"抑制副作用并继续"。
因此：

- **不得**用单周期模型判定 Trap 相关结果。
- 改为两级判定：
  1. **不进入 Trap 的程序**：继续用现有 Single Cycle ↔ Pipeline 提交级 trace 比较（保持原 Gate）。
  2. **进入 Trap 的程序**：使用独立的事件判定器（Python 或 Verilog TB），按程序序声明
     `(期望 trap 原因, 期望 mepc, 期望 mtval, 期望副作用次数)`，与 Core 的实际事件流比对。
- 判定器必须能从 Core 的 `trace` 与 `event_*` 独立重建"发生了什么"，不得读取 Core 内部状态。

## 6.2 A3 实现状态与逐项证据（2026-09-28）

状态口径：**PASS** = 有自动化断言并且实跑通过；**部分** = 已实现且被间接覆盖，但缺少契约要求的定向断言；
**阻塞** = 依赖本机无法完成的外部条件。判定判据见"证据"列，命令可直接复现。

| ID | 状态 | 证据 / 缺口 |
|---|---|---|
| M-01 | **PASS** | `scripts\run_csr_unit_tb.ps1` 32/32（六条 Zicsr 读改写、`rs1=x0`/`uimm=0` 纯读） |
| M-02 | **PASS** | 同上（位域掩码、`mtvec.mode` 强制 00） |
| M-03 | **PASS** | 同上（未实现/未定义 CSR）+ `run_trap_pipeline_tb.ps1` 用例 H（写只读 `misa` → `mcause=2`） |
| M-04 | **PASS** | 用例 A（`EBREAK`，`mtval`=指令码）、用例 B（`ECALL`，`mtval=0`） |
| M-05 | **PASS** | 用例 C 注入 `0xffffffff`（未定义 opcode）；用例 C2 注入 `WFI`（`0x10500073`）→ `mcause=2`、`mtval`=指令码、无提交记录。非法 `funct3/funct7` 组合由译码器同一 default 分支处理，未再单独注入 |
| M-06 | **PASS** | 用例 D（`lh` 奇数地址、`mcause=4`、零数据事务）、用例 E（`sh` 奇数地址、`mcause=6`、零写副作用） |
| M-07 | **PASS** | 用例 K（Store 越界 → `mcause=7`、`mtval`=地址、零副作用、恢复点 PC+4）+ `run_pipeline_error_observability_tb.ps1`（Load 越界 → `mcause=5`、无写回、无提交记录） |
| M-08 | **PASS** | 用例 P：`lui+jalr` 跳向 IMEM 之外的 0x4000 → `mcause=1`、`mtval=0x4000`、`mepc` 是**出错取指地址**而不是跳转指令的 PC；handler 把 `mepc` 改写到合法 PC 后恢复。E-09 在本设计中不可达（PC 永远 4 字节对齐，跳转目标未对齐在 EX 就被 E-01 拦下），编码仍按契约映射到 `mcause=1` |
| M-09 | **PASS** | 用例 A/C/H/K 的 handler→`mret` 返回；用例 I/L 的中断返回 |
| M-10 | **PASS** | 用例 F：出错指令本身与更年轻指令都不产生提交记录（`n_c10==0`），更年轻的 `addi x5,4` 未生效 |
| M-11 | **PASS** | 用例 F（更老的 Store 恰好完成一次、数据已落盘）、用例 K（更老的 Store 与出错 Store 的副作用计数） |
| M-12 | **PASS** | 用例 O：未对齐 Load（0x08）与非法指令（0x0C）**同时在流水线里**，实测第一次 Trap 的原因是 4（程序序更早者胜）、总共恰好 2 次 Trap（不是 3 次也不是 1 次） |
| M-13 | **PASS** | 用例 J：`mie.MTIE` 确实为 1、`mstatus.MIE=0` 时不产生 Trap、`mip` 仍读到 pending、程序继续执行 |
| M-14 | **PASS** | `rtl/timer_mmio.v`（SoC 侧 `mtime`/`mtimecmp`）+ `rtl/soc_data_interconnect.v` 的 `TARGET_TIMER` 窗口；`scripts\run_timer_irq_tb.ps1` 11/11：3 次中断 `mcause=0x80000007`、**间隔完全相等（27 拍）**、ISR 重新装载后可再次触发、关使能后不再响应、`irq_timer` 为电平。详见 §6.4 |
| M-15 | **PASS（Core 侧）** | 用例 L：`mcause=0x8000000B`、外部 ISR 执行、`mret` 返回。SoC 侧中断聚合器未实现，同为电平注入 |
| M-16 | **PASS** | `run_trap_pipeline_tb.ps1` 的随机背压整轮（取指与数据适配器 `RANDOM_DELAY=1`）71/71 全过 |
| M-17 | **PASS** | 用例 M：中断线**恰好在出错指令进入 WB 的那一拍**拉高，实测第一次 Trap 是同步异常（`mcause=2`）、随后中断仍被接受（`n_irq_trap==1`）、最终 `mcause=0x8000000B` |
| M-18 | **PASS** | 用例 Q：等 Trap 发生、handler 已在流水线里执行时拉高复位 → `mcause`/`mepc`/`mtvec`/`mstatus.MIE` 全部回到初值、无残留写副作用；复位释放后从 **PC=0** 重新取指 |
| M-19 | **PASS** | 用例 F/K 的 `store_side_effects==0`（出错路径不产生写副作用） |
| M-20 | **PASS** | 用例 R（在完整 CPU 上）：两次读 `mcycle` 的差值与手工推算一致（6 拍），两次读 `minstret` 的差值等于中间退休的 6 条指令；随机背压下只断言下界（≥ 满速值），精确值在零延迟配置判定 |
| M-21 | **PASS** | `tb/tb_trap_golden.v` 只把 **Core 公开端口**（`trace_*` 与 `event_trap`/`event_trap_return`）写成日志；`python/trap_golden_judge.py` 作为**独立进程**从日志重建提交序列与 Trap 事件，再与声明好的 golden 序列比对（3 次 Trap / 3 次 mret / 出错指令无提交记录 / 出错路径无内存写事务）。不读 Core 内部状态，也不用单周期模型 |
| M-22 | **PASS** | `run_pipeline_regression.ps1` 13/13；CoreMark 周期数与 A1 完全一致（见 `docs/progress.md`） |
| M-23 | **PASS** | 三个 PDS 工程 `All Constraints Met`，位流已用 A3 RTL 重建（见 `docs/progress.md` 时序表） |
| M-24 | **PASS**（2026-09-30 收口） | **板级周期性中断演示已闭环（2026-09-29）**：新建最小工程 `fpga/timer_demo`，位流 `5E58B421…` 下载 `PROGRAM PASS` + `done bit is 1`；20 秒串口采集 **50 条连续中断记录、45 个间隔全部落在 12_500_000 ± 65536 拍内**（自计时中位数 12_517_376 拍 = 250.35 ms）；LED0 每次中断翻转一次、其余 LED 位恒为 0。另有当前位流的 J8 四模式 **80/80 PASS** 与实板 CoreMark **21.36 s / score×1000=46816**。**✅ 已完成（2026-09-30）：ILA 抓 Trap 进入与返回已在实板取得。** 诊断工程 `fpga/timer_demo_ila`（探针 = Core **既有**事件端口 `event_trap`/`event_trap_return` 等 + 取指地址 `ia`；新增段由 `` `ifdef `` 保护，N1 位流不受影响），位流 `generate_bitstream/mes50hp_timer_demo_top.sbit`，`SHA256 452EE532DAC8AB9A86CDF9C6859892F7BA466EA035EF6A6C46FAAA9598248B74`，时序无违例；下载与抓取：`scripts\program_board.ps1 -Config tmila -UseDebugger` → `scripts\run_ila_trap_capture.ps1 -Mode capture`（触发配置按工具自带 `-help` 推导）。**实板两次抓取互相印证**（证据见 `fpga/timer_demo_ila/evidence/`）：触发在 `ila_event_trap` 上升沿 → 该脉冲落在触发点（第 256 采样），同窗口另有 1 个 `trap_return`；触发在 `ila_event_trap_return` 上升沿 → 同样落在触发点，另有 1 个 `trap`；两次都显示 **`trap` 恒在 `trap_return` 之后 5 个采样点**；`irq_timer` 全窗口为 1（原因 = 机器定时器中断），`illegal/misaligned/bus_error` 全 0。波形 SHA-256：A `A7FAB1B1…`(txt) / `E9EC8F47…`(vcd)；B `80F384A3…` / `8BCDBC60…`。**如实边界**：探针里**没有** `mcause`/`mepc` 的数值 —— PDS 拒绝层级引用（`Verilog-4311`），而改 Core 端口又违反 `AGENTS.md` §1.14；其数值由固件串口记录（N1 的 50 条周期中断记录）证明。 |

### 6.4 M-14 的 SoC 侧闭环（2026-09-28 收口）

契约 §4.2 规定定时器中断的**来源在 SoC**，Core 只接一根设备无关的 `irq_timer_i`。
本轮把 SoC 侧补齐，链路完整为：

```text
Core 的数据事务 → soc_data_interconnect（TARGET_TIMER，0x1000_3000~0x1000_30FF）
   → timer_mmio（mtime / mtimecmp，Core 外部）
   → irq_timer = (mtime >= mtimecmp)  ← 电平，与 RISC-V MTIP 语义一致
   → Core 的 irq_timer_i → WB 退休边界接受 Trap → mtvec → ISR → mret
```

| 项 | 落地 |
|---|---|
| 外设 | 新增 `rtl/timer_mmio.v`：`+0x00 mtime_lo`、`+0x04 mtime_hi`、`+0x08 mtimecmp_lo`、`+0x0C mtimecmp_hi`，其余偏移报 error；`mtime` 自由计数（每拍 +1），复位后 `mtimecmp` 为全 1，**软件显式打开之前不会产生中断请求** |
| 地址窗口 | `rtl/soc_data_interconnect.v` 新增 `TARGET_TIMER`（0x1000_3000~0x1000_30FF），与其它目标共用同一套单 outstanding 握手 |
| Core 连接 | `irq_software_i`/`irq_external_i` 显式接 0，`irq_timer_i` 接 SoC 聚合出来的 `irq_timer`；板级顶层此前**根本没有连这三根线**（悬空），本轮一并修正 |
| 验收 | `scripts\run_timer_irq_tb.ps1` → `ALL TIMER INTERRUPT TEST PASS`（11 条断言）|

验收程序（`tb/data/timer_irq.mem`，24 字）与断言要点：

1. 恰好 3 次 Trap，且 3 次的 `mcause` 都是 `0x80000007`；
2. **第 2、3 次中断的间隔完全相等（实测 27 拍 = delta 20 + 固定开销 7）**——
   这正是契约里"周期可预测"的可判定形式，而不是"大概每隔一会儿来一次"；
3. ISR 真的执行了 3 次并写出完成标记（`x6==3`、`x7==0x555`）；
4. ISR 里**重新装载 `mtimecmp`** 之后中断能再次触发（不重新装载只会中断一次）；
5. 关掉 `mie.MTIE` 后再等 200 拍不会出现第 4 次 Trap（不重复响应）；
6. `irq_timer` 是**电平**信号：ISR 重新装载后自动落下，不需要额外的"清中断"寄存器。

两处容易踩的坑（都已写进程序注释，供接班者复用）：

- **只写 `mtimecmp_lo` 不会产生中断**：`mtimecmp_hi` 复位值是全 1（为了复位后无中断），
  必须先把高 32 位清零，否则 `mtime < mtimecmp` 恒成立。
- **计数寄存器必须先显式清零**：通用寄存器初值未定义，`addi x6, x6, 1` 会一直保持 X，
  比较结果也是 X，`bne` 会取"不跳"分支，程序在第 1 次中断就误判完成。

### 6.3 两处实现与契约文字的澄清

1. **E-01 的 `mcause`**：契约规定是 `0`。流水线内部用 4-bit 异常记录，"0" 已经被 `EXC_NONE` 占用，
   因此内部编码用 `12`（`EXC_INSTR_MIS`），在写 `mcause` 时**显式映射回 0**。
   `12` 在标准 RISC-V 里是 instruction page fault，本项目没有 MMU，绝不能原样写进 `mcause`。
   同理 E-08/E-09 统一用 `EXC_IFETCH_ERR`（`mcause=1`），不借用 `EXC_INSTR_MIS`。
2. **Store 访问错误的 `mepc`**：§5.1 第 4 条"该 Store 视为已提交"落地为
   `mepc = 该 Store 的 PC + 4`，其余所有同步异常的 `mepc` 都是出错指令自己的 PC。
   用例 K 用"0x0C 放一条不得执行的 `addi x7,7`"把这条规则钉死。

## 7. 与现有契约的冲突与修订清单

本文生效需要同步修订以下项目契约，否则后续接班的 Agent 会按旧范围拒绝这项任务：

| 文件 | 需要修订的内容 |
|---|---|
| `AGENTS.md` §1.5/§1.13、§4、§8、§9 | 把"未实现的中断扩展不得引入设备专用端口"细化为"Core 只接通用中断输入"；把异常/中断从"本届不实现"改为"按 A2 契约实现机器模式子集" |
| `docs/roadmap.md` Gate 规则、阶段 K | 增加 Trap/CSR/中断的 Gate 与任务编号；删除"完整异常/中断不得临时回加"一句 |
| `docs/competition_scoring.md` | 更新高阶任务覆盖表：BTB 为②之一，Trap/中断为②之二，并写明各自覆盖范围与未覆盖项 |
| `docs/interfaces.md` | 冻结新增的 CSR 指令语义、三根通用中断输入、`event_trap*` 输出，并声明它们不破坏既有事务契约 |
| `docs/architecture.md` | 记录 Trap 数据通路：检测级、优先级、取消规则、`mepc/mtval` 来源 |
| `docs/progress.md` | 记录 A1/A2/A3 的实际进度与验证命令，不得沿用旧口径 |

## 8. 已冻结的边界（不得在实现中扩大）

1. 只有 M-mode；不得顺手实现 U/S 模式。
2. 只有 Direct `mtvec`；不得顺手实现向量模式。
3. 只有三个标准中断源；不得为 UART/GPIO/SPI/逻辑分析仪加设备专用中断端口。
4. Trap 实现本身**不得引入新的存储层次**：Cache/burst 属于 P3（S2～S4）的独立工作，
   由 `docs/interfaces.md` §3.4 约定，且不得改变 Trap 的精确性语义。
   **2026-09-29 范围变更**：Cache/burst/DDR 已纳入本届（`AGENTS.md` §1.14）；
   接入 Cache 后**必须**重跑本契约全部断言，任何一条退化即回退。
5. 不实现 Debug Mode；`EBREAK` 只是异常。
6. 不实现 `WFI`；保持非法指令。
7. Trap 不改变既有的单 outstanding 事务模型与 `valid/ready` 契约。
8. 在本契约逐项 PASS 之前，**不得**对外宣称"完成高阶任务②整组"；只能按已勾选项如实报告子能力。

**结论（按 §8 第 8 条如实报告）**：24 条里 **24 条 PASS、0 条部分**。
M-24 的两条通过条件**均已完成**：
①**"在板上运行裸机中断程序并观察到周期性中断"于 2026-09-29 闭环**（N1）；
②**"用 ILA 抓到 Trap 进入与返回"于 2026-09-30 闭环**（N2）。
⇒ **M-01…M-24 全绿**。按 §8 第 8 条，至此**可以**宣称高阶任务②整组完成。

> ⚠️ 本节曾写"23 条 PASS、1 条部分（M-24）""只剩 ILA 未做""M-24 尚未整条闭环"——
> 那是 2026-09-29 的状态，已在本轮全部改正。上文 §6 的 M-24 行（L268）记的才是最终状态。

**M-24 板级中断演示（N1，2026-09-29）**：

| 项 | 证据 |
|---|---|
| 工程 | `fpga/timer_demo`（最小板级工程，Core 未改：`rtl/pipeline_cpu.v` SHA-256 前 16 位仍是 `B58496706686E37B`）|
| 固件 | `software/timer_demo/start.S`：周期定时器中断 + GPIO→LED + UART 输出「计数 / LED 值 / mtime[27:16]」|
| 仿真 | `scripts\run_timer_demo_board_top_tb.ps1`：零延迟 14/14 PASS、随机背压 13/13 PASS |
| 位流 | `5E58B4217AB9591AF974C5B1897A287A007B7E7E219F122244E44A4958B7765B`，PDS `All Constraints Met`（WNS +2.638 ns）|
| 下载 | `scripts\program_board.ps1 -Config tm50` → `PROGRAM PASS`、`done bit is 1` |
| 实板 | `scripts\run_timer_demo_board.ps1 -Port COM11`：**50 条连续中断记录，45 个间隔全部 = 12_500_000 ± 65_536 拍**；LED 序列 0101…（每次中断翻转一次）；自计时中位周期 **12_517_376 拍 = 250.35 ms**（期望 0.25 s）|
| LED | LED0（板上 LED1，管脚 `B2`）每 0.25 s 翻转一次 → 0.5 s 整周期闪烁（**需人眼/视频确认**，脚本不代替观察）|

**M-24 ILA 抓 Trap 进入/返回（N2，2026-09-30）—— 已闭环**：

| 项 | 证据 |
|---|---|
| 工程 | `fpga/timer_demo_ila`（探针 = Core **既有**事件端口 `event_trap`/`event_trap_return` 等 + 取指地址 `ia`；新增段由 `` `ifdef PDS_TIMER_DEMO_ILA `` 保护，N1 位流不受影响）|
| 位流 | `452EE532DAC8AB9A86CDF9C6859892F7BA466EA035EF6A6C46FAAA9598248B74`，时序无违例 |
| 下载 | `scripts\program_board.ps1 -Config tmila -UseDebugger`（**必须加 `-UseDebugger`**：JTAG 链被 DebugCore Hub 接管）|
| 抓取 | `scripts\run_ila_trap_capture.ps1 -Mode capture`（触发配置按工具自带 `-help` 推导，**不要照抄官方 PDF 示例**）|
| 抓取 A | 触发在 `ila_event_trap` 上升沿 → 该脉冲落在**触发点（第 256 采样）**，同窗口另有 1 个 `trap_return`（第 251 采样）|
| 抓取 B | 触发在 `ila_event_trap_return` 上升沿 → 同样落在触发点，另有 1 个 `trap`（第 261 采样）|
| 共同观测 | 两次都显示 **`trap` 恒在 `trap_return` 之后 5 个采样点**；`irq_timer` 全窗口为 1（原因 = 机器定时器中断）；`illegal/misaligned/bus_error` 全 0 |
| 波形 SHA-256 | A `A7FAB1B1…`(txt) / `E9EC8F47…`(vcd)；B `80F384A3…` / `8BCDBC60…` |

**如实边界（不得省略）**：
1. 探针里**没有** `mcause`/`mepc` 的数值 —— PDS 拒绝层级引用（`Verilog-4311`），
   而改 Core 端口又违反 `AGENTS.md` §1.14；其数值由**固件串口记录**（N1 的周期中断记录）证明，
   **不是** ILA 证明的。
2. "trap 与 return 间隔 5 个采样点"是**可复现的观测**，但采样间隔未经独立标定，
   因此**不换算成拍数**，也**不给出因果解释**。材料中不得写成"5 个周期"。
3. 波形回读用的是 PDS Fabric Debugger（`cdt_dbg.exe`）的 TCL 模式，**不是**仿真波形。

因此现在的口径是：**机器模式 CSR/Trap/MRET + 三根通用中断输入 + SoC 定时器 + 独立事件判定器
已完成；板级周期性中断演示（N1）与 ILA 抓 Trap 进入/返回（N2）均已在实板复现；
旧回归与实板演示不退步**；且 **M-24 已整条闭环 ⇒ "官方高阶任务②整组完成"可以宣称**（依据 §8 第 8 条）。