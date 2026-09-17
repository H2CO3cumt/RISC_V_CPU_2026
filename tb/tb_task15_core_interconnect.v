`timescale 1ns/1ps

// Integration test: the existing Task 11 program uses the same Core source,
// but its data traffic now crosses the Task 15 interconnect into external RAM.
module tb_task15_core_interconnect;
    reg clk;
    reg reset;
    integer failures;
    integer cycle_count;

    wire c_req_valid, c_req_ready, c_req_write;
    wire [31:0] c_req_addr, c_req_wdata;
    wire [3:0] c_req_wstrb;
    wire c_rsp_valid, c_rsp_ready, c_rsp_error;
    wire [31:0] c_rsp_rdata;
    wire i_req_valid, i_req_ready, i_rsp_valid, i_rsp_ready, i_rsp_error;
    wire [31:0] i_req_addr, i_rsp_data;
    wire ram_req_valid, uart_req_valid, gpio_req_valid, app_req_valid;
    wire ram_req_ready, uart_req_ready, gpio_req_ready, app_req_ready;
    wire [31:0] target_req_addr, target_req_wdata;
    wire target_req_write;
    wire [3:0] target_req_wstrb;
    wire ram_rsp_valid, uart_rsp_valid, gpio_rsp_valid, app_rsp_valid;
    wire ram_rsp_ready, uart_rsp_ready, gpio_rsp_ready, app_rsp_ready;
    wire [31:0] ram_rsp_rdata, uart_rsp_rdata, gpio_rsp_rdata, app_rsp_rdata;
    wire ram_rsp_error, uart_rsp_error, gpio_rsp_error, app_rsp_error;
    wire [31:0] unused_uart_requests, unused_gpio_requests, unused_app_requests;
    wire [31:0] unused_uart_writes, unused_gpio_writes, unused_app_writes;

    single_cycle_cpu #(
        .IMEM_DEPTH(12),
        .IMEM_INIT_FILE("tb/data/task11_single_cycle.mem")
    ) core (
        .clk(clk), .reset(reset),
        .d_req_valid(c_req_valid), .d_req_ready(c_req_ready),
        .d_req_addr(c_req_addr), .d_req_write(c_req_write),
        .d_req_wdata(c_req_wdata), .d_req_wstrb(c_req_wstrb),
        .d_rsp_valid(c_rsp_valid), .d_rsp_ready(c_rsp_ready),
        .d_rsp_rdata(c_rsp_rdata), .d_rsp_error(c_rsp_error),
        .i_req_valid(i_req_valid), .i_req_ready(i_req_ready), .i_req_addr(i_req_addr),
        .i_rsp_valid(i_rsp_valid), .i_rsp_ready(i_rsp_ready), .i_rsp_data(i_rsp_data), .i_rsp_error(i_rsp_error)
    );

    task15_imem_adapter #(
        .DEPTH(12), .INIT_FILE("tb/data/task11_single_cycle.mem")
    ) imem (
        .clk(clk), .reset(reset), .req_valid(i_req_valid), .req_ready(i_req_ready), .req_addr(i_req_addr),
        .rsp_valid(i_rsp_valid), .rsp_ready(i_rsp_ready), .rsp_data(i_rsp_data), .rsp_error(i_rsp_error)
    );

    soc_data_interconnect u_interconnect (
        .clk(clk), .reset(reset),
        .cpu_req_valid(c_req_valid), .cpu_req_ready(c_req_ready),
        .cpu_req_addr(c_req_addr), .cpu_req_write(c_req_write),
        .cpu_req_wdata(c_req_wdata), .cpu_req_wstrb(c_req_wstrb),
        .cpu_rsp_valid(c_rsp_valid), .cpu_rsp_ready(c_rsp_ready),
        .cpu_rsp_rdata(c_rsp_rdata), .cpu_rsp_error(c_rsp_error),
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

    task15_ram_adapter #(.DEPTH(256)) ram (
        .clk(clk), .reset(reset), .req_valid(ram_req_valid), .req_ready(ram_req_ready),
        .req_addr(target_req_addr), .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(ram_rsp_valid), .rsp_ready(ram_rsp_ready), .rsp_rdata(ram_rsp_rdata), .rsp_error(ram_rsp_error),
        .write_side_effect_count()
    );
    task15_test_target uart (
        .clk(clk), .reset(reset), .req_valid(uart_req_valid), .req_ready(uart_req_ready), .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(uart_rsp_valid), .rsp_ready(uart_rsp_ready), .rsp_rdata(uart_rsp_rdata), .rsp_error(uart_rsp_error), .request_count(unused_uart_requests), .write_count(unused_uart_writes)
    );
    task15_test_target gpio (
        .clk(clk), .reset(reset), .req_valid(gpio_req_valid), .req_ready(gpio_req_ready), .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(gpio_rsp_valid), .rsp_ready(gpio_rsp_ready), .rsp_rdata(gpio_rsp_rdata), .rsp_error(gpio_rsp_error), .request_count(unused_gpio_requests), .write_count(unused_gpio_writes)
    );
    task15_test_target app (
        .clk(clk), .reset(reset), .req_valid(app_req_valid), .req_ready(app_req_ready), .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(app_rsp_valid), .rsp_ready(app_rsp_ready), .rsp_rdata(app_rsp_rdata), .rsp_error(app_rsp_error), .request_count(unused_app_requests), .write_count(unused_app_writes)
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

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failures = 0;
        cycle_count = 0;
        repeat (2) @(negedge clk);
        reset = 1'b0;

        while ((core.pc !== 32'd48) && (cycle_count < 250)) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        @(negedge clk);
        #1;

        expect_word(core.u_regfile.regs[3], 32'd15, 1);
        expect_word(core.u_regfile.regs[4], 32'd15, 2);
        expect_word(core.u_regfile.regs[5], 32'd10, 3);
        expect_word(ram.mem[0], 32'd15, 4);
        expect_word(ram.mem[1], 32'd10, 5);
        expect_word(ram.write_side_effect_count, 32'd2, 6);
        expect_word(unused_uart_requests, 32'd0, 7);
        expect_word(unused_gpio_requests, 32'd0, 8);
        expect_word(unused_app_requests, 32'd0, 9);
        if (cycle_count < 250)
            $display("TEST 10 PASS: Core + interconnect completed in %0d cycle(s)", cycle_count);
        else begin
            $display("TEST 10 FAIL: timeout");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("ALL TASK15 CORE/INTERCONNECT TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);
        $finish;
    end
endmodule
