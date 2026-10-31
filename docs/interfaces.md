# Core / SoC Interface Contract

> 最后更新：2026-09-14
> 当前状态：单周期与流水线 Core 都复用同一事务语义；流水线 `pipeline_cpu` 的逐根端口在 Task 18 冻结，Task 19～25 及 Task 30 回归与 PDS 已通过。应用 MMIO 子窗口和可编程激励发生器均位于 Core 外部。

本文档定义 CPU Core 与 SoC、存储器、外设之间的稳定边界。目标是让 UART、GPIO、逻辑分析仪、传感器、SPI 或其他加速器可以在 Core 外部增加、删除或替换，而不重新设计 IF、ID、EX、MEM、WB、Hazard、Forwarding、Stall 或 Flush。

## 1. 分层边界

```text
                          +-------------------------------+
                          |        single/pipeline core   |
  instruction response <-| instruction transaction port  |
  instruction request  ->|                               |
  data response        <-| data transaction port         |
  data request         ->|                               |
  generic interrupt    ->| interrupt input (later Gate)  |
  commit/perf events   <-| trace and event outputs       |
                          +---------------+---------------+
                                          |
                         stable Core / SoC boundary
                                          |
       +------------------+---------------+-------------------+
       | instruction/data adapter + address decode/interconnect|
       +--------+---------+--------+---------+---------+-------+
                |                  |          |         |
              RAM/ROM            UART       GPIO      SPI / sensor /
                                                       logic analyzer /
                                                       accelerator
```

### Core 内部负责

- RV32I 指令执行、PC、Register File、ALU 和 Load/Store 语义。
- 单周期或 IF/ID/EX/MEM/WB 五级流水线数据通路。
- Forwarding、Load-Use Stall、Control Hazard、Branch/Jump Flush。
- 把取指和数据访问表达成统一事务，并正确等待事务完成。
- 提交级 trace 和与流水线行为直接相关的性能事件输出。
- 未来赛后异常/中断研究所需的精确 Trap 行为和通用中断输入扩展点；本届不实现。

### Core 外部负责

- RAM/ROM/BRAM 控制器、Cache、总线 adapter、地址译码和互连。
- UART、GPIO、SPI、传感器、逻辑分析仪、加速器及其寄存器。
- MMIO 地址表、设备片选、未映射地址响应和设备级等待状态。
- 厂商总线/IP 接口、时钟域转换、引脚和板级顶层。
- MES50HP 专用的 50 MHz 时钟、内部/外部 Reset 选择、按键/LED 极性转换、CP2102 UART/扩展口连接和 `.fdc` 约束；完整规则见 `docs/fpga_platform.md`。
- 可由 Core 事件驱动、再通过 MMIO 读取的性能监视器。

禁止在 Core 中出现 `uart_*`、`gpio_*`、`spi_*`、`sensor_*`、`capture_*` 或某个加速器专用端口、地址常量和状态机。外设变化只能影响 SoC 顶层、互连、外设 RTL、地址表和软件驱动。

换接 UART、GPIO、逻辑分析仪、传感器、SPI 或其他加速器时，只允许替换 Core 外部的 MMIO 从设备、adapter/wrapper、地址表和软件驱动；CPU Core 源文件、Core 顶层端口及 IF/ID/EX/MEM/WB 流水线主体必须保持不变。

## 2. 统一事务语义

第一版采用分离的取指端口和数据端口（Harvard 形式）。接口遵循 request/response 与 `valid/ready` 握手语义；首版允许每个端口最多存在一个未完成事务，以降低实现和验证难度。

### 2.1 取指事务

请求至少包含：

- `valid`：请求有效。
- `ready`：下游在本周期接受请求。
- 32-bit 字节地址 `addr`，RV32I 正常取指时按 4 字节对齐。

响应至少包含：

- `valid`：响应有效。
- `ready`：Core 在本周期接受响应。
- 32-bit 指令 `data`。
- `error`：未映射、访问错误或后续定义的取指故障。

