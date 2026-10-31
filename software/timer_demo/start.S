# M-24 / N1：MES50HP 板级裸机"周期性定时器中断"演示程序。
#
# 这条程序要证明的东西（就是 M-24 要的实板证据）：
#   1. 中断**周期性**发生——led0 每 delta 拍翻转一次，周期由 mtimecmp 的增量决定；
#   2. ISR 真的在跑——每次中断往 UART 写 5 个字节：
#      "中断计数低 4 位" + "LED 值低 4 位" + "mtime[15:4] 的 3 位十六进制"。
#      前两位是判据（计数逐次递增、LED 位交替）；后三位是**自计时证据**：
#      mtime 是 50 MHz 硬件计数器，两次中断之间它涨了多少就是周期（单位：拍），
#      完全不依赖主机串口时钟。串口上看到的稳态序列形如
#        =101112131415161718191a1b1c1d1e1f1011...
#      其中奇数位是连续递增的中断计数，偶数位是 LED 值（ISR 每次只翻转 bit0、
#      其余位保持 0，所以必然在 0/1 之间交替——这本身就是 LED0 在按周期翻转的串口证据）。
#   3. mret 回到了被打断的位置——主循环是一条自跳转，ISR 返回后仍停在原地，
#      计数继续累加、LED 继续翻转，就说明 PC 被正确恢复，而不是"陷进去出不来"或"重启了程序"。
#
# 为什么这段代码是手写的汇编而不是 C：
#   工程固定用 `-march=rv32i -mabi=ilp32`，这条 march 字符串不含 `zicsr`，
#   汇编器因此**拒绝** csrrw/csrrs/mret 等助记符（实测报
#   `unrecognized opcode 'csrrw', extension 'zicsr' required`）。因此：
#     - 普通指令用真实助记符（可读，且能被汇编器校验）；
#     - CSR 指令只能写成 `.word <编码>`。每条编码都逐位核对，并在注释里给出反解
#       （funct3 / rs1 / csr / rd）。所有 CSR 编码与**已经逐项 PASS** 的
#       `tb/data/timer_irq.mem`（M-14 定时器端到端）逐位一致，不是新编的。
#
# 寄存器分配（全部显式初始化，避免依赖复位后的未定义值）：
#   x6  = 中断计数（每次 +1 不回绕，只把低 4 位打到串口）
#   x9  = 本次中断看到的 mtime 快照（自计时用）
#   x10 = 十六进制字符表地址（下标 0..15 = '0'..'f'，下标 16 = '='）
#   x11 = UART TXDATA 地址 0x1000_0000
#   x12 = GPIO 输出地址   0x1000_1000（LED 低 8 位）
#   x13 = LED 当前值（从 GPIO 读回再翻转，避免另外维护一份影子状态）
#   x14 = MTIMECMP_DELTA（每次中断的间隔，周期的唯一来源；由 Makefile 以 -D 显式给定）
#   x15 = 定时器基地址 0x1000_3000
#   x4,x5,x7,x28 = ISR / 初始化内的临时量
#
# 地址窗口（docs/interfaces.md §3.2，全部在 Core 外部）：
#   UART TXDATA `0x1000_0000`  GPIO 输出 `0x1000_1000`  TIMER `0x1000_3000`
#   定时器字偏移：+0x00 mtime_lo  +0x04 mtime_hi  +0x08 mtimecmp_lo  +0x0C mtimecmp_hi

.include "timer_demo_config.S"

.section .text.start
.globl _start

