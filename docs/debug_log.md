# Debug Log

> 最后更新：2026-10-24（0xAB 组合采集：镜像索引位宽写成 `log2(DEPTH)-1` 导致取指别名；`wait_mark` 标记长度数错）

本文件只记录已经实际发生、对架构或后续开发有复用价值的重要 Bug。尚未开始 RTL 时不预填虚构问题。

## 2026-10-24 波形 + 指令流一次采集（0xAB）这一轮的三个坑

> 背景：给 tr85 这档演示位流加"同一次运行里既采 Core 探针波形、又采提交级 trace"的组合命令。
> 第 1、2 条是**功能性**问题，第 3 条是**验证方法**问题。

### 1. 生成器把存储器索引位宽写成 `log2(DEPTH)-1`，2048 深只认 256 个字 → 取指全部别名

| 项 | 内容 |
|---|---|
| 现象 | 8 KB 镜像（DEPTH=2048）烧进板子和跑仿真，**两边表现完全一样**：CPU 不打印 `LA_READY`，串口只剩噪声（板子侧 COM11 收到连续 0x00，仿真侧日志里全是 `\x00`）。一度怀疑是断电丢位流、又怀疑是固件 C 代码 |
| 定位 | 先把**冻结的 la85 位流**重新烧上板：串口安静（无噪声），说明板子/串口/线都正常 ⇒ 问题在我新做的 8 KB 配置。再把**4 KB 固件镜像**塞进同样 8 KB 的存储器布局重跑仿真：**仍然同样地跑飞** ⇒ 与固件 C 代码无关，是存储器/地址译码。最后逐字比对生成出来的模块：索引被写成 `mem[req_addr[10:2]]`——2048 个字需要 11 位索引，10 位只覆盖 256 个 |
| 根因 | 生成器里 `$addrHi=[int][Math]::Log($Depth,2)-1`：`log2(2048)=11`，减 1 得 10。正确是 `log2(DEPTH)+1`（1024→11、2048→12），因为索引字段是 `req_addr[高位:2]`，高位下标 = 位宽 + 1 |
| 修法 | 改成 `+1`，并在脚本注释里写明"1024→`[11:2]`、2048→`[12:2]`"以及这个坑的后果；对默认档（1024）两处替换都是空操作，交付镜像逐字节不变 |
| 教训 | **"板子和仿真同时坏、且症状一模一样"是好事**：它几乎排除了时序/供电这类硬件因素，把范围直接压到配置上。而**先用冻结的已知良好位流做对照**，是分清"我的改动"与"机器状态"的最快一步 |

### 2. `wait_mark` 的标记长度数错（13 写成 15），TB 永远匹配不上

| 项 | 内容 |
|---|---|
| 现象 | 仿真场景 3 稳定报"等不到标记 len=15"，但同一份日志里明明有 `LA RAW count=` 这一行 |
| 定位 | `wait_mark` 用的是"从尾部倒着比 `len` 个字符"的约定，`len` 必须**正好**等于标记字符串长度。`"LA RAW count="` 是 **13** 个字符（`LA `+`RAW`+空格+`count`+`=`），我按 15 传了进去，多比两个字符必然失败 |
| 修法 | 长度改 13；并且意识到 `wait_mark` 只适合"以 `\r\n` 收尾的整行"标记——对块内子串一律改用 `find_all`（`check_seq`/`check_wave_samples`），场景 3 因此改成"等到 `TRACE_DONE`，再用 `find_all` 逐项断言" |
| 教训 | 结构判据里的**字符串长度是硬编码**，最容易差一两个字符；写完应当立刻在日志里 `grep` 一次确认标记真的存在，而不是等 TB 报"等不到"再去猜 |

### 3. 波形"每拍一个样本"的 `div` 语义：`div=0` 才是每拍

| 项 | 内容 |
|---|---|
| 现象 | 第一版以为 `LA_DIV=1` 表示"每拍采集一次"，写进固件后拍号与指令对不上（`capture_engine` 里 `sample_tick=(sample_div==0)||(div_count>=sample_div)`） |
| 修法 | 固件写 `LA_DIV=0`，回包头部把 `div=` 如实打出来；上位机判据要求 `div==0` 才允许声称"每拍对齐"，否则如实报"拍号与指令对不上" |
| 教训 | **"分频参数"永远要回代码确认语义**（是"每 N 拍一次"还是"再分 N 次"），并且把它写进回包让判据能验——不要让它只活在我的记忆里 |


## 2026-10-24 pyUI 第 2 页重排踩到的两个坑（都在上位机，不涉及 RTL）

> 背景：用户说"第二页太乱了"，把四块独立 Canvas 重排成"一块画布 + 四组泳道 + 一根共享时间轴"。
> 下面两条都属于"代码看起来完全正确、检查也过了，界面上就是不对"的那一类。

### 1. `tk.Text` 的标签名 `sel` 是保留名，`tag_configure` 的背景被静默忽略

| 项 | 内容 |
|---|---|
| 现象 | 指令表里"当前这条"应该整行铺蓝底。程序里 `tag_configure("sel", background="#3c5f96")` + `tag_add("sel", "3.0", "3.end")` 都执行了，`tag_names("3.0")` 里也真有 `sel`、`tag_cget("sel","background")` 能读回 `#3c5f96`，但**界面上一点底色都没有**；行首的 `>` 标记倒是正常 |
| 定位 | 把截图裁一块放大 4 倍（`PrintWindow` 抓图 → 自己写 PNG 解码 → 最近邻放大）才确认"确实没画"。排除字体/状态/滚动后，怀疑标签名：Tk 的 Text 控件**内置**三个特殊标签，`sel` 用于"选中区"，其外观由 `-selectbackground` / `-selectforeground` 决定，`tag_configure` 对该名字无效但不报错 |
| 修法 | 高亮标签改名 `cur`（并加单测钉死：`tag_names` 里必须是 `cur`、**不能**出现 `sel`） |
| 教训 | **`sel` 是 Tk 的保留标签名**。这类"配置生效了但被系统接管"的问题不会报错，只能靠看界面；界面小字体的像素级问题必须放大截图确认，不能靠"代码写了就算" |

### 2. 无人值守的板级检查被模态弹窗挂死，且 stdout 缓冲让日志一个字都看不到

| 项 | 内容 |
|---|---|
| 现象 | 跑 `trace_ui_board_check.py` 后，后台任务**十几分钟没有任何输出**、也不退出。它既没打印 PASS 也没打印 FAIL |
| 定位 | 两层原因叠一起：① 板子断电后丢了 SRAM 位流（`trace_board.py` 直测报 `TimeoutError: UART timeout waiting for b'TRACE_ARMED'; bytes=0`），采集失败 → `_poll_events` 里 `messagebox.showerror(...)` **弹出模态框**，模态框自带的循环让 `app.update()` 永不返回，检查脚本的泵循环被卡死；② 用 PowerShell 重定向跑 `python` 时 stdout 是块缓冲，进程不退出就一个字都不吐，于是看日志完全看不出卡在哪 |
| 修法 | 检查脚本里把 `mes50hp_validation_ui.messagebox` 换成一个**只记账不弹窗**的假对象，失败立刻打印"界面弹窗：…"并计入 FAIL；之后 `python -u`（或 `PYTHONUNBUFFERED=1`）跑后台任务。板子重新 `program_board.ps1 -Config tr85`（哈希未变 `945F36E4…`）后两档都 PASS |
| 教训 | **自动化路径上不允许出现模态交互**：GUI 程序里的 `messagebox` 必须先能被替换掉，否则"失败"会退化成"挂死"，而挂死比失败更难查。另外后台跑 Python 一律加 `-u`，否则看不到进度 |

### 3. 指令表被插入点"横向顶走"，行首标记与高亮列被切掉

| 项 | 内容 |
|---|---|
| 现象 | 离线灌数据截图里一切正常；**实板走 `--page 2 --capture-text` 真采一枪**后，指令表整列向右挪了 2～3 个字符：行首的 `>` 没了、高亮列也看不见（内容本身没变） |
| 定位 | `tk.Text` 的规矩是：当插入点正好位于插入位置时，插入完成后**插入点被顶到插入内容之后**。于是插入点落在第 1 行行尾（约 416 px 宽），Tk 为了"让插入点可见"把画面横向滚动了几像素。离线路径里窗口尺寸与重绘时序不同，恰好没触发 |
| 修法 | 插完文本后 `mark_set("insert", "1.0")` 收回插入点，并 `xview_moveto(0)` 强制横向归零；单测里断言 `xview()[0] == 0.0` 且 `insert == "1.0"` |
| 教训 | **"离线回放对了"不等于"真机路径对了"**：同一段绘制代码，事件顺序不同就会露出不同的毛病。凡是"灌数据截图 + 真跑一遍"都做得到的，两样都要做 |

## 2026-10-19 乘法并行部分积这一轮的两个坑

> 背景：把 `rtl/mdu.v` 的乘法从"两级串联 16x32"改成"四路并联 16x16"，目标是把乘法
> 占用 EX 的拍数从 3 降到 2（`MUL_LAT`）。完工后 CoreMark 仿真 cycles −1.571%、LUT −46、
> 85 MHz 时序仍 Met。下面两处都是**只有跑 PDS 才会暴露**、靠仿真永远看不到的问题。

### 1. 64 位三元相加被综合成"两条 64 位行波进位链串联"（WNS −2.947 ns）

| 项 | 内容 |
|---|---|
| 现象 | `MUL_LAT=1` 的位流 PDS 报 `Some Constraints Violated`：WNS −2.947 ns、估算 Fmax 67.97 MHz，而仿真完全正常（46 项手算 + 提交级 trace 全过） |
| 定位 | 时序报告第一条违例路径：`core/rf/regs → core/mdu_unit/pp00[17] → core/mdu_unit/N31_1_3/gateop_A2/Cout → N31_1_5 → N31_1_7 → …`；`gateop_A2/Cout` 连了十几级，`Logic Levels: 18` |
| 根因 | 第一版把全积写成 `({32'b0,q00} + ({32'b0,q01}<<16)) + (({32'b0,q10}<<16) + {q11,32'b0})`，即**两个 64 位加法器串联**。PDS 把每个 64 位加法实现成一条行波进位链（每级 0.058 ns × 60 多级），两条串联直接爆表 |
| 修法 | 按 16 位分块重写：只用 17 位（低位）与 33 位（高位）加法器，并把"低位进位"做成 `hid0/hid1` 两个候选值再二选一，使最高位加法与最低位加法处在**同一级**。加法深度从 2×64 位行波降到 2 级窄加法 |
| 教训 | **Verilog 里的 `+` 位宽就是关键路径**。写"看起来是加法树"的表达式，综合器未必给你一棵树；位宽越大越容易变成行波链。多位宽算术必须显式分块，并用 PDS 验证，不能只靠仿真 |

### 2. 归档的 PDS 配方缺 `rtl/ras.v`，用当前源码树重建直接编译失败

