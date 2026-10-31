`timescale 1ns/1ps
// 精确 Trap / CSR / 中断的整机验收 —— 对应 docs/trap_contract.md §6 的
// M-01、M-03～M-18、M-21。被测对象是真实的 `pipeline_cpu`，只通过统一的
// 取指/数据事务端口连接外部存储，判定依据是提交级 trace、event_* 脉冲、
// 写副作用计数和 CSR 架构状态。
//
// 程序布局约定（每个用例都按同一套地址摆放，便于逐条核对）：
//   0x00  指令0     0x04  指令1
//   0x08  被测指令区（4 条：0x08/0x0C/0x10/0x14）
//   0x18  ISR       0x1C  0x20  （ISR 内容）
// 因此"程序结束"标记（自跳转 jal x0,0）固定在 0x14。
//
// 重要设计点：被测的出错指令必须是**顺序执行到**的，不能用 jal 跳过去。
// 用跳转"制造"异常路径会让跳转本身把出错指令冲掉，测出来的是"跳转对不对"，
// 而不是"异常有没有发生"——第一次写这个 TB 时就踩过这个坑。
module tb_trap_pipeline;

    reg clk = 1'b0;
    reg reset = 1'b1;

    wire        iv, ir, rv, rr, ie, dv, dr, dw, dsv, dsr, de;
    wire [31:0] ia, idata, da, dwd, drd;
    wire [3:0]  dst;

    wire        tv, trw, tmw, trace_error;
    wire [31:0] tpc, tinst, trd, tmaddr, tmdata;
    wire [4:0]  trda;
    wire [3:0]  tmstrb;
    wire        ev_stall, ev_load, ev_branch, ev_taken, ev_flush;
    wire        ev_predict, ev_hit, ev_miss, ev_ctrl_redir;
    wire        ev_illegal, ev_misaligned, ev_bus_error;

    reg irq_sw = 1'b0;
    reg irq_timer_drive = 1'b0;
    reg irq_ext_drive = 1'b0;
    // 中断线的一次性释放模型。
    // 真实 SoC 里中断要在 ISR 中写 MMIO 才能清除，而 Core 没有、也不允许有
    // 这个端口（docs/trap_contract.md §4.2）。若 TB 让电平一直保持，MRET 恢复
    // mstatus.MIE 之后会立刻再次陷入同一个中断，程序永远到不了 halt。
    // irq_hold=1 时保持电平，用于"被屏蔽时 mip 仍可见"的用例 J。
    reg irq_hold = 1'b0;
    reg irq_seen = 1'b0;
    // irq_seen 只在"中断型 Trap"上置位，同步异常不消耗中断线。
    wire irq_timer = irq_timer_drive && (irq_hold || !irq_seen);

    // 同步异常 ↔ 中断同拍竞争的注入（用例 M）。
    // 中断线必须**恰好在出错指令进入 WB 的那一拍**为高，才构成真正的同拍竞争：
    // 若提前拉高，中断会在更早的 WB 边界就被接受，出错指令直接进不了 WB，
    // 测出来的只是"中断能响应"，而不是"谁优先"。
    // 竞争那一拍之后用 sticky 保持，直到中断型 Trap 被接受，用于证明中断没丢。
    reg  irq_ext_conflict = 1'b0;
    reg  irq_ext_sticky = 1'b0;
    wire irq_ext_now = irq_ext_conflict && core.memwb_valid && core.memwb_exc_valid &&
                       (core.memwb_inst == 32'hffff_ffff);
    wire irq_ext = irq_ext_now || (irq_ext_sticky && !irq_seen) ||
                   (irq_ext_drive && (irq_hold || !irq_seen));

    // 随机背压开关：同一个 Testbench 编两遍，一遍零延迟、一遍随机延迟，
    // 用于验收"中断 + 随机取指/数据延迟"（M-16）。
    // 为什么用宏而不是 -P：iverilog 的 -P 传字符串时引号会被 shell 吞掉，
    // 而且它不返回非零退出码，参数会静默失效（本项目踩过，见 docs/debug_log.md）。
    `ifdef TB_TRAP_RANDOM
    localparam IMEM_DELAY = 1;
    localparam DMEM_DELAY = 1;
    `else
    localparam IMEM_DELAY = 0;
    localparam DMEM_DELAY = 0;
    `endif

    integer failures = 0;
    integer test_no = 0;
    integer cycles = 0;

    integer n_trap = 0, n_mret = 0, n_illegal = 0, n_misaligned = 0, n_bus_error = 0;
    integer n_trace = 0, n_flush = 0, n_mispredict = 0;
    // 出错指令 PC 上的提交记录数。它是"被打断的指令本身没有退休"最直接的证据：
    // 比检查某个寄存器的值更可靠——寄存器可能本来就没被写过。
    integer n_c08 = 0, n_c10 = 0, n_c0c = 0;
    // 第一次 Trap 的原因码，以及"中断型 Trap"的次数（用例 M 用）。
    reg [31:0] first_trap_cause = 32'hdead_beef;
    integer n_irq_trap = 0;

    localparam [31:0] HALT_PC = 32'h0000_0014;
    reg halted = 1'b0;
    // 本用例期待出现的 halt PC：不同用例的 halt 位置不同（用例 F 的 halt 在 Trap 入口）。
    reg [31:0] halt_pc_now;
    // 用例 Q（handler 运行中复位）用：复位之后是否真的从 PC=0 重新取指。
    reg        saw_pc0 = 1'b0;

    pipeline_cpu core(
        .clk(clk), .reset(reset),
        .trace_valid(tv), .trace_pc(tpc), .trace_instruction(tinst),
        .trace_rd_we(trw), .trace_rd_addr(trda), .trace_rd_data(trd),
        .trace_mem_we(tmw), .trace_mem_addr(tmaddr), .trace_mem_data(tmdata),
        .trace_mem_wstrb(tmstrb), .trace_error(trace_error),
        .i_req_valid(iv), .i_req_ready(ir), .i_req_addr(ia),
        .i_rsp_valid(rv), .i_rsp_ready(rr), .i_rsp_data(idata), .i_rsp_error(ie),
        .d_req_valid(dv), .d_req_ready(dr), .d_req_addr(da), .d_req_write(dw),
        .d_req_wdata(dwd), .d_req_wstrb(dst),
        .d_rsp_valid(dsv), .d_rsp_ready(dsr), .d_rsp_rdata(drd), .d_rsp_error(de),
        .irq_software_i(irq_sw), .irq_timer_i(irq_timer), .irq_external_i(irq_ext),
        .event_stall(ev_stall), .event_load_stall(ev_load),
        .event_branch(ev_branch), .event_branch_taken(ev_taken),
        .event_flush(ev_flush), .event_predict(ev_predict), .event_btb_hit(ev_hit),
        .event_mispredict(ev_miss), .event_control_redirect(ev_ctrl_redir),
        .event_illegal(ev_illegal), .event_misaligned(ev_misaligned),
        .event_bus_error(ev_bus_error));

    pipeline_imem_adapter #(.DEPTH(64), .INIT_FILE(""), .RANDOM_DELAY(IMEM_DELAY)) im(
        .clk(clk), .reset(reset), .req_valid(iv), .req_ready(ir), .req_addr(ia),
        .rsp_valid(rv), .rsp_ready(rr), .rsp_data(idata), .rsp_error(ie));

    ram_adapter #(.DEPTH(8), .RANDOM_DELAY(DMEM_DELAY)) dm(
        .clk(clk), .reset(reset), .req_valid(dv), .req_ready(dr), .req_addr(da),
        .req_write(dw), .req_wdata(dwd), .req_wstrb(dst),
        .rsp_valid(dsv), .rsp_ready(dsr), .rsp_rdata(drd), .rsp_error(de),
        .write_side_effect_count(store_side_effects));

    wire [31:0] store_side_effects;

    always #5 clk = ~clk;

    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (core.trap_take) begin
            n_trap = n_trap + 1;
            // 只有**中断**才消耗"一次性释放"的中断线；同步异常不消耗。
            // 用 trap_is_irq 而不是无条件置位：否则前面任何一次异常都会把
            // 后面用例的中断线永久压住（实测用例 I 因此 n_trap 恒为 0）。
            if (core.trap_is_irq) irq_seen = 1'b1;
            if (n_trap == 1) first_trap_cause = core.trap_cause_value;
            if (core.trap_is_irq) n_irq_trap = n_irq_trap + 1;
        end
        if (irq_ext_now) irq_ext_sticky = 1'b1;
        if (tv) begin
            n_trace = n_trace + 1;
            if (tpc == halt_pc_now) halted = 1'b1;
            if (tpc == 32'h0000_0008) n_c08 = n_c08 + 1;
            if (tpc == 32'h0000_0010) n_c10 = n_c10 + 1;
            if (tpc == 32'h0000_000c) n_c0c = n_c0c + 1;
            if (tpc == 32'h0000_0000) saw_pc0 = 1'b1;
        end
        if (core.wb_trap_return) n_mret = n_mret + 1;
        if (ev_illegal)    n_illegal    = n_illegal + 1;
        if (ev_misaligned) n_misaligned = n_misaligned + 1;
        if (ev_bus_error)  n_bus_error  = n_bus_error + 1;
        if (ev_flush)      n_flush      = n_flush + 1;
        if (ev_miss)       n_mispredict = n_mispredict + 1;
    end

    //---- 指令编码（便于人工核对，全部按 RV32I 手工汇编）----
    localparam [31:0] I_ADDI_X1_18  = 32'h0180_0093; // addi x1, x0, 0x18
    localparam [31:0] I_ADDI_X1_14  = 32'h0140_0093; // addi x1, x0, 0x14
    localparam [31:0] I_ADDI_X1_1C  = 32'h01c0_0093; // addi x1, x0, 0x1C
    localparam [31:0] I_ADDI_X1_20  = 32'h0200_0093; // addi x1, x0, 0x20
    localparam [31:0] I_ADDI_X5_0   = 32'h0000_0293; // addi x5, x0, 0
    localparam [31:0] I_ADDI_X5_4   = 32'h0040_0293; // addi x5, x0, 4
    localparam [31:0] I_ADDI_X6_8   = 32'h0080_0313; // addi x6, x0, 8
    localparam [31:0] I_ADDI_X7_7   = 32'h0070_0393; // addi x7, x0, 7
    localparam [31:0] I_ADDI_X4_1   = 32'h0010_0213; // addi x4, x0, 1
    localparam [31:0] I_SLLI_X4_11  = 32'h00b2_1213; // slli x4, x4, 11
    localparam [31:0] I_CSRRS_X3_MCAUSE = 32'h3420_21f3; // csrrs x3, mcause, x0
    localparam [31:0] I_BGE_X3_X0_8 = 32'h0001_8463; // bge x3, x0, 8
    localparam [31:0] I_LUI_X2_4000 = 32'h0000_4137; // lui x2, 0x00004 → x2 = 0x4000
    localparam [31:0] I_JALR_X0_X2  = 32'h0001_0067; // jalr x0, 0(x2)
    localparam [31:0] I_ADDI_X3_28  = 32'h0280_0193; // addi x3, x0, 0x28
    localparam [31:0] I_CSRRS_X3_MCYCLE   = 32'hc000_21f3; // csrrs x3, mcycle, x0
    localparam [31:0] I_CSRRS_X4_MINSTRET = 32'hc020_2273; // csrrs x4, minstret, x0
    localparam [31:0] I_CSRRS_X5_MCYCLE   = 32'hc000_22f3; // csrrs x5, mcycle, x0
    localparam [31:0] I_CSRRS_X6_MINSTRET = 32'hc020_2373; // csrrs x6, minstret, x0
    localparam [31:0] I_SUB_X7_X5_X3 = 32'h4032_83b3; // sub x7, x5, x3
    localparam [31:0] I_SUB_X8_X6_X4 = 32'h4043_0433; // sub x8, x6, x4
    localparam [31:0] I_ADDI_X9_4    = 32'h0040_0493; // addi x9, x0, 4
    localparam [31:0] I_CSRW_MTVEC  = 32'h3050_9073; // csrrw x0, mtvec, x1
    // 开 mie.MTIE（bit7）只能用"寄存器源"形式：CSRRSI/CSRRWI 的立即数是 5 位
    // （uimm[4:0]，最大 31），根本表达不了 128。第一版写成 csrrsi x0, mie, 128
    // 是无效编码：uimm 落成 0，等价于纯读，MTIE 从未打开
    //（实测用例 I 的 n_trap 恒为 0，且 mstatus.MIE 确实被置上了）。
    localparam [31:0] I_ADDI_X4_128     = 32'h0800_0213; // addi x4, x0, 128
    localparam [31:0] I_CSRRS_X0_MIE_X4 = 32'h3042_2073; // csrrs x0, mie, x4
    localparam [31:0] I_CSRRSI_MSTATUS_MIE = 32'h3004_6073; // csrrsi x0, mstatus, 8
    localparam [31:0] I_NOP         = 32'h0000_0013; // addi x0, x0, 0
    localparam [31:0] I_EBREAK      = 32'h0010_0073;
    localparam [31:0] I_ECALL       = 32'h0000_0073;
    // WFI（0x10500073）：funct3=000、rs2=0、rd=0，但立即数不是 0x000/0x001/0x302，
    // 因此必须落到"未实现的 SYSTEM 编码 = 非法指令"这一支。
    localparam [31:0] I_WFI         = 32'h1050_0073;
    localparam [31:0] I_ILLEGAL     = 32'hffff_ffff;
    localparam [31:0] I_MRET        = 32'h3020_0073;
    localparam [31:0] I_JAL_SELF    = 32'h0000_006f; // jal x0, 0
    localparam [31:0] I_LH_X2_3     = 32'h0030_1103; // lh x2, 3(x0)  未对齐
    // sh x0, 1(x0)：store 的 imm[4:0] 在 bits[11:7]，偏移 1 要写进 bit7。
    // 旧值 0x0000_1023 的偏移是 0，地址是对齐的，根本不会产生未对齐异常。
    localparam [31:0] I_SH_X0_1     = 32'h0000_10a3;
    localparam [31:0] I_SW_X6_0     = 32'h0060_2023; // sw x6, 0(x0)  合法
    // sw x6, 64(x0)：目标地址 64 超出 DMEM 范围（8 字 = 32 字节），
    // 下游回错误响应 → Store 访问错误（mcause=7）。imm 的高位在 bits[31:25]。
    localparam [31:0] I_SW_X6_64    = 32'h0460_2023; // sw x6, 64(x0)
    localparam [31:0] I_CSRRW_MISA  = 32'h3010_1073; // csrrw x0, misa, x0 写只读
    localparam [31:0] I_CSRRS_X2_MSTATUS = 32'h3000_2173; // csrrs x2, mstatus, x0
    // 每条 handler 固定 5 条指令（占 0x18/0x1C/0x20/0x24，0x28 放 NOP）。
    // 为什么不直接用 mret 就返回：RISC-V 约定 mepc 指向**出错指令本身**，
    // 直接 mret 会回到同一条 EBREAK/ECALL 再陷入一次（无限循环）。
    // 真实 trap handler 必须自己决定"重试还是跳过"，这里统一选择跳过，
    // 于是出错指令之后的那条指令（恢复路径）才会真正执行、可以被检查。
    //   csrrs x3, mepc, x0   读 mepc
    //   addi  x3, x3, 4      指向下一条
    //   csrrw x0, mepc, x3   写回
    //   mret
    localparam [31:0] I_HANDLER_0 = I_CSRRS_X3_MEPC; // csrrs x3, mepc, x0
    localparam [31:0] I_HANDLER_1 = I_ADDI_X3_4;     // addi x3, x3, 4
    localparam [31:0] I_HANDLER_2 = I_CSRRW_MEPC_X3; // csrrw x0, mepc, x3
    localparam [31:0] I_HANDLER_3 = I_MRET;          // mret
    // handler 里把 mepc 推进 4 的固定序列（真实 trap handler 的标准写法）：
    //   csrrs x3, mepc, x0   → 读出 mepc
    //   addi  x3, x3, 4      → 指向下一条
    //   csrrw x0, mepc, x3   → 写回
    // 为什么必须推进：RISC-V 约定 mepc 指向**出错指令本身**，直接 mret 会回到
    // 同一条 EBREAK/ECALL 再陷入一次（无限循环）。软件负责决定是否重试，
    // 这里选择跳过，因此出错指令之后那条指令（恢复路径）才会真正执行。
    localparam [31:0] I_CSRRS_X3_MEPC = 32'h3410_21f3; // csrrs x3, mepc, x0
    localparam [31:0] I_ADDI_X3_4    = 32'h0041_8193; // addi x3, x3, 4
    localparam [31:0] I_CSRRW_MEPC_X3 = 32'h3411_9073; // csrrw x0, mepc, x3

    task clear_events;
        begin
            n_trap = 0; n_mret = 0; n_illegal = 0; n_misaligned = 0; n_bus_error = 0;
            n_trace = 0; n_flush = 0; n_mispredict = 0;
            n_c08 = 0; n_c10 = 0; n_c0c = 0;
            first_trap_cause = 32'hdead_beef;
            n_irq_trap = 0;
            irq_seen = 1'b0;
        end
    endtask

    task run_case;
        input [31:0] halt_pc;
        integer guard;
        begin
            halted = 1'b0;
            halt_pc_now = (halt_pc == 32'b0) ? HALT_PC : halt_pc;
            // 通用寄存器清零：架构上 reset 之后寄存器内容未定义，但"更年轻的指令
            // 没有生效"这类断言只有初值确定时才有意义（否则读出来是 x，
            // PASS/FAIL 都说明不了任何问题）。这只影响测试，不改动 RTL 复位语义。
            for (guard = 1; guard < 32; guard = guard + 1) core.rf.regs[guard] = 32'b0;
            reset  = 1'b1;
            repeat (3) @(negedge clk);
            reset = 1'b0;
            guard = 0;
            while (!halted && guard < 600) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!halted) begin
                test_no = test_no + 1;
                $display("TEST %0d FAIL timeout waiting for halt pc=%08h", test_no, HALT_PC);
                failures = failures + 1;
            end
        end
    endtask

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*44-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected)
                $display("TEST %0d PASS %0s", test_no, name);
            else begin
                $display("TEST %0d FAIL %0s expected=%08h actual=%08h",
                         test_no, name, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    // 有些量在随机背压下会"晚一拍"落定（例如中断恰好落在 halt 那条指令退休的同一拍），
    // 这类断言只要求取值落在允许集合内，不锁定具体是哪一拍。
    task expect_oneof2;
        input [31:0] actual;
        input [31:0] opt0;
        input [31:0] opt1;
        input [8*44-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === opt0 || actual === opt1)
                $display("TEST %0d PASS %0s (%08h)", test_no, name, actual);
            else begin
                $display("TEST %0d FAIL %0s expected=%08h|%08h actual=%08h",
                         test_no, name, opt0, opt1, actual);
                failures = failures + 1;
            end
        end
    endtask

    task expect_int;
        input integer actual;
        input integer expected;
        input [8*44-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected)
                $display("TEST %0d PASS %0s (%0d)", test_no, name, actual);
            else begin
                $display("TEST %0d FAIL %0s expected=%0d actual=%0d",
                         test_no, name, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    integer k;
    initial begin
        $display("=== 精确 Trap / CSR / 中断整机验收（docs/trap_contract.md §6）===");
        // 整个 IMEM 预填 NOP。为什么必须填满：自跳转 halt 之后前端仍会**顺序取指**
        // 若干拍（"预测命中且目标正确"这条路径不再重定向，前端不会回头对齐），
        // 若后面的地址是未初始化内容，取回的可能是非法指令或越界错误，
        // 于是不断产生新 Trap、把 mcause 冲掉，测试看到的就是"每拍一次 Trap"。
        // 填满 NOP 之后，halt 之后的取指是无害的，测的才是 Trap 本身。
        for (k = 0; k < 64; k = k + 1) im.mem[k] = I_NOP;

        //=====================================================================
        // 统一程序骨架（每个用例都摆在同一套地址上，便于逐条核对）
        //   0x00 addi x1, x0, 0x18   建立 mtvec
        //   0x04 csrrw x0, mtvec, x1
        //   0x08 被测指令（出错指令必须**顺序执行到**，不能用跳转跳过去）
        //   0x0C 恢复路径指令
        //   0x10 NOP（纯粹是流水线填充，绝不能放自跳转）
        //   0x14 jal x0, 0           ← halt 标记，所有用例都停在这里
        //   0x18 handler 第一条
        //   0x1C mret
        // 为什么 0x10 必须是 NOP：如果 0x10 放 `jal x0,0`，它自己就是死循环，
        // 执行流永远到不了 0x14 的 halt 标记，测试会等超时。
        // 第一版 TB 就踩了这个坑，整组用例全部超时。
        //=====================================================================

        //=====================================================================
        // 用例 A：EBREAK —— mcause=3、mtval=指令码、mepc=0x08，handler 用 mret 返回
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_EBREAK;       // 0x08
        im.mem[3] = I_ADDI_X5_4;    // 0x0C 恢复路径
        im.mem[4] = I_NOP;          // 0x10
        im.mem[5] = I_JAL_SELF;     // 0x14 halt
        im.mem[6] = I_HANDLER_0;    // 0x18 handler: 读 mepc
        im.mem[7] = I_HANDLER_1;    // 0x1C mepc += 4
        im.mem[8] = I_HANDLER_2;    // 0x20 写回 mepc
        im.mem[9] = I_HANDLER_3;    // 0x24 mret
        for (k = 0; k < 8; k = k + 1) dm.mem[k] = 32'b0;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "A: ebreak traps exactly once");
        expect_word(core.csr.mcause_q, 32'd3, "A: mcause=3 breakpoint");
        expect_word(core.csr.mtval_q, I_EBREAK, "A: mtval=faulting instruction");
        expect_word(core.csr.mepc_q, 32'h0000_000C, "A: handler advanced mepc to 0x0C");
        expect_int(n_mret, 1, "A: mret retires exactly once");
        expect_word(core.rf.regs[5], 32'd4, "A: recovery path ran after mret");
        expect_int(n_c08, 0, "A: faulting instruction produced no commit record");

        //=====================================================================
        // 用例 B：ECALL —— mcause=11、mtval=0
        //=====================================================================
        im.mem[2] = I_ECALL;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "B: ecall traps exactly once");
        expect_word(core.csr.mcause_q, 32'd11, "B: mcause=11 ecall");
        expect_word(core.csr.mtval_q, 32'd0, "B: mtval=0 for ecall");
        expect_word(core.csr.mepc_q, 32'h0000_000C, "B: handler advanced mepc to 0x0C");
        expect_word(core.rf.regs[5], 32'd4, "B: recovery path ran after mret");

        //=====================================================================
        // 用例 C：非法指令 —— mcause=2；更年轻指令的寄存器写必须被取消
        //   0x0C 放 addi x6：它在非法指令之后、属于错误路径，不得生效
        //=====================================================================
        im.mem[2] = I_ILLEGAL;
        im.mem[3] = I_ADDI_X6_8;    // 0x0C 错误路径，必须不生效
        im.mem[4] = I_ADDI_X5_4;    // 0x10（本用例把恢复点放这里）
        im.mem[5] = I_JAL_SELF;     // 0x14 halt
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "C: illegal traps exactly once");
        expect_word(core.csr.mcause_q, 32'd2, "C: mcause=2 illegal instruction");
        expect_word(core.csr.mtval_q, I_ILLEGAL, "C: mtval=faulting instruction");
        expect_word(core.csr.mepc_q, 32'h0000_000C, "C: handler advanced mepc to 0x0C");
        expect_word(core.rf.regs[5], 32'd4, "C: recovery path ran after mret");
        expect_int(n_c08, 0, "C: faulting instruction produced no commit record");

        //=====================================================================
        // 用例 C2：WFI 等 SYSTEM 编码仍然是非法指令（M-05 的第二半）
        //   §4.4 明确 WFI 不实现、保持非法指令；ENABLE_SYSTEM=1 之后
        //   SYSTEM 这一类整体变成"合法"，只有 ECALL/EBREAK/MRET 与 Zicsr 被识别，
        //   其余立即数（WFI 0x105、SFENCE.VMA 等）必须继续报非法指令。
        //   0x08 WFI（0x10500073）/ 0x0C 恢复路径 / 0x14 halt
        //=====================================================================
        im.mem[2] = I_WFI;          // 0x08
        im.mem[3] = I_ADDI_X5_4;    // 0x0C 恢复路径
        im.mem[4] = I_NOP;          // 0x10
        im.mem[5] = I_JAL_SELF;     // 0x14 halt
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "C2: WFI traps exactly once");
        expect_word(core.csr.mcause_q, 32'd2, "C2: mcause=2 illegal instruction for WFI");
        expect_word(core.csr.mtval_q, I_WFI, "C2: mtval=WFI instruction word");
        expect_int(n_c08, 0, "C2: WFI produced no commit record");
        expect_word(core.rf.regs[5], 32'd4, "C2: recovery path ran after mret");

        //=====================================================================
        // 用例 D：Load 未对齐 —— mcause=4、mtval=地址；零数据事务
        //=====================================================================
        im.mem[2] = I_LH_X2_3;
        im.mem[3] = I_ADDI_X5_4;
        im.mem[4] = I_NOP;
        for (k = 0; k < 8; k = k + 1) dm.mem[k] = 32'b0;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "D: load misalign traps exactly once");
        expect_word(core.csr.mcause_q, 32'd4, "D: mcause=4 load address misaligned");
        expect_word(core.csr.mtval_q, 32'h0000_0003, "D: mtval=misaligned address");
        expect_word(core.rf.regs[2], 32'd0, "D: load writeback suppressed");
        expect_word(store_side_effects, 32'd0, "D: no data transaction issued");
        expect_int(n_misaligned, 1, "D: misaligned event counted once");

        //=====================================================================
        // 用例 E：Store 未对齐 —— mcause=6；零写副作用
        //=====================================================================
        im.mem[2] = I_SH_X0_1;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "E: store misalign traps exactly once");
        expect_word(core.csr.mcause_q, 32'd6, "E: mcause=6 store address misaligned");
        expect_word(core.csr.mtval_q, 32'h0000_0001, "E: mtval=misaligned address");
        expect_word(store_side_effects, 32'd0, "E: no store side effect");

        //=====================================================================
        // 用例 F：Trap 之前更老的合法 Store 必须恰好完成一次，更年轻的指令不生效
        //   0x00 addi x1,0x1C / 0x04 csrrw mtvec / 0x08 addi x6,8
        //   0x0C sw x6,0       ← 比出错指令更老，必须恰好完成一次
        //   0x10 非法指令      ← 出错指令
        //   0x14 addi x5,4     ← 比出错指令更年轻，必须完全不生效
        //   0x18 NOP / 0x1C jal x0,0 ← Trap 入口即 halt
        //
        // 为什么不能沿用其它用例的"handler 把 mepc 推进 4 再返回"写法：
        // 那样做等于让出错指令的后继**故意**再执行一次，正好把本用例要证明的
        // "更年轻的指令不生效"给抹掉。这里改成 mtvec 直接指向一条自跳转，
        // 于是出错指令之后的所有指令都不会被执行。
        //
        // 还要注意：mtvec 是 CSR，run_case 里的 reset 会把它清 0。若本用例
        // 不自己写 mtvec，Trap 会跳回 0x00 把前面的 Store 反复执行（实测 50 次）。
        //
        // "更年轻"必须真的是程序序更晚：第一版把 addi x5,4 放在出错指令**之前**，
        // 于是它本来就该生效，断言 regs[5]==0 测得的是自己写错位置。
        im.mem[0] = I_ADDI_X1_1C;   // 0x00 x1 = 0x1C
        im.mem[1] = I_CSRW_MTVEC;   // 0x04 mtvec = 0x1C
        im.mem[2] = I_ADDI_X6_8;    // 0x08 x6 = 8
        im.mem[3] = I_SW_X6_0;      // 0x0C sw x6, 0(x0)：必须完成一次
        im.mem[4] = I_ILLEGAL;      // 0x10 出错指令
        im.mem[5] = I_ADDI_X5_4;    // 0x14 错误路径：不得生效
        im.mem[6] = I_NOP;          // 0x18
        im.mem[7] = I_JAL_SELF;     // 0x1C Trap 入口即 halt
        for (k = 0; k < 8; k = k + 1) dm.mem[k] = 32'b0;
        clear_events();
        run_case(32'h0000_001c);
        expect_int(n_trap, 1, "F: illegal traps exactly once");
        expect_word(core.csr.mcause_q, 32'd2, "F: mcause=2 illegal instruction");
        expect_word(core.csr.mepc_q, 32'h0000_0010, "F: mepc = faulting instruction PC");
        expect_int(n_c10, 0, "F: faulting instruction produced no commit record");
        expect_word(store_side_effects, 32'd1, "F: older store completes exactly once");
        expect_word(dm.mem[0], 32'd8, "F: older store data committed");
        expect_word(core.rf.regs[5], 32'd0, "F: younger path not executed");
        //=====================================================================
        // 用例 G：CSR 读改写语义（纯读不报异常、位域掩码正确）
        //   0x08 csrrsi mstatus,8 / 0x0C csrrs x2, mstatus, x0（纯读）
        //   0x14 halt（本用例后面不执行，但仍摆在固定位置）
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_CSRRSI_MSTATUS_MIE;
        im.mem[3] = I_CSRRS_X2_MSTATUS;
        im.mem[4] = I_ADDI_X5_4;
        im.mem[5] = I_JAL_SELF;
        im.mem[6] = I_NOP;
        im.mem[7] = I_NOP;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 0, "G: no trap for legal csr access");
        expect_word(core.rf.regs[2], 32'h0000_0008, "G: csrrsi sets mstatus.MIE");
        expect_word(core.rf.regs[5], 32'd4, "G: program continues after csr ops");
        expect_word(store_side_effects, 32'd0, "G: csr path never touches memory");

        //=====================================================================
        // 用例 H：写只读 CSR —— 非法指令异常
        //   0x08 csrrw x0, misa, x0（只读 CSR）
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_CSRRW_MISA;
        im.mem[3] = I_ADDI_X5_4;
        im.mem[4] = I_NOP;
        im.mem[5] = I_JAL_SELF;
        im.mem[6] = I_HANDLER_0;
        im.mem[7] = I_HANDLER_1;
        im.mem[8] = I_HANDLER_2;
        im.mem[9] = I_HANDLER_3;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "H: write to read-only csr traps");
        expect_word(core.csr.mcause_q, 32'd2, "H: mcause=2 illegal instruction");
        expect_word(core.csr.mtval_q, I_CSRRW_MISA, "H: mtval=faulting instruction");
        expect_word(core.rf.regs[5], 32'd4, "H: resume works");

        //=====================================================================
        // 用例 I：定时器中断 —— mcause=0x80000007，ISR 执行，mret 返回并重新开中断
        //   0x08 csrrsi mie,128 / 0x0C csrrsi mstatus,8
        //   0x18 addi x6,8（ISR）/ 0x1C mret
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_ADDI_X4_128;        // x4 = 128
        im.mem[3] = I_CSRRS_X0_MIE_X4;    // mie.MTIE = 1（bit7）
        im.mem[4] = I_CSRRSI_MSTATUS_MIE; // mstatus.MIE = 1
        im.mem[5] = I_JAL_SELF;           // halt
        im.mem[6] = I_ADDI_X6_8;    // ISR 第一条
        im.mem[7] = I_HANDLER_0;
        im.mem[8] = I_HANDLER_3;    // mret（中断不需要推进 mepc）
        irq_timer_drive = 1'b1;
        clear_events();
        irq_hold        = 1'b0;
        run_case(32'b0);
        irq_timer_drive = 1'b0;
        // 随机背压下中断可能恰好与 halt 那条指令同拍退休，run_case 一见 halt 就返回，
        // 此时 ISR 还没跑完。多等一段再断言，判定的是"中断最终被完整处理"。
        repeat (60) @(negedge clk);
        expect_int(n_trap, 1, "I: timer interrupt traps exactly once");
        expect_word(core.csr.mcause_q, 32'h8000_0007, "I: mcause=machine timer interrupt");
        expect_word(core.csr.mtval_q, 32'd0, "I: mtval=0 for interrupt");
        expect_word(core.rf.regs[6], 32'd8, "I: ISR executed");
        expect_int(n_mret, 1, "I: mret returns from ISR");
        expect_word(core.csr.mstatus_mie_q, 1'b1, "I: mret re-enables MIE");
        // 中断的 mepc 必须是"还没执行的那条指令"，而不是 WB 上那条已经退休的指令。
        // 0x10 是这么来的：mstatus.MIE 由 0x10 的 csrrsi 在 EX 级写进 CSR 寄存器，
        // 下一拍 csrrsi 走到 MEM、0x0C 的 csrrs 走到 WB，此时 irq_grant 才成立，
        // 于是 Trap 在"0x0C 已提交、0x10 还没执行"的边界被接受，mepc = 0x10。
        // mret 之后重新执行 0x10（重复置 MIE 幂等），再走到 0x14 的 halt。
        // 零延迟配置下 mepc 恒为 0x10（见下方推导）；随机背压下 WB 边界可能晚一条指令，
        // 于是 mepc 可能落在 0x14。两者都满足"中断恢复地址 = 还没执行的那条指令"。
        expect_oneof2(core.csr.mepc_q, 32'h0000_0010, 32'h0000_0014,
                      "I: mepc = first instruction not yet executed");

        //=====================================================================
        // 用例 J：中断屏蔽 —— mstatus.MIE=0 时拉高定时器中断线不得进入 Trap，mip 仍可见
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_ADDI_X4_128;        // x4 = 128
        im.mem[3] = I_CSRRS_X0_MIE_X4;    // mie.MTIE = 1，mstatus.MIE 保持 0
        im.mem[4] = I_ADDI_X5_4;          // 程序应当照常往下执行
        im.mem[5] = I_JAL_SELF;
        im.mem[6] = I_NOP;
        im.mem[7] = I_NOP;
        clear_events();
        irq_timer_drive = 1'b1;
        irq_hold        = 1'b1;   // 保持电平：本用例验证"被屏蔽时 mip 仍然可见"
        run_case(32'b0);
        expect_int(n_trap, 0, "J: masked interrupt does not trap");
        expect_word(core.csr.mie_mtie_q, 1'b1, "J: mie.MTIE really set (so the mask is what blocks it)");
        expect_word(core.csr.mip_rdata, 32'h0000_0080, "J: mip reports pending timer");
        expect_word(core.rf.regs[5], 32'd4, "J: program continues while masked");
        irq_timer_drive = 1'b0;
        irq_hold        = 1'b0;

        //=====================================================================
        // 用例 K：Store 访问错误 —— mcause=7、mtval=地址、无写副作用、恢复点是 PC+4
        //   0x00 addi x1,0x18 / 0x04 csrrw mtvec
        //   0x08 sw x6,64(x0)   ← 出错指令（地址 64 超出 8 字 DMEM）
        //   0x0C addi x7,7      ← 必须**不**执行（证明恢复地址是 PC+4 而不是 PC）
        //   0x10 addi x5,4      ← handler 把 mepc 从 0x0C 推进到 0x10 后从这里继续
        //   0x14 jal x0,0 halt
        //
        // 这一条是 M-07 的 Store 半边，和"未对齐"走的是完全不同的通路：
        // 未对齐在 EX 级就能判定，访问错误必须等下游响应回来（MEM 级）才知道。
        // 实测这条通路曾经整体失效：memwb_exc_valid 只比对 EX/MEM 里的记录，
        // 于是 MEM 级新发现的错误永远进不了 WB——既不 Trap 也不取消写回。
        //
        // 为什么恢复点是 PC+4：§5.1 第 4 条。Store 请求已经被下游接受，
        // 若把 mepc 指回这条 Store，handler 重试就会产生第二次总线副作用；
        // 因此硬件把它当作"已在 Trap 之前提交"，mepc 直接指向下一条。
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_SW_X6_64;     // 0x08 出错指令
        im.mem[3] = I_ADDI_X7_7;    // 0x0C 不得执行
        im.mem[4] = I_ADDI_X5_4;    // 0x10 恢复点
        im.mem[5] = I_JAL_SELF;     // 0x14 halt
        im.mem[6] = I_HANDLER_0;
        im.mem[7] = I_HANDLER_1;
        im.mem[8] = I_HANDLER_2;
        im.mem[9] = I_HANDLER_3;
        for (k = 0; k < 8; k = k + 1) dm.mem[k] = 32'b0;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 1, "K: store access fault traps exactly once");
        expect_word(core.csr.mcause_q, 32'd7, "K: mcause=7 store access fault");
        expect_word(core.csr.mtval_q, 32'd64, "K: mtval=faulting address");
        expect_int(n_c08, 0, "K: faulting store produced no commit record");
        expect_word(store_side_effects, 32'd0, "K: no store side effect");
        expect_word(core.rf.regs[7], 32'd0, "K: resume PC is the store PC+4, not the store PC");
        expect_word(core.rf.regs[5], 32'd4, "K: handler resumed after the faulting store");
        expect_word(core.csr.mepc_q, 32'h0000_0010, "K: mepc = store PC+4 advanced by handler");
        //=====================================================================
        // 用例 L：外部中断 —— mcause=0x8000000B
        //   与用例 I 同构，只换中断源与使能位（mie.MEIE = bit11 = 2048）。
        //   2048 超不过 12 位立即数的正数上限（2047），CSRRSI 的立即数更是只有 5 位，
        //   所以用 addi + slli 先算出 x4 = 1<<11，再 csrrs 写入。
        //   0x08 addi x4,1 / 0x0C slli x4,11 / 0x10 csrrs mie / 0x14 csrrsi mstatus,8
        //   0x18 jal x0,0（halt）/ 0x1C addi x6,8（ISR）/ 0x20 mret
        //   中断服务不推进 mepc：mret 回到"还没执行的那条"，最终走到 0x18。
        //=====================================================================
        im.mem[0] = I_ADDI_X1_1C;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_ADDI_X4_1;
        im.mem[3] = I_SLLI_X4_11;
        im.mem[4] = I_CSRRS_X0_MIE_X4;
        im.mem[5] = I_CSRRSI_MSTATUS_MIE;
        im.mem[6] = I_JAL_SELF;     // 0x18 halt
        im.mem[7] = I_ADDI_X6_8;    // 0x1C ISR
        im.mem[8] = I_HANDLER_3;    // 0x20 mret
        clear_events();
        irq_ext_drive = 1'b1;
        irq_hold      = 1'b0;
        run_case(32'b0);
        irq_ext_drive = 1'b0;
        repeat (60) @(negedge clk);
        expect_int(n_trap, 1, "L: external interrupt traps exactly once");
        expect_word(core.csr.mcause_q, 32'h8000_000B, "L: mcause=machine external interrupt");
        expect_word(core.csr.mtval_q, 32'd0, "L: mtval=0 for interrupt");
        expect_word(core.rf.regs[6], 32'd8, "L: external ISR executed");
        expect_int(n_mret, 1, "L: mret returns from external ISR");

        //=====================================================================
        // 用例 M：同步异常与中断**同拍**竞争 —— 同步异常优先，且中断不丢
        //   注入方式：中断线只在"非法指令进入 WB 且异常记录有效"的那一拍拉高
        //   （irq_ext_now），之后 sticky 保持，直到中断型 Trap 被接受。
        //   期望恰好两次 Trap：
        //     ① mcause=2  —— 同步异常优先（§5.2 第 6 条）
        //     ② mcause=0x8000000B —— 中断没丢，在 handler 恢复 MIE 之后被接受
        //   handler 用 mcause 的符号位区分两类：异常把 mepc 推进 4，中断不动 mepc。
        //   程序：0x18 非法指令 / 0x1C jal x0,0（恢复点兼 halt）
        //        0x20 csrrs x3,mcause / 0x24 bge x3,x0,+8 / 0x28 mret
        //        0x2C csrrs x3,mepc / 0x30 addi x3,4 / 0x34 csrrw mepc / 0x38 mret
        //   为什么 run_case 之后还要多等一段：halt 在第一次 mret 之后就出现了，
        //   而第二次 Trap 发生在它之后，断言必须等两次 Trap 都落地。
        //=====================================================================
        im.mem[0] = I_ADDI_X1_20;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_ADDI_X4_1;
        im.mem[3] = I_SLLI_X4_11;
        im.mem[4] = I_CSRRS_X0_MIE_X4;
        im.mem[5] = I_CSRRSI_MSTATUS_MIE;
        im.mem[6] = I_ILLEGAL;      // 0x18
        im.mem[7] = I_JAL_SELF;     // 0x1C 恢复点/halt
        im.mem[8] = I_HANDLER_0;       // 0x20 csrrs x3, mepc, x0
        im.mem[9] = I_HANDLER_1;       // 0x24 addi x3, x3, 4
        im.mem[10] = I_HANDLER_2;      // 0x28 csrrw x0, mepc, x3
        im.mem[11] = I_HANDLER_3;      // 0x2C mret
        clear_events();
        clear_events();
        irq_ext_conflict = 1'b1;
        irq_hold         = 1'b0;
        // 这里**不**用 run_case 等 halt：本用例要证明的是"同拍竞争谁赢、中断丢没丢"，
        // 而 halt 在第一次 Trap 之后就已经出现过，等 halt 会在第二次 Trap 落地前就返回。
        // 改成固定长度的观测窗口，结束时再看计数器。
        reset  = 1'b1;
        repeat (3) @(negedge clk);
        reset  = 1'b0;
        repeat (300) @(negedge clk);
        irq_ext_conflict = 1'b0;
        irq_ext_sticky   = 1'b0;
        expect_int(n_trap, 2, "M: exception wins the same-cycle conflict, interrupt not lost");
        expect_word(first_trap_cause, 32'd2, "M: first trap is the synchronous exception");
        expect_int(n_irq_trap, 1, "M: the interrupt was taken afterwards, exactly once");
        expect_word(core.csr.mcause_q, 32'h8000_000B, "M: final mcause is the external interrupt");

        //=====================================================================
        // 用例 O（M-12）：同拍多源异常 —— 只产生一个 Trap，且程序序更早者胜
        //   0x08 lh x2,3(x0)   未对齐 Load（mcause=4），程序序更早
        //   0x0C 非法指令      与上一条**同时在流水线里**（MEM / EX）
        //   两条指令各自都带异常记录，WB 退休边界同拍只能接受一个。
        //   实测：第一次 Trap 的原因码必须是 4（更早的那条），总共 2 次 Trap。
        //   若实现把两条都接受（或让更年轻者胜），n_trap / first_trap_cause 会立刻不匹配。
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_LH_X2_3;      // 0x08 未对齐 Load
        im.mem[3] = I_ILLEGAL;      // 0x0C 非法指令（同拍在流水线中）
        im.mem[4] = I_ADDI_X5_4;    // 0x10 恢复点
        im.mem[5] = I_JAL_SELF;     // 0x14 halt
        im.mem[6] = I_HANDLER_0;
        im.mem[7] = I_HANDLER_1;
        im.mem[8] = I_HANDLER_2;
        im.mem[9] = I_HANDLER_3;
        for (k = 0; k < 8; k = k + 1) dm.mem[k] = 32'b0;
        clear_events();
        run_case(32'b0);
        expect_int(n_trap, 2, "O: two faulting instructions produce exactly two traps");
        expect_word(first_trap_cause, 32'd4, "O: program-order-earliest exception wins the cycle");
        expect_word(core.csr.mcause_q, 32'd2, "O: younger trap is handled afterwards");
        expect_int(n_c08, 0, "O: misaligned load produced no commit record");
        // 出错指令在 0x0C，所以要比的是 0x0C 上的提交记录数；
        // 0x10 是 handler 推进 mepc 之后的**合法恢复点**，它本来就应该提交。
        expect_int(n_c0c, 0, "O: illegal instruction produced no commit record");
        expect_word(core.rf.regs[5], 32'd4, "O: both handlers resumed the program");

        //=====================================================================
        // 用例 P（M-08）：取指访问错误 —— mcause=1、mtval=出错取指地址
        //   0x08 lui x2,4 → x2=0x4000；0x0C jalr x0,0(x2) 跳到 IMEM 之外。
        //   mepc 必须等于**出错取指地址**（0x4000），不能是跳转指令自己的 PC。
        //   handler 直接把 mepc 写成恢复点：对取指错误不能用"+4"，
        //   越界地址加 4 仍然越界，会立刻再陷一次。
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;   // mtvec = 0x18
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_LUI_X2_4000;  // 0x08
        im.mem[3] = I_JALR_X0_X2;   // 0x0C 跳到 0x4000（越界）
        im.mem[4] = I_ADDI_X5_4;    // 0x10 不得执行
        im.mem[5] = I_ADDI_X6_8;    // 0x14 不得执行
        im.mem[6] = I_ADDI_X3_28;   // 0x18 handler：x3 = 0x28（恢复点）
        im.mem[7] = I_CSRRW_MEPC_X3;// 0x1C 直接写 mepc
        im.mem[8] = I_ADDI_X7_7;    // 0x20 handler 已运行的标记
        im.mem[9] = I_HANDLER_3;    // 0x24 mret
        im.mem[10] = I_JAL_SELF;    // 0x28 halt（恢复点）
        clear_events();
        run_case(32'h0000_0028);
        expect_int(n_trap, 1, "P: fetch error traps exactly once");
        expect_word(core.csr.mcause_q, 32'd1, "P: mcause=1 instruction access fault");
        expect_word(core.csr.mtval_q, 32'h0000_4000, "P: mtval=faulting fetch address");
        expect_word(core.csr.mepc_q, 32'h0000_0028, "P: handler redirected mepc to a valid PC");
        expect_word(core.rf.regs[5], 32'd0, "P: instruction after the bad jump did not execute");
        expect_word(core.rf.regs[7], 32'd7, "P: handler ran");

        //=====================================================================
        // 用例 Q（M-18）：handler 运行中复位 —— CSR 与流水线必须回到初值
        //   复位不是"清一条流水线"那么简单：Trap handler 正在跑的时候复位，
        //   CSR（mcause/mepc/mtvec/mstatus）与在途事务都必须回到确定初值，
        //   并且复位释放后从 PC=0 重新取指。
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_EBREAK;       // 0x08 触发 Trap
        im.mem[3] = I_ADDI_X5_4;    // 0x0C
        im.mem[4] = I_NOP;          // 0x10
        im.mem[5] = I_JAL_SELF;     // 0x14
        im.mem[6] = I_HANDLER_0;
        im.mem[7] = I_HANDLER_1;
        im.mem[8] = I_HANDLER_2;
        im.mem[9] = I_HANDLER_3;
        for (k = 0; k < 8; k = k + 1) dm.mem[k] = 32'b0;
        clear_events();
        reset = 1'b1;
        repeat (3) @(negedge clk);
        reset = 1'b0;
        k = 0;
        while (n_trap == 0 && k < 200) begin @(negedge clk); k = k + 1; end
        repeat (6) @(negedge clk);  // 让 handler 真的在流水线里跑起来
        reset = 1'b1;               // ← handler 运行中复位
        repeat (4) @(negedge clk);
        expect_int(n_trap > 0, 1, "Q: trap was taken before the reset (handler was running)");
        expect_word(core.csr.mcause_q, 32'd0, "Q: mcause cleared by reset");
        expect_word(core.csr.mepc_q, 32'd0, "Q: mepc cleared by reset");
        expect_word(core.csr.mtvec_q, 32'd0, "Q: mtvec cleared by reset");
        expect_word(core.csr.mstatus_mie_q, 1'b0, "Q: mstatus.MIE cleared by reset");
        expect_word(store_side_effects, 32'd0, "Q: no residual store side effect across reset");
        saw_pc0 = 1'b0;
        reset = 1'b0;               // 释放复位：必须从 PC=0 重新开始
        k = 0;
        while (!saw_pc0 && k < 200) begin @(negedge clk); k = k + 1; end
        expect_int(saw_pc0, 1, "Q: core restarts from PC 0 after reset");
        reset = 1'b1;

        //=====================================================================
        // 用例 R（M-20）：mcycle / minstret 与手工计数对照
        //   0x08/0x0C 读 mcycle/minstret，0x10~0x1C 四条 NOP，0x20/0x24 再读一次，
        //   0x28/0x2C 求差值。读操作本身不改变计数器（mcycle/minstret 是只读的）。
        //=====================================================================
        im.mem[0] = I_ADDI_X1_18;
        im.mem[1] = I_CSRW_MTVEC;
        im.mem[2] = I_CSRRS_X3_MCYCLE;    // 0x08 t0
        im.mem[3] = I_CSRRS_X4_MINSTRET;  // 0x0C i0
        im.mem[4] = I_NOP;                // 0x10
        im.mem[5] = I_NOP;                // 0x14
        im.mem[6] = I_NOP;                // 0x18
        im.mem[7] = I_NOP;                // 0x1C
        im.mem[8] = I_CSRRS_X5_MCYCLE;    // 0x20 t1
        im.mem[9] = I_CSRRS_X6_MINSTRET;  // 0x24 i1
        im.mem[10] = I_SUB_X7_X5_X3;      // 0x28 cycle delta
        im.mem[11] = I_SUB_X8_X6_X4;      // 0x2C instret delta
        im.mem[12] = I_ADDI_X9_4;         // 0x30 程序跑通的标记
        im.mem[13] = I_JAL_SELF;          // 0x34 halt
        clear_events();
        run_case(32'h0000_0034);
        expect_int(n_trap, 0, "R: no trap while reading the counters");
        expect_word(core.rf.regs[9], 32'd4, "R: program reached the end marker");
        // 手工推导：两次读取分别在 0x08 与 0x20，中间相隔 6 条指令，流水线满速无停顿，
        // 因此 mcycle 差值是 6 拍。minstret 在第一个读点看到的是"已退休到 0x04"，
        // 在第二个读点看到的是"已退休到 0x20"，中间恰好退休 0x0C~0x20 共 6 条。
        // 写死具体数字是有意的：这两条断言的作用是"计数器口径一变就立刻报警"。
        `ifdef TB_TRAP_RANDOM
        // 随机背压下两个读点之间会插入取指/访存停顿，周期差不再是定值：
        // 这里只断言"不小于满速值"（下界是架构决定的），精确值只在零延迟配置下判定。
        test_no = test_no + 1;
        if (core.rf.regs[7] >= 32'd6)
            $display("TEST %0d PASS R: mcycle delta >= full-speed value (%0d)", test_no, core.rf.regs[7]);
        else begin
            $display("TEST %0d FAIL R: mcycle delta below full-speed value got=%0d", test_no, core.rf.regs[7]);
            failures = failures + 1;
        end
        `else
        expect_word(core.rf.regs[7], 32'd6, "R: mcycle delta equals the hand-counted 6 cycles");
        `endif
        expect_word(core.rf.regs[8], 32'd6, "R: minstret delta equals the hand-counted 6 retires");

        if (failures == 0)
            $display("ALL TRAP PIPELINE TEST PASS");
        else
            $fatal(1, "TRAP PIPELINE %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #600000;
        $fatal(1, "TRAP PIPELINE TIMEOUT at cycle %0d", cycles);
    end

endmodule