_start:
    # ---- 0x00 基础地址与计数器 ----
    lui   x15, TIMER_BASE       # x15 = 0x1000_3000 定时器基地址
    lui   x11, UART_BASE        # x11 = 0x1000_0000 UART TXDATA
    lui   x12, GPIO_BASE        # x12 = 0x1000_1000 GPIO 输出（LED）
    addi  x6, x0, 0             # 中断计数清零。**必须显式清零**：寄存器初值未定义，
                                # 用 x6+1 计数会一直是 X，比较/分支结果也是 X，
                                # 输出就完全没有规律。
    la    x10, char_table       # x10 = 字符表地址（'0'..'9' 之后紧跟 '='）

    # ---- 0x14 定时器与中断初始化 ----
    # 这里用 `auipc/addi`（`la`）而不是 `li` 装载：`li` 会因为数值大小展开成 1 条或 2 条，
    # 从而让后面所有标签的地址跟着变。用 `auipc` 之后 Testbench 可以从**指令自己**
    # 反解出 isr_entry 的地址（见 image_pointers 的说明），镜像布局改变也不会失效。
    la    x1, isr_entry         # mtvec = ISR 入口（本程序远小于 1 KB，直接绝对地址）
    .word 0x30509073            # csrrw x0, mtvec, x1：funct3=001 rs1=x1 csr=0x305 rd=x0
    li    x14, MTIMECMP_DELTA   # x14 = 每次中断的间隔（拍）
    addi  x4, x0, 1
    slli  x4, x4, 7             # x4 = 1<<7 = 128 = mie.MTIE（机器定时器中断使能位）
    .word 0x30422073            # csrrs x0, mie, x4：打开 MTIE
    sw    x0, 12(x15)           # **mtimecmp_hi 必须先清零**：复位值是全 1（保证复位后
                                # 不产生中断），只写低 32 位的话 mtime<mtimecmp 恒成立，
                                # 中断永远不会来。
    lw    x5, 0(x15)            # 读当前 mtime
    add   x5, x5, x14           # 第一次装载：deadline = mtime + delta
    sw    x5, 8(x15)            # 写 mtimecmp_lo
    .word 0x30046073            # csrrsi x0, mstatus, 8：打开 mstatus.MIE（全局中断使能）。
                                # 放在最后一次装载**之后**，避免中断在初始化中途插进来。

    # ---- UART 自检字符：证明"板子在上电、程序确实跑到了这里" ----
    lbu   x28, 16(x10)          # 字符表下标 16 = '='（表尾之后第一个字节）
    sw    x28, 0(x11)           # 发送 '='

    # ---- 主循环：**故意什么都不做**，只自跳转等待中断 ----
    # 本演示只观察"中断是否周期性到来"，所以主程序不需要干活。
    # ISR 返回这里之后继续自跳转（而不是重启程序或跑飞），说明 mret 恢复的 PC 是对的。
sleep_loop:
    j     sleep_loop

    # ---- 镜像自描述指针块（程序运行时不会被取到：主循环在 0x50 自跳转）----
    # Testbench 用 flag 字认出这个块，于是**不需要在 Testbench 里写死任何地址**
    # （程序里加一条指令就会整体挪位，写死必错）。
    # 注意：必须在 .align 之后的固定偏移上按顺序排 four 个字，
    # 而且 flag 字（+0x0C）本身要留 0，方便"这个块的结尾是下一个标签"这条不变量自检。
    .align 2
image_pointers:
    .word MTIMECMP_DELTA        # +0x00 本镜像实际的 delta（判断是不是仿真用小值）
    .word isr_entry             # +0x04 ISR 入口地址
    .word sleep_loop            # +0x08 主循环地址
    .word IMAGE_FLAG            # +0x0C 标志字 0x4E315444（"D T 1 N" 小端），Testbench 靠它定位本块

# ---- ISR 入口：对齐到 4 字节边界，方便在反汇编/ILA 里一眼定位 ----
# 约束（由 Testbench 运行期核对，写不成汇编期断言：汇编器不接受 `.if (label & 0xFFFFF000)`）：
#   本标签必须与上面那条装载 mtvec 的 `auipc ra, 0` **在同一个 4 KB 页内**。
#   满足时 auipc 的立即数恒为 0，Testbench 就按"boot 里恰好存在一条
#   `auipc ra,0` + `addi ra,ra,<isr_entry 页内偏移>`"来交叉核对指针块。
    .align 2
isr_entry:
    # ---- 第一件事：采样 mtime 并立刻重装 deadline ----
    # **顺序很关键**：把重装放在最前面，中断间隔才严格等于 delta。
    # 如果像最初那样先做 UART 输出再重装，一旦 UART 忙（上一笔还在发），
    # CPU 会停在 TXDATA 那条 store 上等 back-pressure，重装被推迟到"上一个字节发完"，
    # 于是实际间隔变成 delta + 一个字节的发送时间——实测 delta=20000 时间隔是 24358
    # （多出的 4358 ≈ 50 MHz/115200 的 1 个字节时间），"周期可预测"这条就名不副实了。
    # 重装之后剩下的活儿（LED + 串口）整段都落在下一个 delta 窗口里，不再影响周期。
    lw    x9, 0(x15)            # x9 = 本次中断看到的 mtime（下面要打到串口，做**自计时**证据）
    add   x5, x9, x14           # deadline = 当前 mtime + delta
    sw    x5, 8(x15)            # 写 mtimecmp_lo：**不做这一步只会中断一次**。
                                # irq_timer 是电平信号，重写 mtimecmp 之后自动落下，
                                # 不需要额外的"清中断"寄存器。

    # ---- 然后才是可观测输出 ----
    lw    x13, 0(x12)           # x13 = 上一次写到 GPIO 的 LED 值（gpio_mmio 是可读回的寄存器）
    xori  x13, x13, 1           # 翻转 bit0 → **LED0 每 delta 拍翻转一次**（固定周期闪烁）
    sw    x13, 0(x12)           # 写回 GPIO → LED 低 8 位 = x13（MES50HP 用户 LED 高电平点亮）

    addi  x6, x6, 1             # 中断计数 +1（不回绕，所以串口上能看到连续递增）
    andi  x7, x6, 15            # 只取低 4 位打印成**一位十六进制**：
                                # 每次中断固定 5 个字节进入 UART，ISR 长度恒定。
    addi  x7, x7, 48            # '0' = 48；0..9 直接可读，10..15 落在 ':'..'?' 上
    sw    x7, 0(x11)            # UART TXDATA，发送中断计数

