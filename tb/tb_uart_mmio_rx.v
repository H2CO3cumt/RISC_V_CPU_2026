`timescale 1ns/1ps

module tb_uart_mmio_rx;
    reg clk, reset, uart_rx;
    reg req_valid, req_write, rsp_ready;
    reg [31:0] req_addr, req_wdata;
    reg [3:0] req_wstrb;
    integer failures, test_number;
    wire req_ready, rsp_valid, rsp_error, uart_tx;
    wire [31:0] rsp_rdata;

    uart_mmio #(.UART_MAX_1BAUD(16), .UART_RX_MAX_1BAUD(16)) dut (
        .clk(clk), .reset(reset),
        .uart_req_valid(req_valid), .uart_req_ready(req_ready),
        .uart_req_addr(req_addr), .uart_req_write(req_write),
        .uart_req_wdata(req_wdata), .uart_req_wstrb(req_wstrb),
        .uart_rsp_valid(rsp_valid), .uart_rsp_ready(rsp_ready),
        .uart_rsp_rdata(rsp_rdata), .uart_rsp_error(rsp_error),
        .uart_rx(uart_rx), .uart_tx(uart_tx)
    );

    always #5 clk = ~clk;

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
            uart_rx = value;
            repeat (16) @(posedge clk);
        end
    endtask

    task send_frame;
        input [7:0] data;
        integer i;
        begin
            send_bit(1'b0);
            for (i = 0; i < 8; i = i + 1)
                send_bit(data[i]);
            send_bit(1'b1);
        end
    endtask

    task release_response;
        begin
            @(negedge clk);
            rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            expect_word(rsp_valid, 32'd0);
        end
    endtask

    task read_status;
        input [31:0] expected;
        begin
            @(negedge clk);
            rsp_ready = 1'b0;
            req_addr = 32'h1000_0004;
            req_write = 1'b0;
            req_wstrb = 4'd0;
            req_valid = 1'b1;
            @(posedge clk);
            #1;
            req_valid = 1'b0;
            expect_word(rsp_error, 32'd0);
            expect_word(rsp_rdata, expected);
            release_response;
        end
    endtask

    task read_rxdata;
        input [31:0] expected;
        begin
            @(negedge clk);
            rsp_ready = 1'b0;
            req_addr = 32'h1000_0008;
            req_write = 1'b0;
            req_wstrb = 4'd0;
            req_valid = 1'b1;
            @(posedge clk);
            #1;
            req_valid = 1'b0;
            expect_word(rsp_error, 32'd0);
            expect_word(rsp_rdata, expected);
            release_response;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        uart_rx = 1'b1;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr = 32'd0;
        req_wdata = 32'd0;
        req_wstrb = 4'd0;
        rsp_ready = 1'b1;
        failures = 0;
        test_number = 0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        // 空邮箱 RXDATA 读不接受，CPU 可借此实现阻塞 getchar。
        @(negedge clk);
        req_addr = 32'h1000_0008;
        req_write = 1'b0;
        req_wstrb = 4'd0;
        rsp_ready = 1'b0;
        req_valid = 1'b1;
        #1;
        expect_word(req_ready, 32'd0);
        expect_word(rsp_valid, 32'd0);

        // 收到字节后，原先等待的读请求自动完成并取走该字节。
        send_frame(8'h5A);
        #1;
        req_valid = 1'b0;
        expect_word(rsp_valid, 32'd1);
        expect_word(rsp_error, 32'd0);
        expect_word(rsp_rdata, 32'h0000_005A);
        release_response;
        read_status(32'h0000_0001);

        // 不读取 AA 时再到达 55：邮箱保留 AA，STATUS 置 valid 和 overflow。
        send_frame(8'hAA);
        send_frame(8'h55);
        repeat (8) @(posedge clk);
        read_status(32'h0000_000D);
        read_rxdata(32'h0000_00AA);
        read_status(32'h0000_0009);

        // STATUS bit3 写 1 清除 overflow；其他状态位的写入被忽略。
        @(negedge clk);
        rsp_ready = 1'b0;
        req_addr = 32'h1000_0004;
        req_write = 1'b1;
        req_wdata = 32'h0000_0008;
        req_wstrb = 4'b0001;
        req_valid = 1'b1;
        @(posedge clk);
        #1;
        req_valid = 1'b0;
        expect_word(rsp_error, 32'd0);
        release_response;
        read_status(32'h0000_0001);

        if (failures == 0)
            $display("ALL UART MMIO RX TEST PASS");
        else
            $display("UART MMIO RX TEST FAIL: %0d failures", failures);
        $finish;
    end
endmodule
