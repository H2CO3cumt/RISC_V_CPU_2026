.section .text.start
.globl _start

_start:
    addi sp, zero, 1024
    # Task 17 state golden observes x1..x31.  Initialize every register the
    # program does not otherwise define, so no golden field relies on X state.
    addi gp, zero, 3
    addi tp, zero, 4
    addi t0, zero, 5
    addi t1, zero, 6
    addi t2, zero, 7
    addi s0, zero, 8
    addi s1, zero, 9
    addi a0, zero, 10
    addi a1, zero, 11
    addi a2, zero, 12
    addi a3, zero, 13
    addi a4, zero, 14
    addi a5, zero, 15
    addi a6, zero, 16
    addi a7, zero, 17
    addi s2, zero, 18
    addi s3, zero, 19
    addi s4, zero, 20
    addi s5, zero, 21
    addi s6, zero, 22
    addi s7, zero, 23
    addi s8, zero, 24
    addi s9, zero, 25
    addi s10, zero, 26
    addi s11, zero, 27
    addi t3, zero, 28
    addi t4, zero, 29
    addi t5, zero, 30
    addi t6, zero, 31
    jal  ra, main

halt:
    jal  zero, halt
