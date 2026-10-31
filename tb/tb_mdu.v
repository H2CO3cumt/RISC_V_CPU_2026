`timescale 1ns/1ps

// rtl/mdu.v 的独立 Testbench。
//
// 两条通路的握手不一样，分开验：
//   乘法组：拍数由 RTL 参数 MUL_LAT 决定（编译期用 -DMUL_LAT=n 选择，默认 3）：
//            3 = 锁操作数 1 拍 + 串联部分积 1 拍 + 出结果 1 拍（挡 2 拍）
//            2 = 锁操作数与 4 个并联部分积同拍 + 出结果 1 拍（挡 1 拍）
//            1 = 全组合，不占状态机（挡 0 拍，`busy` 必须恒 0）
//   除法组 = 32 拍迭代：run=1 起拍，busy 落下那一拍读结果。
// 每条运算都检查"结果正确"和"到底花了多少拍"，后者用于锁住周期数约定
//（流水线对它的依赖是"停顿必须是有限且确定的"）。
// 三种 MUL_LAT 用的是**同一份手算期望值**：这是"延迟可调、结果不可变"的判据。
`ifndef MUL_LAT
 `define MUL_LAT 2
`endif

module tb_mdu;
    reg         clk;
    reg         reset;

    reg         run;
    reg  [2:0]  op;
    reg  [31:0] a;
    reg  [31:0] b;
    reg         ack;
    wire        busy;
    wire [31:0] result;

    integer failures;
    integer div_cycles;
    integer mul_index;

    mdu #(.MUL_LAT(`MUL_LAT)) dut (
        .clk(clk),
        .reset(reset),
        .run(run),
        .op(op),
        .a(a),
        .b(b),
        .ack(ack),
        .busy(busy),
        .result(result)
    );

    always #5 clk = ~clk;

    initial $display("MDU CONFIG mul_lat=%0d", `MUL_LAT);

    // 一次完整的"锁操作数 -> 算部分积 -> 读结果 -> 消费"握手。
    //
    // 所有激励都在 **negedge** 上改变：如果在 posedge 之后立刻用阻塞赋值改 ack/run，
    // 就和 DUT 在同一个沿上的采样形成竞争（实测表现为"ack 没被看到"，
    // 于是第二条乘法沿用第一条的结果）。测试平台的时序纪律必须比 RTL 更严。
    task check_mul;
        input [2:0]  mop;
        input [31:0] x;
        input [31:0] y;
        input [31:0] expected;
        input integer n;
        begin
            @(negedge clk);
            op = mop; a = x; b = y; run = 1'b1;
            #1;
            if (`MUL_LAT == 1) begin
                // 全组合模式：乘法不进状态机，这一拍就必须"不忙 + 结果正确"。
                if (busy !== 1'b0) begin
                    $display("TEST %0d FAIL: combinational mul asserted busy", n);
                    failures = failures + 1;
                end
                if (result !== expected) begin
                    $display("TEST %0d FAIL: op=%b a=%h b=%h expected=%h actual=%h",
                             n, mop, x, y, expected, result);
                    failures = failures + 1;
                end else begin
                    $display("TEST %0d PASS", n);
                end
            end else begin
                // 第 1 拍：锁操作数，必须挡住流水线。
                if (busy !== 1'b1) begin
                    $display("TEST %0d FAIL: mul latch cycle not busy", n);
                    failures = failures + 1;
                end
                if (`MUL_LAT == 3) begin
                    @(posedge clk);
                    #1;
                    // 基线第 2 拍：算 16x32 部分积，这一拍同样必须忙（结果还没出来）。
                    if (busy !== 1'b1) begin
                        $display("TEST %0d FAIL: mul partial-product cycle not busy", n);
                        failures = failures + 1;
                    end
                end
                @(posedge clk);
                #1;
                // 出结果那一拍：结果有效，且不再忙。
                if (result === expected) begin
                    $display("TEST %0d PASS", n);
                end else begin
                    $display("TEST %0d FAIL: op=%b a=%h b=%h expected=%h actual=%h",
                             n, mop, x, y, expected, result);
                    failures = failures + 1;
                end
                if (busy !== 1'b0) begin
                    $display("TEST %0d FAIL: mul result cycle still busy", n);
                    failures = failures + 1;
                end
            end
            @(negedge clk); ack = 1'b1;
            @(posedge clk);
            @(negedge clk); ack = 1'b0; run = 1'b0;
            @(posedge clk);
        end
    endtask

    // 起拍一次除法，等 busy 落下，检查结果与拍数。
    task check_div;
        input [2:0]  dop;
        input [31:0] x;
        input [31:0] y;
        input [31:0] expected;
        input integer n;
        begin
            @(negedge clk);
            op = dop;
            a  = x;
            b  = y;
            run    = 1'b1;
            div_cycles = 0;
            @(posedge clk);
            while (busy) begin
                @(posedge clk);
                div_cycles = div_cycles + 1;
            end
            #1;
            if (result === expected) begin
                $display("TEST %0d PASS (busy_cycles=%0d)", n, div_cycles + 1);
            end else begin
                $display("TEST %0d FAIL: op=%b a=%h b=%h expected=%h actual=%h",
                         n, dop, x, y, expected, result);
                failures = failures + 1;
            end
            if (div_cycles + 1 > 34) begin
                $display("TEST %0d FAIL: divide took %0d cycles (>34)", n, div_cycles + 1);
                failures = failures + 1;
            end
            // 消费握手：ack 一拍表示"这条指令被流水线收走了"。
            @(negedge clk); ack = 1'b1;
            @(posedge clk);
            @(negedge clk); ack = 1'b0; run = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        run = 1'b0; op = 3'b000; a = 32'b0; b = 32'b0; ack = 1'b0;
        failures = 0;
        mul_index = 0;

        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        //---------------------------------------------------------------
        // MUL：低 32 位与有符号/无符号无关
        //---------------------------------------------------------------
        check_mul(3'b000, 32'd7,           32'd3,           32'd21,          1);
        check_mul(3'b000, 32'hFFFF_FFF9,   32'd3,           32'hFFFF_FFEB,   2); // -7*3
        check_mul(3'b000, 32'd7,           32'hFFFF_FFFD,   32'hFFFF_FFEB,   3); // 7*-3
        check_mul(3'b000, 32'hFFFF_FFF9,   32'hFFFF_FFFD,   32'd21,          4); // -7*-3
        check_mul(3'b000, 32'h8000_0000,   32'h8000_0000,   32'h0000_0000,   5); // 低 32 位为 0
        check_mul(3'b000, 32'hFFFF_FFFF,   32'hFFFF_FFFF,   32'h0000_0001,   6);
        check_mul(3'b000, 32'h1234_5678,   32'd0,           32'h0000_0000,   7);

        //---------------------------------------------------------------
        // MULH：有符号 x 有符号，取高 32 位
        //---------------------------------------------------------------
        check_mul(3'b001, 32'hFFFF_FFF9,   32'd3,           32'hFFFF_FFFF,   8); // high(-21)
        check_mul(3'b001, 32'h8000_0000,   32'h8000_0000,   32'h4000_0000,   9); // 2^62
        check_mul(3'b001, 32'hFFFF_FFFF,   32'hFFFF_FFFF,   32'h0000_0000,  10); // (-1)*(-1)=1
        check_mul(3'b001, 32'h7FFF_FFFF,   32'h7FFF_FFFF,   32'h3FFF_FFFF,  11);
        check_mul(3'b001, 32'h0000_0000,   32'hFFFF_FFFF,   32'h0000_0000,  12);

        //---------------------------------------------------------------
        // MULHSU：rs1 有符号 x rs2 无符号
        //---------------------------------------------------------------
        check_mul(3'b010, 32'hFFFF_FFFF,   32'hFFFF_FFFF,   32'hFFFF_FFFF,  13); // -1 * 4294967295
        check_mul(3'b010, 32'h8000_0000,   32'hFFFF_FFFF,   32'h8000_0000,  14);
        check_mul(3'b010, 32'h0000_0002,   32'h8000_0000,   32'h0000_0001,  15); // 2 * 2^31 = 2^32

        //---------------------------------------------------------------
        // MULHU：双无符号
        //---------------------------------------------------------------
        check_mul(3'b011, 32'hFFFF_FFFF,   32'hFFFF_FFFF,   32'hFFFF_FFFE,  16);
        check_mul(3'b011, 32'h8000_0000,   32'h0000_0002,   32'h0000_0001,  17);
        check_mul(3'b011, 32'h0000_0001,   32'h0000_0001,   32'h0000_0000,  18);

        //---------------------------------------------------------------
        // 背靠背：run 始终为 1，ack 与"换下一条指令"同拍发生（流水线就是这个时序）。
        // 这一条专门盯住"第二条沿用第一条结果"这一类错误。
        //---------------------------------------------------------------
        op = 3'b000; a = 32'h0000_0003; b = 32'h0000_0005; run = 1'b1;
        if      (`MUL_LAT == 1) ;
        else if (`MUL_LAT == 2) repeat (1) @(posedge clk);
        else                    repeat (2) @(posedge clk);   // 第 1 拍锁、第 2 拍算部分积
        #1;
        if (result !== 32'h0000_000F) begin
            $display("TEST 19 FAIL: back-to-back first result=%h want=0000000f", result);
            failures = failures + 1;
        end else $display("TEST 19 PASS (back-to-back first)");
        @(negedge clk);
        ack = 1'b1; a = 32'h0000_0007; b = 32'h0000_0009;   // 同拍换上下一条（7*9=63）
        if (`MUL_LAT == 1) begin
            // 全组合：换操作数当拍结果就变，不存在"第二条没起来"这件事。
            #1;
            if (result !== 32'h0000_003F) begin
                $display("TEST 20 FAIL: combinational second result=%h want=0000003f", result);
                failures = failures + 1;
            end else $display("TEST 20 PASS (back-to-back second)");
            @(negedge clk); ack = 1'b0;
        end else begin
            @(posedge clk); #1;
            if (busy !== 1'b1) begin
                $display("TEST 20 FAIL: second mul did not start (busy=0)");
                failures = failures + 1;
            end
            @(negedge clk); ack = 1'b0;
            if (`MUL_LAT == 2) repeat (1) @(posedge clk); else repeat (2) @(posedge clk);
            #1;
            if (result !== 32'h0000_003F) begin
                $display("TEST 20 FAIL: back-to-back second result=%h want=0000003f", result);
                failures = failures + 1;
            end else $display("TEST 20 PASS (back-to-back second)");
        end
        @(negedge clk); ack = 1'b1;
        @(posedge clk);
        @(negedge clk); ack = 1'b0; run = 1'b0;
        @(posedge clk);

        //---------------------------------------------------------------
        // DIV：向零截断，四种符号组合
        //---------------------------------------------------------------
        check_div(3'b100, 32'd20,          32'd6,           32'd3,          21);
        check_div(3'b100, 32'hFFFF_FFEC,   32'd6,           32'hFFFF_FFFD,  22); // -20/6 = -3
        check_div(3'b100, 32'd20,          32'hFFFF_FFFA,   32'hFFFF_FFFD,  23); // 20/-6 = -3
        check_div(3'b100, 32'hFFFF_FFEC,   32'hFFFF_FFFA,   32'd3,          24); // -20/-6 = 3
        check_div(3'b100, 32'd7,           32'd2,           32'd3,          25);
        check_div(3'b100, 32'hFFFF_FFF9,   32'd2,           32'hFFFF_FFFD,  26); // -7/2 = -3（向零）
        check_div(3'b100, 32'hFFFF_FFFF,   32'd1,           32'hFFFF_FFFF,  27); // -1/1

        //---------------------------------------------------------------
        // DIVU
        //---------------------------------------------------------------
        check_div(3'b101, 32'hFFFF_FFFF,   32'd2,           32'h7FFF_FFFF,  28);
        check_div(3'b101, 32'h8000_0000,   32'hFFFF_FFFF,   32'h0000_0000,  29);
        check_div(3'b101, 32'hFFFF_FFFE,   32'h0000_FFFF,   32'h0001_0000,  30); // 65536

        //---------------------------------------------------------------
        // REM：余数符号跟随被除数
        //---------------------------------------------------------------
        check_div(3'b110, 32'd20,          32'd6,           32'd2,          31);
        check_div(3'b110, 32'hFFFF_FFEC,   32'd6,           32'hFFFF_FFFE,  32); // -20%6 = -2
        check_div(3'b110, 32'd20,          32'hFFFF_FFFA,   32'd2,          33); // 20%-6 = 2
        check_div(3'b110, 32'hFFFF_FFEC,   32'hFFFF_FFFA,   32'hFFFF_FFFE,  34); // -20%-6 = -2
        // 注意 0xFFFFFFFE 按有符号是 -2，所以 -2 % 65535 = -2（不是 65534）。
        // 这一条专门盯住"被除数符号"这条通路：大除数 + 负被除数最容易把
        // 绝对值通路和符号回补写反。无符号的同一组操作数见 TEST 45。
        check_div(3'b110, 32'hFFFF_FFFE,   32'h0000_FFFF,   32'hFFFF_FFFE,  35);

        //---------------------------------------------------------------
        // REMU
        //---------------------------------------------------------------
        check_div(3'b111, 32'hFFFF_FFFF,   32'd16,          32'd15,         36);
        check_div(3'b111, 32'h8000_0000,   32'd3,           32'd2,          37);

        //---------------------------------------------------------------
        // 除零与溢出（RISC-V 规定的结果）
        //---------------------------------------------------------------
        check_div(3'b100, 32'h1234_5678,   32'b0,           32'hFFFF_FFFF,  38); // div/0 -> -1
        check_div(3'b101, 32'h1234_5678,   32'b0,           32'hFFFF_FFFF,  39); // divu/0 -> 全 1
        check_div(3'b110, 32'h1234_5678,   32'b0,           32'h1234_5678,  40); // rem/0 -> 被除数
        check_div(3'b111, 32'h1234_5678,   32'b0,           32'h1234_5678,  41);
        check_div(3'b100, 32'h8000_0000,   32'hFFFF_FFFF,   32'h8000_0000,  42); // 溢出
        check_div(3'b110, 32'h8000_0000,   32'hFFFF_FFFF,   32'h0000_0000,  43); // 溢出余数 0

        //---------------------------------------------------------------
        // 取消：迭代中途把 run 落下（模拟 Trap/Redirect 清空 ID/EX），
        // 状态机必须立刻回 IDLE，且不影响下一条除法。
        //---------------------------------------------------------------
        op = 3'b100; a = 32'h0000_2710; b = 32'd7; run = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk); run = 1'b0;
        @(posedge clk);
        #1;
        if (busy !== 1'b0) begin
            $display("TEST 44 FAIL: busy stayed high after cancel");
            failures = failures + 1;
        end else begin
            $display("TEST 44 PASS");
        end
        check_div(3'b100, 32'h0000_2710,   32'd7,           32'd1428,       45); // 取消之后仍能正常算

        // 同一组操作数的无符号版本：4294967294 % 65535 = 65534。
        check_div(3'b111, 32'hFFFF_FFFE,   32'h0000_FFFF,   32'h0000_FFFE,  46);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $display("ALL TEST FAIL: %0d failure(s)", failures);

        $finish;
    end
endmodule
