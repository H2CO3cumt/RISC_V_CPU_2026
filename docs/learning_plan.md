# 源代码逐行精读学习计划（自顶向下 · 模块化）

> 最后更新：2026-09-22
> 版本：**源码精读版（第 3 版）**
> 用法：你发一句 **"开始 Tn"**，我就把该模块的逐行逻辑解释发给你，然后出题考你；答对才进下一个。
> 定位：学习资料。**不作为项目完成度证据**，不替代 `docs/progress.md`，也不改任何 RTL 与 Gate。
> ⚠️ **讲解语言风格见 §0.0，这是硬要求，每一条讲解都必须遵守。**

---

## 0.0 讲解语言约定（对学习者本人的要求，最高优先级）

### 学习者画像

- **八十岁的老太太。** 有几十年生活经验和常识判断力，**不缺理解力，缺的只是这个领域的词**。
- 所以：**不许用术语当解释**。每个词第一次出现都要先翻译成大白话，再说它在代码里叫什么。
- **态度要平等、要尊重。** 不用哄小孩的语气（"很简单哦～"），也不许拿"这不就是……嘛"来显得轻松。她是认真来学的，就认真讲。
- **一次只讲一件事。** 一句话只装一个意思。段落短、换行多。宁可多写几行，不写长难句。

### 五条硬规矩

1. **先打比方，再上真名。** 每个模块、每个信号，都要先用生活里见过的东西说清它"是干什么的"，然后再告诉它在代码里的名字。顺序不能反。
2. **不许出现没解释过的缩写。** `PC`、`valid`、`ready`、`Flush`、`Hazard`、`forward`、`stall` 这些，第一次出现必须先给一句大白话。
3. **比方必须经得起抽查。** 比方是进门的台阶，不是终点。台阶下面必须有真东西——凡是有可能被追问的比方，都要随后补一句"这个比方在哪儿就不准了"。
4. **每讲完一段，用一句话收尾**："这一段说白了就是……"。她只要记住这句话，就能跟上后面。
5. **代码引用要落在具体行上。** 说"第 365 行这里"，而不是"在取指逻辑里"。手指头能点到的位置，才不飘。

### 比方对照表（讲解时统一用这套；不重复发明新比方，避免混淆）

| 代码里的东西 | 打比方 | 这个比方在哪儿不准 |
|---|---|---|
| `PC`（程序计数器） | 手里那张写着"下一道菜做什么"的纸条 | 纸条上只写"第几号菜"，不写菜名 |
| 指令存储器 / 取指 | 按号去菜谱架子上取下一张菜谱 | 取菜谱要走一段路（有延迟），不是一伸手就有 |
| `regfile`（寄存器堆） | 灶台边一排小碗，每个碗贴一个号，装一样东西 | 碗只有 32 个；其中 0 号碗永远是空的，往里倒东西也存不住 |
| `alu`（运算器） | 一口炒锅，按吩咐做加、减、比大小 | 锅不会记事儿，炒完就忘，必须有人把菜盛出去 |
| 流水线五级 | 一条做菜流水线，五个人接力：备菜、配菜、炒、装盘、上桌 | 真的厨房可以一个人同时干两件事，这里不行，一拍只走一步 |
| 流水寄存器（IF/ID 等） | 两个人中间那只传菜托盘 | 托盘每一拍都会被换掉，不接住就没了 |
| `valid` 位 | 托盘上压着的小纸条："这盘是菜"或"这盘是空的" | 空盘子也得照样往后传，不能凭空少传一拍 |
| `stall`（停顿） | 前头堵住了，全队原地等一拍 | 等的时候不是所有人都能干别的，是整条线停住 |
| `flush`（冲刷） | 发现前面那条路走错了，把刚端出来的错菜倒掉 | 已经端上桌的（更老的指令）撤不回来，只能倒还没上桌的 |
| `forward`（前递） | 菜还没上桌，直接从炒锅那边递过来先用 | 只有炒锅和装盘这两处能递；还没下锅的递不出来 |
| Load-Use 停顿 | 客人点了要现宰的鱼，下一道菜必须等鱼送到 | 只等一拍，不是一直等 |
| `i_req`/`i_rsp` 握手 | 点菜：你举手（valid），厨房接单（ready），两只手同时举起来才算点上了 | 举起来的手不能缩回去（valid 不许撤销） |
| `if_arm` | 厨房接单的**当下**就把下一张单子写好，端菜和接新单同一拍办完 | 只对取指有效；取数据那条路不用这么办 |
| `branch_predictor`（BTB） | 老熟客常走的那条路，先照老习惯猜着走 | 猜错了要退回来重走，退回是有代价的 |
| `dstate`（数据事务三态机） | 取东西的三步：说一声 → 等回话 → 把东西拿走 | 一次只办一件事，办完才接下一件 |
| `trace`（提交级 trace） | 记账本：每做完一道菜记一笔 | 只记不退，这本账不参与做菜 |

### 和学习计划其他部分的关系

- 本节的规矩**只管怎么讲**，不管*讲什么*。技术内容的正确性标准不降：讲解背后仍然是真实的行号、真实的信号、真实验证过的行为。
- **回答答辩提问时不能只用比方。** 比方是帮你弄懂用的；上台说的话仍然要准确（见附录 A）。
- 如果某个比方让你觉得别扭、或者和代码对不上，**当场说"这个比方不对"**——换一个，不要将就着记。

---

## 0. 怎么用这份计划

### 0.1 与前两版的差别

| 版本 | 验收线 | 状态 |
|---|---|---|
| 第 1 版（吃透/重建优先） | 关掉文件从零写出 RTL | 已停用（归档说明见 §11） |
| 第 2 版（答辩版） | 不看代码口述 1 分钟、被追问三层不倒 | 降级为**逃生包**，见附录 A |
| **本版（源码精读）** | **能指着任意一行说出"它为什么在这里、改动它会破坏什么"** | **当前执行** |

本版不要求你默写 RTL，也不要求你先背答辩话术。它要求的是：**把这份已经验证过的工程代码真正读通**，从顶层模块往下，一层一层读到叶子模块。

### 0.2 三条纪律

1. **自顶向下**：没读完父模块，不读它的子模块。原因见 §1.2。
2. **一次一个模块**：一个 Task 只讲一个模块（或一个模块里明确的一段）。不并发开两个模块。
3. **不许顺手改**：精读阶段只读不改。你在读的过程中发现的"这里好像能优化"，写进 §9 的观察清单，不直接改 RTL。工程侧任何 RTL 改动仍然要走 `docs/roadmap.md` 的 Gate 和 Regression（当前执行 Task 33～35 交付冻结）。

### 0.3 每个 Task 的固定流程

