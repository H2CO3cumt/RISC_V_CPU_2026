# Architecture Decisions

> 最后更新：2026-09-14
> 当前状态：Task 23 Hazard、Task 24 GCC Pipeline、Task 25 性能监视器、Task 26/28/30 PDS 与 Task 30 自动化 Raw 应用闭环已通过；实体板 CoreMark、物理回环和 PDS ILA 证据需在设备连接后采集。

本文件记录会影响多个模块、软件或验证流程的重要架构决定。尚未到达对应 Gate 的内容只记录约束和待验证项，不提前实现。

## 1. ISA 与软件约束

- 处理器目标固定为 RISC-V Unprivileged ISA `v20240411` 的 RV32I Base Integer ISA `Version 2.1`；本届仅实现本文件和 `docs/rv32i_instruction_coverage.md` 明确的范围。
- GCC 固定使用 `-march=rv32i -mabi=ilp32`；Windows 当前采用 xPack `riscv-none-elf-` 前缀，并通过 `RISCV_PREFIX` 引用。优化级别、链接选项和 `libgcc` 使用情况随测试镜像一并记录。
- 未声明支持 `M`、`C` 或其他扩展；反汇编出现相关指令时不得由 Testbench 或软件静默绕过。
- 非对齐访问、`FENCE`、`ECALL`、`EBREAK` 等行为在 Task 12 的指令覆盖表中明确。
- `FENCE`（`opcode=0001111`、`funct3=000`）在无 Cache、写缓冲、乱序或并发 I/O 事务的行为级单周期模型中作为保守 no-op 执行：不写 RegFile、不访问 DMEM、PC 顺序加 4。`pred`、`succ`、`fm`、`rs1` 与 `rd` 均不改变此行为，符合简单实现可采用保守 Fence 的约束。
- `FENCE.I`（Zifencei）、`ECALL`、`EBREAK`、CSR 与其他 SYSTEM 编码不在当前 Core 支持范围；译码输出 `illegal=1`，无 RegFile/DMEM/控制流副作用，PC 顺序加 4。该策略不是 RISC-V trap 或 debug 支持；软件不得依赖它，正式异常/中断接口不属于本届范围。

## 2. Reference Model 与验证策略

- 单周期 CPU 是 Pipeline 的 architectural Reference Model。
- Task 13 只建立 `single_cycle_reference_candidate` 和提交级接口。
- Task 17 在 RV32I、GCC、MMIO、UART/GPIO 与正式 Regression 全部 PASS 后冻结 `single_cycle_stable`。
- Single Cycle 与 Pipeline 必须同时比较最终 `x1`～`x31`、关键 RAM 和提交级 trace。
- 提交级 trace 最少包含：`valid`、`pc`、`instruction`、`rd_we`、`rd_addr`、`rd_data`、`mem_we`、`mem_addr`、`mem_data`、byte enable。
- Debug 时报告第一条不一致提交，并沿 `IF -> ID -> EX -> MEM -> WB` 查找第一个错误周期和信号。

## 3. Memory 与 FPGA 实现边界

- 单周期 Reference Model 可使用行为级组合读 IMEM/DMEM，以保持参考模型简单明确。
- 行为级 IMEM 使用 32-bit 字节地址，`addr >> 2` 选择 word；RV32I 非压缩取指必须满足 `addr[1:0] == 2'b00`。初始化先清零全部 word，再用 `$readmemh` 加载 GNU objcopy `-O verilog --verilog-data-width=4` 生成的镜像；非对齐或越界读取返回零。
- 行为级 DMEM 组合返回包含目标地址的完整 32-bit word，在时钟上升沿按 `wstrb[3:0]` 更新 byte lane；越界读取返回零，越界写入忽略。Load 的 lane 选择/扩展和 Store 的数据对齐由独立 Load/Store Unit 负责。
- 最终 FPGA Pipeline 必须使用与紫光同创 FPGA/PDS 实际 BRAM 读写时序一致的 wrapper。
- Task 10 必须通过目标器件、时钟/Reset、BRAM 读写、初始化和资源推断的 PDS 冒烟验证。
- 本届正式目标冻结为盘古 50（MES50HP）的紫光同创 Logos `PGL50H-6IFBG484`，系统时钟 `FPGA_GCLK_50M=P20` 为 50 MHz（20.000 ns），使用 PDS `.fdc`；平台和验证契约见 `docs/fpga_platform.md`。
- MES50HP 的 Reset 选择、按键/LED 极性和 CP2102 UART 管脚全部由 Core 外部 board wrapper/约束处理。默认 `USE_EXTERNAL_RESET=0` 使用内部上电复位；底板 `REST` 是专用固件重加载信号，CPU 人工复位只从低有效用户按键分配。
- 稳定 Baseline 使用可综合片上 RAM/BRAM，**不依赖** Cache 或 burst；MMIO 始终属于 uncacheable 区域。
- **2026-09-29 范围变更**：I/D Cache 与行式突发纳入本届（`AGENTS.md` §1.14），
  存储层次见本文件「存储层次（行式突发 + 2 路组相联 Cache）」一节；Baseline 路径保持不变、可随时回退。
