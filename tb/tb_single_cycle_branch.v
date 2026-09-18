`timescale 1ns/1ps

module tb_single_cycle_branch;
    reg clk;
    reg reset;
    integer failures;
    integer i;

    core_harness #(
        .IMEM_DEPTH(30),
        .IMEM_INIT_FILE("tb/data/branch.mem")
    ) dut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input integer test_number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected=%h actual=%h", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failures = 0;
        #1;
        // First group: x1=-1, x2=1.  Marker registers start at zero.
        dut.core.u_regfile.regs[1] = 32'hFFFF_FFFF;
        dut.core.u_regfile.regs[2] = 32'h0000_0001;
        for (i = 10; i <= 23; i = i + 1)
            dut.core.u_regfile.regs[i] = 32'b0;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        // Each branch has an ADDI marker on its sequential path.  A taken
        // branch must skip that marker.  The three operand groups cover both
        // outcomes for every RV32I branch condition.
        // 30 static words include seven skipped markers, so this path retires
        // 23 instructions and reaches the first address after the program.
        repeat (92) @(posedge clk);
        #1;

        expect_word(dut.core.u_regfile.regs[10], 32'd1,  1);  // BEQ  not taken
        expect_word(dut.core.u_regfile.regs[11], 32'd0,  2);  // BNE  taken
        expect_word(dut.core.u_regfile.regs[12], 32'd0,  3);  // BLT  taken
        expect_word(dut.core.u_regfile.regs[13], 32'd1,  4);  // BGE  not taken
        expect_word(dut.core.u_regfile.regs[14], 32'd1,  5);  // BLTU not taken
        expect_word(dut.core.u_regfile.regs[15], 32'd0,  6);  // BGEU taken
        expect_word(dut.core.u_regfile.regs[16], 32'd0,  7);  // BEQ  taken
        expect_word(dut.core.u_regfile.regs[17], 32'd1,  8);  // BNE  not taken
        expect_word(dut.core.u_regfile.regs[18], 32'd1,  9);  // BLT  not taken
        expect_word(dut.core.u_regfile.regs[19], 32'd0, 10);  // BGE  taken
        expect_word(dut.core.u_regfile.regs[20], 32'd1, 11);  // BLTU not taken
        expect_word(dut.core.u_regfile.regs[21], 32'd0, 12);  // BGEU taken
        expect_word(dut.core.u_regfile.regs[22], 32'd0, 13);  // BLTU taken
        expect_word(dut.core.u_regfile.regs[23], 32'd1, 14);  // BGEU not taken
        expect_word(dut.core.pc,                32'd120, 15);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "TEST timeout: CPU did not finish within 1000 ns");
    end
endmodule
