`timescale 1ns/1ps

module tb_interconnect;
    reg clk;
    reg reset;
    reg cpu_req_valid;
    reg [31:0] cpu_req_addr;
    reg cpu_req_write;
    reg [31:0] cpu_req_wdata;
    reg [3:0] cpu_req_wstrb;
    reg cpu_rsp_ready;
    integer failures;
    integer response_test_number;

    wire cpu_req_ready;
    wire cpu_rsp_valid;
    wire [31:0] cpu_rsp_rdata;
    wire cpu_rsp_error;
    wire ram_req_valid, uart_req_valid, gpio_req_valid, app_req_valid;
    wire [31:0] target_req_addr, target_req_wdata;
    wire target_req_write;
    wire [3:0] target_req_wstrb;
    wire ram_req_ready, uart_req_ready, gpio_req_ready, app_req_ready;
    wire ram_rsp_valid, uart_rsp_valid, gpio_rsp_valid, app_rsp_valid;
    wire ram_rsp_ready, uart_rsp_ready, gpio_rsp_ready, app_rsp_ready;
    wire [31:0] ram_rsp_rdata, uart_rsp_rdata, gpio_rsp_rdata, app_rsp_rdata;
    wire ram_rsp_error, uart_rsp_error, gpio_rsp_error, app_rsp_error;
    wire [31:0] ram_requests, uart_requests, gpio_requests, app_requests;
    wire [31:0] ram_writes, uart_writes, gpio_writes, app_writes;

    soc_data_interconnect dut (
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

    test_target #(.READ_DATA(32'h1111_0001)) ram (
        .clk(clk), .reset(reset), .req_valid(ram_req_valid), .req_ready(ram_req_ready),
        .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(ram_rsp_valid), .rsp_ready(ram_rsp_ready), .rsp_rdata(ram_rsp_rdata), .rsp_error(ram_rsp_error),
        .request_count(ram_requests), .write_count(ram_writes)
    );
    test_target #(.READ_DATA(32'h2222_0002)) uart (
        .clk(clk), .reset(reset), .req_valid(uart_req_valid), .req_ready(uart_req_ready),
        .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(uart_rsp_valid), .rsp_ready(uart_rsp_ready), .rsp_rdata(uart_rsp_rdata), .rsp_error(uart_rsp_error),
        .request_count(uart_requests), .write_count(uart_writes)
    );
    test_target #(.READ_DATA(32'h3333_0003)) gpio (
        .clk(clk), .reset(reset), .req_valid(gpio_req_valid), .req_ready(gpio_req_ready),
        .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(gpio_rsp_valid), .rsp_ready(gpio_rsp_ready), .rsp_rdata(gpio_rsp_rdata), .rsp_error(gpio_rsp_error),
        .request_count(gpio_requests), .write_count(gpio_writes)
    );
    test_target #(.READ_DATA(32'h4444_0004)) app (
        .clk(clk), .reset(reset), .req_valid(app_req_valid), .req_ready(app_req_ready),
        .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(app_rsp_valid), .rsp_ready(app_rsp_ready), .rsp_rdata(app_rsp_rdata), .rsp_error(app_rsp_error),
        .request_count(app_requests), .write_count(app_writes)
    );

    always #5 clk = ~clk;

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input integer test_number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected=%h actual=%h", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task expect_bit;
        input actual;
        input expected;
        input integer test_number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected=%b actual=%b", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task access;
        input [31:0] addr;
        input write;
        input [31:0] wdata;
        input [3:0] wstrb;
        input [31:0] expected_rdata;
        input expected_error;
        begin
            @(negedge clk);
            cpu_req_addr  = addr;
            cpu_req_write = write;
            cpu_req_wdata = wdata;
            cpu_req_wstrb = wstrb;
            cpu_req_valid = 1'b1;
            while (!cpu_req_ready)
                @(negedge clk);
            @(negedge clk);
            cpu_req_valid = 1'b0;
            while (!cpu_rsp_valid)
                @(negedge clk);
            expect_word(cpu_rsp_rdata, expected_rdata, response_test_number);
            expect_bit(cpu_rsp_error, expected_error, response_test_number + 1);
            response_test_number = response_test_number + 2;
            cpu_rsp_ready = 1'b1;
            @(negedge clk);
            cpu_rsp_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        cpu_req_valid = 1'b0;
        cpu_req_addr = 32'b0;
        cpu_req_write = 1'b0;
        cpu_req_wdata = 32'b0;
        cpu_req_wstrb = 4'b0;
        cpu_rsp_ready = 1'b0;
        failures = 0;
        response_test_number = 1;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        access(32'h0000_0000, 1'b0, 32'b0, 4'b0, 32'h1111_0001, 1'b0);
        access(32'h0000_03FF, 1'b0, 32'b0, 4'b0, 32'h1111_0001, 1'b0);
        access(32'h1000_0000, 1'b0, 32'b0, 4'b0, 32'h2222_0002, 1'b0);
        access(32'h1000_00FF, 1'b0, 32'b0, 4'b0, 32'h2222_0002, 1'b0);
        access(32'h1000_1000, 1'b0, 32'b0, 4'b0, 32'h3333_0003, 1'b0);
        access(32'h1000_10FF, 1'b0, 32'b0, 4'b0, 32'h3333_0003, 1'b0);
        access(32'h1000_2000, 1'b0, 32'b0, 4'b0, 32'h4444_0004, 1'b0);
        access(32'h1000_2FFF, 1'b0, 32'b0, 4'b0, 32'h4444_0004, 1'b0);
        access(32'h1000_1800, 1'b1, 32'hDEAD_BEEF, 4'b1111, 32'b0, 1'b1);
        access(32'hFFFF_FFFF, 1'b1, 32'hDEAD_BEEF, 4'b1111, 32'b0, 1'b1);
        access(32'h0000_0004, 1'b1, 32'hAAAA_0001, 4'b1111, 32'h1111_0001, 1'b0);
        access(32'h1000_0004, 1'b1, 32'hAAAA_0002, 4'b0001, 32'h2222_0002, 1'b0);
        access(32'h1000_1004, 1'b1, 32'hAAAA_0003, 4'b0010, 32'h3333_0003, 1'b0);
        access(32'h1000_2004, 1'b1, 32'hAAAA_0004, 4'b1100, 32'h4444_0004, 1'b0);

        expect_word(ram_requests,  32'd3, 29);
        expect_word(uart_requests, 32'd3, 30);
        expect_word(gpio_requests, 32'd3, 31);
        expect_word(app_requests,  32'd3, 32);
        expect_word(ram_writes,    32'd1, 33);
        expect_word(uart_writes,   32'd1, 34);
        expect_word(gpio_writes,   32'd1, 35);
        expect_word(app_writes,    32'd1, 36);

        if (failures == 0)
            $display("ALL INTERCONNECT TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);
        $finish;
    end
endmodule
