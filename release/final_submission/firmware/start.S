/* 栈顶与镜像容量必须是同一个数：镜像(.text/.rodata/.data/.bss) 占 RAM 区低端，
   栈从 RAM 区顶端往下长。4 KB 配置（默认，交付工程 la85/la50 用的就是它）栈顶 0x1000。

   为什么做成可覆盖的：tr85 是**附加演示位流**，它的固件要塞下"波形 + 指令流一次采集"
   这条组合命令，4 KB 已经装不下（2026-10-24 实测溢出 436 字节）。把容量做成
   `--defsym RAM_KB=N` + 配对的 link 脚本，就能只给 tr85 用 8 KB，而默认值**逐字节不变**
   —— 交付位流的固件镜像因此完全不动。
   两处必须同时改：本文件的 sp 与 link8k.ld 的 LENGTH；只改一处会静默踩坏栈。 */
#ifdef RAM_KB
#define STACK_TOP (RAM_KB << 10)
#else
#define STACK_TOP 0x1000
#endif

.section .text.start
.globl _start
_start:
    li   sp, STACK_TOP
    jal  ra, main
halt:
    jal  zero, halt
