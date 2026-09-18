`timescale 1ns/1ps

module tb_single_cycle_shift_imm;
    reg clk;
    reg reset;
    integer failures;

    core_harness #(
        .IMEM_DEPTH(5),
        .IMEM_INIT_FILE("tb/data/shift_imm.mem")
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

        repeat (2) @(negedge clk);
        reset = 1'b0;

        // LUI creates 0x8000_0000; SRLI/SRAI expose zero-fill versus sign-fill.
        // SLLI by 31 verifies that the ALU uses the five-bit shamt field.
        repeat (20) @(posedge clk);
        #1;

        expect_word(dut.core.u_regfile.regs[2], 32'h0800_0000, 1);
        expect_word(dut.core.u_regfile.regs[3], 32'hF800_0000, 2);
        expect_word(dut.core.u_regfile.regs[5], 32'h8000_0000, 3);
        expect_word(dut.core.pc,                32'd20,         4);

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
