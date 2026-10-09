ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    DROM (r)   : ORIGIN = 0x00008000, LENGTH = 16K
    RAM  (rwx) : ORIGIN = 0x0000C000, LENGTH = 16K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > IMEM

    .rodata :
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > DROM

    .data :
    {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > DROM

    .bss (NOLOAD) :
    {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(16);
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    ASSERT(SIZEOF(.text) <= LENGTH(IMEM), "CoreMark instruction image exceeds IMEM")
    ASSERT(SIZEOF(.rodata) + SIZEOF(.data) <= LENGTH(DROM), "CoreMark constants exceed DROM")
    ASSERT(__bss_end <= __stack_top - 2048, "CoreMark RAM leaves less than 2 KiB stack")
}
