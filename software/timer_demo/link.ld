/* N1 演示程序：代码与只读常量都放在 RAM 窗口 0x0000_0000 起的 4 KB 内。
   SoC 侧 IMEM/DMEM 是同一份 BRAM 镜像（见 fpga/timer_demo 的说明），
   因此 .rodata 的地址可以被 lw/lbu 直接读。 */
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 4K }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
    .rodata : { *(.rodata .rodata.*) } > RAM
    .data : { *(.data .data.*) } > RAM
    .bss : { *(.bss .bss.*) *(COMMON) } > RAM
}