```text
你：开始 T3
我：① 模块在数据通路里的位置（先用 §0.0 的比方说它是干什么的）
    ② 接口表：每根端口 / 关键内部信号 = 谁驱动、谁使用、在哪一级（大白话 + 代码名并列）
    ③ 逐段讲解（按行号区间分段：这一段干什么 → 为什么这么写 → 用一句话总结）
    ④ 设计取舍与陷阱（最容易被误读、误改的地方，以及哪个比方在这里不准）
    ⑤ 3～5 道题（见 §0.4）
你：回答问题
我：逐条判分 → 答错的地方回到对应行号重讲 → 全对则标记 ☑ 并给出下一个 Task 的入口
```

### 0.4 出题的四种类型（每个 Task 都会混合出）

> 出题一律用大白话问，题目里的代码名字后面跟上"就是那个……"的提示。考的是理解，不是记性。

| 类型 | 例子 | 考什么 |
|---|---|---|
| **A 定位题** | "`if_arm`（刚接完单就写下一张单的那个小旗子）在第几行声明、第几行立起来、第几行放下？" | 是否真的读过这一行 |
| **B 追因题** | "菜还没装盘（没到 MEM）的时候，前递这条路为什么不给递？" | 是否理解设计意图，而不是记住结论 |
| **C 改错题** | "如果把第 386 行那个 `ifid_available` 去掉，会发生什么事？" | 是否知道这一行的依赖边界 |
| **D 推演题** | "给这 3 条指令，画出第 1～8 拍 `idex_valid`（托盘上有没有菜）/ `load_use`（要不要等鱼）/ `ifid_valid` 的值" | 能否把模块放回整机时序里 |

**通过标准**：A/B/C 类全对，D 类能画出正确拍序。有错就回到对应行号重讲一次，然后只重考错的那几道。

### 0.5 一次 Task 大概多久

| 模块体量 | 例子 | 讲解 + 出题 + 判分 |
|---|---|---|
| 小（< 60 行） | `regfile.v`、`branch_unit.v`、`hazard_unit.v` | 约 40～60 分钟 |
| 中（60～150 行） | `load_store_unit.v`、`branch_predictor.v`、`forward_unit.v` | 约 60～90 分钟 |
| 大（150～260 行） | `decoder.v` | 约 90～120 分钟，可能拆成两次 |
| 顶层（620 行） | `pipeline_cpu.v` | 拆成 T1～T6 六个 Task，每个 60～90 分钟 |

累计算下来 25 个 Task，按每天 1 个算约 4 周，和 D60 的时间盒对得上。**但节奏由你的答题结果决定，不按日期硬推**：一个 Task 没过就第二天继续，宁可少读两个模块，不要糊过去。

---

## 1. 教学基线：以哪份代码为准

### 1.1 冻结基线

| 项目 | 内容 |
|---|---|
| 教学对象 | `rtl/pipeline_cpu.v` 及其例化的 **10 个模块 / 11 个例化** |
| `pipeline_cpu.v` 行数 | **1089 行**（**工作区版本** = A1 + A3 版，不是 git HEAD 的 139 行旧版） |
| `pipeline_cpu.v` SHA-256 前 16 位 | `B58496706686E37B`（与 `docs/progress.md` A3 收口记的"唯一主版本"一致） |
| 冻结日期 | **2026-09-30 重新冻结**（原 620 行 / `4EE805E75831AED4` 基线已被 A1、A3 两轮改动取代） |
| 为什么用工作区版本 | HEAD 里是取指优化前的 139 行旧版；工作区版本才是 A1（BTB 收益 −3.41%）+ A3（机器模式 CSR/Trap/中断）真正落地、并已用它重建三个位流的那一份 |
| 校验方式 | 每次开讲前重新算一次 SHA-256 前 16 位与行数；**对不上就当场告诉你**，并且不引用旧行号 |

> ⚠️ 行号是会漂移的。文档里所有行号都以 `B58496706686E37B` 这一版为准。如果哈希变了，说明文件被改过，我会先重新定位再讲解，不会拿旧行号硬套。

> ⚠️ **行数统计口径**：本文件的数字按**字节里的换行符个数**数（文件末尾有换行就算作该行已结束）。
> 不要用 `Get-Content | Measure-Object -Line`：它不数空行，而且在含中文的文件上会因编码问题漏行——
> 实测同一个 `rtl/csr_unit.v` 数出过 192 / 216 / 246 三个不同结果，正确的是 **246**。
> 以你在编辑器里看到的行号为准。

子文件冻结值（同一冻结日，SHA-256 取前 16 位）：

| 文件 | 行数 | SHA-256 前 16 | 备注 |
|---|---|---|---|
| `rtl/pipeline_cpu.v` | 1089 | `B58496706686E37B` | A1 + A3 主干 |
| `rtl/csr_unit.v` | 246 | `5C7CF5C9C936EE38` | **A3 新增文件** |
| `rtl/decoder.v` | 365 | `848237324F40AEF7` | 增加 `ENABLE_SYSTEM` 与 Zicsr 译码 |
| `rtl/branch_predictor.v` | 81 | `444D16EF50783EED` | A1 增加"跳转恒 taken" |
| `rtl/hazard_unit.v` | 36 | `D240331AB2B4E7C6` | 仅注释变化 |
| `rtl/forward_unit.v` | 31 | `41F20AD1066C52AD` | 仅注释变化 |
| `rtl/load_store_unit.v` | 114 | `9E7A3B1AE5A74446` | 仅注释变化 |
| `rtl/branch_unit.v` | 26 | `862B758BC9600A38` | 未变 |
| `rtl/alu.v` | 34 | `5330B9E2A2649911` | 未变 |
| `rtl/imm_gen.v` | 48 | `C7CA9FCD913ACEC6` | 未变 |
| `rtl/regfile.v` | 18 | `371DB9031B9F9A97` | 未变 |

> 旧计划里写的 `decoder.v` 258 行、`branch_predictor.v` 54 行等数字，与现在的行数对不上，
> 一部分是这两轮真的改了，一部分是当时数错了。**旧数字一律作废，只引用上表。**

### 1.2 为什么要"自顶向下"，而不是从 `alu.v` 开始

`alu.v` 只有 29 行，看起来最好读——但它**不告诉你任何设计意图**。真正决定"这个 CPU 长什么样"的，是 `pipeline_cpu.v` 里那 543 行新增的胶水逻辑：

- 取指请求为什么要分成 `if_req` / `if_arm` 两种展示形式；
- 四个流水寄存器各存什么、`valid` / `error` 为什么要一路带到 WB；
- 数据事务为什么要用 `dstate` 三态机串行化；
- 冲刷为什么"只清年轻的"。

