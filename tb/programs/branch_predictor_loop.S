.section .text
.globl _start
_start:
    addi x1, x0, 32
    addi x2, x0, 0
loop:
    addi x2, x2, 1
    addi x1, x1, -1
    bne  x1, x0, loop
    sw   x2, 0(x0)
done:
    jal  x0, done