# TIMER_DEMO_MINIMAL_UART：诊断开关。**必须是数值**（不能靠 .ifdef 判断宏是否存在：
# 本工具链的汇编器看不到 gcc -D 传来的宏，实测直接报
# "invalid identifier for .ifdef" / ".endif without .if"）。
# 为 1 时 ISR 只发 1 个字节就 mret，用来把"UART 通道本身"与"连发 5 个字节"分开：
#   只发 1 字节仍然花屏 → 问题在板级 UART 通路/参数；
#   只发 1 字节正常、发 5 字节花屏 → 问题在背靠背连发的时序。
# 交付镜像用缺省值 0（见 timer_demo_config.S），即完整 5 字节记录。
.if TIMER_DEMO_MINIMAL_UART
    .word 0x30200073            # mret
.endif

    andi  x28, x13, 15          # LED 值低 4 位
    add   x28, x10, x28         # 查字符表得到十六进制字符
    lbu   x28, 0(x28)
    sw    x28, 0(x11)           # UART TXDATA，发送 LED 值

    # ---- 自计时：把本次 mtime 的 [27:16] 三位十六进制打出来 ----
    # 为什么值得多花 3 个字节：主机侧 USB 串口的时间戳精度不可靠（实测同一段流算出的
    # 周期能在 200~1300 ms 之间跳），单靠它无法证明"板上周期到底是多少"。
    # mtime 是 50 MHz 的硬件计数器，两次中断之间它涨了多少**就是**周期（以拍为单位），
    # 不依赖任何主机时钟。
    #
    # 位段选择：取 [27:16] 而不是 [15:4]。12 位字段的模是 4096 个"步长"，
    #   - 取 [15:4]（步长 16 拍）→ 模只有 65536 拍，而 delta=12_500_000 拍，
    #     间隔会绕 190 次，差值完全无意义（这一版最初就是这么写错的）；
    #   - 取 [27:16]（步长 65536 拍）→ 模 268M 拍，远大于 delta，不会绕；
    #     量化粒度 65536 拍 / 12_500_000 拍 ≈ 0.52%，足够判"周期就是 delta"。
    srli  x5, x9, 24            # 第 1 位：mtime[27:24]
    andi  x5, x5, 15
    add   x28, x10, x5
    lbu   x28, 0(x28)
    sw    x28, 0(x11)
    srli  x5, x9, 20            # 第 2 位：mtime[23:20]
    andi  x5, x5, 15
    add   x28, x10, x5
    lbu   x28, 0(x28)
    sw    x28, 0(x11)
    srli  x5, x9, 16            # 第 3 位：mtime[19:16]
    andi  x5, x5, 15
    add   x28, x10, x5
    lbu   x28, 0(x28)
    sw    x28, 0(x11)
                                # UART 连续发送由 uart_mmio 的 back-pressure 保证：
                                # TXDATA 写在 UART 忙时会挡住互连握手，CPU 停在这一条上等，
                                # 不会丢字符，也不会覆盖正在发送的字节。
                                # 代价是 ISR 可能比 delta 还长——所以交付用的 delta=12_500_000
                                # （0.25 s）远大于 5 个字节的发送时间（约 434 µs），绰绰有余。
    .word 0x30200073            # mret：回到被打断的位置

# ---- 字符表：**必须覆盖 0..15 全部十六进制位** ----
# 表是直接按"nibble 当下标"用的（ISR 里 `add x28, x10, nibble` + `lbu`），
# 所以下标 10..15 也必须有字符：'a'..'f'。
# **这一版最初漏了它们**：表原来只有 "0123456789="（12 个字节），于是当 mtime 的某一位
# 十六进制是 a..f 时，地址会越过表尾读进程序区之外的填充字（0x0000006F = jal x0,0），
# 串口上就会打印出 'o'（0x6F）——现象很像"UART 发错字节"，其实是**表越界**。
# '='（开机自检字符）故意放在下标 16，即表尾之后第一个字节，由 boot 用偏移 16 取。
#
# 用 .byte 逐字节写：这样"第几个下标是哪个字符"一眼可数，不会像 .word 字面量那样
# 要把 4 个字符按小端手工拼成一个 32 位数（那种写法正是漏掉 a..f 的原因：加字符时
# 只想着往末尾塞，忘了下标必须连续）。
    .align 2
char_table:
    .byte '0', '1', '2', '3', '4', '5', '6', '7'
    .byte '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    .byte '=', 0

halt:
    j     halt
