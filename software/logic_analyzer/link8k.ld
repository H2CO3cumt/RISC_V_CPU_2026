/* tr85 演示位流专用的 8 KB 固件镜像布局（2026-10-24）。
   与 link.ld 的唯一差别是 RAM 长度：4 KB → 8 KB。
   配对约束（改一处漏一处会静默踩坏栈）：
     · 本文件 LENGTH = 8K
     · start.S 的 STACK_TOP 由 -DRAM_KB=8 给出（0x2000）
     · fpga/trace85/rtl/logic_analyzer_program_memory.v 的 DEPTH = 2048
     · fpga/trace85/rtl/mes50hp_trace_top.v 的 RAM_LAST_ADDR = 0x0000_1fff
   交付工程（la50/la85/coremark 等）继续用 link.ld 的 4 KB，逐字节不变。 */
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8K }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
    .rodata : { *(.rodata .rodata.*) } > RAM
    .data : { *(.data .data.*) } > RAM
    .bss : { *(.bss .bss.*) *(COMMON) } > RAM
}