#### 2.1.1 Task 15 单周期取指端口命名冻结

| 信号 | 方向 | 语义 |
|---|---|---|
| `i_req_valid` | Core → SoC | 当前 `PC` 的取指请求有效；`i_req_ready=0` 时 `i_req_addr` 保持稳定。 |
| `i_req_ready` | SoC → Core | SoC 接收当前取指请求。 |
| `i_req_addr[31:0]` | Core → SoC | 32-bit 字节取指地址；RV32I 正常路径按 4-byte 对齐。 |
| `i_rsp_valid` | SoC → Core | 指令响应有效。 |
| `i_rsp_ready` | Core → SoC | Core 准备接收一条指令响应。 |
| `i_rsp_data[31:0]` | SoC → Core | 对齐的 32-bit 指令。 |
| `i_rsp_error` | SoC → Core | 取指失败；当前过渡实现将其装载为零指令以禁止副作用，完整异常/Trap 不属于本届范围。 |

`instruction_reg` 仅保存已经过 `i_rsp_valid && i_rsp_ready` 握手的指令。Core 在 `IF_REQ`、`IF_RSP`、`IF_DONE` 间运行，取指等待周期不得移动 PC、执行旧指令或生成提交事件。

### 2.2 数据事务

请求至少包含：

- `valid`、`ready`。
- 32-bit 字节地址 `addr`，保留有效地址的低两位。
- `write`：读/写方向。
- 32-bit 写数据 `wdata`。
- 4-bit 字节写使能 `wstrb`；`wstrb[n]` 对应对齐字地址 `{addr[31:2], 2'b00} + n` 的 byte lane。

响应至少包含：

- `valid`、`ready`。
- 32-bit 读数据 `rdata`。
- `error`：未映射、访问错误或后续定义的 Load/Store 故障。

#### 2.2.1 Task 15 单周期数据端口命名冻结（进行中）

当前 `rtl/single_cycle_cpu.v` 已使用以下逐根数据端口。方向均以 Core 为参照；这些名称由 Task 15 的外部 RAM、互连及 Testbench 使用，后续 UART/GPIO/Application wrapper 必须复用，不得把设备专用信号加入 Core。

| 信号 | 方向 | 语义 |
|---|---|---|
| `d_req_valid` | Core → SoC | 数据请求有效；等待 `d_req_ready` 时请求字段稳定。 |
| `d_req_ready` | SoC → Core | SoC 接收当前请求。 |
| `d_req_addr[31:0]` | Core → SoC | 字节地址。 |
| `d_req_write` | Core → SoC | `1` 为 Store，`0` 为 Load。 |
| `d_req_wdata[31:0]` | Core → SoC | 按 byte lane 对齐的 Store 数据；Load 时忽略。 |
| `d_req_wstrb[3:0]` | Core → SoC | Store byte enable；Load 时为零。 |
| `d_rsp_valid` | SoC → Core | 已接受请求的唯一完成响应。 |
| `d_rsp_ready` | Core → SoC | Core 接收响应。 |
| `d_rsp_rdata[31:0]` | SoC → Core | 对齐 32-bit Load 数据；Store 时忽略。 |
| `d_rsp_error` | SoC → Core | 访问失败；当前单周期过渡实现禁止 RegFile/Store 副作用并继续 PC，完整 Trap 不属于本届范围。 |

Task 15 的取指/数据逐根端口名称和事务语义现已在单周期候选 Core 使用。仍需完成历史 Core Testbench 对外部 adapter 的统一适配，以及 Task 16 的真实 UART/GPIO wrapper；在这些验证完成前不得冻结 `single_cycle_stable`。

