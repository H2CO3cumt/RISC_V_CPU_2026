# M-24 / N2：板级 ILA 抓 Trap 进入与返回

本工程是 **诊断位流**，用于把 `docs/trap_contract.md` 的 M-24 从"部分"推到 PASS。
它与已交付的 `fpga/timer_demo`（N1）**共用同一个顶层文件**，
只多定义一个 `PDS_TIMER_DEMO_ILA` 宏并加入 Core 之外的一个 DebugCore，
因此 **N1 交付位流不受影响，也不需要重建**。

构建：`powershell -File scripts\run_timer_demo_ila_pds.ps1`
下载：`powershell -File scripts\program_board.ps1 -Config tmila -UseDebugger`
抓取：`powershell -File scripts\run_ila_trap_capture.ps1`

## 探针通道映射（**已从 PDS 生成的 FIC 里读出，不用猜**）

PDS 在工程根目录生成了 `mes50hp_timer_demo_top.fic`，
里面就写着 Fabric Debugger 认的通道名（`Project.unit<0>.triggerChannel<0><n>`）：

| 通道号 | 名字 | 说明 |
|---:|---|---|
| 0 | `ila_event_trap` | **Trap 进入 —— 触发点就用它** |
| 1 | `ila_event_trap_return` | **Trap 返回（mret）** |
| 2 | `ila_event_illegal` | 非法指令 |
| 3 | `ila_event_misaligned` | 非对齐访问 |
| 4 | `ila_event_bus_error` | 总线错误 |
| 5 | `ila_event_ctrl_redirect` | 控制流重定向 |
| 6 | `irq_timer` | 定时器中断请求线 |
| 7 | `perf_retire` | 退休脉冲 |
| 8..39 | `ia[0..31]` | 取指地址（总线名 `ia`） |
| 40..71 | `idata[0..31]` | 取回指令（总线名 `idata`） |
| 72..103 | `da[0..31]` | 数据地址（总线名 `da`） |
| 104..135 | `drd[0..31]` | 数据读回（总线名 `drd`） |

FIC 里还给了现成的总线定义，抓取时可以少配一堆位：

```
Project.unit<0>.triggerBus<0><8><39>   = ia
Project.unit<0>.triggerBus<0><40><71>  = idata
Project.unit<0>.triggerBus<0><72><103> = da
Project.unit<0>.triggerBus<0><104><135>= drd
```

**抓取脚本会自动导入本工程的 FIC**（`scripts/run_ila_trap_capture.ps1` 的默认值），
导错工程（例如 `coremark_ila` 的 FIC）会让通道名全错、触发设不上。

## 金标准：合格波形应该长什么样（**已在仿真里固化，供机械比对**）

`golden_trace.txt` 是用**同一批观测信号**在仿真里跑出来的参考轨迹。
板级 ILA 抓到数据后，不必靠肉眼看波形——按下面 5 条判据逐条对即可。

生成方式（零 RTL 改动；该段在 `` `ifdef TIMER_DEMO_ILA_PROBE_SIM `` 里，
**未定义时完全不可见，既有 N1 回归一字不变**——已实测两遍 `ALL PASS` 且无 GOLD 行）：

```powershell
# 沿用 N1 的板级顶层 TB，只多定义一个宏
iverilog -g2012 -DTIMER_DEMO_SIM -DTIMER_DEMO_TB_DELTA=200000 -DTIMER_DEMO_ILA_PROBE_SIM `
  -s tb_timer_demo_board_top -o tmp/timer_demo/tb_gold <与 run_timer_demo_board_top_tb.ps1 相同的源文件表>
vvp tmp/timer_demo/tb_gold
```

**判据（板上抓取必须同时满足）**

| # | 判据 | 仿真里的实测值 |
|---|---|---|
| C1 | 出现 `ila_event_trap` 脉冲 | 12 次 |
| C2 | 每次进入都跟一次 `ila_event_trap_return` | **12 次，严格配平** |
| C3 | 进入时 `irq_timer` = 1（原因 = 机器定时器中断） | 每次都成立 |
| C4 | 进入后 PC 从被打断处跳到 ISR 入口并顺序推进；返回后回到原 PC | 见下 |
| C5 | 相邻两次进入的间隔恒定 | 恒为 **8000240**，`gap_stable=1` |

**C4 的逐拍轨迹**（仿真 delta=200000，取自 `golden_trace.txt`）：

```
t=16011340000 trap=1 irq=1 ia=00000054   <- Trap 进入脉冲，此时 PC = 0x54（被打断处）
t=16011380000 trap=0 irq=1 ia=00000068   <- 下一拍 PC 已跳到 ISR 入口 0x68
t=16011460000 trap=0 irq=1 ia=0000006c
t=16011500000 trap=0 irq=1 ia=00000070
t=16011540000 trap=0 irq=1 ia=00000074
t=16011660000 trap=0 irq=1 ia=00000078
t=16011700000 trap=0 irq=1 ia=0000007c
t=16011740000 trap=0 irq=1 ia=00000080   <- ISR 体顺序推进
t=16011780000 trap=0 irq=0 ia=00000080   <- irq_timer 落下（中断已被接受）
...                                       （约 34,776 拍后）
GOLD-RET  #2  ia=00000054                <- Trap 返回，PC 回到被打断处
```

关键地址：**被打断 PC = `0x00000054`，ISR 入口 = `0x00000068`，ISR 体 `0x68..0x80`**。

## 触发单元怎么配（**按官方文档语义推导，不是猜的**）

