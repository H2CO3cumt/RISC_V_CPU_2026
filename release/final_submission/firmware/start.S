.section .text.start
.globl _start
_start:
    lui  sp, 1
    jal  ra, main
halt:
    jal  zero, halt
