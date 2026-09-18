`timescale 1ns/1ps

module tb_single_cycle_call_return;
    reg clk;
    reg reset;
    integer failures;

    core_harness #(
        .IMEM_DEPTH(7),
        .IMEM_INIT_FILE("tb/data/call_return.mem")
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
        dut.core.u_regfile.regs[11] = 32'b0;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        // JAL x1 calls PC=16 and records link PC=4.  JALR x0,0(x1) returns
        // to PC=4.  The JAL x0 at PC=8 skips the function body after return.
        repeat (24) @(posedge clk);
        #1;

        expect_word(dut.core.u_regfile.regs[1],  32'd4, 1);
        expect_word(dut.core.u_regfile.regs[10], 32'd1, 2);
        expect_word(dut.core.u_regfile.regs[11], 32'd0, 3);
        expect_word(dut.core.u_regfile.regs[12], 32'd7, 4);
        expect_word(dut.core.u_regfile.regs[13], 32'd9, 5);
        expect_word(dut.core.pc,                 32'd28, 6);

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