`Fabric_Debugger_User_Guide` §5.3.1 的模型是：

- **一个 Trigger Unit 对应一个 Trigger Port**。本 DebugCore IP 只有一个 192 位触发端口
  （`trig0_i`），所以就是 **TU0**；
- **边沿不是用 Function 表达的，而是写在 Value 里**：Binary 进制下
  `X`=不关心、`0/1`=固定值、**`R`=上升沿**、`F`=下降沿、`B`=任意跳变、`N`=无跳变；
- Value 串**MSB 在前**，所以 bit0（`ila_event_trap`）是**最后一个字符**。

⇒ "抓 `ila_event_trap` 上升沿"就是：

```tcl
dbg_fla_set_trig_unit -device 0 -fla 0 -unit 0 -func 1 -radix 0 -value {XXX...XXXR}
dbg_fla_set_trig_cond -device 0 -fla 0 -add trig_trap -active trig_trap -select trig_trap -set { TU0 }
```

`scripts/run_ila_trap_capture.ps1` 的 `-Mode capture` **默认就生成这套**，
并开放 `-TrigUnit/-TrigFunc/-TrigRadix/-TrigValue/-TrigExpr` 供上板时微调。

## 为什么用定时器中断演示而不是 CoreMark

CoreMark 正常运行**不产生 Trap**，抓不到"Trap 进入/返回"。
而本固件**每 250 ms 产生一次机器定时器中断**，`trap_enter` 与 `mret` 周期性可重复，
正好满足 M-24 的验收要求。

## 探针布局（单一 192 位探针 / 50 MHz 采样 / 512 采样深度）

与 `fpga/coremark_ila` **复用同一个 DebugCore IP**，只是这 192 位接的东西不同。

| 位 | 信号 | 说明 |
|---:|---|---|
| 0 | `event_trap` | **Trap 进入脉冲（触发点）** |
| 1 | `event_trap_return` | **Trap 返回脉冲（mret）** |
| 2 | `event_illegal` | 非法指令事件 |
| 3 | `event_misaligned` | 非对齐访问事件 |
| 4 | `event_bus_error` | 总线错误事件 |
| 5 | `event_control_redirect` | 预测命中的控制流重定向 |
| 6 | `irq_timer` | 定时器中断请求线（SoC 侧聚合后送进 Core 的那一根） |
| 7 | `perf_retire` | 退休脉冲（观察周期行为） |
| 39:8 | `ia` | 取指地址 —— 看得到"跳进陷入入口、返回后回到原 PC" |
| 71:40 | `idata` | 取回的指令 |
| 103:72 | `da` | 数据访问地址 |
| 135:104 | `drd` | 数据读回值 |
| 136..139 | `iv` / `ir` / `rv` / `rr` | 取指请求/响应握手 |
| 140..142 | `dv` / `dr` / `dw` | 数据请求握手与写标志 |
| 191:143 | 保留 | 恒 0 |

## 合规边界（不得放宽）

- **`rtl/pipeline_cpu.v` 一字未改**（SHA-256 前缀 `B58496706686E37B`），端口与事务语义不变：
  位 0～6 用的全是 Core **既有**的输出端口（`pipeline_cpu.v` 第 54-59 行）；
  位 7～142 用的是本顶层**本来就有的** SoC 侧网线（取指/访存总线、定时器中断线）。
- DebugCore / JTAG Hub **完全位于 Core 之外**，只观察通用事件与总线，
  不引入设备专用端口，符合 `AGENTS.md` §8 的 Core/SoC 边界。

### ⚠️ 为什么探针里没有 `mepc` / `mcause`（被工具链硬性挡回，别重犯）

本来按 `docs/handoff_next.md` §3.2 的设想，探针要挂到 `csr` 的 `mepc_q`/`mcause_q`，
于是用了层级引用 `core.csr.mepc_q`。**PDS(Logos) 直接拒绝**：

```
E: Verilog-4311: Reference to identifier 'mepc_q' of module instance 'csr' is not allowed.
```

而把 `mepc`/`mcause` 引到 Core 端口又会**改变 `pipeline_cpu.v` 的端口表**，
正是 `AGENTS.md` §1.14 明文禁止的。**两条路都不通**，因此本诊断位流改为：

- 用 Core **既有的事件端口**直接给出"Trap 进入 / Trap 返回"本身（位 0/1）；
- 用**取指地址 `ia`** 作为佐证：能看到 PC 跳进陷入入口、返回后又回到原 PC；
- `mcause`/`mepc` 的**数值**由固件自己的串口记录证明（N1 已闭环的 50 条周期中断记录）。

这个取舍必须在材料里如实写明，不得含糊成"ILA 看到了 mcause"。


## 抓取判据（怎么算"抓到了 Trap 进入与返回"）

一次合格的抓取必须同时看到：

1. 位 0（`event_trap`）出现 **上升沿脉冲**；
2. 位 71:40（`mcause`）在脉冲处等于 **`0x8000_0007`**（机器定时器中断）；
3. 位 39:8（`mepc`）在脉冲处是 ISR 之外的一条合法 PC（即"从哪陷入的"）；
4. 位 1（`event_trap_return`）在若干拍之后出现 **上升沿脉冲**；
5. 位 7（MIE）在进入时由 1→0、返回时由 0→1（`mret` 的语义）。

**止损（照 `docs/handoff_next.md` §3.2 第 3 条）**：
波形回读搞不定就**如实记"ILA 部分未完成"**，
**不得拿仿真波形冒充实板 ILA**。