- Task 9 的当前非对齐策略为检测且不拆分事务：`LB/LBU/SB` 接受任意 byte 地址，`LH/LHU/SH` 仅接受 `addr[0]=0`，`LW/SW` 仅接受 `addr[1:0]=2'b00`。不满足对齐时 `misaligned=1`；Store 保持 `wstrb=4'b0000`，禁止任何写副作用。Task 12 再冻结软件可见的完整 ISA 行为。

## 3.1 存储层次（行式突发 + 2 路组相联 Cache）

**阶段**：S2 行式突发（已完成）→ S3 2 路组相联 I-Cache → S4 2 路组相联 D-Cache。
依据 `AGENTS.md` §1.14 的范围变更与 `docs/handoff_next.md` §3.3 的闸门。

**为什么需要这一层**：Baseline 的后端是片上 BRAM，单笔事务、低延迟，
Cache 挡在前面省不下周期，Off/On 也测不出差别。**一旦把代码/数据搬到板载 DDR3**，
每次访问都要付 DDR 的行激活与命令开销，没有 Cache 会慢很多倍——
这时组相联 Cache + 突发行填充才成为必需品，Off/On 才是真实后端上的真实数字。
S1 已在实板跑通 DDR3 控制器（`S1 DDR3 SMOKE BOARD PASS`）。

**层次结构**（全部位于 Core 外部，Core 端口与事务语义不变）：

```text
pipeline_cpu（rtl/pipeline_cpu.v，SHA-256 前缀 B58496706686E37B，端口未改）
   ├── 统一取指端口 ──> [S3] I-Cache（2 路组相联）──> 行/突发适配器 ──> IMEM / DDR3
   └── 统一数据端口 ──> [S4] D-Cache（2 路组相联，写穿+写缓冲）──> 互连 ──> DMEM / MMIO / DDR3
                                                          └── MMIO 恒 uncacheable，强制绕行
```

**S2 已实现的部件**：`rtl/soc_line_burst_adapter.v`。
它把 Core 的单字访问翻译成"一次行请求 + 连拍返回"（32 B = 8 拍），
并用一个行缓冲接住整行；`BURST_LEN=1` 时退化为逐字事务，
因此 Before/After 是**同一份 RTL**，差异只来自发包方式。

**S3 已实现的部件**：`rtl/soc_icache_2way.v`（2 路 × 32 组 × 32 B = 2 KB，带 Off 开关）。
模块级验证 26 项 PASS。**集成后净收益为负，默认关闭**，原因与边界见本节末。

**S4 已实现的部件**：`rtl/soc_dcache_2way.v`（2 KB，写穿 + 写缓冲，写未命中不分配）。
模块级验证 19 项 PASS，覆盖四项必做功能（写穿+写缓冲、MMIO 强制绕行、
Store→Load 转发、字节写合并）。

**实测收益**（S2，`tb/tb_soc_line_burst_adapter.v`，3 整行 × 8 字顺序读，两种模式各 3 次填充）：

| 指标 | 逐字 | 突发 | 变化 |
|---|---|---|---|
| 下游请求数 | 24 | 3 | −87.5% |
| 下游总线周期 | 48 | 30 | **−37.5%** |

**D-Cache 收益与"后端有多慢"的关系**（`tb/tb_soc_dcache_2way.v`，同一 32 次带局部性的读序列）：

| 后端 | 配置 | 下游读请求 | 下游总线周期 |
|---|---|---|---|
| 慢（读首拍 4 拍） | Off | 32 | 192 |
| 慢 | **On**（命中率 90%） | **3（−90%）** | **39（−79%）** |
| **零等待** | Off（对照） | 32 | 64 |

**⚠️ 关键边界（这条比上面的数字更重要）**：Cache 的收益**完全取决于后端有多慢**。

- 后端**零等待**（片上 BRAM，CoreMark 工程当前配置）：每次访问本来就 1 拍，
  而 Cache 的命中响应是**寄存**的（1 拍），于是**每次取指多 1 拍**。
  实测把 I-Cache 接进真实取指路径后 CoreMark **慢 2.31 倍**
  （1,251,724 → 2,891,324 拍），按 §3.3 的止损规则**默认关闭**。
  根因是 `rtl/pipeline_cpu.v` 第 727–741 行的"响应接收 + 新请求接受同拍交接"优化
  让零等待后端能每拍取一条指令。
- 后端**慢**（DDR3 那类，每次访问都有激活/命令开销）：命中省下的是实打实的多拍等待，
  上表 −79% 就是这个量级。

**因此**：要让 Cache 在**当前**工程配置下兑现，必须先完成
"**零气泡（组合）命中路径**"——该方案已分析清楚但本会话未调通（见 `docs/debug_log.md`）；
或者把后端换成真实慢存储（S1 已跑通的 DDR3），此时 Cache 的收益不依赖零气泡。

**代价与前提（不得省略）**：上表来自**行填充式慢后端模型**（`dcache_mem_model`），
**是模型级、非端到端**数字。

### 3.1.1 S4 的最终实测结论（2026-09-29，已闭环）

**先说功能**：D-Cache 接进 CoreMark 后**功能已正确**，判据有两条硬证据：

