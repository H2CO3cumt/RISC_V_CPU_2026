    .section .text
    .globl _start
    .option norvc
_start:
    addi x1, x0, 42
    sw   x1, 0(x0)
    lw   x2, 0(x0)
    add  x3, x2, x1
    beq  x3, x1, bad_a
    add  x4, x3, x2
    sw   x4, 4(x0)
    lw   x5, 4(x0)
    beq  x5, x4, taken_a
    sw   x1, 8(x0)
taken_a:
    jal  x6, after_jal
    sw   x1, 12(x0)
after_jal:
    addi x7, x6, 1
    lw   x8, 64(x0)       # 未映射到测试 RAM：错误响应且不写回
    addi x8, x0, 8        # immediate 位段不得造成假 Load-Use Stall
    sw   x7, 68(x0)       # 错误 Store 不得产生 side effect/Store trace
    addi x9, x0, 9
    addi x10, x0, 1
    addi x11, x0, 1
    sub  x12, x10, x11
    beq  x12, x0, done
    sw   x1, 16(x0)
bad_a:
    sw   x1, 20(x0)
done:
    addi x13, x0, 13
