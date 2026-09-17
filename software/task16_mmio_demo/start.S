.section .text.start
.globl _start

_start:
    addi sp, zero, 1024
    jal  ra, main

halt:
    jal  zero, halt