1. **影子内存逐笔比对零错读**：用同一份 `coremark_dmem.mem` 建影子，
   每一笔被 Core 接受的数据读都与影子比对 ⇒ **零笔不符**；
2. **UART 日志逐行对比**（基线 vs D-Cache）：**只有计时/性能行不同**
   （`Total ticks`、`CoreMark/MHz`、`PERF cycle=…`），
   **所有 CRC、`Correct operation validated.`、`COREMARK_DONE` 逐字相同**，`bytes` 同为 655。

**再说收益（端到端，零等待 BRAM 后端）**：

| 配置 | cycles | vs 基线 |
|---|---|---|
| 基线（不接 D-Cache） | 1,251,724 | — |
| **D-Cache On** | **1,348,302** | **+7.7%（净亏）** |

`PERF` 行印证：`stall` 由 184,120 涨到 289,791。

⇒ **S4 按 §3.3 的止损条件（Off-On 无净收益）收口：功能正确，但当前配置下无收益，
D-Cache 默认关闭（`ENABLE_DCACHE=0`），不得宣称端到端收益。**

**架构结论（这是本节最该记住的一句）**：
**片上 BRAM 这种零等待后端比"Cache 命中"还快，所以在本工程当前的存储配置下，
任何 Cache 都注定是净亏损。** 一个**正确**的 Cache 并不能改变这一点：
它的价值只体现在"后端足够慢"的场合（DDR3 那类），
而"后端足够慢"意味着必须先把 **DDR3/HMIC 行突发后端真正接进 SoC**
（S1 只证明了板级连通，没有接进 CPU 访存路径）。
**在此之前，Cache 的端到端收益不是一个"优化没做好"的问题，而是一个"前提不成立"的问题。**

**一个不能引用的测量（留档）**：曾试"同后端 Off/On"（两边都用 `slow_ram_adapter` + 读延迟 4），
Off 超时、On 1,217,422 拍。该组数字**不可引用**：
在延迟 4 下**纯直连配置也报影子不符**（是慢后端**模型的写延迟**让影子对不上，不是 Cache 问题），
且 On@4 的 `bytes=628 ≠ 655`，输出本身不完整。

**设计约束（不得放宽）**：
- I-Cache 只能位于取指端口与下级存储之间，D-Cache 只能位于数据端口与 SoC 互连之间；
- MMIO 区域**恒为 uncacheable**，不进 Cache、不合并、不预取；
  **且不可缓存读绝不能写 Cache 数据阵列**（这是 S4 集成错数据的根因，见 `docs/debug_log.md` 第九轮）；
- Cache/突发全部在 Core 外部；Core 内不得出现 Cache 专用端口或设备状态机；
- 每完成一步必须重跑 Trap 契约全部 99 条断言 + 最终回归 + CoreMark，任何退化即回退。



## 4. Core / SoC 边界与应用场景

- 五级流水线 Core 与最终外设严格解耦。Core 只负责 RV32I 执行、IF/ID/EX/MEM/WB、Hazard 控制、统一取指/数据事务和提交/性能事件；完整契约见 `docs/interfaces.md`。
- 地址译码、MMIO 互连、RAM/BRAM、UART、GPIO、SPI、传感器、逻辑分析仪、加速器、厂商总线和板级引脚全部位于 Core 外。
- Core 中不得出现设备专用地址、片选、`busy/done` 或协议状态机。低速设备通过统一 `valid/ready` 背压让 Core 等待。
- 基础 SoC 的参考配置为 `RV32I Core + Interconnect + RAM + UART TX/RX + GPIO`，用于证明软件、MMIO 和板级链路，不代表 Core 固定依赖 UART/GPIO。
- 地址映射在 Task 15 固定于 SoC 互连层，任何区域不得重叠；未映射地址行为必须可测试，并预留一个通用 Application MMIO 窗口。调整外设地址不得修改 Core。
- Task 15 地址表冻结如下。地址按 byte 编址，区间首尾均包含；互连必须使每笔请求至多选中一个目标：

| 区域 | 地址范围 | 属性 | Task 15 行为 |
|---|---|---|---|
| RAM | `0x0000_0000`–`0x0000_03FF` | 普通内存 | 当前 256 × 32-bit 行为级 RAM；后续可替换为 BRAM wrapper。 |
| UART | `0x1000_0000`–`0x1000_00FF` | uncacheable MMIO | 预留给 Task 16 UART wrapper。 |
| GPIO | `0x1000_1000`–`0x1000_10FF` | uncacheable MMIO | 预留给 Task 16 GPIO wrapper。 |
| Application MMIO | `0x1000_2000`–`0x1000_2FFF` | uncacheable MMIO | 通用应用窗口；Task 30 才冻结逻辑分析仪寄存器 offset。 |
| 其余地址 | — | 未映射 | 互连接收请求并返回一次 `rsp_valid=1, rsp_error=1`；不选中任何真实目标，也不产生副作用。 |

