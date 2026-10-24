# trace85 板级证据（提交级 trace 可视化）

> 采集时间：**2026-10-24 重采**（原 2026-10-22 两枪已按下面的说明作废并重跑）
> 平台：MES50HP `PGL50H-6IFBG484`　串口：COM11 @ 115200
> 位流：`fpga/trace85/generate_bitstream/mes50hp_trace_pll_top.sbit`
> SHA-256：`2148CD6F009FCED49D65800B76E4BBB33627C9872186A8E4892776F80A62B5F5`
> PDS：`Design Summary : All Constraints Met`（85.000 MHz，WNS +361 ps / WHS +186 ps，DRM 44/134）
>
> **为什么重采（2026-10-24）**：同日给这档演示位流加了"波形 + 指令流一次采集"
> 的 `0xAB` 组合命令（见 `docs/application_logic_analyzer.md` §6.11.13 与
> `release/evidence/trace85_board_wave/`）。那条命令在 4 KB 镜像里装不下
> （实测溢出 436 字节），所以 tr85 的固件镜像扩到 **8 KB**
> （`start.S` 的栈顶 0x1000→0x2000、`link8k.ld`、存储器 DEPTH 1024→2048、
> 互连 `RAM_LAST_ADDR` 0x0FFF→0x1FFF；**交付工程 la85/la50 仍是 4 KB，逐字节不变**）。
> 代码位置因此整体后移：本目录两枪的**结构数字全部不变**
> （100 条 / 19 个 PC / 每字符 12 条；4096 条 / 22 个 PC / 热点前四 99.49%），
> 但**阶段 0 的具体 PC 值变了**（例如热点 `0x9BC…` → `0xDF0…`）。
> 旧哈希 `945F36E497740628A635E295F6132E86D88D5FEA2C25CA2C43C221A9664F290D` 已作废。

> **源文件与位流的时间差（如实记录）**：2026-10-22 那版位流构建于一次**纯注释**改写之后
> （`rtl/trace_buffer.v` 头部"不做 RLE"→"不做任何压缩"），当时没有重打位流。
> 2026-10-24 因为固件镜像扩容重打了位流，这一条差异随之消失。

## 这是什么

同一台"逻辑分析仪"把探头从 8 根管脚换成了 **Core 的提交级 trace 端口**：
每一条退休指令记录一行 `{pc, 指令字, 写回寄存器与数据, 写存储地址/数据/字节使能, error}`。
记录来自 `pipeline_cpu` 在 Task 18 就冻结的 `trace_*` 观测输出，
**`rtl/pipeline_cpu.v` 的端口与事务语义一个字都没改**。

**输入是任意的**：pyUI 第 2 页的输入框、`capture_trace.cmd` 或
`trace_board.py --text` 里填什么 ASCII（≤32 字符），CPU 就真的收什么、处理什么。
页面完全由回包数据生成，没有任何针对特定字符的硬编码；判据也按实际发送的串重算期望值。

**被测程序有两档**（都烧在位流里，换档不需要重新综合）：

| 阶段 | 做什么 | 典型窗口 | 为什么要有这一档 |
|---|---|---|---|
| 0 | 小写转大写 + 逐字节 XOR + 写回 | 100 条 | 最干净的"一遍过"负载，字符↔指令一一对齐 |
| 1 | 同上，但 Arm 在接收之前 | 4096 条（写满） | 把"等下一个字节"的轮询摊开：99.49% 是空转 |

**这是附加演示位流，不是交付位流。** 交付的 `la85` 位流、100/100 板级验收证据与
`claims_map` 的四份哈希**一个字节都没动**。

## 两枪

| 文件 | 内容 |
|---|---|
| `trace_phase0.{log,html,json}` | 阶段 0：上位机发 `hello,rv`，只记录**处理过程**（不含串口轮询） |
| `trace_phase1.{log,html,json}` | 阶段 1：上位机发 `ABC`，Arm 在接收之前，**连串口轮询一起记录** |


`*.log` 是 UART 原始回包（未加工），`*.html` 是单页可视化，`*.json` 是同一次解析的
判据与摘要。三者由**同一条命令**产生，判据与页面标注同源。

