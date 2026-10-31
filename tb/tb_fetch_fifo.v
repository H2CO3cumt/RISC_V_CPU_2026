`timescale 1ns/1ps
// ===========================================================================
// fetch_fifo 独立 Testbench
// ===========================================================================
// 被测对象：rtl/fetch_fifo.v（取指预取队列）
//
// 时序约定（全 TB 统一）：
//   所有激励都在 **negedge** 驱动，之后延时 #1 采样组合输出。
//   于是"本 negedge 驱动 -> 下一个 posedge 被 DUT 锁存"这两件事一一对应，
//   采样点看到的就是**即将被消费的那一条**，不会晚一拍。
//
// 判据（每条打印 TEST ... PASS/FAIL，末尾 ALL TEST PASS）：
//   T1 复位后 out_valid=0、in_ready=1、level=0
//   T2 满速直通：out_ready 恒 1 时 out_valid 每拍都高，且不占条目（零附加延迟）
//   T3 背压：out_ready=0 灌满后 level=DEPTH、in_ready=0
//   T4 排空顺序：出队顺序与入队完全一致
//   T5 flush：当拍 out_valid 被屏蔽，下一拍清空
//   T6 in_discard：错误路径条目被接收但不入队
//   T7 随机压测（无 flush）：顺序不变式 + 出入队条数守恒
//   T8 随机压测（含 flush）：顺序不变式 + 最终排空
// ===========================================================================
module tb_fetch_fifo;

    // 队列深度由运行脚本用 -Ptb_fetch_fifo.DEPTH=<n> 覆盖，
    // 默认 4。必须同时验证 DEPTH=1（退化成 1 项 skid 缓冲）和 DEPTH=4（真预取）：
    // DEPTH=1 的指针掩码曾经写错过一次，表现为输出 X 顺着 ifid_inst 污染流水线。
    parameter DEPTH = 4;

    reg clk;
    reg reset;

    reg         in_valid;
    wire        in_ready;
    wire        in_fire;
    reg  [31:0] in_inst;
    reg  [31:0] in_pc;
    reg         in_error;
    reg         in_pred_hit;
    reg         in_pred_taken;
    reg  [31:0] in_pred_target;
    reg         in_discard;

    wire        out_valid;
    wire [31:0] out_inst;
    wire [31:0] out_pc;
    wire        out_error;
    wire        out_pred_hit;
    wire        out_pred_taken;
    wire [31:0] out_pred_target;
    reg         out_ready;

    reg         flush;
    wire  [3:0] level;

    integer errors;
    integer i;
    integer hi_cycles;
    integer got;
    integer order_ok;
    integer mism;
    integer push_seq;      // 已被接受的入队总条数（也用作 in_inst 的序号）
    integer expect_next;   // 下一条应该出队时看到的序号
    integer seen;          // 已观测到的出队条数
    integer sent;          // 已观测到的入队条数

`define CHK(cond, msg) \
    if (cond) $display("TEST %0s PASS", msg); \
    else begin $display("TEST %0s FAIL", msg); errors = errors + 1; end

    fetch_fifo #(.DEPTH(DEPTH)) dut (
        .clk             (clk),
        .reset           (reset),
        .in_valid        (in_valid),
        .in_ready        (in_ready),
        .in_fire         (in_fire),
        .in_inst         (in_inst),
        .in_pc           (in_pc),
        .in_error        (in_error),
        .in_pred_hit     (in_pred_hit),
        .in_pred_taken   (in_pred_taken),
        .in_pred_target  (in_pred_target),
        .in_discard      (in_discard),
        .out_valid       (out_valid),
        .out_inst        (out_inst),
        .out_pc          (out_pc),
        .out_error       (out_error),
        .out_pred_hit    (out_pred_hit),
        .out_pred_taken  (out_pred_taken),
        .out_pred_target (out_pred_target),
        .out_ready       (out_ready),
        .flush           (flush),
        .level           (level)
    );

    always #5 clk = ~clk;

    // 上游握手：in_fire 与 in_valid&&in_ready 同义。真实集成里 pipeline_cpu
    // 还会再叠加 !mem_block / if_rsp 门控，正是靠这根 in_fire 传进去的；
    // 这里保持一致，保证 TB 与集成用法同构。
    assign in_fire = in_valid && in_ready;

    // 把上游激励恢复到"什么都不发"的安静状态
    task idle_inputs;
        begin
            in_valid       = 1'b0;
            in_inst        = 32'b0;
            in_pc          = 32'b0;
            in_error       = 1'b0;
            in_pred_hit    = 1'b0;
            in_pred_taken  = 1'b0;
            in_pred_target = 32'b0;
            in_discard     = 1'b0;
            flush          = 1'b0;
        end
    endtask

    initial begin
        clk        = 1'b0;
        reset      = 1'b1;
        out_ready  = 1'b0;
        errors     = 0;
        push_seq   = 0;
        expect_next= 0;
        seen       = 0;
        sent       = 0;
        idle_inputs();

        //------------------------------------------------------------------
        // T1 复位
        //------------------------------------------------------------------
        repeat (3) @(negedge clk);
        #1;
        `CHK(out_valid === 1'b0, "T1.1 reset out_valid=0")
        `CHK(in_ready  === 1'b1, "T1.2 reset in_ready=1")
        `CHK(level     === 4'd0, "T1.3 reset level=0")
        reset = 1'b0;
        #1;

        //------------------------------------------------------------------
        // T2 满速直通：多一级缓冲不能多花一拍
        //------------------------------------------------------------------
        out_ready = 1'b1;
        in_valid  = 1'b1;
        in_inst   = 32'd0;
        in_pc     = 32'h0000_1000;
        hi_cycles = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            out_ready = 1'b1;
            in_valid  = 1'b1;
            in_inst   = i;
            in_pc     = 32'h0000_1000 + i*4;
            #1;
            if (out_valid === 1'b1) hi_cycles = hi_cycles + 1;
        end
        `CHK(hi_cycles == 8, "T2.1 feedthrough out_valid high every cycle")
        `CHK(level     === 4'd0, "T2.2 feedthrough stores nothing level=0")

        //------------------------------------------------------------------
        // T3 背压：灌满后 in_ready 落 0
        //------------------------------------------------------------------
        idle_inputs();
        repeat (2) @(negedge clk);
        #1;
        `CHK(level === 4'd0, "T3.0 precondition queue empty")

        for (i = 0; i < DEPTH + 2; i = i + 1) begin
            @(negedge clk);
            out_ready  = 1'b0;
            in_valid   = 1'b1;
            in_discard = 1'b0;
            in_inst    = 32'sd100 + i;
            in_pc      = 32'sd100 + i;
            #1;
        end
        `CHK(level    === DEPTH,      "T3.1 backpressure level==DEPTH")
        `CHK(in_ready === 1'b0,       "T3.2 backpressure in_ready=0 when full")
        `CHK(out_valid=== 1'b1,       "T3.3 backpressure out_valid still high")

        //------------------------------------------------------------------
        // T4 排空顺序
        //------------------------------------------------------------------
        got      = 0;
        order_ok = 1;
        for (i = 0; i < DEPTH + 2; i = i + 1) begin
            @(negedge clk);
            out_ready  = 1'b1;
            in_valid   = 1'b0;
            in_discard = 1'b0;
            #1;
            if (out_valid === 1'b1) begin
                if (out_inst !== (32'sd100 + got)) begin
                    order_ok = 0;
                    $display("  T4 mismatch idx=%0d got=%0d expect=%0d",
                             got, out_inst, 100 + got);
                end
                got = got + 1;
            end
        end
        `CHK(got == DEPTH && order_ok, "T4.1 drain order preserved and count correct")
        `CHK(level === 4'd0,           "T4.2 drain queue empty")

        //------------------------------------------------------------------
        // T5 flush 清空
        //------------------------------------------------------------------
        idle_inputs();
        @(negedge clk);
        out_ready = 1'b0; in_valid = 1'b1; in_inst = 32'hA0; in_pc = 32'hA0; #1;
        @(negedge clk);
        out_ready = 1'b0; in_valid = 1'b1; in_inst = 32'hA4; in_pc = 32'hA4; #1;
        @(negedge clk);
        out_ready = 1'b0; in_valid = 1'b0; #1;
        // DEPTH=1 时队列最多只能存 1 条，这里不能写死 2 条。
        `CHK(level === ((DEPTH < 2) ? 1 : 2), "T5.1 flush harness queued expected entries")

        @(negedge clk);
        flush = 1'b1; in_valid = 1'b0; out_ready = 1'b0; #1;
        `CHK(out_valid === 1'b0, "T5.2 flush masks out_valid in flush cycle")
        `CHK(in_ready  === 1'b1, "T5.3 flush keeps in_ready=1 to drain upstream")

        @(negedge clk);
        flush = 1'b0; #1;
        `CHK(level     === 4'd0, "T5.4 flush level=0 next cycle")
        `CHK(out_valid === 1'b0, "T5.5 flush out_valid=0 after clear")

        //------------------------------------------------------------------
        // T6 in_discard 不入队
        //------------------------------------------------------------------
        idle_inputs();
        @(negedge clk);
        out_ready = 1'b0; in_valid = 1'b1; in_discard = 1'b1; in_inst = 32'hBAD0; #1;
        `CHK(in_ready === 1'b1, "T6.1 discard entry still accepted (drain semantics)")

        @(negedge clk);
        out_ready = 1'b0; in_valid = 1'b1; in_discard = 1'b1; in_inst = 32'hBAD4; #1;
        `CHK(level === 4'd0, "T6.2 discard entries never stored")

        @(negedge clk);
        out_ready = 1'b0; in_valid = 1'b1; in_discard = 1'b0; in_inst = 32'h600D; #1;

        @(negedge clk);
        out_ready = 1'b1; in_valid = 1'b0; in_discard = 1'b0; #1;
        `CHK(out_valid === 1'b1 && out_inst === 32'h600D,
             "T6.3 discard only the good entry comes out")

        @(negedge clk);
        out_ready = 1'b1; #1;
        `CHK(level === 4'd0, "T6.4 discard queue drained")

        //------------------------------------------------------------------
        // T7 随机压测（无 flush）：顺序不变式 + 守恒
        //------------------------------------------------------------------
        idle_inputs();
        repeat (2) @(negedge clk);
        push_seq    = 0;
        expect_next = 0;
        seen        = 0;
        sent        = 0;
        mism        = 0;

        for (i = 0; i < 600; i = i + 1) begin
            @(negedge clk);
            in_valid   = (({$random} % 10 + 10) % 10) < 7;   // 70%
            out_ready  = (({$random} % 10 + 10) % 10) < 6;   // 60%
            in_discard = (({$random} % 10 + 10) % 10) < 2;   // 20%
            flush      = 1'b0;
            in_inst    = push_seq;                            // 用序号当数据
            in_pc      = push_seq;
            #1;
            if (out_valid === 1'b1 && out_ready === 1'b1) begin
                if (out_inst !== expect_next) begin
                    mism = mism + 1;
                    if (mism <= 5)
                        $display("  T7 order mismatch cyc=%0d got=%0d expect=%0d",
                                 i, out_inst, expect_next);
                end
                expect_next = expect_next + 1;
                seen = seen + 1;
            end
            if (in_valid === 1'b1 && in_ready === 1'b1 && in_discard === 1'b0) begin
                push_seq = push_seq + 1;
                sent     = sent + 1;
            end
        end
        `CHK(mism == 0, "T7.1 random: FIFO order invariant holds")

        // 收尾排空
        for (i = 0; i < DEPTH + 4; i = i + 1) begin
            @(negedge clk);
            out_ready  = 1'b1;
            in_valid   = 1'b0;
            in_discard = 1'b0;
            #1;
            if (out_valid === 1'b1) begin
                if (out_inst !== expect_next) begin
                    mism = mism + 1;
                    $display("  T7 drain mismatch got=%0d expect=%0d", out_inst, expect_next);
                end
                expect_next = expect_next + 1;
                seen        = seen + 1;
            end
        end
        `CHK(mism == 0,        "T7.2 random: drain order invariant holds")
        `CHK(level === 4'd0,   "T7.3 random: queue empty after drain")
        `CHK(seen == sent,     "T7.4 random: no instruction lost or duplicated")
        $display("  T7 info: pushed=%0d popped=%0d", sent, seen);

        //------------------------------------------------------------------
        // T8 随机压测（含 flush）：顺序不变式 + 最终排空
        //------------------------------------------------------------------
        idle_inputs();
        repeat (2) @(negedge clk);
        push_seq    = 0;
        expect_next = 0;
        mism        = 0;

        for (i = 0; i < 600; i = i + 1) begin
            @(negedge clk);
            in_valid   = (({$random} % 10 + 10) % 10) < 7;
            out_ready  = (({$random} % 10 + 10) % 10) < 6;
            in_discard = (({$random} % 10 + 10) % 10) < 2;
            flush      = ((({$random} % 100 + 100) % 100) < 4);   // 4%
            in_inst    = push_seq;
            in_pc      = push_seq;
            #1;
            // flush 当拍不出队（out_valid 已被屏蔽），也不入队（accept 已屏蔽）
            if (out_valid === 1'b1 && out_ready === 1'b1 && flush === 1'b0) begin
                if (out_inst !== expect_next) begin
                    mism = mism + 1;
                    if (mism <= 5)
                        $display("  T8 order mismatch cyc=%0d got=%0d expect=%0d",
                                 i, out_inst, expect_next);
                end
                expect_next = expect_next + 1;
            end
            if (in_valid === 1'b1 && in_ready === 1'b1 && in_discard === 1'b0
                && flush === 1'b0) begin
                push_seq = push_seq + 1;
            end
            if (flush === 1'b1) begin
                // flush 之前的在队条目全部作废：下一条该出队的就是下一个新推入的
                expect_next = push_seq;
            end
        end
        `CHK(mism == 0, "T8.1 random+flush: order invariant holds across flushes")

        for (i = 0; i < DEPTH + 4; i = i + 1) begin
            @(negedge clk);
            out_ready  = 1'b1;
            in_valid   = 1'b0;
            in_discard = 1'b0;
            flush      = 1'b0;
            #1;
            if (out_valid === 1'b1) begin
                if (out_inst !== expect_next) begin
                    mism = mism + 1;
                    $display("  T8 drain mismatch got=%0d expect=%0d", out_inst, expect_next);
                end
                expect_next = expect_next + 1;
            end
        end
        `CHK(mism == 0,      "T8.2 random+flush: drain order invariant holds")
        `CHK(level === 4'd0, "T8.3 random+flush: queue empty after drain")

        //------------------------------------------------------------------
        $display("----------------------------------------------------------");
        if (errors == 0) $display("ALL TEST PASS");
        else             $display("TEST FAIL count=%0d", errors);
        $finish;
    end

    // 看门狗：防止激励写错导致仿真挂死
    initial begin
        #200000;
        $display("TEST TIMEOUT FAIL");
        $finish;
    end

endmodule
