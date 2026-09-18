`timescale 1ns/1ps

module tb_single_cycle_r_type;
    reg clk;
    reg reset;
    integer failures;

    core_harness #(
        .IMEM_DEPTH(13),
        .IMEM_INIT_FILE("tb/data/r_type.mem")
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

        // x1=0x8000_0001 and x2=3.  Every R-Type ALU operation follows.
        repeat (52) @(posedge clk);
        #1;

        expect_word(dut.core.u_regfile.regs[3],  32'h8000_0004,  1); // ADD
        expect_word(dut.core.u_regfile.regs[4],  32'h7FFF_FFFE,  2); // SUB
        expect_word(dut.core.u_regfile.regs[5],  32'h0000_0018,  3); // SLL
        expect_word(dut.core.u_regfile.regs[6],  32'h0000_0001,  4); // SLT
        expect_word(dut.core.u_regfile.regs[7],  32'h0000_0000,  5); // SLTU
        expect_word(dut.core.u_regfile.regs[8],  32'h8000_0002,  6); // XOR
        expect_word(dut.core.u_regfile.regs[9],  32'h1000_0000,  7); // SRL
        expect_word(dut.core.u_regfile.regs[10], 32'hF000_0000,  8); // SRA
        expect_word(dut.core.u_regfile.regs[11], 32'h8000_0003,  9); // OR
        expect_word(dut.core.u_regfile.regs[12], 32'h0000_0001, 10); // AND
        expect_word(dut.core.pc,                 32'd52,        11);

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