## 为什么没有第三档被测程序（2026-10-22 实测结论）

用户反馈"热力图太贫瘠"之后，先试的是"再加一档更吃寄存器的算法（冒泡排序）"。
写完、上板跑通了（16 字符 → **980 条提交、29 个 PC、比较 120 次 = n(n-1)/2**，
判据 15/15 PASS），但**它把镜像模式测坏了**：

- DMEM 只有 4 KB，栈顶固定在 `0x1000`（`start.S` 的 `lui sp,1`）；
- 加排序后 `.bss` 结束在 `0x0FD4`，**栈余量只剩 44 字节**；
- 而镜像路径实测需要约 224 字节栈帧（`main` 112 + `capture_and_report` 80 + `uart_hex` 32），
  于是栈直接压进 `.bss`，踩坏 `dec[]/spi_dec[]` ——
  表现是 `LA TEXT hex=` 里出现空格、`bytes=0000000` 被截断，
  `run_logic_analyzer_mirror_tb` 从 **PASS 变成 2 条断言 FAIL**。

结论：**这个交互固件已经顶到 4 KB DMEM 的天花板**，再加功能必须先扩 DMEM
（要动 `start.S` 的 sp、`logic_analyzer_program_memory.v` 的 DEPTH、`soc_data_interconnect`
的 `RAM_LAST_ADDR`，以及 4 个板级项目和它们的 TB），而那条路会作废已冻结的
`la85`/`la50` 位流与 100/100 证据。所以本轮**撤回排序档**，密度改由"加维度"解决（见上）。

## 阶段 0（处理过程的完整窗口）

- **100 条提交 / 8 个打点 / 19 个不同 PC / status=0x4（done，无溢出）**
- **每个字符 12 条提交**（8 个字符的 marks 间隔为 `[12,12,12,12,12,9,12]`）
- 热点就是那个逐字符处理循环，各 8 次（每个字符一次）：

  | PC | 条数 | 指令 |
  |---|---:|---|
  | `0xDF0` | 8 | `addi x14,x8,0` |
  | `0xDF4` | 8 | `lbu x15,0(x8)` |
  | `0xDF8` | 8 | `sw x15,0(x12)` |
  | `0xDFC` | 8 | `addi x13,x15,-97` |

  即：**读字节 → 大写字判断 → 写回缓冲**，一条不漏地对齐到字符上。
  （2026-10-22 那版 4 KB 镜像里这几个 PC 是 `0x9BC/0x9C0/0x9C4/0x9C8`，
  扩容后整体后移；结构数字不变。）
- 数据流（页面右栏逐条可查）：`#6 lbu x15,0(x8)` → `x15=0x68('h')`；
  `#7 sw x15,...` 写进 MMIO `0x1000222C`（**这就是固件自己打的点**）；
  `#10 addi x15,x15,-32` → `x15=0x48('H')`；`#13 sb x15,0(x14)` 写进缓冲 `0x00000EE8`。
- **总线/MMIO 泳道**：17 次写存储里 **8 次命中 MMIO**（全部是打点寄存器 `0x1000222C`，
  一字符一次），另外 9 次写数据 RAM（缓冲 `0xEE8…`）。
- 固件自证：`ascii=HELLO,RV xor=0x0000006A up=7 chars=8`
- **判据 15/15 PASS**，其中最关键的三条：
  - `pc 与位流镜像同源`：100 条记录的指令字与位流里同一份
    `logic_analyzer_program.mem` 逐条相等，**不一致 0 条**；
  - `store 有效地址与记录低 12 位一致`：按基址寄存器还原出的 32 位有效地址，
    与记录里的 12 位地址逐条吻合，**不一致 0 条**；
  - `打点值等于发送的字符`：`b'hello,rv'` ↔ `b'hello,rv'`。

## 阶段 1（同一个窗口里有多少是空转）