| 项 | 内容 |
|---|---|
| 现象 | 复制 `fpga/coremark_im_85m` 建对照工程后，PDS 在 compile 阶段直接失败：`E: Verilog-4072: [rtl/pipeline_cpu.v(line number: 802)] 'ras' is referenced to undefined module` |
| 定位 | 归档配方 `add_design` 清单里没有 `rtl/ras.v`；而 2026-10-18 之后 `pipeline_cpu.v` 无条件例化 `ras`（由 `ENABLE_RAS` 参数关闭功能，但模块必须存在） |
| 影响 | 这批 09-30 / 10-14 建的归档工程（`coremark_im_85m`、`coremark_85m`、`coremark_90m` 等）**都不能用当前 RTL 重建**，只能引用已经产出的 `.sbit` 与报告 |
| 修法 | 在新建的对照工程配方里补 `add_design ../../rtl/ras.v`；归档工程保持原样（不擅自重打，位流哈希是交付证据） |
| 教训 | **"归档位流的哈希"与"源码树可重建"是两件事**。任何 Before/After 都必须在**同一份配方**下重建基线，不能拿归档数字当分母——本次同配方基线与归档差 13 LUT / 0.031 ns，原因就是源文件集不同 |

### 3. Testbench 的 `retired` 有 ±1 尾拍噪声（不是架构差异）

| 项 | 内容 |
|---|---|
| 现象 | 三种 `MUL_LAT` 的 `retired` 分别是 340,119 / 340,120 / 340,119，看起来像"多退休了一条指令" |
| 定位 | `tb/tb_coremark_pipeline.v` 的结束条件是"GPIO 出现 `0xc3` 后固定再跑 `repeat (200) @(posedge clk)`"，这 200 拍里还在执行停机自跳转循环，对齐位置不同会差 1 条 |
| 判据修正 | 架构等价性一律看 **`instret`（CoreMark 计时窗口内的性能计数器）**，三方都是 `0x51327 = 333,095`，逐位相同；`retired` 只是 TB 的观测尾拍，不作为判据 |
| 教训 | 停机尾拍计数不能当架构判据；报告"指令数一致"要用程序自己读到的 `instret` |

## 2026-10-14 M 扩展（RV32IM）这一轮的四个坑

> 背景：用户批准实现完整 M 扩展并把 CoreMark 的 Before/After 做到实板。四个坑里
> 前三个都在 `rtl/mdu.v` / `rtl/pipeline_cpu.v` 的**握手与语义**上，最后一个在时序上。
> 全部由证据定位（提交级流水账 diff、PDS 时序报告、实板症状），没有一个是猜出来的。

### 1. 背靠背的两条除法指令，第二条沿用了第一条的结果

| 项 | 内容 |
|---|---|
| 现象 | `rem x8, x1, x2` 返回了上一条 `div x7, x1, x2` 的**商**（期望 2，实得 3）；连续 4 条除法只有第 1 条真正迭代 |
| 定位 | `tb/tb_pipeline_m_ext.v` 的 `DIV INSN COUNT got=4 want=13`：13 条除法只有 4 条真的产生了 34 拍停顿 |
| 根因 | 状态机只在 `run` **落下**时才回 IDLE。背靠背的两条同类指令之间 `run` 一直是 1，状态机停在 `S_DONE` 不复位，于是第二条沿用第一条锁存的结果 |
| 修法 | 新增 `ack` 输入：流水线在"该指令连同结果被锁进 EX/MEM"那一拍给出**消费脉冲**，`S_DONE` 依 `ack \|\| !run` 回 IDLE。`ack` 同时用于乘法通路（同一个坑在乘法上表现为第二条沿用第一条的积） |
| 教训 | 多周期单元与流水线之间**必须有一条"我走了"的显式握手**；只靠"输入还在不在"判断，在背靠背场景下必然出错（这条与 `if_arm` 的取指交接是同一类问题） |

### 2. CoreMark rv32im 跑到 306,637 条后整机死锁（停在一条 `lbu` 上）

| 项 | 内容 |
|---|---|
| 现象 | 提交级 trace 停在 `pc=0x000001d8`（`ee_printf` 的数字打印循环里），之后几百万拍不再退休任何指令 |
| 定位 | 反汇编 + 提交流水账：最后退休的是 `add a5,t1,a5`，下一条是 `lbu`（访存），再下一条是 `divu` |
| 根因 | 访存指令的"完成"由**握手**定义：`dstate` 从 `D_RSP` 回 `D_IDLE` 只发生一次，而 MEM→WB 的转移原来与"ID/EX 换入 EX/MEM"是**同一拍原子发生**的。引入除法停顿后两者被拆开：访存指令完成并退休，但 EX/MEM 因为 `mdu_block` 不能换入 → 下一拍 `mem_done` 落下（`dstate` 已是 `D_IDLE`）→ `mem_block` **永久为 1** → 整机冻结 |
| 修法 | 新增 `exmem_retired` 标记（"这条 EX/MEM 记录是否已经形成 MEM/WB 记录"）：MEM→WB 只允许每条记录退休一次，`mem_done` 在退休后保持为 1，MEM 级因此可以与 EX 级解耦排空。`event_misaligned` / `event_bus_error` / `mem_access_error_now` 一并加 `!exmem_retired`，保证事件仍只计一次 |
| 验证 | 修复后 CoreMark rv32im 一次跑完（`bytes=655`、官方 CRC 全过），且 trap 契约 99 条、流水线回归 13 项全部未退化 |
| 教训 | **"某一级的完成"与"下一级能不能接"必须解耦**。原设计靠"同拍换入"隐式保证"每条指令只退休一次"，加入任何停顿源都会把这个隐含假设打破 |

### 3. 一次"假死锁"：并发改 RTL 与跑仿真

| 项 | 内容 |
|---|---|
| 现象 | rv32im 仿真在 5,000,000 拍上限处只退休 2,999,925 条，看起来像死循环 |
| 定位 | 把同一个镜像在**两个版本**上各跑一遍提交级流水账并逐行 diff：前 340,120 条提交**逐条完全相同** |
| 根因 | 那次仿真是在**后台**跑的，而我在它 `iverilog` 编译期间改了 `rtl/mdu.v` / `rtl/pipeline_cpu.v`，编进去的是"改到一半"的源文件 |
| 教训 | **改 RTL 与跑仿真不能并发**。要并发就必须串行化：先改完、再一次性编译+跑。判断"是不是真死锁"的最快办法是"同一份 RTL 重跑是否复现"，与 2026-10-12 那条"回归失败先看能否复现"是同一条纪律 |

### 4. 乘法器：一拍组合 32×32 直接吃掉 2.4 ns，85 MHz 违例

| 项 | 内容 |
|---|---|
| 现象 | 50 MHz CoreMark 的 WNS 从 +2.676 ns 掉到 **+0.234 ns**；85 MHz 逻辑分析仪直接 `Some Constraints Violated`，Slack **−3.268 ns** |
| 定位 | PDS 时序报告：最差路径 `core/rf/regs → core/srca0 → core/mdu_unit/N25_m1/gopapm/PO → m2 → m3 → m4 → core/exmem_alu`，逻辑级数 14 |
| 根因 | 32×32 乘法被综合成 **4 级串联 APM**，串联链本身约 8.4 ns；只把操作数寄存（2 拍版）不够，链还在 |
| 修法 | 分两段流水：第一段把 32×32 拆成两个 **16×32** 部分积（`ma[15:0]*mb`、`ma[31:16]*mb`）分别寄存，串联链缩到 2 级 APM；第二段做"移位相加 + 符号修正"。每条乘法 3 拍。50 MHz WNS 回到 **+1.841 ns**，85 MHz **All Constraints Met** |
| 代价 | 每条乘法 +2 拍（相对一拍组合版）：板级 ticks/迭代 430,579 → 439,975（**+2.2%**），Score 116.122 → **113.642**（50 MHz）/ **193.192**（85 MHz） |
| 教训 | **FPGA 上的"一个 `*`"不是一条路径，而是一条链**。Pango 的 APM 是 18×18，32×32 至少要 4 级；要用它就必须自己切流水，不能指望综合器 |

### 5. 采集源 MUX 把 spi 模式的全速采样余量吃光（实板症状：固件永久卡死）

| 项 | 内容 |
|---|---|
| 现象 | 新位流上板后 static/counter/uart 全过，**spi 模式一发配置包固件就永久卡死**，之后连 static 也无响应，必须重下位流 |
| 定位 | 与 `release/evidence/fmax_ceiling/README.md` §4 记录的 90 MHz 症状**逐字一致**；spi 是唯一 `sample_div=0`（每拍采样）的模式，最吃时序 |
| 根因 | 源选择 MUX 直接串在 `channels → capture_engine` 之间，把这条路径的余量吃掉了 |
| 修法 | 采集源选择的结果**寄存一拍**再进采集引擎（`active_channels_q`）。引擎输入从此来自寄存器，这条路径比加功能之前**更短**；代价是采样点整体晚 1 个系统时钟，对所有判据无影响（窗口整体平移一格） |
| 同类第二处 | Core 的事件信号是组合逻辑，直接进采集引擎让"Core 事件逻辑 → `capture_count` 使能"成为 85 MHz 最差路径（Slack −0.980 ns）。在**板级顶层**给探针再打一拍即可，且只影响探针、不影响 J8 通路 |
| 教训 | 往一条**已经接近上限**的路径上再加一个 LUT，症状可能不是"时序报告变差"，而是**实板功能间歇/永久失效**。所以加外设逻辑时必须回头确认关键路径的宿主 |

### 5b. 同一个坑的"外部版本"：触发永不出现也会永久停住固件（2026-10-14 无人值守跑界面检查时复现）

| 项 | 内容 |
|---|---|
| 现象 | 无人值守的界面检查脚本在跑到"core 预设 + J8 源"那一枪后，**后续每一枪都收不到任何字节**（`UART timeout waiting for b'LA_READY'; bytes=0`）；重下 `la85` 后立刻恢复（`PROGRAM PASS` / done bit 1） |
| 定位 | 该枪的触发是 core 预设默认的 ch6 上升沿；切到 J8 源后 ch6 是**没接信号的外部引脚**，边沿永不出现。固件此时停在 `software/logic_analyzer/logic_analyzer.c` 第 189 行 `while ((LA_STATUS & 4u) == 0u) { }`——**无超时轮询**，既不读串口也不输出 |
| 与被修掉的 spi 卡死的区别 | 第 5 条是**时序余量**问题（新位流 + 全速采样），修好后再不复现；这一条是**协议语义**问题：任何一枪只要触发不命中就会发生，与位流版本无关，属于设计上缺"Arm 超时" |
| 修法（本轮） | 不改固件（改它要重建位流、作废全部哈希与证据）：① 上位机在"一个字节都没收到"时直接提示"固件停在等待采集完成，按 REST 或重下位流"，不再让现场猜接线；② 恢复卡与演示脚本写明这一点与"调试先用电平触发"的纪律；③ 无人值守脚本禁止使用永不命中的触发 |
| 待定 | 给固件加 Arm 超时（例如 2 秒轮询上限 → 打印 `LA_TRIG_TIMEOUT` 后回到命令循环）是**正确**的修法，但需要重建并重测位流；是否在本届做由用户决定，见 `docs/application_logic_analyzer.md` §6.10.7 |
| 教训 | "测试脚本为了图省事随手选一个触发"会**真的把设备弄成不可用状态**，而且症状（串口全哑）看起来像硬件故障。凡是能进入"等一个外部事件"的设备，都要先问：**等不到会怎样** |