- Task 15 的互连在请求握手时锁存唯一目标，直到对应响应握手结束前不接收下一笔请求；这个单 outstanding 限制符合第一版事务契约，避免响应返回时混淆来源。
- Task 16 只验证并冻结 Core/SoC 事务语义和基础互连方法。UART、GPIO 的独立与集成测试必须证明外设可替换，Task 16 不提前实现比赛应用。
- 比赛应用已经选定为“基于自研五级流水 RISC-V 的可重构多协议逻辑分析与故障诊断平台”。CPU 仅通过 MMIO 配置 Core 外部 Capture Engine，Raw 采样/触发数据保存在外设 BRAM，再由软件解析 UART/SPI 并经 UART 发送给 Python 上位机；本届冻结 RLE，完整范围见 `docs/application_logic_analyzer.md`。
- 报名页面作品名称固定为“RISC-V多协议逻辑分析仪”（14/15字符）；技术报告可使用上述完整名称。报名简介的唯一版本保存在 `docs/application_logic_analyzer.md`，后续修改必须同步检查500字符限制和未完成功能的措辞。
- 应用选择已经固定，但集成边界保持可替换：删除逻辑分析仪并换成 SPI、传感器或其他加速器时，只能修改应用外设、SoC 地址表和软件，不能修改 CPU Core。

## 5. Pipeline 与性能观察

- 最终基础架构采用经典 IF、ID、EX、MEM、WB 五级流水线。
- Hazard 按 Forwarding、Load-Use Stall、Branch/Jump Flush、复杂交叉场景依次实现。
- 错误路径指令不得产生寄存器、RAM 或 MMIO side effect，也不得生成有效提交事件。
- Core 输出 retire、stall、load stall、branch、taken branch 和 flush 等统一事件；优先由 Core 外部性能监视器完成 cycle/instret 等计数和 MMIO 映射，避免把软件可见外设接口耦合进流水级控制。
- CoreMark 前必须实现并验证 cycle、instret、stall、load stall、branch、taken branch 和 flush 计数器。
- CoreMark 正式运行不少于 10 秒；保留编译参数、镜像、bitstream、频率和报告的对应关系。
- Pipeline Baseline 冻结时必须保存 ILA 关键波形、CPI 分解、资源、时序、CoreMark/MHz 和 CoreMark/LUT。

### 5.1 Task 18 五级流水线字段与停顿约定

流水线固定为顺序发射、顺序退休的 `IF -> ID -> EX -> MEM -> WB`。所有对外存储访问继续遵循统一事务接口；MEM 级只表达通用读写事务，绝不包含 RAM、UART、GPIO 或应用外设的地址译码。

```text
 fetch_pc -> IF request/response -> IF/ID -> decode -> ID/EX -> ALU/compare -> EX/MEM
                                                        |                         |
                                                        +------ redirect ----------+
 EX/MEM -> generic D request/response -> MEM/WB -> register writeback + commit trace
```

冻结的流水寄存器字段如下：

| 寄存器 | 必须保存的字段 | 目的 |
|---|---|---|
| IF/ID | `valid`、`pc`、`instruction`、取指错误、预测命中/方向/目标 | 将已完成的取指响应和对应预测元数据送入译码；取指错误装入零指令并保留错误位。 |
| ID/EX | `valid`、`pc`、`instruction`、错误位、预测命中/方向/目标、`rs1/rs2 data`、`rs1/rs2/rd`、`imm`、`funct3`、ALU/写回/访存/控制流控制位 | 确保 EX 不依赖后续 IF/ID 的组合译码结果，并可用真实分支结果校验预测。 |
| EX/MEM | `valid`、`pc`、`instruction`、`alu result`、`store data`、`imm`、`rd`、`funct3`、RegWrite/MemRead/MemWrite/ResultSrc | 保持一笔通用数据事务所需字段，直到唯一响应完成。 |
| MEM/WB | `valid`、`pc`、`instruction`、`alu result`、`load result`、`imm`、`rd`、RegWrite/ResultSrc、Store trace 字段及访问错误位 | 唯一产生寄存器写回与提交级 trace 的阶段。 |

`valid=0` 是 Bubble，不能写寄存器、不能建立数据事务、不能产生有效提交。MEM 等待某笔已接受的数据事务响应时，EX/MEM 必须保持，前端停止推进；请求等待 `ready` 时所有请求字段保持稳定。Control redirect 在 EX 级产生：更年轻的 IF/ID 与 ID/EX 指令必须失效，已经接收但属于错误路径的取指响应必须丢弃。已在 MEM 级被下游接受的数据事务不可撤销，因而 redirect 不得影响比该控制流指令更老的 EX/MEM 指令。

Task 18 只冻结以上结构和时序边界。现有候选 RTL 中的 Forwarding、Load-Use Stall 和 Flush 控制不得提前宣称通过；这些功能分别由 Task 20、21、22 的独立定向回归验收。

### 5.2 取指满速交接约定（2026-09-17 CPI 专项冻结）

`docs/interfaces.md` §3 早已要求「流水线 IF 允许在旧取指响应完成握手的同一拍接受下一请求，
以支持一拍一条的连续取指」。CPI 专项实测发现原实现**没有做到**：请求被接受的下一拍没有任何请求对外可见，
每笔取指固定占 2 拍，CPI 被钉在 2.34（见 `docs/coremark_cpi_analysis.md` §2、`docs/rtl_changes.md` 改动 2）。

现在冻结如下约定，后续任何 IF 改动都必须保持：

