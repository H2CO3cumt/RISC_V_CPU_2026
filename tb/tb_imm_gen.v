`timescale 1ns/1ps

module tb_imm_gen;
    reg  [31:0] instruction;
    wire [31:0] imm;
    integer failures;

    imm_gen dut (
        .instruction(instruction),
        .imm(imm)
    );

    task check_imm;
        input [31:0] instruction_value;
        input [31:0] expected;
        input integer test_number;
        begin
            instruction = instruction_value;
            #1;
            if (imm === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display(
                    "TEST %0d FAIL: instruction=%h opcode=%b expected=%h actual=%h",
                    test_number, instruction, instruction[6:0], expected, imm
                );
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        instruction = 32'b0;
        failures = 0;

        // I-Type: zero, positive maximum, negative minimum, and all supported opcodes.
        check_imm(32'h0000_0013, 32'h0000_0000, 1);  // addi: 0
        check_imm(32'h7FF0_0093, 32'h0000_07FF, 2);  // addi: +2047
        check_imm(32'h8000_0093, 32'hFFFF_F800, 3);  // addi: -2048
        check_imm(32'hFFC0_2083, 32'hFFFF_FFFC, 4);  // lw: -4
        check_imm(32'h0060_00E7, 32'h0000_0006, 5);  // jalr: +6

        // S-Type: zero, positive maximum, negative minimum, and -1.
        check_imm(32'h0010_2023, 32'h0000_0000, 6);  // sw: 0
        check_imm(32'h7E10_2FA3, 32'h0000_07FF, 7);  // sw: +2047
        check_imm(32'h8010_2023, 32'hFFFF_F800, 8);  // sw: -2048
        check_imm(32'hFE10_2FA3, 32'hFFFF_FFFF, 9);  // sw: -1

        // B-Type: zero, minimum alignment, forward/backward limits, and -2.
        check_imm(32'h0000_0063, 32'h0000_0000, 10); // beq: 0
        check_imm(32'h0000_0163, 32'h0000_0002, 11); // beq: +2
        check_imm(32'h7E00_0FE3, 32'h0000_0FFE, 12); // beq: +4094
        check_imm(32'h8000_0063, 32'hFFFF_F000, 13); // beq: -4096
        check_imm(32'hFE00_0FE3, 32'hFFFF_FFFE, 14); // beq: -2

        // U-Type: low/high boundary patterns for both LUI and AUIPC.
        check_imm(32'h0000_00B7, 32'h0000_0000, 15); // lui: 0x00000
        check_imm(32'h7FFFF0B7, 32'h7FFF_F000, 16); // lui: 0x7FFFF
        check_imm(32'h8000_0097, 32'h8000_0000, 17); // auipc: 0x80000
        check_imm(32'hFFFF_F0B7, 32'hFFFF_F000, 18); // lui: 0xFFFFF

        // J-Type: zero, minimum alignment, forward/backward limits, and -2.
        check_imm(32'h0000_006F, 32'h0000_0000, 19); // jal: 0
        check_imm(32'h0020_006F, 32'h0000_0002, 20); // jal: +2
        check_imm(32'h7FFF_F06F, 32'h000F_FFFE, 21); // jal: +1048574
        check_imm(32'h8000_006F, 32'hFFF0_0000, 22); // jal: -1048576
        check_imm(32'hFFFF_F06F, 32'hFFFF_FFFE, 23); // jal: -2

        // R-Type and an unsupported opcode must produce the safe default zero.
        check_imm(32'h0020_81B3, 32'h0000_0000, 24); // add
        check_imm(32'hFFFF_FFFF, 32'h0000_0000, 25); // unsupported

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $display("ALL TEST FAIL: %0d failure(s)", failures);

        $finish;
    end
endmodule