### 5c. 采集源接进界面后暴露的两个"假失败"（判据按模式选是错的）
| 项 | 内容 |
|---|---|
| 现象 | 四种"模式 × 采集源"组合里有两种报 FAIL：`uart + Core 源` 报 `UART decode mismatch`；`core 预设 + J8 源` 报 `UART timeout`（触发永不命中） |
| 定位 | 两者都不是采集问题：前者采到的**确实是流水线信号**，是主机拿 UART 帧去套；后者的波形页把一根普通外部线标成 `ch7 = trace_valid` |
| 根因 | 8 根线的物理含义由**采集源**决定，而判据、通道名、波形页标注全都按 `mode` 分支 |
| 修法 | 新增 `capture_view(mode, source)`：源 = Core ⇒ 一律按流水线观测点解释；源 = J8 且 mode = core ⇒ 只报点数/跳变（`raw`）；其余才用协议判据。判据、通道名、读数区、波形页标注全部改按 view 选，两个上位机共用同一规则 |
| 教训 | 一个参数如果改变的是"被测对象是什么"，那它就不能只影响**发送**（报文），还必须影响**解释**（判据/标注/通道名）。只改一半的典型症状就是"采集是对的、结论是错的" |


## 2026-10-14 单文件上位机"点 core 没反应"：写日志时漏传 source，把轮询循环打死了

> 背景：用户实板操作时反馈"点 core 没反应"（截图里连续采集停在 mirror 的波形上、
> 按钮卡在「停止采集」）。查下来是**两个独立缺陷叠在一起**，都出在单文件界面上。

### 1. 致命的一条：`log_packet()` 漏传 `source`，异常从 Tk 的 after 回调窜出，把整个界面冻住

| 项 | 内容 |
|---|---|
| 现象 | 选 core 模式后点采集：日志不出现报文行、波形不刷新、按钮状态不再变化——整个界面像死了。控制台（双击启动时看不见）里是一行 `ValueError: bytes must be in range(0, 256)` |
| 定位 | 复现时抓到的栈：`poll → log_packet → build_packet → bytes(v + [cs])`。core 的 cfg 是 `pre=64, post=1983, source=1`；`build_packet` 靠 **`source is not None`** 才走 0xA8 的 16 位分支，而 `log_packet` 的调用**没传 source**，于是 1983 被当成单字节写进 `bytes()` |
| 为什么界面会"死" | 异常发生在 Tk 的 `after` 回调里，而 `poll()` 末尾那句 `root.after(120, poll)` **永远不会执行** ⇒ 轮询循环从此不存在：不再取队列、不再画图、不再更新按钮。唯一的线索只打到 stderr |
| 根因 | 同一段"拼报文"逻辑被抄了两份：`capture()`（真发出去的那份）传了 `source`，`log_packet()`（写日志的那份）漏了。双源功能是 2026-10-14 加的，只改了前者 |
| 修法 | ① 抽出**唯一**入口 `packet_for_cfg(cfg)`，`capture()` 与 `log_packet()` 都走它（一份实现不可能两处漏字段）；② `poll()` 里除 `queue.Empty` 外**一律捕获**并把 traceback 打进日志面板，`root.after(120, poll)` 放进 `finally` —— 任何一条坏消息都不再能让界面静默冻死 |
| 验证 | 单元用例"六个模式都必须能经同一个 `packet_for_cfg()` 打出报文"（core 断言 16 字节 0xA8 且 post 是 16 位小端）；实板驱动 `tmp/singlefile_switch_check.py`（走真实 mainloop）12 项断言全 OK |
| 教训 | **Tk 的 `after` 回调里抛异常 = 整个循环消失**，而症状是"界面没反应"、线索在看不见的控制台。凡是周期性回调，必须 `try/except` + `finally` 续上；凡是"发出去"和"记下来"两份实现，必须合成一份 |

### 2. 第二条：连续采集运行中切模式不生效（"看起来点了、其实没换"）

| 项 | 内容 |
|---|---|
| 现象 | 连续采集 mirror 跑着时点 core 单选钮：面板上的窗口/采集源都换成了 core 的，但画面还是 mirror 的波形（标题写着"上位机发送 HELLO,RISC-V"），看着像"点了没反应" |
| 根因 | 任务在 `start()` 那一刻就把模式冻结了（`jobs.put((current_mode(), …))` 只读一次），worker 的循环用这个冻结值反复采；模式单选钮在运行中又**没有置灰**，于是"改得动、但不生效" |
| 修法 | 运行中切模式 ⇒ 主动请求停止当前那一枪（`st["stop"]=True`），连续采集再在收尾后**按新模式自动重开**（`st["restart_live"]`）；同时新增 `st["running_mode"]`，状态行与停止提示都写明"正在采 X"，日志记一行"切换模式 → core：正在采的是 mirror，已请求停止…" |
| 验证 | `tmp/singlefile_switch_check.py COM11`（真实 mainloop 驱动真实界面）：mirror 跑满一轮 → 点 core → `stop/restart_live` 双双置起 → 自动重开后 `running_mode=core` 且 core 跑满一轮、最后一帧 `mode=core` → 停止正常 |
| 教训 | "点了没反应"要先分清是**界面没收到**还是**收到了但没作用到正在跑的任务上**。多线程 GUI 里凡是有"启动时快照"的参数，运行中修改都必须显式处理，否则就是在骗用户 |

### 3. 顺带修掉：报错不给恢复办法

`capture()` 的 `_read_until` 只说"等不到 b'LA_READY'（收到 0 字节）"。现在 **0 字节**时额外打三条：
① 板上可能不是逻辑分析仪位流（CoreMark 计分位流开机不打印、只等 `R`）→ 重下 `-Config la85`；
② 固件可能被"永不命中的触发"挂住（mirror 等的是 J8-31↔32 的下降沿）→ 按 REST 或重下位流；
③ 恢复后先跑 static 确认链路。三条与 `release/materials/field_recovery_card.md` 同一口径。

## 2026-10-14 逻辑分析仪"双源可选"TB 的两个坑（一个假 PASS + 一次整轮回归静默卡死）

> 背景：`tb/tb_logic_analyzer.v` 新增了采集源（J8 外部 vs Core 探针）三段判据。这段
> 用例此前从未被真正跑到过，于是同时埋了"假 PASS"和"无限空转"两种失败模式。

### 1. 场景 2 的 PASS 是假 PASS：`wait(dut.done)` 撞上了上一个场景残留的 done

| 项 | 内容 |
|---|---|
| 现象 | `SRC CORE CAPTURE PASS` 打印出来，看起来功能正常；但它读到的 `capture_count=4` 其实是**上一个场景**那次采样的遗留值 |
| 定位 | 插桩打印 `armed/triggered/done/capture_count` 后发现：arm 之后引擎根本没触发，`done` 一直是前一场景留下的 1 |
| 根因 | `wait(dut.done)` **不消耗状态、也不是边沿敏感**。只要上个场景结束时 `done=1`，arm 那一拍之后立刻就能通过 `wait`，于是"读到的是谁的数据"完全取决于时序巧合 |
| 修法 | 先 arm（arm 会清零 `done`），再**显式**驱动触发边沿 `ch0: 0→1`（`trigger_rise=0x01`），最后才 `wait(dut.done)`；`done` 必然由本场景置起 |
| 教训 | 用 `wait(<DUT 状态>)` 做判据时，必须先保证该状态**被本场景清零**。否则它不是判据，只是"上一次成功"的回声 |

### 2. 场景 3 只 arm 不驱动边沿 → 触发永不发生 → `vvp` 满核空转 24 分钟，整轮最终回归静默卡死

| 项 | 内容 |
|---|---|
| 现象 | `run_final_regression.ps1` 走到 `Task 30 logic-analyzer MMIO` 后停住 24 分钟以上；`vvp.exe` 单线程 CPU 时间≈挂钟时间（满核），内存仅 9 MB；外层 PowerShell 与 Agent 都收不到任何输出 |
| 定位 | 复制同一份 RTL/TB 到临时目录，插时间戳探针 + cycle 看门狗复现：卡在场景 3 的 `wait(dut.done)`；`armed=1 triggered=0 capture_count=2048 overflow=1 done=0`，即引擎一路采到缓冲满、触发一次都没发生 |
| 根因 | 该场景配的是 `trigger_mask=0x01` + `trigger_rise=0x01`（ch0 上升沿），但 TB 在 arm 之后**再没有驱动过 `channels`**：J8 源恒为 0，永无边沿。触发不发生 → `done` 不置起 → `wait` 死等 |
| 附带根因 | 同一场景还期望 `read_index=0` 读回 `0x00`，而 `channels` 在上一个场景结束时被留在 `0x01`，arm 后的前几个采样把窗口首样本填成了 `01`。**必须先 `channels=0` 再 arm** |
| 修法 | ① 场景 2/3 都在 arm 之后显式制造 `ch0: 0→1` 边沿；② 场景 3 把 `channels=8'h00` 提到 arm **之前**；③ TB 加 cycle 上限看门狗（超时打印引擎/协议状态并 `$fatal` 退出）；④ `scripts/run_logic_analyzer_tb.ps1` 给 `vvp` 加超时并把输出重定向到 `tmp/logic_analyzer/tb_output.log` |
| 验证 | `scripts\run_logic_analyzer_tb.ps1` 0.3 s 跑完 `ALL LOGIC ANALYZER TEST PASS`（exit 0）；逻辑分析仪簇 11 项测试全部 `exit=0`（含 93 s 的 mirror TB） |
| 教训 | ① 边沿触发型 TB 必须**自己造边沿**，不能指望"输入恰好还停在某个电平"；② 任何 `wait(<DUT 状态>)` 都要配 cycle 上限——否则失败模式不是"报错"，而是**空转烧满一个核且一个字都不输出**（TTY 之外 vvp 的 stdout 是块缓冲）；③ 仿真类子脚本必须自带超时，回归脚本目前只给板级/UART 脚本加了超时 |

## 2026-10-10 仪器面板**移除**这一轮踩到的坑

> 背景：用户判定按键没用，选择 **B 方案**——面板整套删除、LED 退回 `gpio_out`（详见 `docs/progress.md`
> 第三轮与 `docs/application_logic_analyzer.md` §6.8.2）。这一轮属于"加功能再拆功能"，
> 坑全部来自"拆"本身，不来自新功能。

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | PDS 报 `Verilog-4092: Loop limit 2000 exceeded`，而同一 RTL 在 `DEPTH=256` 下一切正常 | `rtl/capture_engine.v` 里有一句复位期把整块 BRAM 清零的 `for` 循环。深度从 256 提到 2048 后循环次数变成 8 倍，超过 PDS 的循环展开上限。**iverilog 仿真同样不报错**，只有综合器拒绝 | 删掉复位清 BRAM 的循环（上电后 BRAM 内容本就不参与判据，每次采集都会重写）。教训同上一轮的 `Verilog-4086`：**仿真器容忍的写法不等于综合器接受** |
| 2 | 拆完面板重建，位流哈希与"加面板之前"对不上，一度怀疑没拆干净 | 紫光 PDS 生成的 `.sbit` 内嵌**构建时间戳**，同一份 RTL、同一台机器重建，SHA-256 每次都不一样 | 哈希只能"重建后同步"到 `demo_preflight.ps1` 与 `claims_map.md`，**不能**拿它当"两次构建是否等价"的判据；等价性改由**资源/时序逐项一致 + 板级 100/100 复测**证明 |
| 3 | 面板拆掉后改 `export_final_submission.ps1`，交付包审计报文件列表与脚本不一致 | 编辑导出脚本时删掉了 TB 的拷贝行，却漏删 `$rtlFiles` 里的 `la_panel.v` 条目；导出脚本一旦与真实文件树脱节，审计立刻抓出 | 按审计报出的差异逐条对齐；`.ps1` 含中文必须带 UTF-8 BOM（`scripts/ensure_ps1_bom.ps1`），否则 PowerShell 5.1 读中文注释会乱码 |
| 4 | `docs/*.md` 批量替换脚本本身 `SyntaxError` 退出 | 该脚本用 ASCII 双引号包裹含中文引号的替换文本，Python 把中文引号当成了字符串边界 | 改用中文引号/转义重写后重跑；批量文档替换脚本必须先干跑（不带 `--write`）确认可解析 |

