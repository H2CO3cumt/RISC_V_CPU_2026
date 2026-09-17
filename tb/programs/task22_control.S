    .section .text
    .globl _start
    .option norvc
_start:
    addi x1, x0, 1
    addi x2, x0, 1
    beq  x1, x2, taken_branch
    sw   x1, 0(x0)          # taken Branch 后的错误路径 Store
    addi x10, x0, 0x55
taken_branch:
    bne  x1, x2, bad_target # not-taken Branch
    addi x3, x0, 3
    jal  x4, jal_target
    sw   x1, 4(x0)          # JAL 错误路径 Store
jal_target:
    addi x5, x4, 1          # JAL link 的紧邻消费者
    la   x6, jalr_target
    jalr x7, 0(x6)
    sw   x1, 8(x0)          # JALR 错误路径 Store
jalr_target:
    addi x8, x7, 1
    jal  x0, done
    sw   x1, 12(x0)         # JAL 错误路径 Store
bad_target:
    sw   x1, 16(x0)
done:
    addi x9, x0, 9
