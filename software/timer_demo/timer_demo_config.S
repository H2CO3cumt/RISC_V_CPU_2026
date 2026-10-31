# N1 演示程序的编译期常量。
#
# 谁来定 MTIMECMP_DELTA：
#   由 Makefile 通过 `-DMTIMECMP_DELTA=<n>` 从命令行传进来（scripts/generate_timer_demo_fpga_memory.ps1
#   决定传真实值还是仿真用小值）。这里只给一个"没人传时"的缺省值。
#
#   **不要**在 .S 里用 `.ifdef`/`.ifndef` 去判断"是不是仿真构建"：本工具链的汇编器
#   看不到 gcc `-D` 传来的宏（实测 `-DTIMER_DEMO_TEST_DELTA` 完全不起作用，
#   结果静默生成了一份 delta 仍是 12_500_000 的"仿真镜像"）。数值一律显式传参。
#
# 缺省 12_500_000：50 MHz 下正好 0.25 s，
# 于是 LED0 以 0.5 s 为整周期闪烁（亮 0.25 s / 灭 0.25 s），人眼可分辨、秒表可测。
.equ MTIMECMP_DELTA, 12500000

# `lui` 的立即数形式：lui rd, imm 会把 imm 左移 12 位。
#   0x1000_3000 >> 12 = 0x10003
#   0x1000_0000 >> 12 = 0x10000
#   0x1000_1000 >> 12 = 0x10001
# UART 的 0x1000_0000 用它省掉一条 addi（低 12 位本来就是 0）。
.equ TIMER_BASE, 0x10003
.equ UART_BASE,  0x10000
.equ GPIO_BASE,  0x10001

# 镜像自描述指针块的标志字。Testbench 靠它找到 software/timer_demo/start.S
# 里的 image_pointers，从而不必写死任何地址。
# 0x4E315444 在内存里按小端读出来是字节 'D' 'T' '1' 'N'。
.equ IMAGE_FLAG, 0x4E315444

# 诊断开关（数值，不是宏存在性）：1 = ISR 只发 1 个 UART 字节。
# 缺省 0 = 交付行为（每次中断发完整 5 字节记录）。
# 注意：只能 `.if TIMER_DEMO_MINIMAL_UART`，**不能**用它做 `.ifdef`——
# 本工具链的汇编器看不到 gcc -D 传的宏，`.ifdef` 会直接报错。
.ifndef TIMER_DEMO_MINIMAL_UART
.equ TIMER_DEMO_MINIMAL_UART, 0
.endif
