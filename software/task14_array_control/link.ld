ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 1K
    DMEM (rwx) : ORIGIN = 0x00000000, LENGTH = 1K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > IMEM

    .rodata : { *(.rodata .rodata.*) } > IMEM

    .data 0x200 :
    {
        *(.data .data.*)
    } > DMEM

    .bss (NOLOAD) :
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > DMEM
}