先读子模块会有一个具体的坏处：你会把 `forward_unit.v` 的输出 `forward_a[1:0]` 理解成一个孤立的三选一，而不知道它上面还套着第二级 `idex_asa/idex_asb` 选择，也不知道 `exmem_forward` 是父模块现推的组合值、不是流水寄存器。

**所以顺序是：先让自己知道"这个模块要解决什么问题"，再进去看它怎么解决。**

### 1.3 先读这一段：`pipeline_cpu.v` 的整体结构（读完再开始 T1）

```text
第    1～  60 行   模块头：parameter + 全部对外端口
                   （trace / i_req+i_rsp / d_req+d_rsp / 三根通用中断输入 / 14 个 event_*）
第   62～ 182 行   全部寄存器声明：IF 状态、IF/ID、ID/EX、EX/MEM、dstate、MEM/WB
                   （其中 120～129 是 ID/EX 的 Zicsr 与异常记录；
                     147～150 是 EX/MEM 的异常记录 / next_pc / mret；
                     177～182 是 MEM/WB 的"退休点异常记录"）
第  184～ 239 行   ID 级：decoder 例化（209～229）、imm_gen 例化（231～234）、字段切分（236～239）
第  241～ 274 行   WB 写回值 wb_value、wb_cancel / wb_fire、regfile 例化（256～265）、WB→ID 旁路（270～274）
第  276～ 332 行   EX 级：forward_unit 例化（286～299）、两级源选择、alu 例化（314～319）、
                   branch_unit 例化（323～328）、ex_target（332）
第  334～ 358 行   EX 级未对齐判定（第二个 load_store_unit 例化 lsu_ex，347～358）
第  360～ 425 行   异常原因编码 EXC_*（370～383）与"异常记录先到先得"的四级合并
第  427～ 460 行   CSR 读改写：Zicsr 三种 funct、纯读判定 ex_csr_write、csr_wdata 掩码
第  462～ 480 行   中断：三根线的使能判定、mcause 编码、同拍优先级 irq_grant
第  482～ 530 行   Trap 接受点（WB）：trap_take / 恢复地址 / 入口 / mcause / mtval / MRET 生效
第  532～ 570 行   csr_unit 例化（机器模式 CSR 状态）
第  572～ 610 行   Load-Use 冒险（hazard_unit 例化 577～584）、访存单元（lsu 例化 595～606）、
                   mem_done / mem_block（608～610）
第  612～ 675 行   控制流解析与重定向：只在校验失败时重定向、Trap/MRET 优先级、redirect_pc
第  677～ 697 行   branch_predictor 例化
第  699～ 746 行   取指请求展示形式（if_present / if_accept / if_request_accept / front_hold）
第  748～ 774 行   事件输出（14 个 event_*）
第  776～1072 行   唯一的时序块：reset 分支 + 各段非阻塞赋值
第 1074～1087 行   提交级 trace 输出
第 1088～1089 行   文件结尾
```

**一个必须建立的心智模型**：这个文件里**只有一个 `always @(posedge clk)`**（第 776 行起）。
所有组合逻辑都是 `wire` / `assign`。能分清"哪些信号是寄存器、哪些是当拍现算的导线"，80% 的困惑会自动消失。

---

## 2. 模块清单与依赖图

### 2.1 `pipeline_cpu.v` 例化的 10 个子模块（共 11 个例化）

| # | 子模块 | 类型 | 例化名 | 在 `pipeline_cpu.v` 的行号 | 所属级 |
|---|---|---|---|---|---|
| 1 | `decoder` | 纯组合 | `dec` | 209～229 | ID |
| 2 | `imm_gen` | 纯组合 | `ig` | 231～234 | ID |
| 3 | `regfile` | 时序（读组合） | `rf` | 256～265 | ID 读 / WB 写 |
| 4 | `forward_unit` | 纯组合 | `fu` | 286～299 | EX |
| 5 | `alu` | 纯组合 | `exalu` | 314～319 | EX |
| 6 | `branch_unit` | 纯组合 | `bu` | 323～328 | EX |
| 7 | `load_store_unit` | 纯组合 | `lsu_ex` | 347～358 | EX（**只取 `misaligned`**，A3 新增的第 2 个例化） |
| 8 | `csr_unit` | 时序 | `csr` | 539～570 | EX 读 / WB 接受 Trap（**A3 新增模块**） |
| 9 | `hazard_unit` | 纯组合 | `hu` | 577～584 | ID→EX 控制 |
| 10 | `load_store_unit` | 纯组合 | `lsu` | 595～606 | MEM |
| 11 | `branch_predictor` | 时序 + 组合查询 | `predictor` | 684～697 | IF 查询 / EX 更新 |

> 注意第 7 与第 10 项是**同一个模块 `load_store_unit.v` 的两个例化**：
> MEM 级那个（`lsu`）真正驱动总线读写，EX 级那个（`lsu_ex`）只借它的 `misaligned` 输出。
> 为什么宁可例化两次也不手写一份判定规则，见 `pipeline_cpu.v` 第 341～344 行的注释。

### 2.2 依赖关系（决定学习顺序）

```text
pipeline_cpu.v（1089 行，T1～T6 讲基础部分；T28a～T28c 讲 Trap 增量）
├── 先学"记状态"的模块：它决定"出事了要记下什么、回来从哪继续"
│   └── csr_unit.v           (246 行)  → 机器模式 CSR + Trap 进入/返回
├── 再学"控制类"子模块：它们决定流水线什么时候停、什么时候冲刷、走哪条前递
│   ├── hazard_unit.v        (36 行)  → load-use 停顿
│   ├── forward_unit.v       (31 行)  → 前递选择
│   └── branch_predictor.v   (81 行)  → 预测与更新
├── 再学"执行类"子模块：它们决定一条指令算出什么
│   ├── alu.v                (34 行)
│   ├── branch_unit.v        (26 行)
│   └── load_store_unit.v    (114 行)
└── 最后学"译码类"子模块：它们把指令翻成上面这些控制信号
    ├── imm_gen.v            (48 行)
    ├── decoder.v            (365 行，含 ENABLE_SYSTEM / Zicsr 段)
    └── regfile.v            (18 行)
```

**顺序理由**：控制类模块读起来最短、又直接对应 T3～T5 讲过的整机时序；执行类模块看的是"算得对不对"；译码类模块行数最多、最像查表，放在你对整条数据通路已经有画面之后再读，才不会变成背编码表。

**注意：这棵树只表示"谁例化谁"，不表示阅读先后。**
按 §0.2 纪律 1（自顶向下），实际阅读顺序是**父模块 → 子模块**：
先把 `pipeline_cpu.v` 整个读完（T1～T6 读基础通路，T28a～T28d 读 A1/A3 增量），
再自上而下读各子模块。`csr_unit.v` 是 `pipeline_cpu.v` 的子模块，所以排在顶层之后（T26）。

