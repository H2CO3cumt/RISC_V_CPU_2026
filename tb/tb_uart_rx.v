`timescale 1ns/1ps

module tb_uart_rx;
    reg clk;
    reg rst;
    reg rx;
    integer failures;
    integer test_number;
    integer valid_count;
    integer frame_error_count;
    reg [7:0] received_data [0:3];

    wire [7:0] rx_data;
    wire rx_data_vld;
    wire rx_frame_error;

    UART_RX #(.MAX_1BAUD(16)) dut (
        .clk_50m(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .rx_data_vld(rx_data_vld),
        .rx_frame_error(rx_frame_error)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rx_data_vld) begin
            received_data[valid_count] = rx_data;
            valid_count = valid_count + 1;
        end
        if (rx_frame_error)
            frame_error_count = frame_error_count + 1;
    end

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        begin
            test_number = test_number + 1;
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected=%h actual=%h", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task send_bit;
        input value;
        begin
            @(negedge clk);
            rx = value;
            repeat (16) @(posedge clk);
        end
    endtask

    task send_frame;
        input [7:0] data;
        input stop_value;
        integer i;
        begin
            send_bit(1'b0);
            for (i = 0; i < 8; i = i + 1)
                send_bit(data[i]);
            send_bit(stop_value);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        rx = 1'b1;
        failures = 0;
        test_number = 0;
        valid_count = 0;
        frame_error_count = 0;

        repeat (2) @(posedge clk);
        rst = 1'b0;

        // 正常 8N1 帧：必须低位优先还原为 A5。
        send_frame(8'hA5, 1'b1);
        repeat (20) @(posedge clk);
        expect_word(valid_count, 32'd1);
        expect_word(received_data[0], 32'h0000_00A5);
        expect_word(frame_error_count, 32'd0);

        // 低电平毛刺不足半位，必须被 START 中点确认逻辑丢弃。
        @(negedge clk);
        rx = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rx = 1'b1;
        repeat (24) @(posedge clk);
        expect_word(valid_count, 32'd1);
        expect_word(frame_error_count, 32'd0);

        // 停止位错误不能提交数据，但必须报告一次 frame_error。
        send_frame(8'h3C, 1'b0);
        @(negedge clk);
        rx = 1'b1;
        repeat (24) @(posedge clk);
        expect_word(valid_count, 32'd1);
        expect_word(frame_error_count, 32'd1);

        // 连续两个正常帧，确认 receiver 能回到 IDLE 并持续接收。
        send_frame(8'h12, 1'b1);
        send_frame(8'hE7, 1'b1);
        repeat (24) @(posedge clk);
        expect_word(valid_count, 32'd3);
        expect_word(received_data[1], 32'h0000_0012);
        expect_word(received_data[2], 32'h0000_00E7);
        expect_word(frame_error_count, 32'd1);

        if (failures == 0)
            $display("ALL UART RX TEST PASS");
        else
            $display("UART RX TEST FAIL: %0d failures", failures);
        $finish;
    end
endmodule
