# Task 12 RV32I 指令覆盖表

> 最后更新：2026-09-12  
> 状态：定向整机测试覆盖已完成；已接入 `riscv-tests` 的 RV32UI Core 子集，Load/Store 上游测试和统一 Regression 尚未完成，因此 Task 12 未通过。

## 1. 适用范围与统一策略

- ISA 目标：RISC-V Unprivileged ISA `v20240411` 的 RV32I Base Integer ISA `Version 2.1`；不支持 `M`、`C`、CSR、特权指令、`Zifencei` 或异常/中断。
- Memory：`LB`/`LBU`/`SB` 可访问任意 byte address；`LH`/`LHU`/`SH` 要求 `addr[0]=0`；`LW`/`SW` 要求 `addr[1:0]=0`。未对齐 Load 不写 `rd`，未对齐 Store 不写 DMEM；两者均顺序执行 `PC+4`，不实现 trap。
- FENCE：`opcode=0001111`、`funct3=000` 为合法 FENCE。在当前无 Cache、写缓冲、乱序或并发 I/O 事务的单周期模型中，执行为无 RegFile/DMEM 副作用的保守 no-op，PC 顺序加 4；所有 `fm`、`pred`、`succ`、`rs1` 和 `rd` 字段均被保守处理。
- FENCE.I、ECALL、EBREAK、CSR 与其他未支持 SYSTEM/非法编码：`illegal=1`，无 RegFile、DMEM 或控制流副作用，PC 顺序加 4。此为当前受控仿真策略，不是 trap/debug 支持，软件不得依赖。

## 2. 已实现指令与整机定向证据

| 指令类别 | 指令 | 正常路径与边界覆盖 | 整机测试证据 | 状态 |
|---|---|---|---|---|
| R-Type ALU | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | 双源寄存器读取、十种 ALU 结果与写回 | `run_single_cycle_r_type_tb.ps1`，11/11 PASS | PASS |
| I-Type ALU | ADDI | 基础算术、立即数写回 | `run_single_cycle_cpu_tb.ps1`，10/10 PASS | PASS |
| I-Type ALU | SLTI, SLTIU | signed/unsigned 比较 | `run_single_cycle_slti_tb.ps1`，4/4 PASS | PASS |
| I-Type ALU | SLLI, SRLI, SRAI | 左移、逻辑/算术右移 | `run_single_cycle_shift_imm_tb.ps1`，4/4 PASS | PASS |
| I-Type ALU | XORI, ORI, ANDI | 三类逻辑立即数结果 | `run_single_cycle_logic_imm_tb.ps1`，4/4 PASS | PASS |
| Load | LB, LH, LW, LBU, LHU | byte lane、halfword、word、符号/零扩展、未对齐无写回 | `run_single_cycle_load_align_tb.ps1`，6/6 PASS | PASS |
| Store | SB, SH, SW | byte strobe、不同 lane、未对齐无 DMEM 写 | `run_single_cycle_store_align_tb.ps1`，6/6 PASS | PASS |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU | taken/not-taken、signed/unsigned、错误路径 marker 抑制 | `run_single_cycle_branch_tb.ps1`，15/15 PASS | PASS |
| U-Type | LUI, AUIPC | upper immediate 写回、PC-relative 运算 | `run_single_cycle_u_type_tb.ps1`，3/3 PASS | PASS |
| Direct jump | JAL | link=`PC+4`、目标跳转、`rd=x0` | `run_single_cycle_call_return_tb.ps1`，6/6 PASS；基础测试亦覆盖 | PASS |
| Indirect jump | JALR | `rs1+imm`、bit 0 清零、调用/返回 | `run_single_cycle_jalr_tb.ps1`，3/3 PASS；`run_single_cycle_call_return_tb.ps1`，6/6 PASS | PASS |
| Memory ordering | FENCE | `RW,RW`、`I,O`、保留字段的保守处理；无有效写使能、顺序 PC | `run_single_cycle_system_boundary_tb.ps1`，32/32 PASS | PASS |

## 3. 上游 RV32UI 测试接入