数据采用 RV32I little-endian 语义。读响应返回包含目标地址的对齐 32-bit word，Core 根据 `addr[1:0]` 和 Load 类型完成 byte/halfword 选择与扩展；Store 时 Core 产生与 `SB/SH/SW` 对应的 `wstrb` 和按 byte lane 对齐的 `wdata`。下游不需要知道当前执行的是哪一种 RISC-V 指令。非对齐或跨 word 访问的支持策略由 Task 12 明确，接口本身不静默拆分事务。

## 3. 强制握手规则

1. 请求只在 `req_valid && req_ready` 的周期被接受。
2. `req_valid && !req_ready` 时，Core 必须保持地址、方向、写数据和字节使能不变。
3. 每个被接受的请求必须产生且只能产生一次响应；写响应表示完成确认，其 `rdata` 被 Core 忽略。第一版同一端口不得在上一事务完成前发出第二个事务。
4. 一次请求握手只建立一个写事务。目标 side effect 可以在下游稍后完成，但必须在成功响应前恰好发生一次；保持 `req_valid`、等待、Stall 或响应重放不得造成重复写。
5. 下游延迟只能通过统一握手令 Core 等待，不得向 Core 增加 `uart_busy`、`spi_done` 等设备专用控制信号。
6. 被 Flush 的错误路径指令不得发出数据事务；已经被下游接受的事务必须按架构规定完成或在发出前被阻止，不能依赖外设撤销 side effect。
7. `rsp_valid && !rsp_ready` 时，下游必须保持响应数据和错误标志稳定，直到响应被 Core 接受。
8. 请求和响应通路不得形成无法收敛的组合环；具体寄存切分在对应 Gate 结合时序报告决定。
9. Reset 后不得残留有效请求、响应或设备写 side effect。

流水线 IF 允许在旧取指响应完成握手的同一拍接受下一请求，以支持一拍一条的连续取指；这仍属于单 outstanding 的边界交接。若 Redirect 发生在一个已展示但尚未接受的请求期间，Core 不得撤回 `valid`，而是完成请求握手并丢弃对应错误路径响应。

#### 3.1 取指前端的两种展示形式与"稳定性"的确切含义

第 2 条要求的是 **`req_valid && !req_ready` 期间字段保持稳定**；它并**没有**要求 `valid` 必须
一直保持为高。流水线 IF 对外的取指请求有两种展示形式，二者在事务语义上等价，
但"可撤回性"不同，后续改动不得混淆：

| 形式 | 来源 | 可撤回性 |
|---|---|---|
| `if_req` | 已冻结在 `if_req_addr_reg` 中的请求，等待 `i_req_ready` | **不可撤回**。一旦展示，地址、方向等字段在 `!ready` 期间必须逐拍保持；Redirect 只能把它标成丢弃，等它正常握手返回后丢弃响应。 |
| `if_arm` | 刚接受完上一笔请求后，用 `fetch_pc` **组合**呈现的下一笔请求 | **可撤回**。它属于"尚未被下游接受"的乐观呈现；在该拍出现 Redirect/Flush（含 Trap）时被收回是合法的，此时它会转成 `if_req` 形式冻结。 |

由此得到两条纪律：

1. 判"请求稳定性"时，只能在**同一笔请求持续在场**的前提下比较字段；
   若 `i_req_valid` 落下，说明该请求已被 Redirect 收回，不构成违例。
2. 不得为了满足更严的隐含假设（例如"`valid` 必须保持"）而给 `if_arm` 叠加额外的冻结寄存器或
   强制重启逻辑。实测过 `if_restart`（前端静默一拍重启）与 `if_arm_addr_reg`（寄存展示地址）
   两种做法：前者在请求被下游挂住时把请求撤掉，与单 outstanding 握手不兼容；
   后者地址虽稳定，但同一拍 `if_arm` 仍会被清除而落下 `valid`，问题照旧。
   **要改的是判据，不是 RTL。**


对首个行为级单周期 Reference Model，可使用始终就绪、固定零/一拍响应的 adapter；该简化只属于测试/存储 adapter，不能改变上述 Core 边界。流水线版本必须能通过可变延迟和随机背压测试。