1. **Core 侧**：接受一笔取指请求的**当拍**就必须武装下一笔请求（`if_arm`），使下一拍
   （即旧响应被接收的那一拍）新请求已经在场，可以同拍完成“旧响应接收 + 新请求接受”的交接。
2. **SoC 侧**：取指存储器的 `req_ready` 必须允许在“响应被接收”的同一拍接收新请求
   （`!rsp_valid||rsp_ready`）；交接当拍 `rsp_valid` 保持为 1、`rsp_data` 换成新请求的数据。
3. **单 outstanding 语义不变**：`*_ready` 策略保证“存在未完成、未被接收的响应时下游不接受新请求”，
   任意时刻仍然只有一笔未完成事务。
4. **字段稳定不变**：`valid && !ready` 时请求地址必须保持；因此 `if_arm` 的展示地址直接取自
   `fetch_pc` 寄存器（不新增寄存级），Redirect 当拍先把在场请求冻结进 `if_req_addr_reg` 再改 `fetch_pc`。
5. **数据端口不需要该策略**：`dstate`（`D_IDLE/D_REQ/D_RSP`）已把数据事务串行化，没有交接场景。

这组约定属于 Core 内部时序 + Core 外部 adapter 的 ready 策略，**不改变任何端口、事务字段或 trace 语义**。

### 5.3 控制流重定向只由"预测错误"触发（A1，2026-09-28）

**背景与量化依据**：原实现在 EX 级对 `idex_jump`（JAL/JALR）**无条件**重定向，同时对条件分支按
`idex_pred_taken != branch_taken` 或目标不符重定向。问题在于跳转同样被 BTB 查询过：只要预测命中，
IF 就已经沿正确目标取指，此时再重定向一次等于把前端三条指令白扔掉。更糟的是跳转的 BTB 训练值
取自对 JAL/JALR 无意义的 `branch_unit` 比较结果，跳转项几乎永远不会被训练成 taken，于是每次跳转都
必然误预测。板级 CoreMark 窗口里这类"预测本可正确却被强制重定向"的跳转约占 28,500 次/迭代。

**冻结的设计决定（两部分，缺一不可）**：

1. **`rtl/branch_predictor.v` 区分"分支"与"跳转"**：每个 BTB 项新增 1 bit `is_jump`。
   查询命中 `is_jump` 项时直接输出 `predicted_taken=1`，不再看 2-bit 饱和计数器；
   2-bit 计数器仍按原语义服务条件分支。理由：条件分支的方向未知、必须靠计数器学；
   而 JAL/JALR 恒 taken，方向不需要学。让两者共用计数器只会让跳转被分支污染成 not-taken。
   `update_taken` 对跳转项恒为真，`update_target` 恒取 EX 算出的真实目标。
2. **`rtl/pipeline_cpu.v` 只在校验失败时重定向**：新增
   `control_resolve`（本条是控制指令且在 EX 且未被访存阻塞）、
   `control_taken`（分支看 `branch_unit`，跳转恒 1）、
   `pred_direction_ok`、`pred_target_ok`、`control_mispredict`。
   `ex_redirect = control_mispredict`。重定向目标统一为 `control_taken ? ex_target : idex_pc + 4`。

**安全性论证**（这是能改的前提，不是"能跑就行"）：

- 预测"对了"的判据是**方向一致且目标相等**（目标只在真实跳走时才比较），
  所以任何目标不符都仍然走重定向，错误路径不会被放行。
- JAL 的目标由 `PC + J 立即数`决定，立即数来自指令位，因此 BTB 一旦命中就一定算对；
  JALR 的目标依赖 `rs1`，BTB 里的目标可能过期，因此**必须**保留目标比较兜底。
- `idex_jump || idex_branch` 之外的控制指令不存在，`control_resolve=0`，
  所有比较都不触发，非控制指令行为逐位不变。
- `ENABLE_BRANCH_PREDICTOR=0` 时 BTB 恒不命中、`pred_taken=0`，
  跳转与 taken 分支都仍然误预测并重定向，Always-Not-Taken Baseline 语义不变。

**事件口径（不许混用历史数据）**：

| 事件 | 语义 | 与改动前的关系 |
|---|---|---|
| `event_branch` | 只统计条件分支 | **不变**，历史 branch_count 可直接比较 |
| `event_branch_taken` | 只统计 taken 的条件分支 | **不变** |
| `event_predict` | 所有被解析的控制指令（分支 + 跳转） | 口径**扩大**了（新增跳转），新材料必须注明 |
| `event_btb_hit` | 解析时该控制指令在 BTB 中命中 | 口径随之扩大 |
| `event_mispredict` | 方向或目标校验失败 | 改动前跳转从不计入，现在计入 |
| `event_flush` | 实际发生的重定向 | 语义不变，数值因优化下降 |
| `event_control_redirect` | **新增**：预测正确因而免掉重定向的控制指令数（仅 taken 分支与跳转） | 无历史对应项 |

**量化收益（同一工作区、同一镜像、Predictor On、RTL 仿真）**：

