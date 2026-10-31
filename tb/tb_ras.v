`timescale 1ns/1ps
// ===========================================================================
// ras 独立 Testbench
// ===========================================================================
// 被测对象：rtl/ras.v（返回地址栈）
//
// 时序约定（关键，写错过一次）：
//   RAS 的状态是**寄存器**，只有 posedge 才更新。因此每一拍的动作顺序必须是
//       来到 negedge -> #1 -> 【先检查】本拍可见状态 -> 【再驱动】本拍激励
//   检查放在驱动之前，看到的就是"上一拍驱动被锁存后"的真实状态。
//   若先驱动再检查，会永远比 DUT 早一拍（初版就栽在这里：push 三次只看到 2）。
//
// 判据（每条打印 TEST ... PASS/FAIL，末尾 ALL TEST PASS）：
//   T1 复位后 valid=0、level=0
//   T2 连续 push 三条 -> top=最后一条、level=3
//   T3 pop 一条 -> top 回到上一条、level 递减
//   T4 弹到空 -> valid=0
//   T5 空栈 pop 不得回绕；之后 push 仍能拿到刚推入的值
//   T6 溢出：推到 DEPTH 后继续推，level 饱和在 DEPTH，top=最后推入值
//   T7 enable=0：状态保持不变、valid 恒 0
//   T8 随机压测：与黄金模型逐拍比对 top / level / valid
// ===========================================================================
module tb_ras;

    // 深度由运行脚本用 -Ptb_ras.DEPTH=<n> 覆盖，默认 8。
    parameter DEPTH = 8;

    reg         clk;
    reg         reset;
    reg         enable;
    reg         push;
    reg  [31:0] ret_addr;
    reg         pop;

    wire [31:0] top;
    wire        valid;
    wire [3:0]  level;

    integer errors;
    integer i;
    integer gwp;
    integer gcnt;
    reg [31:0] gold [0:DEPTH-1];
    integer mism;

`define CHK(cond, msg) \
    if (cond) $display("TEST %0s PASS", msg); \
    else begin $display("TEST %0s FAIL", msg); errors = errors + 1; end

    ras #(.DEPTH(DEPTH)) dut (
        .clk      (clk),
        .reset    (reset),
        .enable   (enable),
        .push     (push),
        .ret_addr (ret_addr),
        .pop      (pop),
        .top      (top),
        .valid    (valid),
        .level    (level)
    );

    always #5 clk = ~clk;

    // 黄金模型（规则与本模块注释一致：pop 优先；空栈 pop 不回绕）
    task g_push(input [31:0] v);
        begin
            gold[gwp] = v;
            gwp = (gwp + 1) % DEPTH;
            if (gcnt < DEPTH) gcnt = gcnt + 1;
        end
    endtask

    task g_pop;
        begin
            if (gcnt > 0) begin
                gwp = (gwp - 1 + DEPTH) % DEPTH;
                gcnt = gcnt - 1;
            end
        end
    endtask

    // 一个采样点：来到 negedge 并等组合值稳定
    task cyc;
        begin
            @(negedge clk);
            #1;
        end
    endtask

    // 驱动一条 push（同时更新模型）
    task drive_push(input [31:0] v);
        begin
            push     = 1'b1;
            pop      = 1'b0;
            ret_addr = v;
            #1;
            g_push(v);
        end
    endtask

    // 驱动一条 pop（同时更新模型）
    task drive_pop;
        begin
            push = 1'b0;
            pop  = 1'b1;
            #1;
            g_pop;
        end
    endtask

    task drive_idle;
        begin
            push = 1'b0;
            pop  = 1'b0;
            #1;
        end
    endtask

    initial begin
        clk      = 1'b0;
        reset    = 1'b1;
        enable   = 1'b1;
        push     = 1'b0;
        pop      = 1'b0;
        ret_addr = 32'b0;
        errors   = 0;
        gwp      = 0;
        gcnt     = 0;
        mism     = 0;
        for (i = 0; i < DEPTH; i = i + 1) gold[i] = 32'b0;

        //------------------------------------------------------------------
        // T1 复位
        //------------------------------------------------------------------
        repeat (3) cyc;
        `CHK(valid === 1'b0, "T1.1 reset valid=0")
        `CHK(level === 4'd0, "T1.2 reset level=0")
        reset = 1'b0;
        #1;

        //------------------------------------------------------------------
        // T2 连续 push 三条：a -> b -> c，c 在栈顶
        //------------------------------------------------------------------
        cyc; drive_push(32'h1000);
        cyc;
        `CHK(level === 4'd1,     "T2.0 level=1 after first push")
        drive_push(32'h2000);
        cyc;
        `CHK(level === ((2 < DEPTH) ? 2 : DEPTH), "T2.1 level after second push")
        drive_push(32'h3000);
        cyc;
        `CHK(level === ((3 < DEPTH) ? 3 : DEPTH), "T2.2 level after third push")
        `CHK(top   === 32'h3000, "T2.3 top=last pushed")

        //------------------------------------------------------------------
        // T3 pop 一条
        //------------------------------------------------------------------
        drive_pop;
        cyc;
        `CHK(level === (((3 < DEPTH) ? 3 : DEPTH) - 1), "T3.1 pop level decrements")
        if (DEPTH >= 2) begin
            `CHK(top === 32'h2000, "T3.2 pop top=previous")
        end else begin
            `CHK(valid === 1'b0, "T3.2 pop to empty when DEPTH=1")
        end

        //------------------------------------------------------------------
        // T4 弹到空
        //------------------------------------------------------------------
        drive_pop;
        cyc; drive_pop;
        cyc;
        `CHK(level === 4'd0, "T4.1 pop all level=0")
        `CHK(valid === 1'b0, "T4.2 pop all valid=0")

        //------------------------------------------------------------------
        // T5 空栈 pop 不得回绕
        //------------------------------------------------------------------
        drive_pop;
        cyc; drive_pop;
        cyc;
        `CHK(level === 4'd0, "T5.1 pop on empty level stays 0")
        `CHK(valid === 1'b0, "T5.2 pop on empty valid stays 0")
        drive_push(32'hDEAD);
        cyc;
        `CHK(top === 32'hDEAD, "T5.3 push after empty pops top correct")
        drive_idle;

        //------------------------------------------------------------------
        // T6 溢出：推到满后继续推，level 饱和、top=最后推入值
        //------------------------------------------------------------------
        cyc;
        reset = 1'b1;
        repeat (2) cyc;
        reset = 1'b0;
        gwp = 0; gcnt = 0;
        #1;

        for (i = 0; i < DEPTH + 2; i = i + 1) begin
            cyc;
            drive_push(32'h5000 + i);
        end
        cyc;
        `CHK(level === DEPTH[3:0],              "T6.1 overflow level saturates at DEPTH")
        `CHK(top   === (32'h5000 + DEPTH + 1),  "T6.2 overflow top=last pushed")
        drive_idle;

        //------------------------------------------------------------------
        // T7 enable=0：状态保持不变、valid=0
        //------------------------------------------------------------------
        cyc;
        enable   = 1'b0;
        push     = 1'b1;
        pop      = 1'b0;
        ret_addr = 32'h7777;
        #1;
        cyc;
        `CHK(valid === 1'b0, "T7.1 disabled valid=0")
        enable = 1'b1;
        push   = 1'b0;
        #1;
        cyc;
        `CHK(top !== 32'h7777, "T7.2 disabled push did not modify stack")

        //------------------------------------------------------------------
        // T8 随机压测：与黄金模型逐拍比对
        //------------------------------------------------------------------
        reset = 1'b1;
        repeat (2) cyc;
        reset  = 1'b0;
        enable = 1'b1;
        gwp    = 0;
        gcnt   = 0;
        mism   = 0;
        drive_idle;

        for (i = 0; i < 800; i = i + 1) begin
            cyc;
            // 先检查：此刻状态是上一拍驱动被锁存后的结果
            if (valid !== (enable && (gcnt != 0))) begin
                mism = mism + 1;
                if (mism <= 5) $display("  T8 valid mismatch cyc=%0d dut=%b model=%0d", i, valid, gcnt);
            end
            if (level !== gcnt[3:0]) begin
                mism = mism + 1;
                if (mism <= 5) $display("  T8 level mismatch cyc=%0d dut=%0d model=%0d", i, level, gcnt);
            end
            if (gcnt != 0 && enable && (top !== gold[(gwp - 1 + DEPTH) % DEPTH])) begin
                mism = mism + 1;
                if (mism <= 5) $display("  T8 top mismatch cyc=%0d dut=%h model=%h",
                                        i, top, gold[(gwp - 1 + DEPTH) % DEPTH]);
            end
            // 再驱动本拍
            enable   = ((({$random} % 10) + 10) % 10) < 9;    // 90%
            push     = ((({$random} % 10) + 10) % 10) < 4;    // 40%
            pop      = ((({$random} % 10) + 10) % 10) < 4;    // 40%
            ret_addr = {$random} % 32'h0001_0000;
            #1;
            // 模型按同一规则推进（pop 优先，与 RTL 一致）
            if (enable && pop)               g_pop;
            else if (enable && push && !pop) g_push(ret_addr);
        end
        `CHK(mism == 0, "T8.1 random: DUT matches golden model")

        //------------------------------------------------------------------
        $display("----------------------------------------------------------");
        if (errors == 0) $display("ALL TEST PASS");
        else             $display("TEST FAIL count=%0d", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("TEST TIMEOUT FAIL");
        $finish;
    end

endmodule
