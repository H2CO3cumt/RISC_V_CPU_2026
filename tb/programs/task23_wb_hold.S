.section .text
.globl _start
_start:
    addi sp, zero, 64
    addi t0, zero, 17
    addi ra, zero, 28
    addi sp, sp, -16
    sw   t0, 0(sp)
    sw   ra, 4(sp)
    lw   a0, 0(sp)
    lw   a1, 4(sp)
done:
    jal  zero, done