### 3.2 SoC 数据地址窗口（Core 外部，2026-09-28 增补定时器）

Core 只发"通用数据事务"，**地址译码全部在 Core 外的互连里**。当前窗口表：

| 窗口 | 范围 | 目标 | 说明 |
|---|---|---|---|
| RAM | `0x0000_0000` ~ `RAM_LAST_ADDR`（按配置 0x3FF / 0xFFF / 0xFFFF） | 数据 RAM | 各工程按容量参数化 |
| UART | `0x1000_0000` ~ `0x1000_00FF` | `uart_mmio` | 基础 SoC 参考外设 |
| GPIO | `0x1000_1000` ~ `0x1000_10FF` | `gpio_mmio` | 基础 SoC 参考外设 |
| APP | `0x1000_2000` ~ `0x1000_2FFF` | `application_mmio_mux` | 性能计数器 + 逻辑分析仪等应用寄存器 |
| **TIMER** | `0x1000_3000` ~ `0x1000_30FF` | `timer_mmio` | **A3 新增**：`mtime`/`mtimecmp`，聚合出 `irq_timer` |
| 未映射 | 其它 | —— | 必须返回 error 响应，不得静默丢弃 |

约定：新增外设只允许**新增窗口或复用 APP 窗口内部的子区间**，
不得改动上表已有窗口，也不得把这些地址常量或译码逻辑放进 CPU Core。
`timer_*` 端口在不需要定时器的配置里可以留空：没有地址译码到该窗口时它的取值不会被任何组合路径选中。
## 4. MMIO、地址译码与外设替换

- Core 只发出普通数据事务，不判断地址属于 RAM 还是外设。
- SoC 互连根据地址表选择唯一目标，并汇合目标的响应。
- 未映射地址、重叠区域和访问宽度错误由互连/目标 wrapper 按 Task 15 约定返回，不在流水线中硬编码。
- UART、GPIO 是基础 SoC 的参考配置，不是 Core 的组成部分。
- 替换或新增 SPI、传感器、逻辑分析仪或加速器时，只增加/替换目标 wrapper、地址区域和软件驱动；Core 源文件及其回归测试不得改动。
- 当前比赛应用已经选定为可重构多协议逻辑分析仪，其 Capture Engine、Trigger、BRAM 和 MMIO wrapper 均属于外设层；本届冻结的 RLE 即使赛后研究也只能位于外设层。具体功能以 `docs/application_logic_analyzer.md` 为准，且该应用规格不得覆盖或削弱本文的 Core/SoC 契约。
- MMIO 写必须精确且不可重复；具备 side effect 的读同样不得被预取、合并或重复。
- Task 30 的 Application 子窗口由 SoC 外部 `application_mmio_mux` 汇合：性能计数器使用 `0x1000_2000..0x1000_20FF`，逻辑分析仪使用 `0x1000_2100..0x1000_21FF`；设备看到的地址是窗口内 byte offset，不含固定基地址。
- 逻辑分析仪的 `READ_INDEX`/`READ_DATA` 是普通 MMIO 读写，`READ_DATA` 不隐式移动指针；Capture Engine 的采样输入和激励输出只存在于 board wrapper，绝不进入 `pipeline_cpu`。
- 逻辑分析仪本地 offset `0x38` 为 pattern control，`0x3C` 为 16-bit divider，`0x40` 为 8-bit data，`0x44` 为只读 output。control `[1:0]` 选择 static/counter/UART/SPI，bit 2 产生一次 restart 脉冲。所有窄寄存器写入遵守 `wstrb`，零 strobe 无副作用。
- Task 30 固件 RAM 地址上界为 `0x00000FFF`；IMEM 与 DMEM 均为 1024×32，同一链接镜像的栈顶为 `0x1000`。该 SoC 地址范围属于 wrapper 参数，未写入 Core。
- **2026-10-21 新增第三子区间**：提交级 trace 使用 `0x1000_2200..0x1000_22FF`（`rtl/core_trace_mmio.v`）。
  它由 `rtl/application_mmio_mux3.v` 在外层汇合：`req_addr[11:8]==4'h0/1` 原样转给**未修改**的
  `application_mmio_mux`，`==4'h2` 截走给 trace，其余仍由内层报"未映射"。
  规格见 `docs/application_logic_analyzer.md` §6.11。**Core 端口与事务语义一字未改**：
  记录的数据源是 §6.1 已冻结的 `trace_*` 观测输出。