- 上游来源：`third_party/riscv-tests`，固定提交 `2ebecad997fa58cd9e5724340ba75aa4b59bd1d0`。
- 本地 target shell：`tb/arch/riscv_tests/riscv_test.h` 与 `link.ld`。它避免上游默认环境的 CSR、`mret` 与 `ecall` 终止方式，改为仅用 RV32I `sw` 向 DMEM `tohost` 地址 `0x4000` 报告自检结果；这不修改上游测试主体或 CPU RTL。
- 运行入口：`./scripts/run_rv32ui_core_suite.ps1`。每个测试先使用 `RISCV_PREFIX` 指定的 `riscv-none-elf-` 工具链编译并转换为 IMEM 镜像，再用 `tb/tb_rv32ui_core.v` 判定 `tohost`。最近一次为 29/29 PASS。

| 上游 RV32UI 类别 | 已运行测试 | 结果 | 适用性说明 |
|---|---|---|---|
| R-Type / I-Type ALU、比较、移位 | `add addi and andi or ori sub xor xori sll slli srl srli sra srai slt slti sltiu sltu` | 19/19 PASS | 不依赖初始化 DMEM 或 SYSTEM。 |
| U-Type / 控制流 | `auipc lui beq bne blt bge bltu bgeu jal jalr` | 10/10 PASS | 验证目标计算、条件与 link；不依赖 trap。 |
| Load / Store | `lb lbu lh lhu lw sb sh sw ld_st st_ld` | 10/10 PASS | `tb_rv32ui_memory.v` 使用同一 ELF Verilog 镜像预装独立 DMEM 的 `.data` 段；覆盖所有目标 Load/Store 与交叉序列。 |
| `fence_i` | `fence_i` | 不适用 | 属于未声明支持的 Zifencei；当前只支持 RV32I `FENCE`。 |
| `simple` / `ma_data` | 未运行 | 待逐项审查 | 需先确认是否依赖当前不支持的环境行为或初始化数据。 |

> 说明：此处的 `riscv-tests` 是上游 ISA 单元测试证据，不等同于 RISC-V ACT 认证。正式 ACT 需要额外的 signature target shell 和参考签名比较，当前不作完成声明。

## 4. 非目标或非法编码的证据

| 类别 | 预期行为 | 测试证据 | 状态 |
|---|---|---|---|
| FENCE.I | `illegal=1`，无副作用，PC=`PC+4` | `run_single_cycle_system_boundary_tb.ps1` | PASS |
| ECALL / EBREAK | `illegal=1`，无副作用，PC=`PC+4`；不支持 trap/debug | `run_single_cycle_system_boundary_tb.ps1` | PASS |
| 其他 SYSTEM / 未支持 opcode | `illegal=1`，无副作用，PC=`PC+4` | `run_single_cycle_system_boundary_tb.ps1` | PASS |
| R/I/Load/Store/Branch 的非法 funct 编码 | Decoder 默认安全控制 | `run_decoder_tb.ps1`，64/64 PASS | PASS |

## 5. 尚未完成的 Task 12 验收项

| 项目 | 当前状态 | 进入下一 Gate 前的完成条件 |
|---|---|---|
| RISC-V architectural tests | 进行中 | 完成上游 RV32UI Load/Store 数据段预装载与适用测试；逐项 PASS 或记录不适用原因与等价测试。 |
| 统一单周期 Regression | 已建立、逐项证据 PASS | `run_task12_regression.ps1` 顺序运行 22 个入口（基础模块、定向整机、RV32UI Core、RV32UI Memory），任一子项失败即返回非零。受控代理命令窗口约 30 秒截断在最终汇总之前；其每个组成入口均已独立 PASS，用户本地 PowerShell 可完整运行该入口。 |
| Task 12 Gate | 未通过 | 上述两项完成，且本表无未解释空项。 |

## 6. 最近一次定向回归快照

- `run_decoder_tb.ps1`：64/64 PASS。
- 全部单周期整机脚本：12 个脚本均 PASS，其中新增系统边界测试为 32/32 PASS。
- `run_rv32ui_core_suite.ps1`：上游 RV32UI Core 子集 29/29 PASS。
- `run_rv32ui_memory_suite.ps1`：上游 RV32UI Memory 子集 10/10 PASS。
- `run_task12_regression.ps1`：统一入口已建立；全部组成入口已独立 PASS。
- 本表只记录已通过的行为级定向测试，不替代 Task 17 的 GCC、MMIO/UART/GPIO 与正式 Reference Model Regression。
