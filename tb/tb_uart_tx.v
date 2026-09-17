`timescale 1ns/1ps

module tb_uart_tx;
    reg clk;
    reg rst;
    reg tx_data_vld;
    reg [7:0] tx_data;
    integer failures;
    integer test_number;

    wire ready;
    wire tx;

    // A short divider makes the protocol test quick; the production default
    // remains 50 MHz / 115200 baud in uart_tx.v.
    UART_TX #(.MAX_1BAUD(4)) dut (
        .clk_50m(clk), .rst(rst), .tx_data_vld(tx_data_vld), .tx_data(tx_data),
        .ready(ready), .tx(tx)
    );

    always #5 clk = ~clk;

    task expect_bit;
        input actual;
        input expected;
        begin
            test_number = test_number + 1;
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected=%b actual=%b", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task sample_next_bit;
        input expected;
        begin
            repeat (4) @(posedge clk);
            #1;
            expect_bit(tx, expected);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        tx_data_vld = 1'b0;
        tx_data = 8'b0;
        failures = 0;
        test_number = 0;

        repeat (2) @(posedge clk);
        #1;
        expect_bit(ready, 1'b1);
        expect_bit(tx, 1'b1);
        rst = 1'b0;

        // Send A5: start=0, data LSB first=1,0,1,0,0,1,0,1, stop=1.
        @(negedge clk);
        tx_data = 8'hA5;
        tx_data_vld = 1'b1;
        @(posedge clk);
        #1;
        expect_bit(ready, 1'b0);
        expect_bit(tx, 1'b0);
        @(negedge clk);
        tx_data_vld = 1'b0;
        tx_data = 8'h3C; // Must not alter the already accepted A5 frame.

        sample_next_bit(1'b1);
        sample_next_bit(1'b0);
        sample_next_bit(1'b1);
        sample_next_bit(1'b0);
        sample_next_bit(1'b0);
        sample_next_bit(1'b1);
        sample_next_bit(1'b0);
        sample_next_bit(1'b1);
        sample_next_bit(1'b1);
        repeat (4) @(posedge clk);
        #1;
        expect_bit(ready, 1'b1);
        expect_bit(tx, 1'b1);

        if (failures == 0)
            $display("ALL UART TX TEST PASS");
        else
            $display("UART TX TEST FAIL: %0d failures", failures);
        $finish;
    end
endmodule