> 为什么不能"先读简单的叶子"：`csr_unit.v` 只有 246 行、又不例化任何东西，看起来最好入门；
> 但它的输出 `csr_illegal` 单独看毫无意义——它在顶层要跟 `csr_we` 的 `&& !csr_illegal_q` 门控
> 配合才构成"非法 CSR 写不产生副作用"。先读叶子就会把这一对拆散来看。
> 这和 §1.2 举的 `forward_unit` 例子是同一类错误。

### 2.3 不属于流水线数据通路的文件（不在本计划主线内）

| 文件 | 为什么不在主线 | 处理方式 |
|---|---|---|
| `rtl/imem.v`、`rtl/dmem.v` | 行为级仿真存储器，只服务单周期 Reference Model | 附录 B 速览 |
| `rtl/single_cycle_cpu.v` | 架构 Reference Model，不是流水线 | 附录 B 速览 |
| `rtl/soc_fpga_memory.v` | 板级 BRAM wrapper | 附录 B 速览 |
| `rtl/soc_data_interconnect.v` | Core 外地址译码 | 附录 B 速览 |
| `rtl/uart_tx.v`、`rtl/uart_rx.v`、`rtl/uart_mmio.v`、`rtl/gpio_mmio.v`、`rtl/perf_mmio.v`、`rtl/perf_monitor.v` | Core 外外设，与流水线解耦 | 附录 B 速览 |
| `rtl/application_mmio_mux.v`、`rtl/logic_analyzer_mmio.v`、`rtl/capture_engine.v`、`rtl/logic_analyzer_pattern_gen.v` | 比赛应用外设 | 附录 B 速览 |
| `rtl/timer_mmio.v` | A3 新增：`mtime`/`mtimecmp`，机器定时器中断的**源头** | T29 讲（不逐行到底，但要看懂中断是怎么抬起来的） |
| `rtl/soc_line_burst_adapter.v` | 高阶项① S2：行式突发适配 | T30 讲 |
| `rtl/soc_icache_2way.v` | 高阶项① S3：2 路组相联 I-Cache | T31 讲 |
| `rtl/soc_dcache_2way.v` | 高阶项① S4：2 路组相联 D-Cache | T32 讲 |
| `fpga/**/pll_80m.v`、PDS IP 生成的 `ips_dbc_*.v` | 厂商 IP / 板级 | 不读，只在答辩逃生包里说清参数 |

> 这不是说它们不重要，而是：**本届交付的评分主线是 Core。** 读外设的边际收益远低于把 Core 读透。
>
> **`rtl/csr_unit.v` 曾经属于"不在主线"的一类，现在不是了**：它是 Core 内部的架构状态，
> 而且 Trap 是本届进阶任务的核心，所以它被提到 §2.1 与 §2.2 的主线上（T26）。

---

## 3. Task 总表（36 项：基础 T1～T25 + 进阶 T26～T32，其中 T28 拆 4 片）

状态记号：`☐` 未开始 ／ `▶` 进行中 ／ `☑` 已通过

### 第一层：顶层 `rtl/pipeline_cpu.v`（1089 行）

> T1～T6 讲的是**基础数据通路**（端口、流水寄存器、五级逻辑、时序块）。
> A1（BTB 取指元数据）与 A3（Trap/CSR）在顶层新增的部分由 **T28a～T28d** 单独讲，见 §3「第六层」。
> T1～T6 的行号区间已经按 1089 行版重算过（见 §1.3）。

| Task | 范围（1089 行版） | 主题 | 状态 |
|---|---|---|---|
| **T1** | 1～60 | 模块头与端口：六类对外接口为什么这么分 | ▶ |
| **T2** | 62～182 | 全部寄存器声明与四个流水寄存器的字段 | ☐ |
| **T3** | 184～274 | ID 级：译码、字段切分、写回值、读寄存器、WB→ID 旁路 | ☐ |
| **T4** | 276～358 | EX 级基础通路：前递两级选择、ALU、分支判定、跳转目标、EX 级未对齐判定 | ☐ |
| **T5** | 572～746 | Load-Use、访存与 `mem_done`/`mem_block`、控制流解析与重定向、预测器例化、IF 段请求展示形式 | ☐ |
| **T6** | 748～1089 | 事件输出 + 唯一时序块逐段精读 + trace 输出 | ☐ |

> **第 360～570 行（异常原因编码、CSR 读改写、中断判定、Trap 接受点、`csr_unit` 例化）不在 T1～T6 里**，
> 它们是 A3 加进来的部分，由 T28b / T28c 单独讲。
> 所以 T4 读到第 358 行会"跳"到第 572 行，这是有意的，不是漏读。

### 第二层：流水线控制子模块

| Task | 文件 | 行数 | 主题 | 状态 |
|---|---|---|---|---|
| **T7** | `rtl/hazard_unit.v` | 32 | load-use 判决：为什么消费者停在 ID，EX 用气泡顶替 | ☐ |
| **T8** | `rtl/forward_unit.v` | 28 | 前递优先级、`rd!=0` 排除、为什么排除 Load | ☐ |
| **T9** | `rtl/branch_predictor.v` | 81 | 16 项直接映射、2-bit 饱和计数器、初始 `2'b10`、EX 级更新；**A1 新增：跳转项恒 taken（`update_is_jump`）** | ☐ |

### 第三层：执行单元

| Task | 文件 | 行数 | 主题 | 状态 |
|---|---|---|---|---|
| **T10** | `rtl/alu.v` | 29 | 10 种运算、SLT/SLTU、SRA/SRL、移位量低 5 位 | ☐ |
| **T11** | `rtl/branch_unit.v` | 25 | 六种条件分支、signed/unsigned 极值 | ☐ |
| **T12** | `rtl/load_store_unit.v` | 111 | byte lane、符号/零扩展、byte enable、非对齐策略 | ☐ |

### 第四层：译码与状态

| Task | 文件 | 行数 | 主题 | 状态 |
|---|---|---|---|---|
| **T13** | `rtl/imm_gen.v` | 41 | I/S/B/U/J 五类拼接、符号扩展、B/J 位重排 | ☐ |
| **T14** | `rtl/decoder.v` | 365 | 主译码、ALU 控制、`illegal` 与安全默认值 | ☐ |
| **T15** | `rtl/decoder.v` | 365 | 全指令逐类核对：每条指令的控制信号组合为什么不冲突 | ☐ |
| **T16** | `rtl/regfile.v` | 18 | 同步写、组合读、`x0` 保护、与 WB→ID 旁路的关系 | ☐ |

### 第五层：接口与外设（速览，不逐行）