## 5. 调试、性能与赛后扩展点

- **I/D Cache 与 burst 已于 2026-09-29 经用户批准纳入本届**（`AGENTS.md` §1.14）。
  放置位置**不得改变**：I-Cache 只能位于取指端口与下级存储之间，D-Cache 只能位于数据端口与 SoC 互连之间，
  且不得改变 Core 事务语义；具体契约见本文件 §3.4「行/突发适配器与 Cache 契约」。
- SoC 的地址属性表仍保留 cacheable/uncacheable 概念；所有 MMIO 区域始终为 uncacheable。
- Core 输出统一提交级 trace。具体 ILA、波形采集器或调试桥只观察这些输出，不反向侵入流水级控制。
- Core 输出 `retire`、`stall`、`load_stall`、`branch`、`branch_taken`、`flush`、`predict`、`btb_hit`、`mispredict`，以及 `illegal`、`misaligned`、`bus_error` 观察事件；外部性能监视器负责计数和 MMIO 映射。提交 trace 的 `trace_error` 标明该退休记录被错误抑制了架构副作用。
- 性能 MMIO 在原有 `0x00..0x34` 七项计数器和 `0x38` 清零控制之后，新增 `predict=0x40/0x44`、`btb_hit=0x48/0x4C`、`mispredict=0x50/0x54` 的低/高 32-bit 只读寄存器。

### 5.1 行/突发适配器契约（S2，2026-09-29 新增）

本节记录 **Core 外部**的新契约。Core 的端口、位宽与事务语义**一字未改**，
`rtl/pipeline_cpu.v` 的 SHA-256 前缀仍为 `B58496706686E37B`。

> **2026-10-21 复核更正（不改变上面这条结论，只更正证据）**：该哈希前缀**已经失效**。
> `rtl/pipeline_cpu.v` 在 2026-10-14 的 M 扩展轮次里被改过（ID/EX 增加 mdu 位、
> `ex_result` 增加 mdu 分支、新增 `exmem_retired`、`mdu_block` 停顿握手），
> 当前 SHA-256 为 `4759E3FD68A31CA20250D54345112CA1465C1035A24CB1C72E51905D5B2C7D17`。
> "端口表、方向、字段与事务语义未变"这一结论仍然成立（见本文件 §6.1 与 §6.1 的 M 扩展小节），
> 但**不要把哈希前缀当作这句话的证据**——它现在只能证明"同一份文件没再变"。

**位置**：`rtl/soc_line_burst_adapter.v`，插在 Core 的统一访问端口与下级存储之间。

**Core 侧**（与 §2 冻结语义完全一致，不新增信号）：`req_valid/req_ready/req_addr/
req_write/req_wdata/req_wstrb` + `rsp_valid/rsp_ready/rsp_rdata/rsp_error`。
每端口仍是单笔事务、最多一个未完成请求。

**下游存储侧**（新增，仅存在于 Core 外部）：