**方法论收获**：这一轮最好的证据不是"我删了哪些文件"，而是
**移除后位流的 LUT/FF/DRM/WNS/WHS/Fmax 与加面板之前逐项一致**（4479 / 3610 / 6.0 / +0.588 / +0.310 / 89.4721 MHz）。
它把"删除干净"从主观判断变成一个可复现的量化结论——这套"改完比资源表"的做法后续任何还原/回退都适用。

## 2026-10-10 仪器面板 / 读数这一轮踩到的坑

> ⚠️ 下表第 1、4 行涉及的 `rtl/la_panel.v` 与面板 TB 已在同日**整套移除**（见上一节），保留作机理记录；
> 第 5 行的读数缺陷修复**仍然有效**。

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | PDS 报 `Verilog-4086: More than one always block assigned a value to the same variable 'p_arm'`，**iverilog 却编译通过** | `rtl/la_panel.v` 里控制脉冲被"状态块"和"脉冲块"两个 always 同时赋值。仿真器按后写覆盖容忍，综合器直接拒绝 | 脉冲只留脉冲块一个驱动；状态块只置 `panel_active` |
| 2 | PDS 报 `ConstraintEditor-0098: contains illegal character, only ASCII characters are supported` | 往 `.fdc` 追加了中文注释，而约束文件只接受 ASCII | 注释改英文 |
| 3 | 改完编码，PDS 又报 `ConstraintEditor-0046: invalid command name "//"` | `.fdc` 是 TCL 语法，注释符是 `#` 不是 `//`；第一次清理时还漏掉了乱码那行 | 全部改 `#`，并逐行确认无 `//` |
| 4 | 板级 TB 的按键用例"看起来通过"但**其实没跑** | `$finish` 在主 initial 块里，并行写的按键 initial 块被提前截断 | 按键序列并进主块；断言从"查瞬态 `armed`"改成"先 Clear 再 Arm，看是否重新采到数"（面板逐拍采样，几拍就采完，查瞬态必然查到 done） |
| 5 | 读数把 8658 ns 印成 `8.659 ks`、把 SPI 的 SCLK 读成 10.07 MHz（真值 10.62） | ① 纳秒值直接丢给通用 SI 格式化；② 周期用平均值，被字节间隙这类偶发长间隔带偏 | 时间用专用 `fmt_time(ns)`；周期改用**中位数**并同时给出抖动 min…max |

另外记录一条**不可复现的瞬时失败**：加面板后的第一次 100/100 验收里 mirror 卡住
（现象：收到 `LA_ARMED`、发出字符串、`LA_READY` 永不到来 = 已 arm 但没触发）。
重新下载同一位流后连跑 3 次镜像 + 完整 100/100 全 PASS，**未能复现**；
当时的静态证据（前四个模式用的是上位机参数、日志与 summary 正常）表明面板没有接管。
留此备查：若再次出现，优先查 J8 31↔32 那根跳线与串口状态，不要先去改 RTL。


## 记录格式

每个 Bug 使用以下字段：

- 日期与任务。
- 失败测试和最小复现程序。
- 第一个错误周期。
- 第一个错误信号。
- 预期值与实际值。
- 根因。
- 最小修复范围。
- 修复后的验证命令与 Regression 结果。
- 是否影响 Reference Model、接口或架构文档。

### 2026-10-09 / 上位机工具链被 `git restore` 冲回旧版（三处不一致）

- **现象**：`python -m unittest discover -s python` 只跑 8 个测试且全过，但
  `python python/tests/test_waveform_page.py` 一跑就 ImportError：
  `cannot import name 'write_waveform_page' from 'logic_analyzer'`。
- **第一个错误信号**：`python/logic_analyzer.py` 只有 5398 字节、没有 `def write_waveform_page`，
  而 `python/tests/test_waveform_page.py`（10-09 新增、未跟踪）明确按该函数的新契约断言。
  同一批被冲掉的还有 `logic_analyzer_serial.py`（缺 `on_run` 回调和波形页导出）、
  `mes50hp_validation_ui.py`（缺实时波形面板）、`waveform_panel.py`（旧版）。
  **`waveform_viewer.html` 反而活着**，因为它也是未跟踪文件——这正是"未提交工作被选择性冲掉"的特征。
- **根因**：这些 Python 工具当时**只存在于未提交的工作区**（交付包里有一份 10-03 的快照）。
  一次 `git restore`/`checkout` 把它们退回 HEAD 的 9 月版本；而 10-09 新写的测试与 HTML 模板
  是未跟踪文件，所以留了下来，形成"新测试 vs 旧实现"的组合。
- **次要后果**：交付包根目录的 `波形预览.html` 也是 10-03 的旧模板（不含
  `decodeUart`/`drawByteLabels`/`zannot`），而 10-09 重新生成的
  `release/evidence/logic_analyzer_board_85m/*/` 页面是带标注的新版 —— 最抢眼的那个文件恰好最旧。
- **最小修复范围**：只动上位机工具与导出脚本，不碰 RTL、位流、固件和冻结范围。
  以 `tmp/pkg_cm_verify/tools/`（10-03 那次"含实时面板"的完整快照）为准恢复
  `logic_analyzer.py` / `logic_analyzer_serial.py` / `mes50hp_validation_ui.py` / `waveform_panel.py`，
  再把 `write_waveform_page` 的可选字段（`sample_ns`/`sample_hz`/`decode`/`tag_names`/`segments`）
  按 10-09 的测试契约补回；`waveform_viewer.html` 保持 10-09 的新版不动。
- **验证**：`python python/tests/test_waveform_page.py`（6 项）、`test_waveform_panel.py`（10 项）、
  `test_timer_demo_serial.py`、`python -m unittest test_logic_analyzer test_logic_analyzer_serial test_coremark_serial`
  全 PASS；`scripts\run_waveform_viewer_test.ps1` → `ALL TEST PASS`；
  `scripts\run_logic_analyzer_python.ps1` → `ALL LOGIC ANALYZER PYTHON TEST PASS`（exit 0）。
- **影响**：不涉及 Core、接口、Reference Model；只影响上位机交付件。

### 2026-10-09 / 导出被被独占的构建垃圾卡死（半成品包）

- **现象**：`export_final_submission.ps1` 在最后一步抛
  `Get-FileHash : The file '…\release\final_submission\pds.log' cannot be read`，
  包内容其实已经写好，却**缺 `SHA256SUMS.txt` 与 zip** —— 一个"看着像导出成功、实际不完整"的半成品。
- **第一个错误信号**：`pds.log` 被别的进程独占（PDS GUI 打开过交付工程；本机还有 Sangfor 端点保护在挂钩文件访问），
  连 `Remove-Item -Force` 与 `Rename-Item` 都失败。
- **根因**：导出脚本给**包里所有文件**算哈希（`Get-ChildItem -File -Recurse`），
  而 `audit_release_package.ps1` 的交付物集合是**排除 `.lock`/`.log`/`sim/` 的**。
  导出比审计严格，于是"审计根本不会看的构建垃圾"把导出卡死了。
- **最小修复范围**：`scripts/export_final_submission.ps1` 两处 ——
  ① 哈希清单与 zip 打包都改用与审计一致的排除规则（zip 用 `ZipFile` + 文件清单，避免
  `Compress-Archive <目录>/*` 又把 `pds.log` 读进去）；② 顺带记录：编辑该文件后**必须补回 UTF-8 BOM**，
  否则 Windows PowerShell 5.1 按 ANSI 解码中文，会报
  `Unexpected token '}'` 与 `The string is missing the terminator: "@`（本轮实际踩到）。
- **验证**：`export_final_submission.ps1` → `FINAL SUBMISSION EXPORT PASS files=178`；
  `create_release_manifest.ps1` → `RELEASE MANIFEST PASS files=3679`；
  `audit_release_package.ps1` → `RELEASE PACKAGE AUDIT PASS final_files=179 artifacts=3`；
  三处位流副本 SHA-256 仍为 `788F1CEB…DCE2`（未重新综合）。
- **影响**：只影响发布流程，不影响 RTL 与位流。

### 2026-09-17 / 交付冻结：改名暴露出的 4 个既有脆弱点

一次性把 `taskNN_*` 命名改成功能化命名（`fpga/coremark`、`fpga/logic_analyzer`、`fpga/coremark_ila`、
`scripts/run_*`、`tb/tb_*`、`tb/data/*.mem`、`software/*` 等）。改名本身不改行为，但暴露并修掉了 4 个既有问题：

1. **测试依赖仓库里的陈旧固件产物**：`run_soc_harness_tb.ps1` 直接读 `software/<prog>/build/<prog>.mem`，
   自己不做 `make`。旧产物一直存在所以从没暴露；固件改名后立刻报 `$readmemh: Unable to open …`。
   修复：runner 增加 `make -C software/mmio_demo all`，测试自包含。
2. **发布审计把位流哈希写死**：`audit_release_package.ps1` 里 `$expected='2C09E690…'`，任何一次重新综合后
   审计必然失败，无法跟随新位流。修复：以 `fpga/logic_analyzer/generate_bitstream/…sbit` 为唯一真实来源，
   要求 `final_submission` 与 `release/artifacts` 两处副本与之逐字节一致。
3. **审计依赖 `rg`**：本机 PATH 无 ripgrep 时审计在命名检查处中断（不是「没发现问题」，而是命令失败）。
   修复：优先用 `rg`，缺失时回退到 PowerShell `Select-String`，保留「交付包不得出现 taskNN」这条检查。
4. **导出脚本整目录删除**：`Remove-Item -Recurse` 遇到被 PDS GUI 占用的 `.pds.lock` 时中途失败，
   留下**半成品发布包**（本次实际发生）。修复：改为逐项删除、跳过被占用条目并告警；
   `.lock` 本来就被清单与审计按设计排除。

证据：修复后 `run_final_regression.ps1`（-Quick 与全量）均 `ALL AUTOMATED FINAL REGRESSION PASS`；
`FINAL SUBMISSION EXPORT PASS files=206`、`RELEASE MANIFEST PASS files=1963`、`RELEASE PACKAGE AUDIT PASS final_files=126 artifacts=3`。

### 2026-09-17 / 工具：Fabric Debugger 无 GUI 抓 ILA 波形的可行流程

- 背景：赛题要求「利用 ILA 抓取的波形图分析 CoreMark 关键算法的流水线效率」，此前只有诊断位流、没有实体波形。
- 结论：`cdt_dbg.exe -file <tcl>` 提供了完整 CLI，**不需要打开 GUI**。可用命令（来自
  `Fabric_Debugger_User_Guide.pdf`）：`dbg_connect / dbg_scan_chain / dbg_program / dbg_import_fic /
  dbg_fla_get_bus / dbg_fla_run / dbg_fla_trig_immd / dbg_fla_export_wf_data / dbg_disconnect / dbg_close`。