| Task | 文件 | 主题 | 状态 |
|---|---|---|---|
| **T17** | `rtl/soc_data_interconnect.v` | 地址表、单 outstanding、片选与未映射行为 | ☐ |
| **T18** | `rtl/soc_fpga_memory.v` | 同步 BRAM 模型与 `req_ready` 策略（含 `!rsp_valid\|\|rsp_ready`） | ☐ |
| **T19** | `rtl/perf_monitor.v` + `perf_mmio.v` | 七项计数器与 MMIO 读取 | ☐ |
| **T20** | `rtl/uart_tx.v` + `uart_rx.v` + `uart_mmio.v` | 波特率分频、帧格式、RX 三个 sticky 状态位 | ☐ |
| **T21** | `rtl/gpio_mmio.v` | 最简 MMIO 外设模板 | ☐ |
| **T22** | `rtl/application_mmio_mux.v` + `logic_analyzer_mmio.v` | Application 窗口分址与显式读索引 | ☐ |
| **T23** | `rtl/capture_engine.v` + `logic_analyzer_pattern_gen.v` | 触发、前后采样、clock-enable、四种激励模式 | ☐ |
| **T24** | `rtl/single_cycle_cpu.v` | Reference Model 与提交级 trace 的对照实现 | ☐ |
| **T25** | 综合复盘 | 跨模块时序推演：给程序，逐拍说清信号 | ☐ |

### 第六层：进阶任务增量（A1 / A3 / 高阶项①，T26～T32）

> 这一层是 2026-09-30 追加的，对应 `docs/advanced_task_plan_qa.md` 的 A1/A3
> 与 `docs/handoff_next.md` §3.3 的 S2～S4。
>
> **阅读顺序遵守 §0.2 纪律 1（自顶向下）——不按任务编号，也不按"哪个简单先读哪个"：**
>
> 1. **先读完父模块 `pipeline_cpu.v`**：T1～T6 读基础数据通路，T28a～T28d 读 A1/A3 在顶层新增的部分。
>    两者是**同一个文件**，必须在进入任何子模块之前读完。
> 2. **再读它的子模块**：T7～T16（原有）+ **T26 `csr_unit.v`** + **T27 `decoder.v` 的 SYSTEM/Zicsr 段**。
> 3. **最后读 Core 之外那一棵树**：T17～T24（SoC/外设）+ T29（定时器与互连）+ T30～T32（cache/burst）。
>    它们**不是** `pipeline_cpu.v` 例化的，而属于板级/SoC 顶层那一棵树，所以排在最后。
>
> T30～T32 内部仍按 S2 → S3 → S4 的顺序（先有行式突发，再有 I-Cache，最后 D-Cache）。

| Task | 文件 / 范围 | 行数 | 主题 | 状态 |
|---|---|---|---|---|
| **T26** | `rtl/csr_unit.v` | 246 | 机器模式 CSR 状态：13 个 CSR、位段掩码、Trap 进入 / MRET 返回、`minstret`、只读与未实现地址的非法判定 | ☐ |
| **T27** | `rtl/decoder.v` 的 SYSTEM/Zicsr 段 | 约 90 | `ENABLE_SYSTEM` 为什么默认 0、`csr_en/csr_wen/csr_funct`、`ecall`/`ebreak`/`mret` 三条译码线 | ☐ |
| **T28a** | `pipeline_cpu.v` 39～56、120～182 | 约 80 | 三根中断输入、两个 Trap 观察事件、4-bit 异常记录、四个流水寄存器里的 Trap 字段 | ☐ |
| **T28b** | `pipeline_cpu.v` 205～228、360～460 | 约 130 | 产生点：`dec_trap_*`、`EXC_*` 编码、"先到先得"的四级合并、CSR 读改写 | ☐ |
| **T28c** | `pipeline_cpu.v` 462～570、649～675 | 约 130 | 接受点与改路：`trap_take`、恢复地址三选一、`mtval`、`redirect_pc` 优先级、`csr_unit` 例化 | ☐ |
| **T28d** | `pipeline_cpu.v` 699～746、776～1072 | 约 340 | 取指前端：在途请求地址为什么不能改、丢弃与重新登记；时序块里的 Trap 相关分支 | ☐ |
| **T29** | `rtl/timer_mmio.v` + `soc_data_interconnect.v` 的 `TARGET_TIMER` 段 | 154 + 173 | 中断源在 SoC：`mtime`/`mtimecmp`、窗口译码、为什么 Core 只看到三根通用线 | ☐ |
| **T30** | `rtl/soc_line_burst_adapter.v` | 301 | S2 行式突发：一次要一整行 | ☐ |
| **T31** | `rtl/soc_icache_2way.v` | 297 | S3 2 路组相联 I-Cache。**重点不是性能，是"命中响应寄存一拍为什么把每拍一条取指弄丢了"** | ☐ |
| **T32** | `rtl/soc_dcache_2way.v` | 445 | S4 2 路组相联 D-Cache。**重点：`S_RFIL` 数据阵列写入的 `cacheable_q` 门控（S4 第九轮定位的真根因）** | ☐ |

**预计耗时**（按 §0.5 口径）：T26 约 60～90 分钟；T27 约 40 分钟；T28a～T28d 各 60～90 分钟；
T29 约 60 分钟；T30～T32 各 60～90 分钟。
`T28a`～`T28d` 里的字母只是**切片编号**，每次仍然只讲一片，讲完就出题，不合并。

---

## 4. 进度与产出登记

> 每通过一个 Task，我在这里补一行。行号以 §1.1 的 SHA 为准。

| Task | 状态 | 完成日期 | 讲解中记下的产出文件 | 出题结果 | 备注 |
|---|---|---|---|---|---|
| T1 | ▶ | | | | 2026-09-30 开始，按自顶向下纪律从顶层模块头与端口读起 |
| T2 | ☐ | | | | |
| T3 | ☐ | | | | |
| T4 | ☐ | | | | |
| T5 | ☐ | | | | |
| T6 | ☐ | | | | |
| T7 | ☐ | | | | |
| T8 | ☐ | | | | |
| T9 | ☐ | | | | |
| T10 | ☐ | | | | |
| T11 | ☐ | | | | |
| T12 | ☐ | | | | |
| T13 | ☐ | | | | |
| T14 | ☐ | | | | |
| T15 | ☐ | | | | |
| T16 | ☐ | | | | |
| T17 | ☐ | | | | |
| T18 | ☐ | | | | |
| T19 | ☐ | | | | |
| T20 | ☐ | | | | |
| T21 | ☐ | | | | |
| T22 | ☐ | | | | |
| T23 | ☐ | | | | |
| T24 | ☐ | | | | |
| T25 | ☐ | | | | |
| T26 | ☐ | | `docs/learning/t26_csr_unit.md` | | 讲解稿已备好，但**按自顶向下纪律后置**：读完顶层 T1～T6 / T28a～T28d 再读 |
| T27 | ☐ | | | | |
| T28a | ☐ | | | | |
| T28b | ☐ | | | | |
| T28c | ☐ | | | | |
| T28d | ☐ | | | | |
| T29 | ☐ | | | | |
| T30 | ☐ | | | | |
| T31 | ☐ | | | | |
| T32 | ☐ | | | | |

