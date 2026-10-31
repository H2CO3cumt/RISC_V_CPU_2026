`timescale 1ns/1ps

module tb_branch_predictor;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b1;
    reg [31:0] query_pc = 32'b0;
    reg update_valid = 1'b0;
    reg [31:0] update_pc = 32'b0;
    reg update_taken = 1'b0;
    reg update_is_jump = 1'b0;
    reg [31:0] update_target = 32'b0;
    wire query_hit;
    wire predicted_taken;
    wire [31:0] predicted_target;
    integer failures = 0;

    branch_predictor dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .query_pc(query_pc),
        .query_hit(query_hit),
        .predicted_taken(predicted_taken),
        .predicted_target(predicted_target),
        .update_valid(update_valid),
        .update_pc(update_pc),
        .update_taken(update_taken),
        .update_is_jump(update_is_jump),
        .update_target(update_target)
    );

    always #5 clk = ~clk;

    task expect_prediction;
        input [31:0] pc;
        input expected_hit;
        input expected_taken;
        input [31:0] expected_target;
        begin
            query_pc = pc;
            #1;
            if (query_hit !== expected_hit ||
                predicted_taken !== expected_taken ||
                (expected_hit && predicted_target !== expected_target)) begin
                $display("TEST predictor FAIL pc=%h hit=%b taken=%b target=%h",
                         pc, query_hit, predicted_taken, predicted_target);
                failures = failures + 1;
            end
            else begin
                $display("TEST predictor PASS pc=%h", pc);
            end
        end
    endtask

    task update_branch;
        input [31:0] pc;
        input taken;
        input [31:0] branch_target;
        begin
            @(negedge clk);
            update_valid = 1'b1;
            update_pc = pc;
            update_taken = taken;
            update_is_jump = 1'b0;
            update_target = branch_target;
            @(posedge clk);
            #1;
            update_valid = 1'b0;
        end
    endtask

    task update_jump;
        input [31:0] pc;
        input [31:0] jump_target;
        begin
            @(negedge clk);
            update_valid = 1'b1;
            update_pc = pc;
            update_taken = 1'b1;
            update_is_jump = 1'b1;
            update_target = jump_target;
            @(posedge clk);
            #1;
            update_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;

        expect_prediction(32'h0000_0040, 1'b0, 1'b0, 32'b0);
        update_branch(32'h0000_0040, 1'b1, 32'h0000_0020);
        expect_prediction(32'h0000_0040, 1'b1, 1'b1, 32'h0000_0020);

        // 10 -> 11 饱和，随后两次不跳转依次回到 10、01。
        update_branch(32'h0000_0040, 1'b1, 32'h0000_0020);
        update_branch(32'h0000_0040, 1'b1, 32'h0000_0020);
        expect_prediction(32'h0000_0040, 1'b1, 1'b1, 32'h0000_0020);
        update_branch(32'h0000_0040, 1'b0, 32'h0000_0020);
        expect_prediction(32'h0000_0040, 1'b1, 1'b1, 32'h0000_0020);
        update_branch(32'h0000_0040, 1'b0, 32'h0000_0020);
        expect_prediction(32'h0000_0040, 1'b1, 1'b0, 32'h0000_0020);

        // 相同索引、不同 tag 必须替换，旧分支随后 miss。
        update_branch(32'h0000_0080, 1'b0, 32'h0000_0090);
        expect_prediction(32'h0000_0080, 1'b1, 1'b0, 32'h0000_0090);
        expect_prediction(32'h0000_0040, 1'b0, 1'b0, 32'b0);

        // 跳转项（JAL/JALR）方向恒为 taken，不看饱和计数器。
        update_jump(32'h0000_0100, 32'h0000_0200);
        expect_prediction(32'h0000_0100, 1'b1, 1'b1, 32'h0000_0200);

        // 同一项改回条件分支后，方向重新交给 2-bit 饱和计数器：
        // 跳转项按 taken 建立计数器为 10，第一次 not-taken 落到 01，
        // 此时 counter[1] 已经是 0，方向立刻变成 not-taken。
        update_branch(32'h0000_0100, 1'b0, 32'h0000_0200);
        expect_prediction(32'h0000_0100, 1'b1, 1'b0, 32'h0000_0200);
        update_branch(32'h0000_0100, 1'b0, 32'h0000_0200);
        expect_prediction(32'h0000_0100, 1'b1, 1'b0, 32'h0000_0200);

        // 再训练两次 taken，计数器回到 11，分支方向恢复 taken —— 说明双向
        // 饱和计数器在分支项上仍按原语义工作，没有被 is_jump 破坏。
        update_branch(32'h0000_0100, 1'b1, 32'h0000_0200);
        update_branch(32'h0000_0100, 1'b1, 32'h0000_0200);
        expect_prediction(32'h0000_0100, 1'b1, 1'b1, 32'h0000_0200);

        // 冲突项被跳转覆盖后，方向和目标都立即跟随跳转项。
        update_jump(32'h0000_0080, 32'h0000_0210);
        expect_prediction(32'h0000_0080, 1'b1, 1'b1, 32'h0000_0210);

        enable = 1'b0;
        expect_prediction(32'h0000_0080, 1'b0, 1'b0, 32'b0);

        if (failures == 0) begin
            $display("ALL BRANCH PREDICTOR TEST PASS");
        end
        else begin
            $fatal(1, "BRANCH PREDICTOR %0d TESTS FAIL", failures);
        end
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "BRANCH PREDICTOR TIMEOUT");
    end
endmodule
