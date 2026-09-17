`timescale 1ns/1ps

module tb_single_cycle_load_align;
    reg clk;
    reg reset;
    integer failures;

    task15_core_harness #(
        .IMEM_DEPTH(7),
        .DMEM_DEPTH(1),
        .IMEM_INIT_FILE("tb/data/task12_load_align.mem")
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

        // LH x2, 1(x1) is misaligned: x2 must retain its sentinel 0x55.
        // The other four loads use natural alignment and must write their results.
        repeat (40) @(posedge clk);
        #1;

        expect_word(dut.core.u_regfile.regs[2], 32'h0000_0055, 1);
        expect_word(dut.core.u_regfile.regs[3], 32'h0000_80FF, 2);
        expect_word(dut.core.u_regfile.regs[4], 32'hFFFF_FF80, 3);
        expect_word(dut.core.u_regfile.regs[5], 32'h0000_0080, 4);
        expect_word(dut.core.u_regfile.regs[6], 32'h80FF_7F01, 5);
        expect_word(dut.core.pc,                32'd28,         6);

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