| 指标 | Before | After | 变化 |
|---|---:|---:|---:|
| CoreMark cycles | 1,295,932 | 1,251,724 | **−44,208（−3.41%）** |
| CPI | 1.6539 | 1.5906 | −0.0633 |
| flush_count | 81,562 | 69,120 | −12,442 |
| 官方四 CRC 与 `Correct operation validated.` | 全过 | 全过 | 一致 |

**明确不宣称的内容**：赛题页与旧文档里"约 7.7% 周期空间"是**估计上界**，本轮实测为 3.41%，
差距来自 JALR（函数返回）目标依赖运行期值、16 项 BTB 容量有限，并非所有跳转都能预测正确。
不得把 7.7% 写成已实现收益。

**影响面**：涉及 `rtl/branch_predictor.v`、`rtl/pipeline_cpu.v`、`rtl/perf_monitor.v`
（新增只读计数 `control_redirect_count`）及对应 Testbench；
**不改变 Core/SoC 事务字段、握手语义、提交 trace 字段或 architectural state**。

## 5.4 精确 Trap 数据通路（A3，2026-09-28）

契约以 `docs/trap_contract.md` 为唯一来源；本节只记录**实现**层面的决定，
以及"为什么这样接"和"改哪里会破坏什么"。

### 5.4.1 检测级与"异常记录"

每条指令携带一条 4-bit 异常记录（`EXC_NONE/IFETCH_ERR/ILLEGAL/EBREAK/LOAD_MIS/
STORE_MIS/LOAD_ACC/STORE_ACC/ECALL/INSTR_MIS`）沿 `IF→ID→EX→MEM→WB` 前进，规则只有一条：
**先到先得**——只在进入某一级时填一次，已有记录就不再覆盖。因为指令按程序序逐级推进，
先填进去的必然是程序序更早的异常，因此天然满足契约 §5.2 的优先级要求，
不需要再写一张"同拍多个异常谁赢"的组合优先级表。

| 级 | 能确定的异常 | 说明 |
|---|---|---|
| IF | 取指错误、取指地址未对齐 | `i_rsp_error` 与 `pc[1:0]` |
| ID | —— | 只把 IF 的记录搬到 ID/EX；译码得到 `csr_en/trap_ecall/trap_ebreak/trap_mret` |
| EX | 指令地址未对齐、非法指令、CSR 非法、`ECALL`、`EBREAK`、访存未对齐 | 访存未对齐在 EX 就能判，见 5.4.3 |
| MEM | 访存访问错误 | 必须等下游响应回来才知道 |

`mtval` 不单独存：它的语义是"出错的地址或指令码"，这两样本来就躺在流水寄存器里
（`memwb_pc` / `memwb_inst` / `memwb_alu`），在 WB 级按原因码选择即可。

### 5.4.2 Trap 接受点：退休边界（WB）

`trap_take = !mem_block && memwb_valid && (有同步异常 || irq_grant)`。

- **只在 WB 接受**：此时"比出错指令更老"的指令全部已经退休并产生副作用，
  满足契约 §5.1 第 1 条；而"更年轻"的指令仍在 EX/MEM、ID/EX、IF/ID 里，可以整体取消。
- **同步异常**取消出错指令本身（`wb_cancel = trap_take && 有同步异常`），
  `wb_fire`（写回与提交记录）因此落下，契约 §5.1 第 3 条成立。
- **中断不取消** WB 这条指令：中断在语义上发生在它**提交之后**。
  这是"同步异常优先于中断"的具体落点。
- `mem_block` 期间不接受 Trap，避免"访存还没完成就改 PC"。
- `MRET` 在 EX 级解析并重定向到 `mepc`；Trap 同拍优先，此时 `MRET` 被取消，
  既不改 PC 也不改 `mstatus`（契约 §5.2 第 6 条）。

### 5.4.3 访存未对齐为什么在 EX 级再判一次

未对齐只要有地址就能确定，把它放在 EX 可以和非法指令、`ECALL/EBREAK` 走同一条通路。
判定规则**直接再例化一个 `load_store_unit`**（`lsu_ex`），而不是手写一份比较：
规则只能有一个出处，否则日后改了一处漏一处，EX 的"要不要报未对齐"与
MEM 的"要不要发总线事务"就会互相矛盾。MEM 级的那一份仍然保留，
负责"不发出总线事务"和 `event_misaligned`（每条指令恰好一次脉冲）。

### 5.4.4 `mepc` 与 `mtval` 的来源

| 情形 | `mepc` |
|---|---|
| 同步异常（含取指、未对齐、非法、`ECALL`/`EBREAK`） | 出错指令自己的 PC（`memwb_pc`），**不是 PC+4** |
| Store 访问错误 | 出错 Store 的 PC+4（契约 §5.1 第 4 条：请求已被下游接受，视为在 Trap 之前提交，避免 handler 重试造成第二次总线副作用） |
| 中断 | `memwb_next_pc`——本条指令**程序序上的下一条**，即"还没执行的那条" |

`memwb_next_pc` 随指令一起流过流水线（EX 级按"是否真的跳走"算出），
不能用 `exmem_pc` 顶替：跳转/分支重定向当拍，EX/MEM 里可能正是一个气泡。

`mtval`：非法指令/`EBREAK` → 指令码；`ECALL` 与中断 → 0；
取指错误/未对齐 → 出错取指地址；访存未对齐/访问错误 → 出错访存地址。

