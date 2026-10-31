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
    # 注意：这里原本是 lw x8, 64(x0) 与 sw x7, 68(x0)（越界，制造访问错误）。
    # 引入机器模式 Trap 之后，访问错误会精确陷入并把 PC 交给 mtvec，
    # 而单周期 Reference Model 没有 Trap（ENABLE_SYSTEM=0），
    # 于是这条指令之后两条 trace 流必然分叉——不是 RTL 错，是两个模型的语义不同。
    # 访问错误 / 未对齐 / 非法指令的覆盖已经移到
    #   tb/tb_trap_pipeline.v（用例 D/E/F/K）与 tb/tb_pipeline_error_observability.v，
    # 这两个 Testbench 才是"错误与 Trap"的正确判据；本 Testbench 只保留
    # 与 Reference Model 逐条对齐的 Hazard 覆盖，因此改用合法地址。
    lw   x8, 60(x0)       # 合法地址（RAM 最后一字），紧邻 addi 检查 immediate 位段
    addi x8, x0, 8        # immediate 位段不得造成假 Load-Use Stall
    sw   x7, 56(x0)       # 合法 Store，必须产生恰好一次 side effect
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
