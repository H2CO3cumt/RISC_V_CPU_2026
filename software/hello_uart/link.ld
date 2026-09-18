ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > RAM

    .rodata : { *(.rodata .rodata.*) } > RAM

    .data : { *(.data .data.*) } > RAM

    .bss (NOLOAD) :
    {
        *(.bss .bss.*)
        *(COMMON)
    } > RAM
}
