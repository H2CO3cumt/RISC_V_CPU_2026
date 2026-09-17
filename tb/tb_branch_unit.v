`timescale 1ns/1ps

module tb_branch_unit;
    reg  [31:0] a;
    reg  [31:0] b;
    reg  [2:0]  funct3;
    wire        taken;
    integer     failures;

    branch_unit dut (
        .a(a),
        .b(b),
        .funct3(funct3),
        .taken(taken)
    );

    task check_branch;
        input [31:0] a_value;
        input [31:0] b_value;
        input [2:0]  funct3_value;
        input        expected_taken;
        input integer test_number;
        begin
            a      = a_value;
            b      = b_value;
            funct3 = funct3_value;
            #1;
            if (taken === expected_taken)
                $display("TEST %0d PASS", test_number);
            else begin
                $display(
                    "TEST %0d FAIL: funct3=%b a=%h b=%h expected=%b actual=%b",
                    test_number, funct3, a, b, expected_taken, taken
                );
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        a        = 32'd0;
        b        = 32'd0;
        funct3   = 3'b000;
        failures = 0;

        // BEQ and BNE: equality is independent of signed interpretation.
        check_branch(32'd5,         32'd5,         3'b000, 1'b1,  1);
        check_branch(32'd5,         32'd10,        3'b000, 1'b0,  2);
        check_branch(32'hFFFF_FFFF, 32'hFFFF_FFFF, 3'b000, 1'b1,  3);
        check_branch(32'd5,         32'd5,         3'b001, 1'b0,  4);
        check_branch(32'd5,         32'd10,        3'b001, 1'b1,  5);

        // BLT: signed positive, equality, opposite-sign, and negative pairs.
        check_branch(32'd5,         32'd10,        3'b100, 1'b1,  6);
        check_branch(32'd10,        32'd5,         3'b100, 1'b0,  7);
        check_branch(32'd5,         32'd5,         3'b100, 1'b0,  8);
        check_branch(32'hFFFF_FFFF, 32'd1,         3'b100, 1'b1,  9);
        check_branch(32'd1,         32'hFFFF_FFFF, 3'b100, 1'b0, 10);
        check_branch(32'h8000_0000, 32'h7FFF_FFFF, 3'b100, 1'b1, 11);
        check_branch(32'hFFFF_FFFD, 32'hFFFF_FFFF, 3'b100, 1'b1, 12);
        check_branch(32'hFFFF_FFFF, 32'hFFFF_FFFD, 3'b100, 1'b0, 13);

        // BGE: exact complement of signed less-than, including equality.
        check_branch(32'd5,         32'd10,        3'b101, 1'b0, 14);
        check_branch(32'd10,        32'd5,         3'b101, 1'b1, 15);
        check_branch(32'd5,         32'd5,         3'b101, 1'b1, 16);
        check_branch(32'hFFFF_FFFF, 32'd1,         3'b101, 1'b0, 17);
        check_branch(32'd1,         32'hFFFF_FFFF, 3'b101, 1'b1, 18);
        check_branch(32'h8000_0000, 32'h7FFF_FFFF, 3'b101, 1'b0, 19);

        // BLTU: the same bit patterns interpreted as unsigned values.
        check_branch(32'd5,         32'd10,        3'b110, 1'b1, 20);
        check_branch(32'd10,        32'd5,         3'b110, 1'b0, 21);
        check_branch(32'd5,         32'd5,         3'b110, 1'b0, 22);
        check_branch(32'hFFFF_FFFF, 32'd1,         3'b110, 1'b0, 23);
        check_branch(32'd1,         32'hFFFF_FFFF, 3'b110, 1'b1, 24);
        check_branch(32'h8000_0000, 32'h7FFF_FFFF, 3'b110, 1'b0, 25);

        // BGEU: unsigned greater-than-or-equal, including equality.
        check_branch(32'd5,         32'd10,        3'b111, 1'b0, 26);
        check_branch(32'd10,        32'd5,         3'b111, 1'b1, 27);
        check_branch(32'd5,         32'd5,         3'b111, 1'b1, 28);
        check_branch(32'hFFFF_FFFF, 32'd1,         3'b111, 1'b1, 29);
        check_branch(32'h8000_0000, 32'h7FFF_FFFF, 3'b111, 1'b1, 30);

        // Reserved Branch funct3 values must not take a branch.
        check_branch(32'd0,         32'd0,         3'b010, 1'b0, 31);
        check_branch(32'hFFFF_FFFF, 32'd0,         3'b011, 1'b0, 32);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end
endmodule
