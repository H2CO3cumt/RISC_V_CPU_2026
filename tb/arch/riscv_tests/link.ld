OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text.init : { *(.text.init) }
  .text : { *(.text) }

  /* Keep the test result in a known, separately observable DMEM word. */
  . = 0x00004000;
  .tohost : { *(.tohost) }
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