- 踩坑记录：
  1. **必须先下载匹配的位流再 `dbg_import_fic`**，否则报 `Debugger-4001: FIC file isn't matching`。
  2. `dbg_fla_power_init` 在本设计上失败（`get_power_on_init_data exec unsuccessfully`）。它是可选项：
     IP 未开「power-on init data」时必然失败，但**不影响抓取**。TCL 脚本里若保留它，会因为
     “命令失败即中断后续命令”而整段停在导出之前——要么去掉，要么在其后加 `clean`。
  3. `dbg_fla_set_capture -type N -samples 512` 报 `Capture type or arguments is illegal`；
     直接用 IP 默认抓取配置即可（本设计为单窗口 512 拍）。
  4. `open_cable` 偶尔耗时 5 分钟以上（USB 重新枚举）。**同一时刻只能有一个进程占用下载线**：
     前一次中断的 `cdt_dbg` 不退出会一直占线，导致后续进程卡在 `open_cable`/`dbg_scan_chain`。
     排查方法：`Get-CimInstance Win32_Process -Filter "Name like 'cdt%'"` 看有几个客户端。
  5. CoreMark 镜像 `AUTOSTART=0` 会等串口 `R`：抓取期间需要另起一个持续发 `R` 的进程；
     重下位流会复位 FPGA 并让固件重新等待 `R`。
- 成果：512 拍窗口，IPC 0.635 / CPI 1.575（板级整段 1.5388，差 2.3%），
  窗口内 84.3% 提交落在 `__mulsi3` 软件乘法循环。证据与复现见 `release/evidence/ila_coremark/README.md`。

### 2026-09-17 / CPI 专项：取指每两拍一条，把 CPI 钉在 2.34（**Score 最大单项损失**）

- 现象：实体板 50/80 MHz 两点 `CoreMark/MHz x1000` 都是 591，CPI 2.3443 / 2.3445；
  按每 1000 条指令分解 `2344.3 = 理想 1000 + stall 106.4 + flush 103.3 + 剩余 1134.6`，
  这个「剩余 1134.6（48.4%）」既不是 Hazard stall 也不是 flush，长期没有归因。
- 第一错误点：**取指事务的第二个周期**——请求被接收后的那一拍，取指端口没有任何请求在场。
  （不是 EX/MEM 的数据事务，也不是 Hazard 逻辑。）
- 第一错误信号：`i_req_valid` 在窗口 1,788,110 拍中有 **920,207 拍（51.5%）为低**；
  相邻 IF/ID 写入间隔直方图里 **间隔 2 占 664,411 次（86.7%）、间隔 1 只有 1 次**。
- 预期与实际：`docs/interfaces.md` §3 明确要求「流水线 IF 允许在旧取指响应完成握手的同一拍接受下一请求，
  以支持一拍一条的连续取指」；实际每笔取指固定占 2 拍，1,532,008/1,788,110 拍（85.7%）是取指底座，
  其中 **768,832 拍（43.0%）纯属取指串行化损失**。
- 根因（两处，缺一不可）：
  1. Core：`pipeline_cpu.v` 在 `if_request_accept` 当拍 `if_req<=0`，而重新登记 `if_req_addr_reg`
     要等到“响应被接收”那一拍的结尾（`if(!if_req)` 分支），因此下一拍请求不可见，
     “旧响应接收 + 新请求接受”的同拍交接永远无法发生。
  2. SoC：实体板取指存储器 `assign req_ready=!rsp_valid`，在交接当拍（`rsp_valid=1 && rsp_ready=1`）
     恰好为 0，即使 Core 把请求送到也会被拒收。
- 最小修复：Core 新增 `if_arm`（接受请求当拍立即武装下一笔请求，展示地址直接来自已寄存的 `fetch_pc`，
  不新增地址寄存级，`!ready` 时地址仍稳定；Redirect 当拍先冻结成 `if_req` 再改 `fetch_pc`）；
  取指存储器 `req_ready` 改为 `!rsp_valid||rsp_ready`（数据端口不变，`dstate` 已串行化）。
  详见 `docs/rtl_changes.md` 改动 2。
- 归因方法（可复现）：新建只读观测台 `tb/tb_cpi_attribution.v` + `tb/cpi_board_memory_model.v`
  （与 `coremark_imem`/`coremark_dmem` 逐拍一致），口径自证：观测台 CPI **2.342** vs 实体板 **2.3443**。
  单改 SoC 侧 ready 策略收益只有 2.342 → 2.321（−0.9%），证明瓶颈在 Core。
- 验证：-Quick 与全量回归 `ALL AUTOMATED FINAL REGRESSION PASS`；官方 CoreMark RTL 仿真
  cycles 1,852,156 → 1,295,932；实体板 50 MHz Score 29.559 → **45.051**、CPI 2.3443 → **1.5388**、
  22.196 s、四 CRC 全过；80 MHz PLL Score 47.295 → **72.081**、CPI 1.5387；逻辑分析仪 50/80 MHz 各 80/80 PASS。
- 影响：只改 Core 内部取指握手与 Core 外取指 adapter 的 ready 策略。Core 顶层端口、单 outstanding 语义、
  提交级 trace 语义、Reference Model 等价性全部不变；80 MHz WNS 由 +0.145 ns 变为 +0.667 ns（更好）。

### 2026-09-17 / CPI 专项：load-use 停顿计数 3 → 4（测试期望按新时序纠正，非放宽）

- 失败测试：`scripts/run_pipeline_load_use_tb.ps1`（固定延迟编译）报 `LOAD STALL COUNT FAIL got=4 want=3`。
- 第一错误点：`tb/data/load_use.mem` 中 `0x24 lw x7,0(x0)` → `0x28 add x8,x1,x7` 这一对的 ID/EX 周期。
- 第一错误信号：`event_load_stall` 在该对指令上多出一次脉冲（`LOADUSE cyc=27 ex_load_pc=00000024 id_pc=00000028`）。
- 预期与实际：该程序共有 **4 组相邻 load-use**（0x08→0x0c、0x10→0x14、0x18→0x1c、0x24→0x28），
  满速取指下 4 组都必须检出；旧期望值 3 是“取指每两拍一条”时代的历史标定——
  当时取指空洞恰好插在 0x24→0x28 之间，把这对相邻指令在流水线里拉开成两级，
  既不构成 load-use、也不需要停顿。
- 根因：不是 RTL 缺陷，而是旧值把“前端串行化顺带掩盖了一个真实冒险”误当成正确基线。
- 最小修复：`EXPECT_LOAD_STALL` 3 → 4，并在脚本内写明理由；同时用一次性探针
  （`tmp/cpi/probe_loaduse.v`）逐事件打印 4 次 `LOADUSE` 的 PC 对，确认与程序里的 4 组 hazard 一一对应。
- 验证：同测试的**提交级 trace 与最终 architectural state 对比全部 PASS**；
  `scripts/run_final_regression.ps1`（-Quick 与全量）均 `ALL AUTOMATED FINAL REGRESSION PASS`。
- 影响：仅测试期望值；流水线功能、接口与 Reference Model 不受影响。

### 2026-09-17 / 工具：频率扫描汇总把 `Minimum Pulse Width` 当成 setup WNS

- 最小复现：`scripts\run_fmax_sweep_rtl.ps1 -Tag cpi -Periods '11.765,11.111'`，
  再看 `tmp/fmax_sweep/cpi_sweep_summary.csv` 与同目录的 `report_timing/*.rtr`。
- 现象：85 MHz 汇总写 `WNS=4.365`、90 MHz 写 `WNS=4.038`，而 `.rtr` 的
  `Setup Summary(Slow Corner)` 实际是 `+0.393` / `−0.374`；4.365 其实是
  `Minimum Pulse Width Summary(Slow Corner)` 的 slack。
- 第一错误点：汇总脚本的报表解析（不是 PDS、不是 RTL）。
- 根因：原解析用“第一个形如 `名字 名字 数字 数字 整数 整数` 的行”取 WNS/WHS，
  而报告里 `Recovery/Removal/Minimum Pulse Width/Setup(Fast Corner)` 等小节是同一形态。
- 最小修复：改为**按小节定位**——先记录当前小节名（`^名字:`），只在
  `Setup Summary(Slow Corner)` 取 WNS/TNS/失败端点、在 `Hold Summary(Slow Corner)` 取 WHS/THS；
  并从 `Performance Summary` 行额外记录估计 Fmax。同时修正小节名捕获的正则
  （原正则贪婪匹配只捕到 `Setup Summary`，漏掉 `(Slow Corner)` 后缀）。
- 验证：`-Tag cpi3 -Periods '11.765,11.111'` 汇总输出
  `f84998 WNS=0.393 fail=0 WHS=0.231 MET`、`f90001 WNS=-0.374 fail=102 WHS=0.312 VIOLATED`，
  与手工从 `.rtr` 读取的数值逐字段一致。
- 影响：仅扫描汇总脚本；`docs/performance_tuning.md` 中的历史 WNS 数字本来就直接取自 `.rtr`，不受影响。

### 2026-09-17 / 工具：`run_coremark_fpga_tb.ps1` 会静默把板级镜像恢复成“未窗口对齐”版本

- 最小复现：跑一次 `scripts/run_coremark_fpga_tb.ps1`，再检查 `fpga/coremark/rtl/coremark_imem.mem`
  是否还含 `start_time()` 的 `PERF_CONTROL` 写（`... 100027B7 00100713 02E7AC23`）。
- 现象：脚本 `finally` 恢复最终 1000 迭代镜像时漏传 `-PerfWindowAlign 1`，使仓库源码退回未对齐版本，
  与已经实体板实测通过的位流不一致；板级 CPI 归因依赖这个对齐窗口（否则 `COREMARK_READY`
  的 UART 轮询会进入计数窗口，产生 `stall > cycles` 的失真数据）。
- 根因：恢复步骤只对齐了 `-Iterations/-ClockHz/-AutoStart`，漏了观测口径开关。
- 最小修复：`finally` 中补 `-PerfWindowAlign 1`，并加注释说明为什么不能省。
- 验证：修复后重跑 `run_coremark_fpga_tb.ps1`，`coremark_imem.mem` 仍含窗口对齐的写操作。
- 影响：仅镜像生成脚本；不改被测执行路径。

### 2026-09-17 / Task 33：发布证据把综合与布局布线两个阶段的资源数字混排

- 最小复现：运行 `scripts/run_release_evidence.ps1`，比较 `release/evidence/automated_metrics.json` 的 `ff` 与 `docs/progress.md`、`release/HANDOFF.md`、技术报告中引用的 `3129 FF`。
- 第一错误点：`python/release_evidence.py` 的 `utilization()` 解析逻辑；不是 PDS 综合、时序或实体板问题。
- 预期与实际：`fpga/logic_analyzer/flow.log` 综合段为 LUT 3459 / 寄存器 3129 / DRM18K 5.5，device map 段为实现 FF 3120；旧实现从综合段取 LUT 与 DRM，却从 device map 段取 FF，生成 `3459 LUT + 3120 FF + 5.5 DRM` 的混合行，与全部已发布材料不一致。
- 根因：`utilization()` 在 `Device Utilization Summary` 块内匹配 `| FF |`，而 `Total LUTs`/`Total DRM18Ks` 来自综合统计，两者属于不同阶段。
- 最小修复：FF 改取综合统计 `Total Registers`（3129），并新增 `ff_implemented`（3120）单独保留布局布线后实现值；`automated_metrics.md` 增加一行阶段说明。不修改任何综合或时序结论。
- 回归：`run_release_evidence.ps1` 输出 `ALL RELEASE EVIDENCE TEST PASS`；JSON 为 `lut=3459, ff=3129, ff_implemented=3120, drm=5.5, setup=2.661, hold=0.312, fmax=57.6735`，与 `fpga/logic_analyzer/synthesize/mes50hp_logic_analyzer_top.snr` 的综合行一致；`create_release_manifest.ps1` 与 `audit_release_package.ps1` 仍 PASS。
- 影响：仅发布证据提取脚本与证据文件；不影响 RTL、Core/SoC 接口、时序或实体板结论。