- **4096 条提交（窗口写满）/ 3 个打点 / 22 个不同 PC / status=0xC（done+overflow）**
- **前 4 个热点占整窗 99.49%**，其中三个就是 `uart_putc` 的忙等循环：

  | PC | 条数 | 占比 | 指令 |
  |---|---:|---:|---|
  | `0x014` | 1358 | 33.2% | `lw x15,0(x14)`（读 UART STATUS） |
  | `0x018` | 1358 | 33.2% | `andi x15,x15,1`（取 TX busy 位） |
  | `0x01C` | 1357 | 33.1% | `beq x15,x0,-8`（忙就继续转） |

- 这一枪的 `overflow=1` 是**合法的**：`count == 窗口容量 == 4096`。
  判据要求"只有写满才允许溢出"，正是为了不让软件正常 stop 之后继续退休的指令被误记成溢出
  （那条 bug 的根因见 `docs/debug_log.md`）。
- **判据 14/14 PASS**，`pc 与位流镜像同源` 在 4096 条记录上**不一致 0 条**。

## 复现

```powershell
scripts\run_trace85_pds.ps1                       # 构建位流（All Constraints Met）
scripts\program_board.ps1 -Config tr85            # 下载：PROGRAM PASS
python python\trace_board.py --port COM11 --phase 0 --text "hello,rv"
python python\trace_board.py --port COM11 --phase 1 --text "ABC"
```

两条 `trace_board.py` 都必须打印 `TRACE BOARD PASS`（15/15 与 14/14 条判据）。

不带命令行的两条路（**输入任意字符串**）：

```text
python\capture_trace.cmd             双击，会问你要发什么；也可 capture_trace.cmd "abc"
开启 pyUI → 第 ② 页「CPU 数据流」→ 填字符串 → 点「采集」
```

走真实界面路径的板级检查（真的构造 pyUI、真的填输入框、真的点按钮）：

```powershell
python python\trace_ui_board_check.py --port COM11 --text "hello,rv" --phase 0
# -> TRACE UI OK   text='hello,rv' phase=0 nodes=100 可见=100 条 items=411 rows={'reg': 9, 'pc': 12, 'mem': 8} page=60381 bytes
# -> TRACE UI BOARD CHECK PASS
```

**2026-10-24 复核（第 2 页重排之后）**：板子重新下载同一位流
（`program_board.ps1 -Config tr85`，SHA-256 仍是 `945F36E4…`），
上面这条界面路径两档都通过：阶段 0 `nodes=100 可见=100 条 items=411`、
阶段 1 `nodes=4096 可见=308 条 items=1817`（4096 条按"一条记录 ≥3 px"分段显示，
见 `docs/application_logic_analyzer.md` §6.11.10）。
本目录里的 `trace_phase{0,1}.{log,html,json}` **没有重采**，仍是 2026-10-22 那两枪。

## 边界（必须原样进材料）

- **记录里的 `mem_addr` 只有 12 位**（IMEM/DMEM 各 4 KB），所以**光看记录分不出 RAM 和 MMIO**。
  页面用窗口内已知的基址寄存器还原 32 位有效地址：还原得出来就按 MMIO/RAM 分类并显示全地址，
  还原不出来就标"地址未知"（深灰条）并只显示低 12 位——**不猜高 20 位**。
  还原出来的地址还要与记录里的低 12 位逐条对拍（判据 `store 有效地址与记录低 12 位一致`）。
- **load 地址不在记录里**：`trace_mem_we` 的语义是"本指令是否写存储"，所以 load 只有值、
  没有地址；页面能显示 load 读到什么，地址只在基址寄存器于窗口内被写过时才推算。
- 132 位记录里没有时间戳，所以这是**提交级**视图（一条记录 = 一条退休指令）；
  每拍的取指/停顿/冲刷要看 8 通道 Core 探针的波形页（`docs/application_logic_analyzer.md` §6.10）。
- 它不是实时流式：一条记录 132 位、85 MHz 下内核产出约 600 MB/s，而 115200 只有
  11.52 kB/s，**差约 5 万倍**。口径是"Arm → 收尾 → 上传一窗 → 回放"，与真实逻辑分析仪一致。
- 不把本功能称为 PDS ILA，也不宣称替代它。
