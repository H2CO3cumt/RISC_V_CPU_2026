`timescale 1ns/1ps

module tb_imem;
    reg  [31:0] addr;
    wire [31:0] loaded_instruction;
    wire [31:0] blank_instruction;
    wire [31:0] program_instruction;
    integer     failures;

    imem #(
        .DEPTH(4),
        .INIT_FILE("tb/data/imem_test.mem")
    ) loaded_dut (
        .addr(addr),
        .instruction(loaded_instruction)
    );

    imem #(
        .DEPTH(4)
    ) blank_dut (
        .addr(addr),
        .instruction(blank_instruction)
    );

    imem #(
        .DEPTH(17),
        .INIT_FILE("software/task3_hello/build/hello.mem")
    ) program_dut (
        .addr(addr),
        .instruction(program_instruction)
    );

    task check_result;
        input [31:0] addr_value;
        input [31:0] expected_loaded;
        input [31:0] expected_blank;
        input integer test_number;
        begin
            addr = addr_value;
            #1;
            if ((loaded_instruction === expected_loaded) &&
                (blank_instruction === expected_blank)) begin
                $display("TEST %0d PASS", test_number);
            end
            else begin
                $display("TEST %0d FAIL: addr=%h", test_number, addr_value);
                $display("  expected loaded=%h blank=%h", expected_loaded, expected_blank);
                $display("  actual   loaded=%h blank=%h", loaded_instruction, blank_instruction);
                failures = failures + 1;
            end
        end
    endtask

    task check_program;
        input [31:0] addr_value;
        input [31:0] expected_instruction;
        input integer test_number;
        begin
            addr = addr_value;
            #1;
            if (program_instruction === expected_instruction)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: program addr=%h expected=%h actual=%h", test_number, addr_value, expected_instruction, program_instruction);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        addr     = 32'b0;
        failures = 0;

        // Continuous aligned instruction fetches and initialization order.
        check_result(32'h0000_0000, 32'h0050_0093, 32'b0, 1);
        check_result(32'h0000_0004, 32'h00A0_0113, 32'b0, 2);
        check_result(32'h0000_0008, 32'h0020_81B3, 32'b0, 3);
        check_result(32'h0000_000C, 32'h0030_2023, 32'b0, 4);

        // Misaligned addresses must not alias an aligned instruction word.
        check_result(32'h0000_0001, 32'b0, 32'b0, 5);
        check_result(32'h0000_0006, 32'b0, 32'b0, 6);
        check_result(32'h0000_000F, 32'b0, 32'b0, 7);

        // DEPTH=4 makes 0x10 and all larger word addresses out of range.
        check_result(32'h0000_0010, 32'b0, 32'b0, 8);
        check_result(32'hFFFF_FFFC, 32'b0, 32'b0, 9);

        // GNU objcopy Verilog format: @ address records and multiple words per line.
        check_program(32'h0000_0000, 32'h0100_00EF, 10);
        check_program(32'h0000_0010, 32'hFF01_0113, 11);
        check_program(32'h0000_0040, 32'h0000_006F, 12);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end
endmodule