| 信号 | 方向 | 语义 |
|---|---|---|
| `m_req_valid` / `m_req_ready` | 适配器 ↔ 存储 | 行请求握手 |
| `m_req_addr[31:0]` | 适配器 → 存储 | **行首**字节地址（按 `LINE_BYTES` 对齐） |
| `m_req_len[7:0]` | 适配器 → 存储 | 本次连拍数 − 1；`0` 表示单拍 |
| `m_beat_valid` / `m_beat_ready` | 存储 → 适配器 | 数据拍握手 |
| `m_beat_data[31:0]` | 存储 → 适配器 | 一拍一个 32-bit 字，按序 |
| `m_beat_last` | 存储 → 适配器 | 本次突发最后一拍 |
| `m_beat_error` | 存储 → 适配器 | 与 `m_beat_last` 同拍有效 |

**参数**：`LINE_BYTES`（默认 32）、`BURST_LEN`（`1` = 逐字模式，`>1` = 突发模式）。
`BURST_LEN=1` 时 `m_req_len` 恒为 0、每笔单拍，下游看到的就是逐字事务，与既有
`soc_fpga_memory` 行为等价——这就是 Before/After 的同一份 RTL 基线。

**写事务**：S2 阶段**写一律直通下游、不进缓存**，且同样要回一个完成响应
（Core 的数据端口要求"每笔请求恰好一个响应"）。写缓冲与写策略属于 S4。

**已量化的收益**（`tb/tb_soc_line_burst_adapter.v`，24 次读 = 3 整行 × 8 字顺序访问，
两种模式各 3 次行填充、21 次命中，前提校验 `measurement_same_miss_count` PASS）：

| 指标 | 逐字（Before） | 突发（After） | 变化 |
|---|---|---|---|
| 下游请求数 | 24 | 3 | **−87.5%** |
| 下游总线周期 | 48 | 30 | **−37.5%** |
| Core 侧等待周期 | — | 30 拍 / 24 次读 | — |

**止损已检查**：`handoff_next.md` §3.3 规定"突发方案实测总线周期没有下降 → 停"，
实测下降 37.5%，**未触发止损**。

### 5.2 D-Cache 契约（S4，2026-09-29 新增）

`rtl/soc_dcache_2way.v`，位于 Core 的数据端口与 SoC 互连之间（Core 外部）。

**Core 侧**（与 §2.2 冻结语义完全一致，不新增信号）：
`req_valid/req_ready/req_addr/req_write/req_wdata/req_wstrb` +
`rsp_valid/rsp_ready/rsp_rdata/rsp_error`。每端口仍是单笔事务。

**下游侧**：读沿用 §5.1 的行请求 + 连拍（行读 `len=WORDS-1`，直连单字读 `len=0`）；
新增单笔写 `m_wr_valid/m_wr_ready/m_wr_addr/m_wr_data/m_wr_strb`。

**写策略：写穿 + 写缓冲（明确不做写回）**

- 写命中：按 `wstrb` 逐字节就地合并进本行，**同时**把整笔写发往下游；
- 写未命中：**不分配**行（no-write-allocate），直接发往下游；
- 写缓冲：**单条目**。写是 posted 的——完成响应在下游接受该写时给出；
  缓冲占满期间 `req_ready=0` 让 Core 等待，从而保证写顺序。
- **为什么不做写回**：脏行未落盘会与 Trap/精确异常语义纠缠
  （异常点必须对应架构可见状态），复杂度高一个量级；`handoff_next.md` §3.3 也要求先做写穿。

**MMIO 强制绕行（硬性）**

地址 `> CACHEABLE_LAST_ADDR`（参数，默认 `0x0000_FFFF`，即 §3.2 表中 RAM 窗口的上界）
一律**不查表、不分配、不更新行**：读直连下游、写直接下推。
因此 MMIO 的副作用（读清标志、写触发）不会被缓存、合并或重复。

**Store → Load 转发（硬性）**

两条来源都必须覆盖，缺任一条都会读到旧值：
① 写缓冲里尚未落盘的那一笔，地址同字且与 `wstrb` 相交时用缓冲字节覆盖读回值；
② 写命中已就地更新的行，命中路径读到的本来就是新值。

