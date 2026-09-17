`timescale 1ns/1ps

module tb_single_cycle_cpu;
    reg clk;
    reg reset;
    integer failures;

    task15_core_harness #(
        .IMEM_DEPTH(12),
        .IMEM_INIT_FILE("tb/data/task11_single_cycle.mem")
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

        // Keep reset asserted across two rising edges, then start from PC=0.
        repeat (2) @(negedge clk);
        reset = 1'b0;

        // Ten retired instructions execute: BEQ and JAL each skip one word.
        repeat (50) @(posedge clk);
        #1;

        expect_word(dut.core.u_regfile.regs[1], 32'd5,  1);
        expect_word(dut.core.u_regfile.regs[2], 32'd10, 2);
        expect_word(dut.core.u_regfile.regs[3], 32'd15, 3);
        expect_word(dut.ram.mem[0],     32'd15, 4);
        expect_word(dut.core.u_regfile.regs[4], 32'd15, 5);
        expect_word(dut.core.u_regfile.regs[5], 32'd10, 6);
        expect_word(dut.core.u_regfile.regs[6], 32'd0,  7);
        expect_word(dut.core.u_regfile.regs[7], 32'd40, 8);
        expect_word(dut.ram.mem[1],     32'd10, 9);
        expect_word(dut.core.pc,                32'd48, 10);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "TEST timeout: CPU did not finish within 500 ns");
    end
endmodule