### 已有产出（可复用，不重做）

| 文件 | 内容 | 与哪些 Task 相关 |
|---|---|---|
| `docs/learning/t02_core_datapath.md` | 手绘版 `pipeline_cpu` 五级数据通路图（mermaid）+ 四个流水寄存器字段 + 四条关键路径 + 五个判断点 | T2、T4、T5 的对照基准 |

---

## 5. 代码地图：每条关键信号在哪一行

> 先给"索引"，读代码时用来跳转。**细节仍以逐行讲解为准**，这里的表只是骨架。

### 5.1 六类对外接口（T1）

| 组 | 输出侧 | 输入侧 | 语义 |
|---|---|---|---|
| 取指事务 | `i_req_valid`、`i_req_addr`、`i_rsp_ready` | `i_req_ready`、`i_rsp_valid`、`i_rsp_data`、`i_rsp_error` | 单 outstanding，有效时地址稳定，`valid` 不得撤销 |
| 数据事务 | `d_req_valid`、`d_req_addr`、`d_req_write`、`d_req_wdata`、`d_req_wstrb`、`d_rsp_ready` | `d_req_ready`、`d_rsp_valid`、`d_rsp_rdata`、`d_rsp_error` | 同上，由 `dstate` 串行化 |
| 通用中断输入（A3 新增） | — | `irq_software_i`、`irq_timer_i`、`irq_external_i` | 三根**设备无关**的电平信号（第 42～44 行）。中断源、使能、优先级、聚合全在 SoC；Core 里不许出现设备名或设备地址 |
| 提交级 trace | `trace_valid`、`trace_pc`、`trace_instruction`、`trace_rd_we`、`trace_rd_addr`、`trace_rd_data`、`trace_mem_we`、`trace_mem_addr`、`trace_mem_data`、`trace_mem_wstrb`、`trace_error` | — | 只读观测口，不参与执行 |
| 性能事件 | `event_stall`、`event_load_stall`、`event_branch`、`event_branch_taken`、`event_flush`、`event_predict`、`event_btb_hit`、`event_mispredict`、`event_illegal`、`event_misaligned`、`event_bus_error` | — | 脉冲，喂给 Core 外 `perf_monitor`（第 46～59 行） |
| 性能事件（A1/A3 新增） | `event_control_redirect`、`event_trap`、`event_trap_return` | — | 同样只读。`event_control_redirect` = A1 省下来的那几次重定向；`event_trap`/`event_trap_return` 是板级 ILA 抓 Trap 进入/返回的探针（第 764～765 行） |

### 5.2 关键内部信号（T2～T6）

| 信号 | 属于 | 含义 |
|---|---|---|
| `fetch_pc` / `if_req_addr_reg` / `fetch_req_pc` | IF 三个地址寄存器 | 下一笔要取的地址 / 在途请求地址 / 已接受待响应那笔的地址 |
| `if_req` / `if_arm` / `if_rsp` / `if_discard` / `if_req_discard` | IF 事务状态 | 请求已冻结 / 刚接受完上一笔 / 正在等响应 / 响应要丢弃 / 请求已被标错 |
| `ifid_valid` / `ifid_pc` / `ifid_inst` / `ifid_error` / `ifid_pred_*` | IF/ID | Bubble 位 + 指令 + 取指错误 + 预测元数据 |
| `idex_*` | ID/EX | 操作数 `idex_a/idex_b`、`idex_imm`、地址/rd/f3、全部控制位、预测元数据 |
| `exmem_*` | EX/MEM | `exmem_alu`、`exmem_store`、`exmem_f3`、访存控制位；**无预测元数据** |
| `dstate` | 数据事务 | `D_IDLE` → `D_REQ` → `D_RSP` |
| `memwb_*` | MEM/WB | 唯一产生写回与 trace 的地方，含 `memwb_error`、`memwb_sdata`、`memwb_wstrb` |
| `wb_value` / `wb_fire` | WB | 四选一写回值 / 有效退休 |
| `mem_done` / `mem_block` | MEM | 本拍访存是否完成 / 是否让前端停住 |
| `load_use` | Hazard | Load-Use 停顿请求 |
| `branch_resolve` / `branch_mispredict` / `ex_redirect` / `redirect_pc` | EX | 分支解析与重定向 |
| `id_advance` / `ifid_available` / `if_accept` / `if_request_accept` / `front_hold` | IF 交接 | 是否允许推进、是否能接收新响应、两个握手、前端是否停 |

### 5.3 四条非对称设计（最容易被误读，T4/T5/T6/T28 会重点讲）

1. **`exmem_forward` 是 3 选 1，`wb_value` 是 4 选 1** —— 多出来的 `memwb_mem` 才是 Load 数据；Load 数据在 EX/MEM 那一拍根本不存在，所以不能进 `exmem_forward`。
2. **冲刷只清年轻的** —— `idex_valid <= 0` 和 `ifid_valid <= 0`，但**不动 `exmem_*`**，因为 EX/MEM 的数据事务可能已经被 SoC 接受了，不可撤销。
3. **`if_req` 与 `if_arm` 两种取指展示形式** —— 对外语义完全等价（都是单 outstanding 的取指事务），`if_arm` 只是消除"接受后一拍没有请求在场"的空洞，让取指达到每拍一条。
4. **Trap 只在 WB（退休边界）接受**（A3 新增，第 482～530 行）—— 不是"一发现就跳"。因为在 WB 接受才能天然保证"更老的指令全部完成、更年轻的指令全部取消"。
   由此推出一条最容易记错的精确性结论：**出错指令紧邻的后继那条也会被取消**，所以标准 handler 要写"读 `mepc` → +4 → 写回 → `mret`"。
   还有一处必须分清：`memwb_exc_valid` **绝对不能**被 `trap_take` 门控（第 833～836 行），否则会退化成"永远判不出异常"。

---

## 6. 参考资料（按需查，不通读）