**量化（必须先说明后端有多慢）**：见 `docs/architecture.md` §3.1。
注意：该量化来自**行填充式慢后端模型**，不是端到端 CoreMark 数字。


- 本届不实现异常/中断。赛后如研究，Core 仍只能接收通用中断源或聚合结果，不使用 UART/GPIO/SPI 专用中断端口；中断控制器和源映射属于 SoC。

## 6. 冻结与变更规则

- 本文当前冻结的是边界、事务字段和握手语义，不虚构 RTL 已实现或验证。
- Task 15 冻结单周期 Core adapter、地址表和互连的逐根信号名；Task 18 复核流水线是否复用同一语义，并冻结流水线 Core 顶层端口。
- 后续允许在 adapter 后连接简单 RAM、BRAM、Cache、厂商总线或外设互连，但不得让这些变化传播进流水线主体。
- MES50HP board wrapper 与 `.fdc` 使用 `docs/fpga_platform.md` 已归档的手册管脚和 3.3 V 电平；后续只允许补入实际使用信号，不得改变 Core 事务字段、握手语义或 Core 顶层设备无关性。辅助平台须另建 wrapper/约束，不覆盖 MES50HP 配置。
- Task 15 只在 SoC 地址表中预留通用 Application MMIO 窗口；Task 30 才冻结逻辑分析仪具体寄存器 offset。两次冻结均不得改变 Core 端口。
- 接口如需不兼容变更，必须先在 `docs/architecture.md` 记录原因、影响和迁移办法，并重跑 Core、互连和 SoC Regression。

### 6.1 Task 18 流水线 Core 顶层端口冻结

流水线顶层模块名为 `pipeline_cpu`。它复用 Task 15 的 `i_req_*`、`i_rsp_*`、`d_req_*`、`d_rsp_*` 字段、方向、单 outstanding 限制与 Reset 语义，逐根名称不另行变体。除了 `clk`、`reset` 与这两组通用事务端口，冻结的观测输出如下：

| 信号组 | 字段 | 语义 |
|---|---|---|
| 提交 trace | `trace_valid`、`trace_pc`、`trace_instruction`、`trace_rd_we`、`trace_rd_addr`、`trace_rd_data`、`trace_mem_we`、`trace_mem_addr`、`trace_mem_data`、`trace_mem_wstrb`、`trace_error` | 以退休顺序输出；Bubble、非法/访问错误和被 Flush 的路径不得形成副作用 trace。A3 之后"被 Trap 取消的指令"也不再形成提交记录。 |
| 通用性能事件 | `event_stall`、`event_load_stall`、`event_branch`、`event_branch_taken`、`event_flush`、`event_predict`、`event_btb_hit`、`event_mispredict`、`event_control_redirect`、`event_illegal`、`event_misaligned`、`event_bus_error` | 单周期脉冲，仅描述流水线行为；计数、MMIO 映射和软件可见寄存器由 Core 外部性能监视器实现。 |
| Trap 事件 | `event_trap`、`event_trap_return` | 单周期脉冲：前者在"进入 Trap 的那一拍"为 1，后者在 `MRET` 真正退休的那一拍为 1。只描述"发生过什么"，不带原因码——原因码由软件读 `mcause`。 |
| 通用中断输入（A3 新增） | `irq_software_i`、`irq_timer_i`、`irq_external_i` | **仅这三根**、设备无关、电平有效。中断源、定时器、使能位、聚合与优先级全部属于 SoC；Core 内不得出现设备名、设备地址或设备状态机。`mip` 是这三根线的只读窗口，Core 不锁存也不清除。 |

禁止在该模块增加设备地址、片选或 UART/GPIO/逻辑分析仪专用端口。后续 SoC、BRAM、外设或 MES50HP board wrapper 只能消费上述通用端口。

### 6.1 M 扩展（RV32IM，2026-10-14）不改变本节任何一条