### 2026-09-17 / Task 33：交付包早于最终位流，审计哈希与实体证据不一致

- 最小复现：运行 `audit_release_package.ps1` 检查最终包哈希，或比较 `release/final_submission/bitstream/mes50hp_riscv_logic_analyzer.sbit` 与 `fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit`。
- 第一错误点：交付导出时间戳（09-17 08:37）早于 J8 约束校正、Capture Engine 分频边沿修复与最终 PDS 重建（13:45～13:47）；不是 RTL、时序或综合问题。
- 预期与实际：审计期望位流 SHA-256 `2C09E690…`（实体板 80/80 回环所用），实际包内为 `01C394618BB473E6…`；同时 `evidence/logic_analyzer_board_final` 缺失，`.fdc` 仍写连续脚对 `3..18`，`capture_engine.v`、`logic_analyzer_pattern_gen.v` 与三份上位机工具均为修复前版本。
- 根因：实体回环修复与最终位流重建之后没有重新执行导出与发布清单。
- 最小修复：重新运行 `export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1`；不修改任何源文件。
- 回归：三条命令分别输出 `FINAL SUBMISSION EXPORT PASS files=215`、`RELEASE MANIFEST PASS files=1221`、`RELEASE PACKAGE AUDIT PASS final_files=132 artifacts=3`；位流三处副本 SHA-256 一致；`run_final_regression.ps1 -Quick` 输出 `ALL AUTOMATED FINAL REGRESSION PASS`。
- 影响：不影响 Reference Model、Core/SoC 接口或架构文档；仅交付产物一致性。

### 2026-09-17 / 发布脚本：PowerShell 5.1 解码与 .NET Core API 依赖

- 最小复现：本机仅 Windows PowerShell 5.1（ACP=936）时运行 `powershell -File scripts/audit_release_package.ps1` 报 `missing release/final_submission/鍚姩…cmd`；`export_final_submission.ps1` 在写清单时报 `[System.IO.Path]` 不包含 `GetRelativePath`。
- 第一错误点：解释器与脚本编码/API 契约，不是发布内容本身；导出已在复制阶段完成后失败，包内没有 `SHA256SUMS.txt` 且 zip 仍是旧文件。
- 根因：无 BOM 的 UTF-8 脚本被 PS 5.1 按 GBK 解码，中文字符串与文件名损坏；`Path.GetRelativePath` 属 .NET Core/.NET Standard 2.1，.NET Framework 4.x 不提供。
- 最小修复：为 `audit_release_package.ps1`、`export_final_submission.ps1`、`create_release_manifest.ps1`、`generate_coremark_fpga_memory.ps1` 补 UTF-8 BOM，并统一用 PowerShell 7 执行发布脚本（本机为 Codex 运行时 `C:\Users\xwc\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe`，7.6.5）。
- 回归：用 pwsh 7 重跑导出、清单与审计全部 PASS；其余 91 个纯 ASCII 脚本在 PS 5.1 下不受影响。
- 影响：仅发布工具链可移植性；不改变 RTL、Testbench 接口或验证结论。

### 2026-09-17 / Task 30：分频采样丢失 UART 边沿触发

- 最小复现：MES50HP J8 物理回环运行 UART `0xA5`，旧实现返回 `UART decode mismatch`；静态和计数器模式正常。
- 第一错误点：`capture_engine.previous_sample` 在非 `sample_tick` 周期被更新，导致发生在两个有效采样点之间的下降沿只保持一个系统时钟并在采样前消失。
- 根因：边沿检测把“上一系统时钟值”误当成“上一有效采样值”，分频采样时触发点可能落入 UART 数据位内部。
- 最小修复：Arm 时锁存当前输入，之后仅在 `armed && sample_tick` 时更新 `previous_sample`；同时让 UART pattern restart 先输出完整 idle-high 位，并由 Python 在位中心解码。
- 回归：新增 `divided edge retained` 定向测试；Capture Engine、MMIO、SoC、board-top 和 Python 全部 PASS。PDS 50 MHz All Constraints Met，JTAG 下载 DONE=1；static/counter/UART/SPI 各 20 次，共 80/80 实体回环 PASS。
- 影响：不改变 CPU Core 或 Core/SoC 接口；修复范围仅为 Core 外采集外设、发生器和上位机解码。

## 当前记录

### 2026-09-17 / 性能调优轮：冻结范围审计脚本依赖外部 rg，长期处于静默失效状态

- 最小复现：运行 `scripts/run_scope_audit.ps1`，当前环境报 `The term 'rg' is not recognized`。
- 第一个错误点：脚本第 6 行对 `rg` 的调用，不是 RTL、时序或综合问题。
- 预期与实际：审计应当扫描 `rtl`、`fpga/logic_analyzer`、`software/logic_analyzer`、`python`
  并拒绝已冻结功能（RLE/Cache/异常中断/AI/DDR/HDMI/PCIe/千兆网/I2C/16 通道）的实现；
  实际上 `rg` 不在 PATH 上，`2>$null` 又把"命令未找到"吞掉，
  于是 `$violations` 恒为空、脚本无条件走到 `SCOPE AUDIT PASS`。
- 根因：审计实现依赖外部可执行文件且隐藏了失败；`ErrorActionPreference=Stop` 无法捕获非终止的错误流重定向。
- 最小修复：`run_scope_audit.ps1` 改为纯 PowerShell 实现（`Get-ChildItem` + `Select-String`），
  显式排除 PDS 构建产物（`generate_bitstream`/`synthesize`/`place_route` 等）与 `__pycache__`，
  并新增正向断言（BTB 必须是 `valid[0:15]` 16 项 + `counter[0:15]` 2-bit）。
- 验证：注入一个含 `cache` 字样的临时文件后审计报 `FROZEN FEATURE SCOPE AUDIT FAIL` 并以非零码退出；
  删除后输出 `SCOPE AUDIT SCANNED files=47` 与 `SCOPE AUDIT PASS`。
  **注意**：该修复意味着此前若干轮记录的"Task 33 冻结范围审计 PASS"不具备证据效力，本文件在此更正。
- 影响：不改变 RTL、Core/SoC 接口或时序结论；仅让审计恢复真实检测能力。

### 2026-09-17 / 性能调优轮：板级性能计数器窗口未对齐，导致 CPI 归因完全失真

- 最小复现：下载 50 MHz CoreMark 位流（`PERF_WINDOW_ALIGN=0`），
  运行 `python/coremark_serial.py COM11 --clock-hz 50000000`，读 `PERF` 行。
- 第一个错误点：`perf_monitor` 的 `cycle_count` / `stall_count` 等计数器是**自由运行**的，
  从复位释放一直累加到 `portable_fini()` 回读时刻，**不**只在 CoreMark 计时窗口内计数。
- 预期与实际：预期 `stall/cycles` 在 5%~15% 量级；
  实际出现 `stall` **超过** `cycles`（1.70e9 vs 2.84e9 的旧数据里），
  修正前一次读数甚至出现 `branch` 超过 `instret`——物理上不可能，说明窗口口径错误。
- 根因：`COREMARK_READY` 会先等上位机发 `R` 才开跑，那段轮询是紧凑的 load+branch 循环，
  每次都要走统一事务（含固定 2 拍握手），因此产生上亿次 stall 与 branch，
  把 CoreMark 内核的真实 CPI 完全淹没。
- 最小修复：在 `software/coremark/core_portme.c` 的 `start_time()` 中加入
  `PERF_CONTROL = 1u`（写 perf_mmio CONTROL，字节偏移 0x38）清零计数器，
  由 Makefile 开关 `PERF_WINDOW_ALIGN` 控制（默认 0，保持历史镜像逐字节可比；
  正式板级归因镜像用 1）。该语句只改观测口径，不改被测量的执行路径。
- 验证：对齐后 50 MHz 实测 `cycles=1,693,816,436`、`ticks=1,691,496,677`，
  窗口差仅 0.14%（对齐前为数亿周期）；CPI 2.3443，与 RTL 仿真的 2.3747 相差 1.3%。
  80 MHz PLL 镜像独立复现：CPI 2.3445、`stall/cycles` 4.53%，与 50 MHz 逐项吻合到 0.02% 以内。
- 影响：**历史 `release/evidence/coremark_board.json` 的七项计数器不可用于 CPI 归因**
  （`ticks`/`score` 字段仍有效）；`docs/coremark_cpi_analysis.md` 已改为以
  `coremark_board_opt50m_aligned.json` 为准。不改变任何 RTL 或架构结论。


### 2026-09-15 / Task 30：Task 30 栈顶与互连 RAM 上界不一致

- 最小复现：将裸机栈顶扩大到 `0x1000` 后运行 `run_logic_analyzer_soc_tb.ps1`，软件读取的 `post_count` 变为 8192。
- 第一错误点：函数栈访问地址超过互连原 `0x3FF` RAM 窗口，返回 error/zero，随后局部变量被破坏。
- 根因：DMEM adapter 已扩大到 1024 words，但 SoC 互连仍用 1 KiB byte 地址上界。
- 修复：Task 30 board wrapper 与 SoC TB 同步使用 `RAM_LAST_ADDR=0x0FFF`，启动代码用 `lui sp,1` 设置栈顶；Core 与统一事务接口不变。
- 验证：AUTOSTART SoC 报告 `count=10 trigger_index=4 post_cfg=4`，交互式 board-top 亦 PASS。

### 2026-09-15 / Task 23：数据事务等待跨越 WB 周期时丢失转发值

- 最小复现：较老指令在 WB 写 `rd` 的同周期，较新 ID/EX 指令因 EX/MEM 数据事务等待而保持；等待结束时寄存器文件读快照仍为写回前值。
- 第一错误点：解除 `mem_hold` 后的 EX operand，原 forward unit 此时已看不到前一周期 WB producer。
- 根因：ID/EX 被整体保持时，源操作数快照没有吸收同周期提交的 WB 数据。
- 修复：保持 ID/EX 时若 WB 命中源寄存器，更新相应 operand snapshot；新增 `wb_hold` fixed/random 定向 trace 比较。
- 验证：`run_pipeline_wb_hold_tb.ps1` 两种时序 8/8 trace PASS，Task 23 十入口回归与 Task 24 GCC fixed/random 全部 PASS。

### 2026-09-15 / Task 26～30：PDS recipe 被生成脚本覆盖及大 case ROM 不可实现

- 现象：PDS 会生成或修改 `impl.tcl`，原构建脚本把生成文件误当稳定 recipe；CoreMark 的逐字 case ROM也导致综合规模和时间不可接受。
- 根因：源配方与工具输出未隔离；程序镜像没有利用 PDS 可初始化同步 DRM。
- 修复：每次构建复制只读 `pds_recipe.tcl` 到临时 recipe，并校验源 hash；CoreMark/Task 30 改为固定深度同步数组与 `.mem` 初始化，PDS 日志确认 DRM 映射。
- 验证：Task 26、Task 28、Task 30 均完成 Compile 到 bitstream，50 MHz setup/hold 全部满足；CoreMark 同步 memory board-top 仿真输出官方 CRC。

