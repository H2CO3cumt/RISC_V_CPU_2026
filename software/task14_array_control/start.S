.section .text.start
.globl _start

_start:
    addi sp, zero, 1024

    lui  t0, %hi(__bss_start)
    addi t0, t0, %lo(__bss_start)
    lui  t1, %hi(__bss_end)
    addi t1, t1, %lo(__bss_end)

clear_bss:
    bgeu t0, t1, start_main
    sw   zero, 0(t0)
    addi t0, t0, 4
    jal  zero, clear_bss

start_main:
    jal  ra, main

halt:
    jal  zero, halt
