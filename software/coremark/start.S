.section .text.start
.globl _start
_start:
    lui  sp, %hi(__stack_top)
    addi sp, sp, %lo(__stack_top)

    lui  t0, %hi(__bss_start)
    addi t0, t0, %lo(__bss_start)
    lui  t1, %hi(__bss_end)
    addi t1, t1, %lo(__bss_end)
1:
    bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    jal  zero, 1b
2:
    jal  ra, main
3:
    jal  zero, 3b
