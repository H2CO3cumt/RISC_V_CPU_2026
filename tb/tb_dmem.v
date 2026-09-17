`timescale 1ns/1ps

module tb_dmem;
    reg         clk;
    reg  [31:0] addr;
    reg         we;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    wire [31:0] rdata;
    integer     failures;
    integer     i;

    dmem #(
        .DEPTH(4)
    ) dut (
        .clk(clk), .addr(addr), .we(we), .wdata(wdata),
        .wstrb(wstrb), .rdata(rdata)
    );

    task expect_read;
        input [31:0] addr_value;
        input [31:0] expected_rdata;
        input integer test_number;
        begin
            addr  = addr_value;
            we    = 1'b0;
            wdata = 32'b0;
            wstrb = 4'b0000;
            #1;
            if (rdata === expected_rdata)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: addr=%h expected rdata=%h actual rdata=%h", test_number, addr_value, expected_rdata, rdata);
                failures = failures + 1;
            end
        end
    endtask

    task write_and_expect;
        input [31:0] addr_value;
        input [31:0] wdata_value;
        input [3:0]  wstrb_value;
        input [31:0] expected_rdata;
        input integer test_number;
        begin
            addr  = addr_value;
            we    = 1'b1;
            wdata = wdata_value;
            wstrb = wstrb_value;
            #1;
            clk = 1'b1;
            #1;
            if (rdata === expected_rdata)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: addr=%h wdata=%h wstrb=%b expected rdata=%h actual rdata=%h", test_number, addr_value, wdata_value, wstrb_value, expected_rdata, rdata);
                failures = failures + 1;
            end
            clk = 1'b0;
            #1;
        end
    endtask

    initial begin
        clk      = 1'b0;
        addr     = 32'b0;
        we       = 1'b0;
        wdata    = 32'b0;
        wstrb    = 4'b0000;
        failures = 0;

        // Testbench-controlled initialization makes initial contents deterministic.
        for (i = 0; i < 4; i = i + 1)
            dut.mem[i] = 32'b0;

        expect_read(32'h0000_0000, 32'h0000_0000, 1);

        // Full-word write, followed by reads through every byte address in the word.
        write_and_expect(32'h0000_0008, 32'h1122_3344, 4'b1111, 32'h1122_3344, 2);
        expect_read(32'h0000_0009, 32'h1122_3344, 3);
        expect_read(32'h0000_000A, 32'h1122_3344, 4);
        expect_read(32'h0000_000B, 32'h1122_3344, 5);

        // Individual byte lanes: values are already aligned by load_store_unit.
        write_and_expect(32'h0000_0008, 32'h0000_00AA, 4'b0001, 32'h1122_33AA, 6);
        write_and_expect(32'h0000_0008, 32'h0000_BB00, 4'b0010, 32'h1122_BBAA, 7);
        write_and_expect(32'h0000_0008, 32'h00CC_0000, 4'b0100, 32'h11CC_BBAA, 8);
        write_and_expect(32'h0000_0008, 32'hDD00_0000, 4'b1000, 32'hDDCC_BBAA, 9);

        // Low and high halfword writes preserve the other two byte lanes.
        write_and_expect(32'h0000_000C, 32'h1234_5678, 4'b1111, 32'h1234_5678, 10);
        write_and_expect(32'h0000_000C, 32'h0000_ABCD, 4'b0011, 32'h1234_ABCD, 11);
        write_and_expect(32'h0000_000C, 32'hFEDC_0000, 4'b1100, 32'hFEDC_ABCD, 12);

        // DEPTH=4 permits byte addresses 0x00 through 0x0F only.
        write_and_expect(32'h0000_0010, 32'hFFFF_FFFF, 4'b1111, 32'h0000_0000, 13);
        expect_read(32'h0000_000C, 32'hFEDC_ABCD, 14);

        if (failures == 0)
            $display("ALL TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end
endmodule
