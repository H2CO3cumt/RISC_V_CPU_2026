`timescale 1ns/1ps

module tb_single_cycle_jalr;
    reg clk;
    reg reset;
    integer failures;

    task15_core_harness #(
        .IMEM_DEPTH(9),
        .IMEM_INIT_FILE("tb/data/task12_jalr_pc_align.mem")
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

        // PC=0: x1 = 0x21.  PC=4: jalr x5, 0(x1).
        // The target must be 0x20 rather than the unaligned 0x21.
        repeat (2) @(negedge clk);
        reset = 1'b0;

        repeat (12) @(posedge clk);
        #1;

        expect_word(dut.core.u_regfile.regs[5], 32'd8,  1);
        expect_word(dut.core.u_regfile.regs[7], 32'd7,  2);
        expect_word(dut.core.pc,                32'd36, 3);

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
