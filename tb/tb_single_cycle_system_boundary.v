`timescale 1ns/1ps

module tb_single_cycle_system_boundary;
    reg clk;
    reg reset;
    integer failures;

    core_harness #(
        .IMEM_DEPTH(17),
        .IMEM_INIT_FILE("tb/data/system_boundary.mem")
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

    task expect_bit;
        input actual;
        input expected;
        input integer test_number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected=%b actual=%b", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task check_no_side_effect;
        input expected_illegal;
        input integer test_base;
        begin
            expect_bit(dut.core.illegal,             expected_illegal, test_base);
            expect_bit(dut.core.reg_write_effective, 1'b0,             test_base + 1);
            expect_bit(dut.core.store_complete,      1'b0,             test_base + 2);
        end
    endtask

    task wait_for_instruction;
        input [31:0] expected_pc;
        integer guard;
        begin
            guard = 0;
            while (((dut.core.pc !== expected_pc) || (dut.core.if_state !== dut.core.IF_DONE)) && (guard < 200)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (guard == 200) begin
                $display("TIMEOUT waiting for PC=%h", expected_pc);
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

        // Execute setup and the first store, then inspect each system encoding
        // before its active edge.  Every checked instruction must be side-effect free.
        wait_for_instruction(32'd12); // FENCE RW,RW
        check_no_side_effect(1'b0, 1);

        wait_for_instruction(32'd20); // FENCE I,O
        check_no_side_effect(1'b0, 4);

        wait_for_instruction(32'd28); // reserved FENCE fields
        check_no_side_effect(1'b0, 7);

        wait_for_instruction(32'd36); // FENCE.I
        check_no_side_effect(1'b1, 10);

        wait_for_instruction(32'd44); // ECALL
        check_no_side_effect(1'b1, 13);

        wait_for_instruction(32'd52); // EBREAK
        check_no_side_effect(1'b1, 16);

        wait_for_instruction(32'd60); // unsupported opcode
        check_no_side_effect(1'b1, 19);

        // First edge retires the unsupported opcode at PC=60; the second
        // retires the final marker ADDI at PC=64.
        wait_for_instruction(32'd64);
        @(posedge clk);
        #1;

        // Each marker ADDI after a checked instruction proves PC advanced by four.
        expect_word(dut.core.u_regfile.regs[1], 32'h00000055, 22);
        expect_word(dut.core.u_regfile.regs[2], 32'h00000044, 23);
        expect_word(dut.ram.mem[0],     32'h00000044, 24);
        expect_word(dut.core.u_regfile.regs[3], 32'h00000056, 25);
        expect_word(dut.core.u_regfile.regs[4], 32'h00000057, 26);
        expect_word(dut.core.u_regfile.regs[5], 32'h00000058, 27);
        expect_word(dut.core.u_regfile.regs[6], 32'h00000059, 28);
        expect_word(dut.core.u_regfile.regs[7], 32'h0000005a, 29);
        expect_word(dut.core.u_regfile.regs[8], 32'h0000005b, 30);
        expect_word(dut.core.u_regfile.regs[9], 32'h0000005c, 31);
        expect_word(dut.core.pc,                32'd68,       32);

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