### 2026-09-14 / Task 33：最终 Regression 聚合器被历史 `exit 0` 提前终止

- 最小复现：`run_final_regression.ps1 -SkipExternal` 直接调用 `run_rv32i_regression.ps1`；Task 12 的第一个独立 Testbench 脚本正常结束时会执行 `exit 0`，父聚合器随后不再继续。
- 第一错误点：回归调度器进程边界，不是 RTL 或 Testbench 结果；日志会停在 Task 12 中段而汇总文件可能保留旧结果。
- 根因：PowerShell 脚本内的 `exit` 终止当前解释器，聚合器用 `& script` 调用时没有隔离子进程；Task 23 也存在相同风险。
- 最小修复：Task 12、Task 23 和最终聚合器统一通过当前可用的 PowerShell 解释器以 `-File` 子进程调用每个入口；保留原有退出码并在失败时停止。
- 验证：Task 12 日志完整包含 22 个入口并输出 `ALL TASK12 REGRESSION PASS`；Task 23 输出 9 个入口；修正后的 `run_final_regression.ps1 -SkipExternal` 输出 `ALL FINAL REGRESSION PASS`，外部模式输出本地 PASS 加 3 项明确 BLOCKED。
- 影响：仅修复回归调度和证据完整性，不改变 Core、SoC、接口或既有 Testbench。

### 2026-09-14 / Task 26/30：PDS 许可证自动发现路径

- 现象：当前 Codex 进程的 `PANGO_LICENSE_FILE`、用户/系统环境变量均为空；PDS 命令行因此报 `Flow-0183`。已检查 PDS 安装目录、`D:\Pango`、`C:\Users\xwc\AppData\Roaming\pango`、`C:\Users\xwc\AppData\Local\pango` 和 `D:\ToolsSoftware\pango`，当前沙箱可见范围未发现 `PDS-*.lic`/`pango*.lic`。
- 处理：Pipeline 与 Task 30 PDS 脚本增加 `-LicenseFile` 参数、标准目录自动发现和未发现时的明确警告；发现合法文件后会自动设置 `PANGO_LICENSE_FILE`，并同时检查 PDS 返回码与 `Flow-0183` 文本。
- 验证：无许可证参数时仍按预期明确失败；使用候选 ModelSim/Intel/Robei 文件会被 PDS 判为格式不兼容，未被误当作 Pango License。
- 影响：不改变 RTL；只要合法 Pango `.lic` 位于自动发现目录或由环境/参数提供，脚本即可直接执行综合，不需要修改工程文件。

### 2026-09-14 / Task 30：逻辑分析仪响应地址未锁存与测试写事务悬挂

- 最小复现：在 Application MMIO 请求接受后立即改变 `req_addr`，或在独立 TB 写请求后不消费写响应。
- 第一错误点：响应等待周期的 `rsp_rdata`/`rsp_valid`；原 wrapper 组合使用当前地址，测试写响应则使 `rsp_valid` 永久保持。
- 根因：设备未在请求握手时锁存读数据/错误位；TB 写任务没有遵守统一 response handshake。
- 最小修复：`perf_mmio` 与 `logic_analyzer_mmio` 在 `req_valid && req_ready` 时锁存响应数据和错误，`capture_engine` 仍只接受一次 arm/stop/clear 脉冲；TB 写任务等待并消费响应。
- 验证：`run_perf_mmio_tb.ps1`、`run_logic_analyzer_tb.ps1`、`run_application_mmio_mux_tb.ps1`、`run_logic_analyzer_soc_tb.ps1` 全部 PASS，并覆盖错误地址、随机背压和软件配置路径。
- 影响：仅修改 Core 外部 MMIO/测试；不改变 `pipeline_cpu` 端口或事务契约。

### 2026-09-14 / Task 30：PDS/实体板/CoreMark 外部证据阻塞

- 现象：本地 RTL、软件和 Python 回归全部通过，但 Task 30 PDS 批处理输出 `Flow-0183`，仓库没有官方 CoreMark 源码，J8 相邻脚对物理回环尚未在当前会话连接。
- 根因范围：许可证、第三方源码授权/下载和真实 MES50HP 设备属于工作区外部状态，不是仿真失败。
- 处理：`run_logic_analyzer_pds.ps1` 与 `run_final_regression.ps1` 明确检测并报告 BLOCKED；不使用其它 benchmark 冒充 CoreMark，不用内部 pattern loopback 冒充物理闭环。
- 影响：不得标记 G9/G10/G11 或 `competition_final`；本地 PASS 证据仍可复现，待具备许可证、源码和实体板后按 `docs/reproduction.md` 重跑。

### 2026-09-14 / Task 23：Redirect 撤回被背压的取指 valid

- 最小复现：`hazard_stress` 使用随机取指背压，并在 taken Branch/JAL 附近令 `i_req_valid=1, i_req_ready=0`。
- 第一错误点：Redirect 周期的取指请求接口；地址仍保持相同，但 `i_req_valid` 在握手前被撤回。
- 预期与实际：契约要求 `valid && !ready` 时 valid 与地址持续稳定；候选流水线把 `i_req_valid` 组合依赖于 `ex_redirect/front_hold`，因此错误变为 0。
- 根因：为提升 IF 吞吐而加入的响应/请求同拍交接没有保留独立的已登记请求槽，Redirect 直接抑制了尚未接受的请求。
- 最小修复：恢复 `if_req` 与稳定的 `if_req_addr_reg`；Redirect 只将等待请求和未来响应标为 discard，请求仍正常握手，返回后丢弃，再从目标 PC 发起新事务。
- 验证：`run_pipeline_hazard_stress_tb.ps1` 固定及随机背压各 20/20 条提交 trace PASS，请求稳定性监视器无错误，两个合法 Store 的请求副作用数与 Store trace 数均为 2；`run_pipeline_reset_abort_tb.ps1` 证明 Reset 可中止未接受 Store 且重启后只写一次。
- 影响：修改流水线 IF 控制，不改变 Core/SoC 端口或单 outstanding 契约；需纳入 Task 23 及后续完整 Regression。

### 2026-09-13 / Task 16：PDS 综合忽略 `$readmemh` 导致板级固件未初始化

- 最小复现：Task 16 SoC 顶层使用 `$readmemh("mmio_demo.mem", ...)` 初始化 IMEM/DMEM 后执行 PDS 综合。
- 现象：PDS 报告 initial block / `$readmemh` 不参与综合；仿真中的 Hello/GPIO 行为不能直接作为下载 bitstream 的固件证据。
- 第一错误点：综合初始化阶段；不是 CPU 指令周期或 MMIO 互连信号错误。
- 根因：该 PDS 流程不会把 Verilog 仿真时存储器初始化自动映射为综合后的 BRAM/逻辑内容。
- 最小修复：将 Task 16 demo 的 24 个镜像字改为综合可见的 Verilog 常量函数；保留 `mem/mmio_demo.mem` 作为仿真/追踪参考文件，并保持单周期 CPU 与 SoC 接口不变。
- 验证：`run_soc_harness_tb.ps1` 19/19 PASS，`run_mes50hp_soc_demo_tb.ps1` 的双行/30 字节连续 UART 检查 PASS；PDS Compile→Synthesize→Map→Place→Route→Timing→Bitstream 完成，50 MHz 下预计 59.0179 MHz、WNS 3.056 ns、TNS 0，综合日志不再出现 `$readmemh` 警告。
- 影响：当前 bitstream 固化为持续输出版 Task 16 demo；更换固件需重新生成常量并重新实现。尚未进行实体板下载与串口验收。

### 2026-09-13 / Task 16：UART 无输出的根因是缺少独立 USB-UART 数据线

- 最小复现：仅连接供电线与 JTAG 下载线，Windows 只枚举 FTDI 下载器的 COM9/COM10，未枚举底板 CP2102。
- 第一错误点：FPGA 外部的 USB-UART 物理连接；不是 `uart_mmio`、CPU、UART 波特率状态机或 FPGA 管脚约束。
- 根因：MES50HP 的 JTAG 与底板 CP2102 USB-UART 是独立链路；未插 USB-UART Type-C 数据线时，串口工具打开的是下载器通道。
- 修复：保留电源/JTAG，同时连接底板 USB-UART Type-C 数据线，使用 CP2102 的 COM 口，以 115200、8N1、无流控接收。
- 验证：当前 PDS map 为 `uart0_tx LOC=R9`、`uart0_rx LOC=R8`；实体板串口持续、无乱码地显示 `Hello RISC-V!`。
- 影响：UART TX 的实体板链路已通过；GPIO 的 `0xAA` LED 实物图仍需补充后才能宣布 Task 16 / G5 完成。

### 2026-09-12 / Task 12：未对齐 Load 会错误写回零值

- 最小复现：DMEM word 0 为 `32'h80FF_7F01`，先执行 `addi x2, x0, 0x55`，再执行未对齐的 `lh x2, 1(x1)`，其中 `x1=0`。
- 现象：`load_store_unit` 已将 `misaligned` 置 `1` 且 `load_data` 保持默认 `0`，但 CPU 仅以该信号抑制 `dmem_we`；RegFile 仍接收原始 `reg_write`，使 `x2` 被错误写成零值。
- 第一错误点：RegFile 写使能连接 `rd_we=reg_write`；第一个错误状态更新是未对齐 Load 周期的寄存器写回。
- 根因：未对齐策略只覆盖 Store，没有将 Load 的 `misaligned` 检测接入 RegFile 写使能。
- 最小修复：增加 `reg_write_effective = reg_write && !(mem_read && misaligned)`，并将 RegFile 的 `rd_we` 改接该信号；保留已有 `dmem_we = mem_write && !misaligned` 与顺序 `PC+4` 行为。
- 验证：运行 `./scripts/run_single_cycle_load_align_tb.ps1`，6/6 PASS：未对齐 `LH` 不改变哨兵 `x2=0x55`；对齐 `LHU/LB/LBU/LW` 写回分别为 `0x000080FF`、`0xFFFFFF80`、`0x00000080`、`0x80FF7F01`。运行 `./scripts/run_single_cycle_store_align_tb.ps1`，6/6 PASS：`SB`、两个对齐 `SH` 与 `SW` 按 byte strobe 更新，未对齐 `SH` 不改变 DMEM。现有单周期、JALR、U-Type、SLTI、Shift-Immediate、Logic-Immediate 回归亦全部 PASS。
- 影响：当前无异常单周期模型仅保证自然对齐 Load/Store；未对齐访问检测后不产生 RegFile 或 DMEM 写副作用，但不实现 trap。该限制须在 Task 12 覆盖表和后续 Core/SoC 文档中保持一致。

### 2026-09-10 / Task 10：MES50HP JTAG/LED 冒烟通过

