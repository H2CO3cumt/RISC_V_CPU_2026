`timescale 1ns/1ps

module tb_regfile;
    reg        clk;
    reg [4:0]  rs1_addr;
    reg [4:0]  rs2_addr;
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    reg [4:0]  rd_addr;
    reg [31:0] rd_data;
    reg        rd_we;
    integer    failures;

    regfile dut (
        .clk(clk), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_we(rd_we)
    );

    always #5 clk = ~clk;

    task expect_equal;
        input [31:0] actual;
        input [31:0] expected;
        input integer test_number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected %h, got %h", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        rd_addr = 5'd0;
        rd_data = 32'h0;
        rd_we = 1'b0;
        failures = 0;

        #1;
        expect_equal(rs1_data, 32'h0000_0000, 1);

        // Write and read x1.
        rd_addr = 5'd1;
        rd_data = 32'h1234_5678;
        rd_we = 1'b1;
        @(posedge clk);
        #1;
        rd_we = 1'b0;
        rs1_addr = 5'd1;
        #1;
        expect_equal(rs1_data, 32'h1234_5678, 2);

        // Write x31 and read x1/x31 through independent ports.
        rd_addr = 5'd31;
        rd_data = 32'hCAFE_BABE;
        rd_we = 1'b1;
        @(posedge clk);
        #1;
        rd_we = 1'b0;
        rs1_addr = 5'd1;
        rs2_addr = 5'd31;
        #1;
        expect_equal(rs1_data, 32'h1234_5678, 3);
        expect_equal(rs2_data, 32'hCAFE_BABE, 4);

        // A write to x0 must be ignored, and either read port must see zero.
        rd_addr = 5'd0;
        rd_data = 32'hFFFF_FFFF;
        rd_we = 1'b1;
        @(posedge clk);
        #1;
        rd_we = 1'b0;
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        #1;
        expect_equal(rs1_data, 32'h0000_0000, 5);
        expect_equal(rs2_data, 32'h0000_0000, 6);

        // Before the write edge a read sees the old value; after it, the new value.
        rd_addr = 5'd6;
        rd_data = 32'h0000_0000;
        rd_we = 1'b1;
        @(posedge clk);
        #1;
        rd_data = 32'h0000_0066;
        rs1_addr = 5'd6;
        #1;
        expect_equal(rs1_data, 32'h0000_0000, 7);
        @(posedge clk);
        #1;
        rd_we = 1'b0;
        expect_equal(rs1_data, 32'h0000_0066, 8);

        // Consecutive writes retain their separate values.
        rd_addr = 5'd4;
        rd_data = 32'h4444_4444;
        rd_we = 1'b1;
        @(posedge clk);
        #1;
        rd_addr = 5'd5;
        rd_data = 32'h5555_5555;
        @(posedge clk);
        #1;
        rd_we = 1'b0;
        rs1_addr = 5'd4;
        rs2_addr = 5'd5;
        #1;
        expect_equal(rs1_data, 32'h4444_4444, 9);
        expect_equal(rs2_data, 32'h5555_5555, 10);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $display("ALL TEST FAIL: %0d failure(s)", failures);
        $finish;
    end
endmodule