### 5.4.5 中断输入为什么只有三根

Core 只接 `irq_software_i` / `irq_timer_i` / `irq_external_i` 三根设备无关电平，
加对应使能位构成请求。定时器、中断控制器、使能、聚合、优先级全部在 SoC 侧；
`mip` 只是这三根线的只读窗口，Core 不锁存、不清除，因此**中断的清除是软件对 SoC 的动作**，
Core 里不会出现任何设备名、设备地址或设备状态机（`AGENTS.md` §8）。

### 5.4.6 影响面

涉及 `rtl/pipeline_cpu.v`（异常记录、Trap 接受点、`MRET` 重定向）、新增 `rtl/csr_unit.v`、
`rtl/decoder.v`（`ENABLE_SYSTEM` 参数，默认 0 保持单周期 Reference Model 逐位不变）。
**不改变** `i_req_*`/`i_rsp_*`/`d_req_*`/`d_rsp_*` 的事务语义、握手规则与字段，
也不改变已有的提交 trace 字段；新增的只有三根通用中断输入与两个 Trap 观察事件。

## 5.5 M 扩展（RV32IM）的乘除法单元（2026-10-14）

### 5.5.1 为什么做

CoreMark 的矩阵段每次迭代固定 10,575 次乘法，RV32I 下全部走 libgcc `__mulsi3` 的移位加循环
（反汇编实测循环体 6 条指令、平均 7.94 次循环迭代/次乘法；板级 ILA 窗口 84.3% 的提交落在该循环里）。
按指令数折算，**约 60% 的退休指令花在软件乘法上**（`docs/coremark_cpi_analysis.md` §5 之后的最大单项）。
板级实测 CoreMark/MHz **0.936 → 2.272**（2.43×）。

### 5.5.2 数据通路

```text
ID/EX ──┬─ idex_mdu_en / idex_mdu_op[2:0] ─┐
        │  (decoder 对 funct7=0000001 整组译码) │
        └─ srca0 / srcb0（已前递的源操作数）──┴─► rtl/mdu.v ──► ex_result ──► EX/MEM
                                                        │
                                        busy ───────────┘（mdu_block：把 ID/EX 冻在 EX）
```

- **乘法组**（`op[2]=0`，mul/mulh/mulhsu/mulhu）：**3 拍**。
  第 1 拍锁操作数 → 第 2 拍把 32×32 拆成两个 **16×32** 部分积并寄存 → 第 3 拍移位相加 + 符号修正。
  为什么不是 1 拍组合：32×32 被综合成 **4 级串联 APM**，85 MHz 下 Slack −3.268 ns。
  四种语义共用一个无符号全积，`mulh/mulhsu/mulh` 只差"操作数符号位各自贡献的一份修正项"。
- **除法组**（`op[2]=1`，div/divu/rem/remu）：**32 拍**恢复余数法（shift-subtract），
  有符号按"绝对值相除 + 末拍补符号"，除零返回全 1 / 被除数，溢出（−2³¹/−1）自然正确。
- **握手**：`run`（EX 上有一条 M 指令）+ `ack`（该指令连同结果被锁进 EX/MEM 的那一拍）。
  `ack` 的意义是**区分"还是同一条"与"换了一条"**——背靠背的同类指令之间 `run` 从不落下，
  缺了它第二条会沿用第一条的结果（实测 `rem` 返回了商）。

### 5.5.3 与流水线的耦合点（两处，都必须留在契约里）

1. **`mdu_block`**：结果没就绪时把 ID/EX 冻在 EX。它是**EX 级**的暂停，与 MEM 级的 `mem_block` 是两回事。
2. **`exmem_retired`**：访存的"完成"由握手定义（`dstate` D_RSP→D_IDLE 只发生一次），
   而 MEM→WB 原来与"ID/EX 换入 EX/MEM"**同拍原子发生**。加入 EX 级暂停后两者被拆开，
   必须有一个"这条 EX/MEM 记录已经退休过"的标记，MEM 级才能与 EX 级解耦排空
   （否则 `mem_done` 在握手结束那拍落下、`mem_block` 永久为 1，实测整机死锁）。

### 5.5.4 边界

- **Core 对外端口一根未改**（`docs/interfaces.md` §293～299 不变）：M 是 ISA 扩展，不是外设。
- **单周期 Reference Model 必须同 ISA**：两个 CPU 共用 `rtl/decoder.v` 的 M 译码与 `rtl/mdu.v`，
  否则"最终架构状态一致"的比较在任何用到乘除法的程序上直接失效。
- 引用 CoreMark 分数时**必须写明 ISA**：`rv32i`（默认/可比口径）与 `rv32im`（增强口径）并列，
  CoreMark 输出自带 `Compiler flags` 一行可自证。

## 6. 本届评分范围、高阶功能与删减边界

