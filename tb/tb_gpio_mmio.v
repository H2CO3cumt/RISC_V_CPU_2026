`timescale 1ns/1ps

module tb_gpio_mmio;
    reg clk;
    reg reset;
    reg gpio_req_valid;
    reg [31:0] gpio_req_addr;
    reg gpio_req_write;
    reg [31:0] gpio_req_wdata;
    reg [3:0] gpio_req_wstrb;
    reg gpio_rsp_ready;
    integer failures;
    integer test_number;

    wire gpio_req_ready;
    wire gpio_rsp_valid;
    wire [31:0] gpio_rsp_rdata;
    wire gpio_rsp_error;
    wire [31:0] gpio_out;

    gpio_mmio dut (
        .clk(clk), .reset(reset),
        .gpio_req_valid(gpio_req_valid), .gpio_req_ready(gpio_req_ready),
        .gpio_req_addr(gpio_req_addr), .gpio_req_write(gpio_req_write),
        .gpio_req_wdata(gpio_req_wdata), .gpio_req_wstrb(gpio_req_wstrb),
        .gpio_rsp_valid(gpio_rsp_valid), .gpio_rsp_ready(gpio_rsp_ready),
        .gpio_rsp_rdata(gpio_rsp_rdata), .gpio_rsp_error(gpio_rsp_error),
        .gpio_out(gpio_out)
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

    // Hold rsp_ready low first.  This proves the device accepts exactly one
    // request, performs the write once, and keeps its response stable.
    task transaction;
        input [31:0] address;
        input write;
        input [31:0] wdata;
        input [3:0] wstrb;
        input [31:0] expected_rdata;
        input expected_error;
        input [31:0] expected_gpio;
        begin
            @(negedge clk);
            gpio_rsp_ready = 1'b0;
            gpio_req_addr = address;
            gpio_req_write = write;
            gpio_req_wdata = wdata;
            gpio_req_wstrb = wstrb;
            gpio_req_valid = 1'b1;

            @(posedge clk);
            #1;
            expect_bit(gpio_req_ready, 1'b0);
            expect_bit(gpio_rsp_valid, 1'b1);
            expect_bit(gpio_rsp_error, expected_error);
            expect_word(gpio_rsp_rdata, expected_rdata);
            expect_word(gpio_out, expected_gpio);

            // A second stalled cycle must not alter the response or GPIO.
            @(posedge clk);
            #1;
            expect_bit(gpio_req_ready, 1'b0);
            expect_bit(gpio_rsp_valid, 1'b1);
            expect_bit(gpio_rsp_error, expected_error);
            expect_word(gpio_rsp_rdata, expected_rdata);
            expect_word(gpio_out, expected_gpio);

            @(negedge clk);
            gpio_req_valid = 1'b0;
            gpio_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            expect_bit(gpio_req_ready, 1'b1);
            expect_bit(gpio_rsp_valid, 1'b0);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        gpio_req_valid = 1'b0;
        gpio_req_addr = 32'b0;
        gpio_req_write = 1'b0;
        gpio_req_wdata = 32'b0;
        gpio_req_wstrb = 4'b0;
        gpio_rsp_ready = 1'b1;
        failures = 0;
        test_number = 0;

        repeat (2) @(posedge clk);
        #1;
        expect_bit(gpio_req_ready, 1'b1);
        expect_bit(gpio_rsp_valid, 1'b0);
        expect_word(gpio_out, 32'b0);
        reset = 1'b0;

        // SW, then SB at byte offset 1, then SH at byte offset 2.
        transaction(32'h1000_1000, 1'b1, 32'h1234_5678, 4'b1111, 32'b0, 1'b0, 32'h1234_5678);
        transaction(32'h1000_1001, 1'b1, 32'h0000_AA00, 4'b0010, 32'b0, 1'b0, 32'h1234_AA78);
        transaction(32'h1000_1002, 1'b1, 32'hBEEF_0000, 4'b1100, 32'b0, 1'b0, 32'hBEEF_AA78);
        transaction(32'h1000_1000, 1'b0, 32'b0, 4'b0, 32'hBEEF_AA78, 1'b0, 32'hBEEF_AA78);

        // Undefined register offset must report an error and have no side effect.
        transaction(32'h1000_1004, 1'b1, 32'hFFFF_FFFF, 4'b1111, 32'b0, 1'b1, 32'hBEEF_AA78);

        if (failures == 0)
            $display("ALL GPIO MMIO TEST PASS");
        else
            $display("GPIO MMIO TEST FAIL: %0d failures", failures);
        $finish;
    end
endmodule