- 最小复现：下载 `fpga/mes50hp_bram_smoke` 的 bitstream，使用 `P20` 作为 50 MHz 时钟，观察 `LED1=B2`。
- 现象：PDS 首次扫描板载 SPI Flash 报 `JtagServer-0335` / `Configuration-0008`；改为确认 JTAG FPGA 链并下载临时 bitstream 后成功，`LED1` 常亮。
- 第一错误点：Flash 扫描路径；不是 RTL、PDS 综合或 BRAM 逻辑错误。
- 根因范围：Flash 扫描与 FPGA 临时配置是不同下载路径；当前已验证 JTAG FPGA 配置路径正常，Flash 固化路径暂不作为本次 BRAM 冒烟前置条件。
- 验证：PDS Compile/Synthesize/Device Map/Place & Route/Timing/Generate Bitstream 已完成；实体板首次下载后 LED1 PASS，随后再次下载同一 bitstream 后 LED1 仍 PASS。当前不要求断电，因为 bitstream 尚未固化到 SPI Flash。
- 影响：Task 10 / G2 正式 PASS。SPI Flash 固化路径仍需单独排查，但不影响本次临时 JTAG FPGA 冒烟证据。

### 2026-09-08 / Task 10：PDS 批处理缺少许可证环境变量

- 最小复现：执行 `D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe -project D:\RISC_V_CPU_2026\fpga\bram_smoke\bram_smoke.pds -run cmd_synthesize`。
- 现象：PDS 在读取工程之前退出，输出 `Flow-0183: Environment variable PANGO_LICENSE_FILE is not set. Check license failed.`。
- 第一错误点：PDS 许可证检查；尚未进入 Verilog 编译、器件核对或 `.fdc` 解析，因此没有 RTL 周期/信号错误。
- 根因范围：当前 Windows 会话未配置本机 Pango PDS 的合法许可证路径或许可证服务器。
- 最小修复：通过 PDS 的许可证配置或用户已有许可证设置 `PANGO_LICENSE_FILE`，重启 PDS / PowerShell 后重跑同一命令；不得跳过许可证检查或改用其他器件。
- 验证现状：PDS 图形界面已使用其现有许可证完成首轮 Compile、Synthesize、Device Map、Place & Route、Timing 和 bitstream 生成；命令行仍不可直接复现该流程。
- 影响：阻塞可复现的 PDS 批处理，但不阻塞用户已授权的 GUI 流程；不影响 IMEM/DMEM 行为级模型的已通过回归。

### 2026-09-08 / Task 10：首轮“BRAM 冒烟”被综合器裁剪为分布式 RAM

- 最小复现：检查首轮 PDS 综合输出 `fpga/bram_smoke/synthesize/apm_drm_lutram_utilization.log`。
- 现象：原 RTL 声明为 256×32 RAM，但报告实际为 `2 x 3 bit`、`GTP_RAM32X1SP/GTP_RAM32X2SP`；没有块 RAM/DRM 资源。
- 第一错误点：综合优化阶段；固定写入两个地址和固定数据使未观测的数组空间可被裁剪，PDS 行为符合逻辑优化规则。
- 根因：自检覆盖不足，不能以 RTL 中的数组声明替代综合后的真实资源证据。
- 最小修复：测试改为 1024 个动态地址和 LFSR 数据的全覆盖写入、同步读和逐字比较，重新综合后必须以资源报告确认真实块 RAM/DRM 映射。
- 验证现状：修改后的独立 Icarus 测试已输出 `ALL BRAM SMOKE TEST PASS`；修改后的 PDS 资源报告尚未生成。
- 影响：先前生成的 `.sbit` 不得下载作为 BRAM 验收证据；Task 10 Gate 仍未通过。

### 2026-09-07 / Task 10：OSS CAD Suite 的 VVP 运行时启动崩溃

- 最小复现：执行 `D:\oss-cad-suite\bin\vvp.exe -V`，以及运行只包含 `$display` / `$finish` 的空 Testbench。
- 现象：Windows 弹出 `vvp.exe - 应用程序错误`，报告指令引用不可读内存；仿真终端无 PASS/FAIL 输出。
- 第一错误点：`vvp.exe` 进程启动阶段；尚未进入 RTL 的时间 0 仿真事件，因此不存在错误 RTL 信号或周期。
- 根因范围：OSS CAD Suite 内置的 Icarus 14.0 development (`s20260301-363-g1d2aa1b6f-dirty`) VVP 运行环境故障；与 DMEM、动态数组索引和 Testbench 时钟驱动无关。
- 最小修复：保留原工具目录但停止使用其 VVP；将 Icarus Verilog 12 Windows 稳定包独立安装到 `D:\Tools\iverilog-v12`，仿真脚本默认选择该目录，并允许用 `-IcarusRoot` / `IVERILOG_ROOT` 覆盖。
- 验证：稳定版 `vvp -V` 正常；Task 4～10 当前基础模块回归全部 PASS：RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32、Load/Store Unit 35/35、DMEM 14/14。
- 影响：仅本地仿真工具链；不影响 RTL 架构、Core/SoC 接口或 Reference Model 行为。Task 10 仍需 IMEM 与 PDS/BRAM 冒烟后才能通过。

### 2026-09-03 / Task 3：Windows ISA 检查命令不兼容

- 最小复现：在 Windows PowerShell 的 `software/hello_uart` 目录执行 `make all`。
- 现象：ELF、反汇编和镜像均已生成，但 `check-isa` 调用 Linux `grep` 失败，`make` 返回 Error 2。
- 根因：Makefile 使用了 Windows 环境中未提供的 Linux `grep` 命令。
- 最小修复：将该检查替换为 Windows `cmd /c findstr`；不改动 C 源码、链接脚本、生成物格式或 ISA 约束。
- 验证：执行 `make clean; make all`，输出 `TASK3 ISA CHECK PASS: RV32I-only disassembly`。
- 影响：仅构建脚本兼容性；不影响 CPU 架构、Reference Model、Core/SoC 接口或 RTL。

### 2026-10-21 / 提交级 trace：假 overflow（RTL 语义错）

- 最小复现：`scripts\run_core_trace_soc_tb.ps1`，phase=0 正常抓取 8 个字符。
- 现象：固件回包头部 `TRACE RAW … status=0000000C`，即 done=1 的同时 **overflow=1**，
  而 `count=100` 远小于窗口容量 —— 溢出位是假的。
- 根因：`rtl/trace_buffer.v` 的溢出条件写成 `done && trace_valid`。软件 `stop` 之后
  CPU 当然还要继续退休指令（导出循环本身就有上百条），于是每一次**正常收尾**都会置 overflow。
- 最小修复：新增 `full` 寄存器，只有"被容量写满而收尾"才允许置 overflow；
  软件 stop 后的退休指令不再计入。上位机判据 `judge()` 同时补 `depth` 参数，
  要求 `overflow==0 或 count>=depth` 才算过。
- 验证：`scripts\run_trace_buffer_tb.ps1`（10 项）、`run_core_trace_mmio_tb.ps1`（11 项）、
  `python -m unittest python.tests.test_trace_view`（27 项）全 PASS；
  SoC 端到端场景 1 回包变成 `status=0x04`。
- 影响：仅新增的 trace 外设；`pipeline_cpu.v` 与交付位流 la85 未受影响。

### 2026-10-21 / 提交级 trace：上位机在固件发 LA_READY 期间发命令会被吞

- 最小复现：`tb/tb_core_trace_soc.v` 场景 1 结束（收到 `TRACE_DONE`）后立刻发 0xAA 命令。
- 现象：固件完全不响应后续命令，仿真白等 300 万拍才超时；日志里只多出 10 字节 `LA_READY`。
- 根因：`uart_rx` **没有接收 FIFO**。`TRACE_DONE` 出现时固件还在阻塞发 `LA_READY`，
  这期间进来的 4 个命令字节被后续字节覆盖。
- 最小修复：TB 与上位机一律"**先等 `LA_READY`，再发下一条命令**"
  （`trace_board.py` 用 `synchronize_ready()` 做同一件事）。
  这条纪律与镜像模式"必须等 `LA_ARMED` 才发字符串"是同一条。
- 验证：场景 2 从"等不到标记"变成正常回包（进而暴露出 TB 的 `GOT_MAX` 太小）。
- 影响：仅测试与上位机时序；不是 RTL 缺陷。

### 2026-10-21 / 提交级 trace：132 位记录被 4 个字静默截断

- 最小复现：读 `RD_W3`（offset 0x20）拼回一条记录，与期望的 132 位值对拍。
- 现象：`error` 位恒为 0、`mem_data` 最高 4 位永远丢失，而页面上"看着有数据"。
- 根因：132 位装不进 4 个 32 位字；第一版 `RD_W3` 写成 `{28'b0, rd_record[131:96]}`
  赋给 32 位寄存器，高 4 位被静默丢掉。
- 最小修复：增加 `RD_W4`（offset 0x30）只承载 `rd_record[131:128]`，`RD_W3` 改为 `[127:96]`；
  代价是一条记录 5 次 MMIO 读，不做有损截断。
- 验证：`tb/tb_core_trace_mmio.v` 的 T6 用整条 132 位值逐位对拍 PASS。
- 影响：仅新增的 trace 外设与其上位机。

### 2026-10-21 / 往 .ps1 里粘中文后必须补 BOM，否则脚本"语法错误"但不是语法错

- 最小复现：用编辑器（不是本仓库的 `ensure_ps1_bom.ps1`）写一个含中文注释的 `.ps1`，
  再用 `powershell.exe -File` 执行。
- 现象：报 `Missing expression after ','` / `Unexpected token ')'` /
  `TerminatorExpectedAtEndOfString` 之类，指向的行往往完全正常。
- 根因：Windows PowerShell 5.1 把**无 BOM** 的 `.ps1` 按 ANSI 解码，中文注释变成乱字节，
  其中某个字节看起来像引号或括号，解析器就在远处报错。
- 最小修复：改完任何含非 ASCII 字符的 `.ps1`，立刻跑
  `scripts\ensure_ps1_bom.ps1`（它给缺 BOM 的非 ASCII 脚本补 UTF-8 BOM）。
  本轮实际被这条咬到三次：`run_core_trace_soc_tb.ps1`、`program_board.ps1`、
  `generate_logic_analyzer_fpga_memory.ps1` / `run_final_regression.ps1`。
- 影响：只影响 `powershell.exe`（5.1）的执行；不影响 RTL、测试判据或产物内容。

### 2026-10-21 / 原生命令的 stderr 在 `$ErrorActionPreference='Stop'` 下会把脚本打停

- 最小复现：在 `$ErrorActionPreference='Stop'` 的脚本里调 `make.exe`，
  而 gcc/ld 往 **stderr** 打一条 `warning: ... has a LOAD segment with RWX permissions`。
- 现象：脚本在 gcc 那一行之后**静默中止**，后面的步骤全没跑，退出码 1；
  外部只看到 gcc 命令行 + 那条警告。奇怪的是同一个脚本单独跑能过、
  在 `run_final_regression.ps1` 里跑就停 —— 差别只在错误动作的作用域。
- 根因：PowerShell 5.1 把原生命令的 stderr 包成 ErrorRecord，在 `Stop` 下是终止错误，
  于是一条**警告**变成致命错误。
- 最小修复：`scripts/generate_logic_analyzer_fpga_memory.ps1` 在调用 `make.exe` 期间
  临时把错误动作放开，成败一律以 `$LASTEXITCODE` 判定（与 `run_final_regression.ps1`
  里既有的 `Run-Test` 做法一致）。
- 验证：修前 `generate_log-...ps1 -AutoStart 0` 退出码 1；修后退出码 0 并打印
  `LOGIC ANALYZER FPGA MEMORY GENERATED depth=1024 autostart=0 used_words=922`。
- 影响：仅构建脚本健壮性；不改 RTL、判据或产物。
