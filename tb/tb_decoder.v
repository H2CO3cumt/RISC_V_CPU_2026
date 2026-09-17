`timescale 1ns/1ps

module tb_decoder;
    reg  [31:0] instruction;
    wire        reg_write;
    wire        alu_src_a;
    wire        alu_src_b;
    wire [3:0]  alu_ctrl;
    wire        mem_read;
    wire        mem_write;
    wire [1:0]  result_src;
    wire        branch;
    wire        jump;
    wire        jalr;
    wire        illegal;
    integer     failures;

    decoder dut (
        .instruction(instruction),
        .reg_write(reg_write),
        .alu_src_a(alu_src_a),
        .alu_src_b(alu_src_b),
        .alu_ctrl(alu_ctrl),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .result_src(result_src),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .illegal(illegal)
    );

    task check_control;
        input [6:0] opcode_value;
        input [2:0] funct3_value;
        input [6:0] funct7_value;
        input       expected_reg_write;
        input       expected_alu_src_a;
        input       expected_alu_src_b;
        input [3:0] expected_alu_ctrl;
        input       expected_mem_read;
        input       expected_mem_write;
        input [1:0] expected_result_src;
        input       expected_branch;
        input       expected_jump;
        input       expected_jalr;
        input       expected_illegal;
        input integer test_number;
        begin
            instruction = {
                funct7_value,
                5'd2,
                5'd1,
                funct3_value,
                5'd3,
                opcode_value
            };
            #1;
            if ({
                reg_write,
                alu_src_a,
                alu_src_b,
                alu_ctrl,
                mem_read,
                mem_write,
                result_src,
                branch,
                jump,
                jalr,
                illegal
            } === {
                expected_reg_write,
                expected_alu_src_a,
                expected_alu_src_b,
                expected_alu_ctrl,
                expected_mem_read,
                expected_mem_write,
                expected_result_src,
                expected_branch,
                expected_jump,
                expected_jalr,
                expected_illegal
            }) begin
                $display("TEST %0d PASS", test_number);
            end
            else begin
                $display(
                    "TEST %0d FAIL: instr=%h op=%b f3=%b f7=%b",
                    test_number, instruction, opcode_value, funct3_value, funct7_value
                );
                $display(
                    "  expected rw=%b a=%b b=%b alu=%b mr=%b mw=%b res=%b br=%b j=%b jr=%b ill=%b",
                    expected_reg_write, expected_alu_src_a, expected_alu_src_b,
                    expected_alu_ctrl, expected_mem_read, expected_mem_write,
                    expected_result_src, expected_branch, expected_jump,
                    expected_jalr, expected_illegal
                );
                $display(
                    "  actual   rw=%b a=%b b=%b alu=%b mr=%b mw=%b res=%b br=%b j=%b jr=%b ill=%b",
                    reg_write, alu_src_a, alu_src_b, alu_ctrl, mem_read,
                    mem_write, result_src, branch, jump, jalr, illegal
                );
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        instruction = 32'b0;
        failures = 0;

        // R-Type: all ten RV32I ALU operations.
        check_control(7'b0110011, 3'b000, 7'b0000000, 1, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 0, 1);  // ADD
        check_control(7'b0110011, 3'b000, 7'b0100000, 1, 0, 0, 4'b0001, 0, 0, 2'b00, 0, 0, 0, 0, 2);  // SUB
        check_control(7'b0110011, 3'b111, 7'b0000000, 1, 0, 0, 4'b0010, 0, 0, 2'b00, 0, 0, 0, 0, 3);  // AND
        check_control(7'b0110011, 3'b110, 7'b0000000, 1, 0, 0, 4'b0011, 0, 0, 2'b00, 0, 0, 0, 0, 4);  // OR
        check_control(7'b0110011, 3'b100, 7'b0000000, 1, 0, 0, 4'b0100, 0, 0, 2'b00, 0, 0, 0, 0, 5);  // XOR
        check_control(7'b0110011, 3'b001, 7'b0000000, 1, 0, 0, 4'b0101, 0, 0, 2'b00, 0, 0, 0, 0, 6);  // SLL
        check_control(7'b0110011, 3'b101, 7'b0000000, 1, 0, 0, 4'b0110, 0, 0, 2'b00, 0, 0, 0, 0, 7);  // SRL
        check_control(7'b0110011, 3'b101, 7'b0100000, 1, 0, 0, 4'b0111, 0, 0, 2'b00, 0, 0, 0, 0, 8);  // SRA
        check_control(7'b0110011, 3'b010, 7'b0000000, 1, 0, 0, 4'b1000, 0, 0, 2'b00, 0, 0, 0, 0, 9);  // SLT
        check_control(7'b0110011, 3'b011, 7'b0000000, 1, 0, 0, 4'b1001, 0, 0, 2'b00, 0, 0, 0, 0, 10); // SLTU
        check_control(7'b0110011, 3'b111, 7'b0100000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 11); // illegal AND encoding
        check_control(7'b0110011, 3'b000, 7'b0000001, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 12); // unsupported M encoding

        // OP-IMM: normal immediates accept arbitrary imm[11:5]; shifts check funct7.
        check_control(7'b0010011, 3'b000, 7'b1111111, 1, 0, 1, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 0, 13); // ADDI -1-like high bits
        check_control(7'b0010011, 3'b010, 7'b1010101, 1, 0, 1, 4'b1000, 0, 0, 2'b00, 0, 0, 0, 0, 14); // SLTI
        check_control(7'b0010011, 3'b011, 7'b0110011, 1, 0, 1, 4'b1001, 0, 0, 2'b00, 0, 0, 0, 0, 15); // SLTIU
        check_control(7'b0010011, 3'b100, 7'b1100110, 1, 0, 1, 4'b0100, 0, 0, 2'b00, 0, 0, 0, 0, 16); // XORI
        check_control(7'b0010011, 3'b110, 7'b0011001, 1, 0, 1, 4'b0011, 0, 0, 2'b00, 0, 0, 0, 0, 17); // ORI
        check_control(7'b0010011, 3'b111, 7'b1001100, 1, 0, 1, 4'b0010, 0, 0, 2'b00, 0, 0, 0, 0, 18); // ANDI
        check_control(7'b0010011, 3'b001, 7'b0000000, 1, 0, 1, 4'b0101, 0, 0, 2'b00, 0, 0, 0, 0, 19); // SLLI
        check_control(7'b0010011, 3'b101, 7'b0000000, 1, 0, 1, 4'b0110, 0, 0, 2'b00, 0, 0, 0, 0, 20); // SRLI
        check_control(7'b0010011, 3'b101, 7'b0100000, 1, 0, 1, 4'b0111, 0, 0, 2'b00, 0, 0, 0, 0, 21); // SRAI
        check_control(7'b0010011, 3'b001, 7'b0100000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 22); // illegal SLLI
        check_control(7'b0010011, 3'b101, 7'b0010000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 23); // illegal right shift

        // Load: five legal and all three illegal funct3 values.
        check_control(7'b0000011, 3'b000, 7'b1111111, 1, 0, 1, 4'b0000, 1, 0, 2'b01, 0, 0, 0, 0, 24); // LB
        check_control(7'b0000011, 3'b001, 7'b1010101, 1, 0, 1, 4'b0000, 1, 0, 2'b01, 0, 0, 0, 0, 25); // LH
        check_control(7'b0000011, 3'b010, 7'b0000000, 1, 0, 1, 4'b0000, 1, 0, 2'b01, 0, 0, 0, 0, 26); // LW
        check_control(7'b0000011, 3'b100, 7'b0101010, 1, 0, 1, 4'b0000, 1, 0, 2'b01, 0, 0, 0, 0, 27); // LBU
        check_control(7'b0000011, 3'b101, 7'b0011001, 1, 0, 1, 4'b0000, 1, 0, 2'b01, 0, 0, 0, 0, 28); // LHU
        check_control(7'b0000011, 3'b011, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 29);
        check_control(7'b0000011, 3'b110, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 30);
        check_control(7'b0000011, 3'b111, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 31);

        // Store: three legal and all five illegal funct3 values.
        check_control(7'b0100011, 3'b000, 7'b1111111, 0, 0, 1, 4'b0000, 0, 1, 2'b00, 0, 0, 0, 0, 32); // SB
        check_control(7'b0100011, 3'b001, 7'b1010101, 0, 0, 1, 4'b0000, 0, 1, 2'b00, 0, 0, 0, 0, 33); // SH
        check_control(7'b0100011, 3'b010, 7'b0000000, 0, 0, 1, 4'b0000, 0, 1, 2'b00, 0, 0, 0, 0, 34); // SW
        check_control(7'b0100011, 3'b011, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 35);
        check_control(7'b0100011, 3'b100, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 36);
        check_control(7'b0100011, 3'b101, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 37);
        check_control(7'b0100011, 3'b110, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 38);
        check_control(7'b0100011, 3'b111, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 39);

        // Branch: six legal and both illegal funct3 values.
        check_control(7'b1100011, 3'b000, 7'b0000000, 0, 1, 1, 4'b0000, 0, 0, 2'b00, 1, 0, 0, 0, 40); // BEQ
        check_control(7'b1100011, 3'b001, 7'b1111111, 0, 1, 1, 4'b0000, 0, 0, 2'b00, 1, 0, 0, 0, 41); // BNE
        check_control(7'b1100011, 3'b100, 7'b0101010, 0, 1, 1, 4'b0000, 0, 0, 2'b00, 1, 0, 0, 0, 42); // BLT
        check_control(7'b1100011, 3'b101, 7'b1010101, 0, 1, 1, 4'b0000, 0, 0, 2'b00, 1, 0, 0, 0, 43); // BGE
        check_control(7'b1100011, 3'b110, 7'b0011001, 0, 1, 1, 4'b0000, 0, 0, 2'b00, 1, 0, 0, 0, 44); // BLTU
        check_control(7'b1100011, 3'b111, 7'b1100110, 0, 1, 1, 4'b0000, 0, 0, 2'b00, 1, 0, 0, 0, 45); // BGEU
        check_control(7'b1100011, 3'b010, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 46);
        check_control(7'b1100011, 3'b011, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 47);

        // JAL accepts arbitrary immediate bits; JALR only accepts funct3 000.
        check_control(7'b1101111, 3'b000, 7'b0000000, 1, 1, 1, 4'b0000, 0, 0, 2'b10, 0, 1, 0, 0, 48);
        check_control(7'b1101111, 3'b111, 7'b1111111, 1, 1, 1, 4'b0000, 0, 0, 2'b10, 0, 1, 0, 0, 49);
        check_control(7'b1100111, 3'b000, 7'b1111111, 1, 0, 1, 4'b0000, 0, 0, 2'b10, 0, 1, 1, 0, 50);
        check_control(7'b1100111, 3'b001, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 51);
        check_control(7'b1100111, 3'b010, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 52);
        check_control(7'b1100111, 3'b011, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 53);
        check_control(7'b1100111, 3'b100, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 54);
        check_control(7'b1100111, 3'b101, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 55);
        check_control(7'b1100111, 3'b110, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 56);
        check_control(7'b1100111, 3'b111, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 57);

        // U-Type accepts arbitrary immediate bit patterns.
        check_control(7'b0110111, 3'b000, 7'b0000000, 1, 0, 0, 4'b0000, 0, 0, 2'b11, 0, 0, 0, 0, 58); // LUI
        check_control(7'b0110111, 3'b111, 7'b1111111, 1, 0, 0, 4'b0000, 0, 0, 2'b11, 0, 0, 0, 0, 59); // LUI arbitrary imm
        check_control(7'b0010111, 3'b000, 7'b0000000, 1, 1, 1, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 0, 60); // AUIPC
        check_control(7'b0010111, 3'b111, 7'b1111111, 1, 1, 1, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 0, 61); // AUIPC arbitrary imm

        // Unsupported opcodes must have no architectural side effects.
        check_control(7'b0000000, 3'b000, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 62);
        check_control(7'b1111111, 3'b111, 7'b1111111, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 63);
        check_control(7'b0000111, 3'b010, 7'b0000000, 0, 0, 0, 4'b0000, 0, 0, 2'b00, 0, 0, 0, 1, 64); // unsupported LOAD-FP

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $display("ALL TEST FAIL: %0d failure(s)", failures);

        $finish;
    end
endmodule