| 想了解 | 看哪个 |
|---|---|
| 流水寄存器字段的冻结约定、取指满速交接约定 | `docs/architecture.md` §5.1、§5.2 |
| BTB 为什么"跳转恒 taken"、为什么只在校验失败时重定向（A1 的设计决定） | `docs/architecture.md` §5.3 |
| **Trap/CSR 的唯一契约**：CSR 支持矩阵、异常原因编码、`mtval` 语义、优先级表、M-01～M-24 验收项 | `docs/trap_contract.md` |
| Core/SoC 边界与事务语义（唯一契约） | `docs/interfaces.md` |
| 进阶任务的任务包划分与宣称规则（A0～A7） | `docs/advanced_task_plan_qa.md` |
| Cache/burst 的 S1～S4 闸门、量化证据与止损条件 | `docs/handoff_next.md` §3.3 |
| 手绘版数据通路图（T2/T4/T5 的对照基准） | `docs/learning/t02_core_datapath.md` |
| T26 的讲解与产出 | `docs/learning/t26_csr_unit.md` |
| `if_arm` 改动的前因后果与 Before/After | `docs/rtl_changes.md` 改动 2、`docs/coremark_cpi_analysis.md` |
| CPI 归因的完整证据链 | `docs/coremark_cpi_analysis.md` |
| 真实踩坑记录（读代码看不懂"为什么这么写"时的解释） | `docs/debug_log.md` |
| 频率/资源/时序数据与口径 | `docs/performance_tuning.md` |
| 指令覆盖表 | `docs/rv32i_instruction_coverage.md` |

> **口径纪律**：从本计划里引用的所有性能数字，都必须能说出它的来源是「实体板实测 / 时序扫描 / PDS 综合 / RTL 仿真估算」。混口径是最容易被追问击穿的错误。

---

## 7. 与工程侧的关系

- 本计划**只读不写 RTL**。精读期间不改任何 `rtl/*.v`。
- 你在精读中发现的可疑点，写进 §9 观察清单；要不要动、什么时候动，按 `docs/roadmap.md` 的 Gate 单独决定。
- 当前工程侧仍在 Task 33～35 的交付冻结阶段。本计划不改变交付主线，也不作为完成度证据。
- 如果某次精读真的发现了一个**已定位的正确性 bug**，那不是"顺手改"，而是走正常流程：写入 `docs/debug_log.md` → 最小修复 → 重跑受影响 Regression → 报告 PASS/FAIL。

---

## 8. 每日自检

- [ ] 今天只读了一个模块，没有跳读
- [ ] **今天的讲解里每个术语都先有了一句大白话，没有拿术语解释术语**（§0.0）
- [ ] **今天至少有一个比方让你"哦，原来是这样"了一下**；如果全程听着发飘，说明比方没打对，当场提出来换
- [ ] 能对着代码指出：这个信号哪一行声明、哪一行被赋值、被谁使用
- [ ] 出题的 D 类（推演题）能正确画出拍序
- [ ] 今天没有为了"更懂"而修改任何 RTL
- [ ] 学到的"为什么"写进了 §9 或对应产出文件

---

## 9. 观察清单（精读中发现、但暂不改的点）

| # | 日期 | 位置（文件 + 行号 + SHA） | 观察到什么 | 影响面 | 处理 |
|---|---|---|---|---|---|
| 1 | | | | | 待定 |
| 2 | | | | | 待定 |

---

## 10. 易踩的坑（开读前先看一遍）

| 坑 | 正确认识 |
|---|---|
| 把 `wire` 当成寄存器 | 这个文件里只有第 **776** 行起一个 `always @(posedge clk)`。其余全是当拍现算的组合值，包括 `exmem_forward`、`wb_value`、`ex_a/ex_b`、`ex_exc_cause` |
| 以为前递发生在 ID 级 | 前递目标是 **EX**。ID 级另有一个独立的 `WB→ID` 旁路（`id_a`/`id_b`），两者不是一回事 |
| 把 `ifid_pc` 当成 `fetch_pc` | `ifid_pc` 来自 `fetch_req_pc`（**已接受待响应**那笔的地址），不是当前展示的请求地址 |
| 认为 `idex_store` 存在 | 没有这个信号。Store 数据在 EX 级是 `srcb0`，搬进 EX/MEM 变成 `exmem_store`，到 MEM 级才由 LSU 重排成 `ls_store` |
| 认为 Load 结果在 EX/MEM 里 | 不在。`exmem_forward` 没有 `mem` 分支；Load 数据要等 MEM 级响应才回来，落在 `memwb_mem` |
| 认为 `error` 可以提前报 | 不行。`ifid_error` → `idex_error` → `exmem_error` → `memwb_error` 一路带到 WB 才随指令退休报 |
| 以为重定向能撤回在途请求 | 不能。只能 `if_discard` / `if_req_discard` 标记，等它正常握手回来后丢掉 |
| 用 git HEAD 的 `pipeline_cpu.v` 对照行号 | HEAD 是 139 行旧版，没有 `if_arm`、没有 Trap。行号全部按工作区 **1089 行**版本（§1.1） |
| 以为"异常一发现就跳走"（A3） | 不是。异常只是被**记下来**（4-bit 记录随指令前进了四级），真正的跳转只在 **WB** 那一拍发生（`trap_take`，第 494 行） |
| 以为 `mepc` 永远是 PC+4（A3） | 不是。同步异常恢复地址是**出错指令自己的 PC**；只有"已经发出去并被下游接受的 Store 访问错误"才推进到 PC+4（第 505～507 行） |
| 以为 `trap_take` 会顺手改 CSR（A3） | 它只是送往 `csr_unit` 的一个脉冲（`trap_enter`）。改 `mstatus`/`mepc`/`mcause` 全在 `csr_unit.v` 里发生，而且与 `csr_we` 之间有"Trap 优先"的互斥（第 546 行） |

---

## 11. 版本历史

| 版本 | 日期 | 内容 | 状态 |
|---|---|---|---|
| 第 1 版 | 2026-09-19 之前 | "吃透/重建优先"：T01 端口清单、T02 手绘数据通路图、T06～T10 五次重建 | 停用。仅 T01/T02 产出被后续版本吸收 |
| 第 2 版 | 2026-09-22 | "答辩版"：9 张任务卡（K1～K9）、数字速查表、红点清单 | 降级为附录 A 逃生包 |
| 第 3 版 | 2026-09-22 | 源码逐行精读版：自顶向下 25 个 Task，逐模块讲解 + 出题验收 | 已被第 4 版取代（基线作废） |
| **第 4 版** | **2026-09-30** | **基线重新冻结为 A1+A3 工作区版（`pipeline_cpu.v` 1089 行 / `B58496706686E37B`）：§1.1 全部数字重算、§1.3 结构图重画、§2.1 例化表由 9 项改为 11 项（新增 `csr_unit` 与 EX 级 `lsu_ex`）、§5.3 增第四条、§10 增三个 Trap 坑，并追加第六层 T26～T32（进阶任务增量）** | **当前执行** |

---

## 附录 A：答辩逃生包（原第 2 版的有效部分，保留备查）

> 用途：如果临近答辩、时间不够走完源码精读，就退回这一套"说清楚"的准备。它不需要读代码，只需要能出声讲。
> **它不替代源码精读**，只是保底方案。