- 评分主线及取舍以 `docs/competition_scoring.md` 为准：完整 RV32I、五级流水线与 Hazard、UART/GPIO、CoreMark 三项性能指标、实际应用、ILA 分析和规范材料全部为 P0。
- 官方“高级控制逻辑”按“动态分支预测以及完整异常/中断”描述。本届按期初的 BTB 完成其中"动态分支预测"一项；"完整异常/中断"按 `docs/trap_contract.md` 的机器模式子集另行实现，只有该契约逐项 PASS 才宣称完成该高阶组，且必须附覆盖表。
- 最终流水线采用 16 项直接映射 BTB + 2-bit 饱和计数器，只预测条件分支；IF 携带命中、方向和目标元数据，EX 用真实结果恢复错误路径。
- 以 Predictor Off 为 Always-Not-Taken Baseline，统计 prediction、BTB hit 和 misprediction，并比较 Predictor Off/On 的 CoreMark 周期、CPI、LUT、FF 与 Fmax。
- BTB 单项不宣称完成官方“高级控制逻辑”；完整异常/中断仍不属于本届范围。
- **2026-09-29 经用户批准的范围变更**：**I-Cache、D-Cache、burst 与外部 DDR3 由"本届不做"改为"本届要做"**
  （`AGENTS.md` §1.14），作为官方高阶项①按 S1→S2→S3→S4 推进；接口契约见 `docs/interfaces.md`
  §5.1（行/突发适配器）与 §5.2（D-Cache），实测结论见本文 §3.1/§3.1.1。
  **本届仍明确不做**：U/S 模式、向量 Trap、Debug Mode、`WFI`（机器模式子集已按 `docs/trap_contract.md` 实现）、
  AI/YOLO、自定义 RISC-V 指令、HDMI、PCIe 和千兆网；RLE 仍为赛后研究。
- 接口文档的 Cache 解耦扩展原则**已从"防止绑死"升级为"已实现的契约"**：
  Cache/突发全部位于 Core 外部，**`rtl/pipeline_cpu.v` 的端口与事务语义未变**（SHA-256 前缀 `B58496706686E37B`）。
- 逻辑分析仪 P0 固定为 8 通道、基础边沿/电平/掩码触发、前后采样、BRAM、Raw、UART/SPI 软件解析和简单 Python/VCD；本届冻结 RLE。16 通道、I²C、协议感知/多级触发、外部 DDR 和复杂 GUI 均删除。

## 7. 尚待对应 Gate 决定的项目

- 内部上电复位实现和 BRAM 实测结果：Task 10。目标器件、时钟、UART、按键/LED、J8、PMOD 管脚及电平均已由 MES50HP 手册确认；逻辑分析仪 8 路输入/输出映射已冻结，完整表见 `docs/fpga_platform.md`。
- RAM/MMIO 地址映射、单周期 adapter 和互连逐根信号名：Task 15。
- 流水寄存器字段、控制信号和流水线 Core 顶层逐根端口名：Task 18；接口语义必须保持与 `docs/interfaces.md` 一致。
- 逻辑分析仪 8 路物理输入和 8 路激励输出固定在 J8 隔行相邻脚对 `3/4、7/8、11/12、15/16、19/20、23/24、27/28、31/32`（输出奇数脚、输入偶数脚）。板外结果链路使用 CP2102 UART；不能用内部回环冒充物理闭环，也不得要求修改五级流水线主体。
- 赛后 RLE 的记录格式、最大游程和溢出策略：只有本届提交完成且 Task 31 被重新立项时决定。
- BTB 使用 `PC[5:2]` 索引、`PC[31:6]` 标签，在 EX 条件分支解析时更新；错误方向或错误目标均恢复到真实下一 PC，不改变 architectural state 或 Core/SoC 外设接口。

## 8. Task 30 应用层实现决策（2026-09-14）

- Capture Engine 使用系统时钟加 clock-enable，不生成新的采样时钟；默认 8 通道、256 条 Raw BRAM 记录。
- `application_mmio_mux` 将通用 Application 窗口分为性能计数器 `0x1000_2000..0x1000_20FF` 和逻辑分析仪 `0x1000_2100..0x1000_21FF`。两个设备均以单 outstanding `valid/ready` 响应，地址在设备接受请求时转成本地 offset。
- 逻辑分析仪读取采用显式 `READ_INDEX` + `READ_DATA`，不使用读后自增 side effect；因此随机响应背压不会重复或跳过样本。
- MES50HP 应用顶层的 `capture_ch`/`loopback_tx`、UART、LED 和内部上电复位均为 Core 外部板级端口。软件只访问普通 MMIO，Pipeline Core 源文件与基础 SoC 复用不变。
- PDS 顶层使用同步数组和固定深度 `.mem` 初始化 Task 30 IMEM/DMEM，PDS 将其映射到 DRM；`LOGIC_ANALYZER_SIM` 只改变相对文件路径，不改变存储器时序。正式固件为 `AUTOSTART=0` 的 UART 交互版本。
- `logic_analyzer_pattern_gen` 位于 Core 外，产生静态、计数器、UART 8N1 或 SPI mode 0 激励并送往 J8。采样输入也来自 J8 的相邻输入脚，实体演示用 8 根跳线逐对闭合输出/输入脚。
- Task 28 CoreMark 将 8192-word IMEM、4096-word只读数据和4096-word运行 RAM 分离成同步初始化 DRM。上电等待 `R` 再进入计时区间，避免串口连接延迟进入 CoreMark 时间。
