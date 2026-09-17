`timescale 1ns/1ps

module tb_load_store_unit;
    reg  [1:0]  addr_low;
    reg  [2:0]  funct3;
    reg  [31:0] mem_rdata;
    reg  [31:0] store_data;
    reg         is_load;
    reg         is_store;
    wire [31:0] load_data;
    wire [31:0] store_wdata;
    wire [3:0]  store_wstrb;
    wire        misaligned;
    integer     failures;

    load_store_unit dut (
        .addr_low(addr_low), .funct3(funct3), .mem_rdata(mem_rdata),
        .store_data(store_data), .is_load(is_load), .is_store(is_store),
        .load_data(load_data), .store_wdata(store_wdata),
        .store_wstrb(store_wstrb), .misaligned(misaligned)
    );

    task check_result;
        input [1:0]  addr_value;
        input [2:0]  funct3_value;
        input        load_value;
        input        store_value;
        input [31:0] rdata_value;
        input [31:0] store_data_value;
        input [31:0] expected_load_data;
        input [31:0] expected_store_wdata;
        input [3:0]  expected_store_wstrb;
        input        expected_misaligned;
        input integer test_number;
        begin
            addr_low   = addr_value;
            funct3     = funct3_value;
            is_load    = load_value;
            is_store   = store_value;
            mem_rdata  = rdata_value;
            store_data = store_data_value;
            #1;
            if ((load_data === expected_load_data) &&
                (store_wdata === expected_store_wdata) &&
                (store_wstrb === expected_store_wstrb) &&
                (misaligned === expected_misaligned)) begin
                $display("TEST %0d PASS", test_number);
            end
            else begin
                $display("TEST %0d FAIL: addr=%b funct3=%b load=%b store=%b", test_number, addr_low, funct3, is_load, is_store);
                $display("  expected load=%h wdata=%h wstrb=%b misaligned=%b", expected_load_data, expected_store_wdata, expected_store_wstrb, expected_misaligned);
                $display("  actual   load=%h wdata=%h wstrb=%b misaligned=%b", load_data, store_wdata, store_wstrb, misaligned);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;

        // rdata lanes 3..0 are 80, FF, 7F, 78 respectively.
        // LB: every lane, including positive and negative bytes.
        check_result(2'b00, 3'b000, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_0078, 32'b0, 4'b0000, 0,  1);
        check_result(2'b01, 3'b000, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_007F, 32'b0, 4'b0000, 0,  2);
        check_result(2'b10, 3'b000, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'hFFFF_FFFF, 32'b0, 4'b0000, 0,  3);
        check_result(2'b11, 3'b000, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'hFFFF_FF80, 32'b0, 4'b0000, 0,  4);

        // LBU: same lanes, always zero-extended.
        check_result(2'b00, 3'b100, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_0078, 32'b0, 4'b0000, 0,  5);
        check_result(2'b01, 3'b100, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_007F, 32'b0, 4'b0000, 0,  6);
        check_result(2'b10, 3'b100, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_00FF, 32'b0, 4'b0000, 0,  7);
        check_result(2'b11, 3'b100, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_0080, 32'b0, 4'b0000, 0,  8);

        // LH/LHU: both aligned halfwords plus representative non-aligned cases.
        check_result(2'b00, 3'b001, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_7F78, 32'b0, 4'b0000, 0,  9);
        check_result(2'b10, 3'b001, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'hFFFF_80FF, 32'b0, 4'b0000, 0, 10);
        check_result(2'b01, 3'b001, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'b0,         32'b0, 4'b0000, 1, 11);
        check_result(2'b11, 3'b001, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'b0,         32'b0, 4'b0000, 1, 12);
        check_result(2'b00, 3'b101, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_7F78, 32'b0, 4'b0000, 0, 13);
        check_result(2'b10, 3'b101, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h0000_80FF, 32'b0, 4'b0000, 0, 14);
        check_result(2'b01, 3'b101, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'b0,         32'b0, 4'b0000, 1, 15);
        check_result(2'b11, 3'b101, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'b0,         32'b0, 4'b0000, 1, 16);

        // LW: aligned word plus every non-aligned address low value.
        check_result(2'b00, 3'b010, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'h80FF_7F78, 32'b0, 4'b0000, 0, 17);
        check_result(2'b01, 3'b010, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'b0,         32'b0, 4'b0000, 1, 18);
        check_result(2'b10, 3'b010, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'b0,         32'b0, 4'b0000, 1, 19);
        check_result(2'b11, 3'b010, 1, 0, 32'h80FF_7F78, 32'h1234_ABCD, 32'b0,         32'b0, 4'b0000, 1, 20);

        // SB: one byte and one byte strobe in each lane.
        check_result(2'b00, 3'b000, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'h0000_00CD, 4'b0001, 0, 21);
        check_result(2'b01, 3'b000, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'h0000_CD00, 4'b0010, 0, 22);
        check_result(2'b10, 3'b000, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'h00CD_0000, 4'b0100, 0, 23);
        check_result(2'b11, 3'b000, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'hCD00_0000, 4'b1000, 0, 24);

        // SH: aligned lanes and both non-aligned addresses.
        check_result(2'b00, 3'b001, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'h0000_ABCD, 4'b0011, 0, 25);
        check_result(2'b10, 3'b001, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'hABCD_0000, 4'b1100, 0, 26);
        check_result(2'b01, 3'b001, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'b0,         4'b0000, 1, 27);
        check_result(2'b11, 3'b001, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'b0,         4'b0000, 1, 28);

        // SW: complete word only at an aligned address.
        check_result(2'b00, 3'b010, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'h1234_ABCD, 4'b1111, 0, 29);
        check_result(2'b01, 3'b010, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'b0,         4'b0000, 1, 30);
        check_result(2'b10, 3'b010, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'b0,         4'b0000, 1, 31);
        check_result(2'b11, 3'b010, 0, 1, 32'b0, 32'h1234_ABCD, 32'b0, 32'b0,         4'b0000, 1, 32);

        // Unsupported encodings and no request retain safe defaults.
        check_result(2'b00, 3'b011, 1, 0, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'b0, 32'b0, 4'b0000, 0, 33);
        check_result(2'b00, 3'b111, 0, 1, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'b0, 32'b0, 4'b0000, 0, 34);
        check_result(2'b11, 3'b000, 0, 0, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'b0, 32'b0, 4'b0000, 0, 35);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end
endmodule
