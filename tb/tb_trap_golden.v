`timescale 1ns/1ps
// M-21：独立 golden 事件判定器的**日志产生端**。
//
// 这个 Testbench 刻意只读 Core 的**公开端口**：
//   trace_*（提交级 trace）与 event_trap / event_trap_return。
// 它**不读** Core 内部信号（不碰 csr、不碰 trap_take、不碰流水寄存器），
// 也不使用单周期 Reference Model（它根本不支持 Trap）。
// 判定由 `python/trap_golden_judge.py` 独立完成：脚本只看这份日志，
// 自己重建"提交了什么、哪几拍进了 Trap、mret 了几次"，再和声明的期望序列比对。
//
// 程序（同一个 case 连做 3 个不同的异常，handler 统一把 mepc 推进 4）：
//   0x00 addi x1, x0, 0x1C   建立 mtvec
//   0x04 csrrw x0, mtvec, x1
//   0x08 ecall               ← 异常 A（E-10）
//   0x0C 0xffffffff          ← 异常 B（E-02）
//   0x10 sh x0, 1(x0)        ← 异常 C（E-06，未对齐 Store，不得产生写事务）
//   0x14 addi x5, x0, 4      恢复路径（三条异常都被跳过后才会执行）
//   0x18 jal x0, 0           halt
//   0x1C csrrs x3, mepc, x0  handler
//   0x20 addi x3, x3, 4
//   0x24 csrrw x0, mepc, x3
//   0x28 mret
module tb_trap_golden;

    reg clk = 1'b0;
    reg reset = 1'b1;

    wire        iv, ir, rv, rr, ie, dv, dr, dw, dsv, dsr, de;
    wire [31:0] ia, idata, da, dwd, drd;
    wire [3:0]  dst;

    wire        tv, trw, tmw, terr;
    wire [31:0] tpc, tinst, trd, tmaddr, tmdata;
    wire [4:0]  trda;
    wire [3:0]  tmstrb;
    wire        ev_trap, ev_trap_return;

    integer logfd;
    integer cycles = 0;

    pipeline_cpu core(
        .clk(clk), .reset(reset),
        .trace_valid(tv), .trace_pc(tpc), .trace_instruction(tinst),
        .trace_rd_we(trw), .trace_rd_addr(trda), .trace_rd_data(trd),
        .trace_mem_we(tmw), .trace_mem_addr(tmaddr), .trace_mem_data(tmdata),
        .trace_mem_wstrb(tmstrb), .trace_error(terr),
        .i_req_valid(iv), .i_req_ready(ir), .i_req_addr(ia),
        .i_rsp_valid(rv), .i_rsp_ready(rr), .i_rsp_data(idata), .i_rsp_error(ie),
        .d_req_valid(dv), .d_req_ready(dr), .d_req_addr(da), .d_req_write(dw),
        .d_req_wdata(dwd), .d_req_wstrb(dst),
        .d_rsp_valid(dsv), .d_rsp_ready(dsr), .d_rsp_rdata(drd), .d_rsp_error(de),
        .irq_software_i(1'b0), .irq_timer_i(1'b0), .irq_external_i(1'b0),
        .event_stall(), .event_load_stall(), .event_branch(), .event_branch_taken(),
        .event_flush(), .event_predict(), .event_btb_hit(), .event_mispredict(),
        .event_control_redirect(), .event_trap(ev_trap), .event_trap_return(ev_trap_return),
        .event_illegal(), .event_misaligned(), .event_bus_error());

    pipeline_imem_adapter #(.DEPTH(11), .INIT_FILE("tb/data/trap_golden.mem"),
                            .RANDOM_DELAY(0), .FILL_WORD(32'h0000_006f)) im(
        .clk(clk), .reset(reset), .req_valid(iv), .req_ready(ir), .req_addr(ia),
        .rsp_valid(rv), .rsp_ready(rr), .rsp_data(idata), .rsp_error(ie));

    ram_adapter #(.DEPTH(8), .RANDOM_DELAY(0)) dm(
        .clk(clk), .reset(reset), .req_valid(dv), .req_ready(dr), .req_addr(da),
        .req_write(dw), .req_wdata(dwd), .req_wstrb(dst),
        .rsp_valid(dsv), .rsp_ready(dsr), .rsp_rdata(drd), .rsp_error(de),
        .write_side_effect_count());

    always #5 clk = ~clk;

    initial begin
        logfd = $fopen("tmp/trap_golden/trace.log", "w");
        if (logfd == 0) begin
            $display("TRAP GOLDEN LOG OPEN FAIL");
            $fatal(1);
        end
    end

    // 只写公开端口。格式固定、字段顺序固定，供 Python 判定器解析。
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (tv)
            $fwrite(logfd, "T %0d %08h %08h %0d %0d %08h %0d %08h %08h %0d\n",
                    cycles, tpc, tinst, trw, trda, trd, tmw, tmaddr, tmdata, tmstrb);
        if (ev_trap)
            $fwrite(logfd, "TRAP %0d\n", cycles);
        if (ev_trap_return)
            $fwrite(logfd, "MRET %0d\n", cycles);
    end

    initial begin
        repeat (2) @(negedge clk);
        reset = 1'b0;
        // 跑到 halt 之后还在原地自跳转，取 40 条提交记录足够覆盖
        // "3 次异常 + 3 次 handler + 恢复路径 + halt 循环"。
        repeat (400) @(negedge clk);
        $fclose(logfd);
        $display("TRAP GOLDEN LOG DONE cycles=%0d", cycles);
        $finish;
    end

endmodule
