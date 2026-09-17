`timescale 1ns/1ps

module tb_alu;
    reg signed [31:0] a;
    reg signed [31:0] b;
    reg        [3:0]  alu_ctrl;
    wire       [31:0] result;
    integer failures;

    alu dut (
        .a(a),
        .b(b),
        .alu_ctrl(alu_ctrl),
        .result(result)
    );

    task check_result;
        input [31:0] expected;
        input integer test_number;
        begin
            #1;
            if (result === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display(
                    "TEST %0d FAIL: ctrl=%b a=%h b=%h expected=%h actual=%h",
                    test_number, alu_ctrl, a, b, expected, result
                );
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        a = 32'd0;
        b = 32'd0;
        alu_ctrl = 4'd0;
        failures = 0;

        // ADD: normal addition and 32-bit wraparound boundaries.
        a = 32'h0000_0001; b = 32'h0000_0002; alu_ctrl = 4'b0000;
        check_result(32'h0000_0003, 1);
        a = 32'h7FFF_FFFF; b = 32'h0000_0001;
        check_result(32'h8000_0000, 2);
        a = 32'hFFFF_FFFF; b = 32'h0000_0001;
        check_result(32'h0000_0000, 3);

        // SUB: normal subtraction, negative result, and wraparound boundary.
        a = 32'h0000_0005; b = 32'h0000_0003; alu_ctrl = 4'b0001;
        check_result(32'h0000_0002, 4);
        a = 32'h0000_0000; b = 32'h0000_0001;
        check_result(32'hFFFF_FFFF, 5);
        a = 32'h8000_0000; b = 32'h0000_0001;
        check_result(32'h7FFF_FFFF, 6);

        // Bitwise logic.
        a = 32'hF0F0_F0F0; b = 32'h0FF0_0FF0; alu_ctrl = 4'b0010;
        check_result(32'h00F0_00F0, 7);
        alu_ctrl = 4'b0011;
        check_result(32'hFFF0_FFF0, 8);
        alu_ctrl = 4'b0100;
        check_result(32'hFF00_FF00, 9);
        a = 32'h0000_0000; b = 32'hFFFF_FFFF; alu_ctrl = 4'b0010;
        check_result(32'h0000_0000, 10);

        // SLL: shift amounts 0 and 31, discarded high bit, and b[4:0] masking.
        a = 32'h0000_0001; b = 32'h0000_0000; alu_ctrl = 4'b0101;
        check_result(32'h0000_0001, 11);
        b = 32'h0000_001F;
        check_result(32'h8000_0000, 12);
        a = 32'hFFFF_FFFF; b = 32'h0000_0001;
        check_result(32'hFFFF_FFFE, 13);
        a = 32'h0000_0001; b = 32'h0000_0020;
        check_result(32'h0000_0001, 14);

        // SRL: zero fill, boundary shift, and zero shift.
        a = 32'h8000_0000; b = 32'h0000_0001; alu_ctrl = 4'b0110;
        check_result(32'h4000_0000, 15);
        a = 32'hFFFF_FFFF; b = 32'h0000_001F;
        check_result(32'h0000_0001, 16);
        a = 32'h7FFF_FFFF; b = 32'h0000_0000;
        check_result(32'h7FFF_FFFF, 17);

        // SRA: sign fill for negatives and zero fill for a positive value.
        a = 32'h8000_0000; b = 32'h0000_0001; alu_ctrl = 4'b0111;
        check_result(32'hC000_0000, 18);
        a = 32'hFFFF_FFFF; b = 32'h0000_001F;
        check_result(32'hFFFF_FFFF, 19);
        a = 32'h7FFF_FFFF; b = 32'h0000_0001;
        check_result(32'h3FFF_FFFF, 20);
        a = 32'h8000_0001; b = 32'h0000_0004;
        check_result(32'hF800_0000, 21);

        // SLT: signed comparisons around zero and the signed extrema.
        a = 32'hFFFF_FFFF; b = 32'h0000_0001; alu_ctrl = 4'b1000;
        check_result(32'h0000_0001, 22);
        a = 32'h0000_0001; b = 32'hFFFF_FFFF;
        check_result(32'h0000_0000, 23);
        a = 32'h8000_0000; b = 32'h7FFF_FFFF;
        check_result(32'h0000_0001, 24);
        a = 32'h0000_0000; b = 32'h0000_0000;
        check_result(32'h0000_0000, 25);

        // SLTU: the same bit patterns interpreted as unsigned values.
        a = 32'hFFFF_FFFF; b = 32'h0000_0001; alu_ctrl = 4'b1001;
        check_result(32'h0000_0000, 26);
        a = 32'h0000_0001; b = 32'hFFFF_FFFF;
        check_result(32'h0000_0001, 27);
        a = 32'h8000_0000; b = 32'h0000_0000;
        check_result(32'h0000_0000, 28);
        a = 32'h0000_0000; b = 32'h8000_0000;
        check_result(32'h0000_0001, 29);
        a = 32'h7FFF_FFFF; b = 32'h7FFF_FFFF;
        check_result(32'h0000_0000, 30);

        // Unsupported control values return the defined safe default.
        a = 32'hFFFF_FFFF; b = 32'hFFFF_FFFF; alu_ctrl = 4'b1111;
        check_result(32'h0000_0000, 31);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $display("ALL TEST FAIL: %0d failure(s)", failures);

        $finish;
    end
endmodule
