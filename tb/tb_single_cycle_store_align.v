`timescale 1ns/1ps

module tb_single_cycle_store_align;
    reg clk;
    reg reset;
    integer failures;

    core_harness #(
        .IMEM_DEPTH(14),
        .DMEM_DEPTH(1),
        .IMEM_INIT_FILE("tb/data/store_align.mem")
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
        dut.ram.mem[0] = 32'h80FF_7F01;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        // SB at A+2, SH at A+0, SH at A+2, SW at A, then misaligned SH at A+1.
        repeat (16) @(posedge clk);
        #1;
        expect_word(dut.ram.mem[0], 32'h80AA_7F01, 1);

        repeat (16) @(posedge clk);
        #1;
        expect_word(dut.ram.mem[0], 32'h80AA_BEEF, 2);

        repeat (16) @(posedge clk);
        #1;
        expect_word(dut.ram.mem[0], 32'h1234_BEEF, 3);

        repeat (16) @(posedge clk);
        #1;
        expect_word(dut.ram.mem[0], 32'h5566_7788, 4);

        repeat (4) @(posedge clk);
        #1;
        expect_word(dut.ram.mem[0], 32'h5566_7788, 5);
        expect_word(dut.core.pc,            32'd56,         6);

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
