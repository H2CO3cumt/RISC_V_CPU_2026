`timescale 1ns/1ps

// Task 16 integration: real UART/GPIO MMIO slaves behind the frozen Task 15
// interconnect.  The source below models only generic CPU data transactions.
module tb_task16_peripheral_interconnect;
    reg clk, reset, cpu_req_valid, cpu_req_write, cpu_rsp_ready, uart_rx;
    reg [31:0] cpu_req_addr, cpu_req_wdata;
    reg [3:0] cpu_req_wstrb;
    integer failures, test_number;

    wire cpu_req_ready, cpu_rsp_valid, cpu_rsp_error;
    wire [31:0] cpu_rsp_rdata;
    wire ram_req_valid, uart_req_valid, gpio_req_valid, app_req_valid;
    wire ram_req_ready, uart_req_ready, gpio_req_ready, app_req_ready;
    wire [31:0] target_req_addr, target_req_wdata;
    wire target_req_write;
    wire [3:0] target_req_wstrb;
    wire ram_rsp_valid, uart_rsp_valid, gpio_rsp_valid, app_rsp_valid;
    wire ram_rsp_ready, uart_rsp_ready, gpio_rsp_ready, app_rsp_ready;
    wire [31:0] ram_rsp_rdata, uart_rsp_rdata, gpio_rsp_rdata, app_rsp_rdata;
    wire ram_rsp_error, uart_rsp_error, gpio_rsp_error, app_rsp_error;
    wire uart_tx;
    wire [31:0] gpio_out;

    soc_data_interconnect u_interconnect (
        .clk(clk), .reset(reset),
        .cpu_req_valid(cpu_req_valid), .cpu_req_ready(cpu_req_ready),
        .cpu_req_addr(cpu_req_addr), .cpu_req_write(cpu_req_write),
        .cpu_req_wdata(cpu_req_wdata), .cpu_req_wstrb(cpu_req_wstrb),
        .cpu_rsp_valid(cpu_rsp_valid), .cpu_rsp_ready(cpu_rsp_ready),
        .cpu_rsp_rdata(cpu_rsp_rdata), .cpu_rsp_error(cpu_rsp_error),
        .ram_req_valid(ram_req_valid), .ram_req_ready(ram_req_ready),
        .uart_req_valid(uart_req_valid), .uart_req_ready(uart_req_ready),
        .gpio_req_valid(gpio_req_valid), .gpio_req_ready(gpio_req_ready),
        .app_req_valid(app_req_valid), .app_req_ready(app_req_ready),
        .target_req_addr(target_req_addr), .target_req_write(target_req_write),
        .target_req_wdata(target_req_wdata), .target_req_wstrb(target_req_wstrb),
        .ram_rsp_valid(ram_rsp_valid), .ram_rsp_ready(ram_rsp_ready), .ram_rsp_rdata(ram_rsp_rdata), .ram_rsp_error(ram_rsp_error),
        .uart_rsp_valid(uart_rsp_valid), .uart_rsp_ready(uart_rsp_ready), .uart_rsp_rdata(uart_rsp_rdata), .uart_rsp_error(uart_rsp_error),
        .gpio_rsp_valid(gpio_rsp_valid), .gpio_rsp_ready(gpio_rsp_ready), .gpio_rsp_rdata(gpio_rsp_rdata), .gpio_rsp_error(gpio_rsp_error),
        .app_rsp_valid(app_rsp_valid), .app_rsp_ready(app_rsp_ready), .app_rsp_rdata(app_rsp_rdata), .app_rsp_error(app_rsp_error)
    );

    task15_ram_adapter #(.DEPTH(256), .RANDOM_DELAY(0)) ram (
        .clk(clk), .reset(reset), .req_valid(ram_req_valid), .req_ready(ram_req_ready),
        .req_addr(target_req_addr), .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(ram_rsp_valid), .rsp_ready(ram_rsp_ready), .rsp_rdata(ram_rsp_rdata), .rsp_error(ram_rsp_error), .write_side_effect_count()
    );

    uart_mmio #(.UART_MAX_1BAUD(16), .UART_RX_MAX_1BAUD(16)) uart (
        .clk(clk), .reset(reset),
        .uart_req_valid(uart_req_valid), .uart_req_ready(uart_req_ready),
        .uart_req_addr(target_req_addr), .uart_req_write(target_req_write),
        .uart_req_wdata(target_req_wdata), .uart_req_wstrb(target_req_wstrb),
        .uart_rsp_valid(uart_rsp_valid), .uart_rsp_ready(uart_rsp_ready), .uart_rsp_rdata(uart_rsp_rdata), .uart_rsp_error(uart_rsp_error),
        .uart_rx(uart_rx), .uart_tx(uart_tx)
    );

    gpio_mmio gpio (
        .clk(clk), .reset(reset),
        .gpio_req_valid(gpio_req_valid), .gpio_req_ready(gpio_req_ready),
        .gpio_req_addr(target_req_addr), .gpio_req_write(target_req_write),
        .gpio_req_wdata(target_req_wdata), .gpio_req_wstrb(target_req_wstrb),
        .gpio_rsp_valid(gpio_rsp_valid), .gpio_rsp_ready(gpio_rsp_ready), .gpio_rsp_rdata(gpio_rsp_rdata), .gpio_rsp_error(gpio_rsp_error),
        .gpio_out(gpio_out)
    );

    task15_test_target app (
        .clk(clk), .reset(reset), .req_valid(app_req_valid), .req_ready(app_req_ready),
        .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(app_rsp_valid), .rsp_ready(app_rsp_ready), .rsp_rdata(app_rsp_rdata), .rsp_error(app_rsp_error), .request_count(), .write_count()
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

    task cpu_access;
        input [31:0] address;
        input write_enable;
        input [31:0] write_data;
        input [3:0] write_strobe;
        input [31:0] expected_data;
        input expected_error;
        begin
            @(negedge clk);
            cpu_rsp_ready = 1'b0;
            cpu_req_addr = address;
            cpu_req_write = write_enable;
            cpu_req_wdata = write_data;
            cpu_req_wstrb = write_strobe;
            cpu_req_valid = 1'b1;
            wait (cpu_req_ready == 1'b1);
            @(posedge clk);
            @(negedge clk);
            cpu_req_valid = 1'b0;
            wait (cpu_rsp_valid == 1'b1);
            #1;
            expect_word(cpu_rsp_error, expected_error);
            expect_word(cpu_rsp_rdata, expected_data);
            @(negedge clk);
            cpu_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            expect_word(cpu_rsp_valid, 32'd0);
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

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        cpu_req_valid = 1'b0;
        cpu_req_write = 1'b0;
        cpu_req_addr = 32'd0;
        cpu_req_wdata = 32'd0;
        cpu_req_wstrb = 4'd0;
        cpu_rsp_ready = 1'b1;
        uart_rx = 1'b1;
        failures = 0;
        test_number = 0;
        repeat (2) @(posedge clk);
        reset = 1'b0;

        cpu_access(32'h1000_1000, 1'b1, 32'h0000_00AA, 4'b0001, 32'd0, 1'b0);
        expect_word(gpio_out, 32'h0000_00AA);

        cpu_access(32'h1000_0000, 1'b1, 32'h0000_0048, 4'b0001, 32'd0, 1'b0);
        expect_word(uart_tx, 32'd0);
        cpu_access(32'h1000_0004, 1'b0, 32'd0, 4'd0, 32'h0000_0002, 1'b0);

        send_frame(8'h3C);
        cpu_access(32'h1000_0004, 1'b0, 32'd0, 4'd0, 32'h0000_0005, 1'b0);
        cpu_access(32'h1000_0008, 1'b0, 32'd0, 4'd0, 32'h0000_003C, 1'b0);
        cpu_access(32'h1000_0004, 1'b0, 32'd0, 4'd0, 32'h0000_0001, 1'b0);

        if (failures == 0)
            $display("ALL TASK16 PERIPHERAL/INTERCONNECT TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);
        $finish;
    end
endmodule
