`timescale 1ns/1ps

module tb_uart_mmio;
    reg clk;
    reg reset;
    reg uart_req_valid;
    reg [31:0] uart_req_addr;
    reg uart_req_write;
    reg [31:0] uart_req_wdata;
    reg [3:0] uart_req_wstrb;
    reg uart_rsp_ready;
    reg uart_rx;
    integer failures;
    integer test_number;
    integer accepted_tx_count;

    wire uart_req_ready;
    wire uart_rsp_valid;
    wire [31:0] uart_rsp_rdata;
    wire uart_rsp_error;
    wire uart_tx;

    uart_mmio #(
        .UART_MAX_1BAUD(4)
    ) dut (
        .clk(clk), .reset(reset),
        .uart_req_valid(uart_req_valid), .uart_req_ready(uart_req_ready),
        .uart_req_addr(uart_req_addr), .uart_req_write(uart_req_write),
        .uart_req_wdata(uart_req_wdata), .uart_req_wstrb(uart_req_wstrb),
        .uart_rsp_valid(uart_rsp_valid), .uart_rsp_ready(uart_rsp_ready),
        .uart_rsp_rdata(uart_rsp_rdata), .uart_rsp_error(uart_rsp_error),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    always #5 clk = ~clk;

    // 统计真正交给 UART_TX 的字节数，验证响应背压不会重复触发副作用。
    always @(posedge clk) begin
        if (reset)
            accepted_tx_count = 0;
        else if (dut.uart_tx_data_vld)
            accepted_tx_count = accepted_tx_count + 1;
    end

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

    // 释放当前响应；调用前 req_valid 必须已撤销，避免被误当作下一笔请求。
    task finish_response;
        begin
            @(negedge clk);
            uart_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            expect_bit(uart_rsp_valid, 1'b0);
            expect_bit(uart_req_ready, 1'b1);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        uart_req_valid = 1'b0;
        uart_req_addr = 32'd0;
        uart_req_write = 1'b0;
        uart_req_wdata = 32'd0;
        uart_req_wstrb = 4'd0;
        uart_rsp_ready = 1'b1;
        uart_rx = 1'b1;
        failures = 0;
        test_number = 0;
        accepted_tx_count = 0;

        repeat (2) @(posedge clk);
        #1;
        expect_bit(uart_req_ready, 1'b1);
        expect_bit(uart_rsp_valid, 1'b0);
        expect_bit(uart_tx, 1'b1);
        reset = 1'b0;

        // 空闲 STATUS：bit0=ready=1，bit1=busy=0。
        @(negedge clk);
        uart_rsp_ready = 1'b0;
        uart_req_addr = 32'h1000_0004;
        uart_req_write = 1'b0;
        uart_req_wstrb = 4'b0000;
        uart_req_valid = 1'b1;
        @(posedge clk);
        #1;
        uart_req_valid = 1'b0;
        expect_bit(uart_rsp_valid, 1'b1);
        expect_bit(uart_rsp_error, 1'b0);
        expect_word(uart_rsp_rdata, 32'h0000_0001);
        finish_response;

        // 第一个 TXDATA 写：接受后 UART 输出起始位，且响应被背压时不得重复发送。
        @(negedge clk);
        uart_rsp_ready = 1'b0;
        uart_req_addr = 32'h1000_0000;
        uart_req_write = 1'b1;
        uart_req_wdata = 32'h0000_00A5;
        uart_req_wstrb = 4'b0001;
        uart_req_valid = 1'b1;
        @(posedge clk);
        #1;
        expect_bit(uart_rsp_valid, 1'b1);
        expect_bit(uart_rsp_error, 1'b0);
        expect_bit(uart_tx, 1'b0);
        expect_word(accepted_tx_count, 32'd1);
        repeat (2) @(posedge clk);
        #1;
        expect_bit(uart_rsp_valid, 1'b1);
        expect_bit(uart_req_ready, 1'b0);
        expect_word(accepted_tx_count, 32'd1);
        uart_req_valid = 1'b0;
        finish_response;

        // UART 仍在发送 A5；STATUS 必须报告 busy。
        @(negedge clk);
        uart_rsp_ready = 1'b0;
        uart_req_addr = 32'h1000_0004;
        uart_req_write = 1'b0;
        uart_req_wstrb = 4'b0000;
        uart_req_valid = 1'b1;
        @(posedge clk);
        #1;
        uart_req_valid = 1'b0;
        expect_bit(uart_rsp_error, 1'b0);
        expect_word(uart_rsp_rdata, 32'h0000_0002);
        finish_response;

        // 非法 TXDATA 读在 UART busy 时仍须立即响应，且不可产生发送副作用。
        @(negedge clk);
        uart_rsp_ready = 1'b0;
        uart_req_addr = 32'h1000_0000;
        uart_req_write = 1'b0;
        uart_req_wstrb = 4'b0000;
        uart_req_valid = 1'b1;
        #1;
        expect_bit(uart_req_ready, 1'b1);
        @(posedge clk);
        #1;
        uart_req_valid = 1'b0;
        expect_bit(uart_rsp_valid, 1'b1);
        expect_bit(uart_rsp_error, 1'b1);
        expect_word(accepted_tx_count, 32'd1);
        finish_response;

        // 合法 TXDATA 写在 busy 期间必须保持未接受，直到 UART_TX 再次 ready。
        @(negedge clk);
        uart_rsp_ready = 1'b1;
        uart_req_addr = 32'h1000_0000;
        uart_req_write = 1'b1;
        uart_req_wdata = 32'h0000_003C;
        uart_req_wstrb = 4'b0001;
        uart_req_valid = 1'b1;
        #1;
        expect_bit(uart_req_ready, 1'b0);
        repeat (3) @(posedge clk);
        #1;
        expect_bit(uart_req_ready, 1'b0);
        expect_bit(uart_rsp_valid, 1'b0);
        expect_word(accepted_tx_count, 32'd1);

        // 等待 A5 的停止位完成；保持 valid 的该笔请求随后被唯一接受。
        // wait 在 UART_TX 变为 ready 的组合更新后返回；下一拍才是该请求握手。
        wait (uart_req_ready == 1'b1);
        @(posedge clk);
        #1;
        uart_req_valid = 1'b0;
        expect_bit(uart_rsp_valid, 1'b1);
        expect_bit(uart_rsp_error, 1'b0);
        expect_word(accepted_tx_count, 32'd2);
        finish_response;

        if (failures == 0)
            $display("ALL UART MMIO TEST PASS");
        else
            $display("UART MMIO TEST FAIL: %0d failures", failures);
        $finish;
    end
endmodule