### A.1 四个必答数字串（每个都要带口径）

| 指标 | 数值 | 口径 |
|---|---|---|
| CoreMark Score | 45.051 @ 50 MHz / 72.081 @ 80 MHz PLL | 实体板实测 |
| CoreMark/MHz ×1000 | 901（两点一致） | 实体板实测 |
| CPI | 1.5388 / 1.5387（双频差 0.006%） | 实体板实测 |
| 优化前 CPI → 后 | 2.3443 → 1.5388（Score +52.4%） | 实体板实测 |
| 最高工作频率 / 上板频率 | 85 MHz（时序扫描，WNS +0.393 ns）/ 80 MHz（实体板实跑） | 两者**不可混说** |
| 资源（最终唯一配置） | 3459 LUT、3129 FF、5.5 DRM18K | PDS 综合 |
| BTB | 16 项直接映射 + 2-bit 饱和计数器，初始 `2'b10` | `rtl/branch_predictor.v` |
| 逻辑分析仪 | 8 通道、Raw 深度 256、J8 回环 80/80 PASS | 外设 + 实体板 |

### A.2 七个一句话答案

1. **总述**：RV32I 五级流水线 CPU，Verilog 从零写，跑在 PGL50H 盘古 50 上；Core 只通过通用取指/访存/提交事务对外，外设全在 Core 外面。
2. **五级**：IF/ID/EX/MEM/WB，四个流水寄存器都带 `valid` 和 `error`；`error` 必须带到 WB 才报。
3. **数据冒险**：靠前递，`EX/MEM → EX` 优先于 `MEM/WB → EX`；Load 例外，紧跟着的消费者停在 ID 停一拍。
4. **控制冒险**：分支在 EX 定目标，错了就冲刷 IF/ID 和 ID/EX；**只清年轻的**，因为 EX/MEM 的事务可能已被接受。
5. **性能**：优化前 CPI 2.3443，根因是取指请求被接受后下一拍没有请求在场，每笔取指占 2 拍；`if_arm` 让接受当拍就武装下一笔，CPI 降到 1.5388。
6. **边界**：Core 只有四类端口；RAM、译码、UART、GPIO、逻辑分析仪全在 Core 外；换外设不动 Core 源文件。
7. **应用**：8 通道可重构多协议逻辑分析仪，Core 外 MMIO 外设，触发 + 前后采样 + BRAM 环形缓冲 + UART 上传 + Python/VCD。

### A.3 追问三层速查

| 追问 | 答案要点 |
|---|---|
| 前递到哪一级？ | EX，不是 ID。ID 另有一个独立的 WB→ID 旁路 |
| 为什么 Load 要停而 ALU 结果不用？ | ALU 结果 EX 末尾就有；Load 数据要到 MEM 末尾才回来，差一拍 |
| 为什么 SoC 侧也要改才有效？ | `req_ready` 必须是 `!rsp_valid \|\| rsp_ready`，两边一起才能把取指钉在每拍一条 |
| 预测正确还要冲刷吗？ | 有代价：预测正确也走无条件重定向，浪费拍数，这是已知优化空间 |
| 为什么不用 RLE？ | 范围取舍，不是做不出来 |
| 85 和 80 是什么关系？ | 85 是时序扫描证据，80 是实体板 PLL 实跑，绝不可混说 |

### A.4 红线

- 不得再引用 `CPI 2.6682`、`CoreMark/MHz 0.520`、`68.2594 MHz` —— 那些是早期 RTL 仿真估算，已被实体实测取代。
- 不许编。答不上来就说"我确认过的是……，这部分我没展开"。

---

## 附录 B：速览模块的一句话定位

| 文件 | 一句话 |
|---|---|
| `rtl/imem.v` | 行为级取指存储器：字节地址 `>>2` 选 word，非对齐/越界返回零，`$readmemh` 初始化 |
| `rtl/dmem.v` | 行为级数据存储器：组合读、按 `wstrb` 同步写 byte lane、越界读写有明确约定 |
| `rtl/single_cycle_cpu.v` | 架构 Reference Model，输出提交级 trace 供流水线逐条比对 |
| `rtl/soc_fpga_memory.v` | 板级同步 BRAM 模型；取指端口 `req_ready` 允许"响应接收同拍接受新请求" |
| `rtl/soc_data_interconnect.v` | Core 外地址译码：RAM/UART/GPIO/Application/未映射五段，单 outstanding |
| `rtl/perf_monitor.v` | Core 外七项计数器：cycle、instret、stall、load stall、branch、taken、flush |
| `rtl/perf_mmio.v` | 把上面七项映射到 Application 窗口 `0x1000_2000..0x1000_20FF` |
| `rtl/uart_tx.v` / `uart_rx.v` | 8N1 收发；80 MHz 下 694 分频 ≈ 115274 baud（−0.064%） |
| `rtl/uart_mmio.v` | UART 寄存器接口；RX 三个 sticky 状态位 |
| `rtl/gpio_mmio.v` | 最简 MMIO 外设模板，可替换性演示用 |
| `rtl/application_mmio_mux.v` | Application 窗口分址：性能计数器 / 逻辑分析仪 |
| `rtl/logic_analyzer_mmio.v` | 显式 `READ_INDEX` + `READ_DATA`，不靠读后自增，背压不重不漏 |
| `rtl/capture_engine.v` | 系统时钟 + clock-enable、8 通道、256 条 Raw 环形缓冲、前后采样计数 |
| `rtl/logic_analyzer_pattern_gen.v` | Core 外激励发生器：static / counter / UART 8N1 / SPI mode 0 |
| `rtl/csr_unit.v` | **A3 新增，Core 内部**：13 个机器模式 CSR、位段掩码、只读/未实现地址报非法、Trap 进入与 `MRET` 返回的状态迁移、`minstret` 计数。已在 §2.1/§2.2 主线上（T26） |
| `rtl/timer_mmio.v` | **A3 新增，Core 外部**：`mtime` / `mtimecmp`（`0x1000_3000` 窗口），机器定时器中断的源头 |
| `rtl/soc_line_burst_adapter.v` | **高阶项① S2，Core 外部**：把单次访问攒成"一整行"的突发读写 |
| `rtl/soc_icache_2way.v` | **高阶项① S3，Core 外部**：2 路组相联 I-Cache，位于取指端口与下级存储之间 |
| `rtl/soc_dcache_2way.v` | **高阶项① S4，Core 外部**：2 路组相联 D-Cache，位于数据端口与互连之间；MMIO 区域永远旁路 |
| `fpga/**/pll_80m.v` | `GTP_PLL_E3`：`IDIV=1, FDIV=16, ODIV0=10 → 80 MHz`；PGL50H 无法精确产生 85 MHz |