M 扩展（`mul`/`mulh`/`mulhsu`/`mulhu`/`div`/`divu`/`rem`/`remu`）是**核心内部**的 ISA 扩展：

- `pipeline_cpu` 的**端口表、方向、字段与事务语义逐根不变**（上表 4 组一个字段都没动）；
- 新增的只有内部文件 `rtl/mdu.v`，以及 `rtl/decoder.v` 的两个输出 `mdu_en`/`mdu_op`
  （Core 内部信号，不出端口）；
- 单周期 Reference Model 同步实现同一套 M（`rtl/single_cycle_cpu.v` + 同一个 `rtl/mdu.v`），
  否则 §7 的 Core 层"与 Reference 一致"这一条在任何用到乘除法的程序上直接失效；
- ISA 口径：`rv32i` 仍是默认与可比口径，`rv32im` 是并列的增强配置，引用分数必须写明（`AGENTS.md` §1.7）。

### 6.2 逻辑分析仪的采集源选择（Core 外部，2026-10-14）

- 新增的 MMIO 寄存器 **18（偏移 0x48，`src_sel`）** 属于**应用外设**，不属于 Core：
  0 = J8 外部 8 路物理输入（默认），1 = Core 内部观测点。
- 探针取的是 Core **已有的冻结观测输出**（`i_req_valid`/`i_req_ready`/`i_rsp_valid`/
  `d_req_valid`/`d_req_ready`/`event_stall`/`event_flush`/`trace_valid`），
  在**板级顶层**接成 `probe_channels` 并**打一拍**后进入采集引擎；
  Core 源文件、端口与事务语义不受影响，Core 也不感知这个外设。
- 采集源选择的结果在 `rtl/logic_analyzer_mmio.v` 内**寄存一拍**再进采集引擎
  （理由见 `docs/rtl_changes.md` 改动 4：不寄存会吃掉 spi 模式全速采样路径的余量，
  实板症状是固件永久卡死）。
- 应用侧详细规格（0xA8 命令、通道定义、判据）以 `docs/application_logic_analyzer.md` §6.10 为准。
- **上位机一侧的对应契约**：`python/logic_analyzer_serial.py` 的
  `capture_view(mode, source)` 把"用什么模式采"（窗口/触发预设）与"这一窗是什么"
  （通道含义与判据）分开——源 = Core 时一律按流水线观测点解释，源 = J8 时才是该协议。
  两个界面（`mes50hp_validation_ui.py`、`逻辑分析仪演示.py`）都必须暴露这个开关，
  否则功能在演示现场不可用（2026-10-14 用户指出后补做）。

## 7. 解耦验收矩阵

| 层级 | 必测内容 | PASS 条件 |
|---|---|---|
| Core | 通用存储模型、固定延迟、随机背压、Reset、Flush | 请求保持稳定；无丢失、重复事务；错误路径无 side effect |
| Interconnect | RAM/MMIO/未映射/边界/重叠防护 | 每次只选中一个目标，响应返回正确发起端 |
| Peripheral | UART、GPIO 及后续设备的独立协议测试 | 不依赖 Core 内部信号即可独立 PASS |
| SoC 组合 | RAM-only、RAM+UART/GPIO、RAM+UART/GPIO/逻辑分析仪 | 使用同一份 Core 源文件，换配置后原 Core Regression 保持 PASS |
| Reference 对比 | Single Cycle 与 Pipeline 运行同一程序 | 最终 architectural state 与提交级 trace 一致 |

只有同时满足以下条件，才能宣称 Core/外设已解耦：

1. Core 顶层没有设备专用信号、地址和逻辑。
2. 至少三种 SoC 组合复用完全相同的 Core 源文件。
3. 可变延迟/背压不会造成重复或丢失 Load/Store/MMIO 事务。
4. 新增或替换外设不需要修改 IF/ID/EX/MEM/WB、Hazard、Forwarding、Stall 或 Flush。
