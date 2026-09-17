.section .text.start
.globl _start

_start:
    jal ra, main

halt:
    jal x0, halt
