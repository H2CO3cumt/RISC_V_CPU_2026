`timescale 1ns/1ps

// Task 16 end-to-end harness.  The unchanged CPU executes the real GCC
// image; all storage, address decoding and peripherals stay outside Core.
module tb_task16_soc_harness;
    localparam UART_BIT_CYCLES = 16;
    localparam UART_EXPECTED_BYTES = 15;

    reg clk;
    reg reset;
    reg uart_rx;
    integer failures;
    integer cycle_count;
    integer uart_byte_count;
    integer monitor_frame_error_count;

    wire i_req_valid, i_req_ready, i_rsp_valid, i_rsp_ready, i_rsp_error;
    wire [31:0] i_req_addr, i_rsp_data;
    wire d_req_valid, d_req_ready, d_req_write;
    wire [31:0] d_req_addr, d_req_wdata;
    wire [3:0] d_req_wstrb;
    wire d_rsp_valid, d_rsp_ready, d_rsp_error;
    wire [31:0] d_rsp_rdata;
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
    wire [7:0] monitor_uart_data;
    wire monitor_uart_data_vld, monitor_uart_frame_error;
    reg [7:0] uart_bytes [0:UART_EXPECTED_BYTES-1];

    single_cycle_cpu core (
        .clk(clk), .reset(reset),
        .trace_valid(), .trace_pc(), .trace_instruction(),
        .trace_rd_we(), .trace_rd_addr(), .trace_rd_data(),
        .trace_mem_we(), .trace_mem_addr(), .trace_mem_data(), .trace_mem_wstrb(),
        .i_req_valid(i_req_valid), .i_req_ready(i_req_ready), .i_req_addr(i_req_addr),
        .i_rsp_valid(i_rsp_valid), .i_rsp_ready(i_rsp_ready), .i_rsp_data(i_rsp_data), .i_rsp_error(i_rsp_error),
        .d_req_valid(d_req_valid), .d_req_ready(d_req_ready), .d_req_addr(d_req_addr),
        .d_req_write(d_req_write), .d_req_wdata(d_req_wdata), .d_req_wstrb(d_req_wstrb),
        .d_rsp_valid(d_rsp_valid), .d_rsp_ready(d_rsp_ready), .d_rsp_rdata(d_rsp_rdata), .d_rsp_error(d_rsp_error)
    );

    task15_imem_adapter #(
        .DEPTH(256),
        .INIT_FILE("software/task16_mmio_demo/build/task16_mmio_demo.mem"),
        .RANDOM_DELAY(0)
    ) imem (
        .clk(clk), .reset(reset), .req_valid(i_req_valid), .req_ready(i_req_ready), .req_addr(i_req_addr),
        .rsp_valid(i_rsp_valid), .rsp_ready(i_rsp_ready), .rsp_data(i_rsp_data), .rsp_error(i_rsp_error)
    );

    soc_data_interconnect u_interconnect (
        .clk(clk), .reset(reset),
        .cpu_req_valid(d_req_valid), .cpu_req_ready(d_req_ready), .cpu_req_addr(d_req_addr),
        .cpu_req_write(d_req_write), .cpu_req_wdata(d_req_wdata), .cpu_req_wstrb(d_req_wstrb),
        .cpu_rsp_valid(d_rsp_valid), .cpu_rsp_ready(d_rsp_ready), .cpu_rsp_rdata(d_rsp_rdata), .cpu_rsp_error(d_rsp_error),
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

    // The linker places .text and .rodata in the same 1 KiB RAM image.
    // This Harvard harness therefore preloads both external instruction ROM
    // and data RAM, so LBU reads of the string use the linked bytes at 0x50.
    task15_ram_adapter #(
        .DEPTH(256),
        .INIT_FILE("software/task16_mmio_demo/build/task16_mmio_demo.mem"),
        .RANDOM_DELAY(0)
    ) ram (
        .clk(clk), .reset(reset), .req_valid(ram_req_valid), .req_ready(ram_req_ready),
        .req_addr(target_req_addr), .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(ram_rsp_valid), .rsp_ready(ram_rsp_ready), .rsp_rdata(ram_rsp_rdata), .rsp_error(ram_rsp_error), .write_side_effect_count()
    );

    uart_mmio #(.UART_MAX_1BAUD(UART_BIT_CYCLES), .UART_RX_MAX_1BAUD(UART_BIT_CYCLES)) uart (
        .clk(clk), .reset(reset), .uart_req_valid(uart_req_valid), .uart_req_ready(uart_req_ready),
        .uart_req_addr(target_req_addr), .uart_req_write(target_req_write), .uart_req_wdata(target_req_wdata), .uart_req_wstrb(target_req_wstrb),
        .uart_rsp_valid(uart_rsp_valid), .uart_rsp_ready(uart_rsp_ready), .uart_rsp_rdata(uart_rsp_rdata), .uart_rsp_error(uart_rsp_error),
        .uart_rx(uart_rx), .uart_tx(uart_tx)
    );

    // Reuse the independently verified 8N1 receiver as a line observer.
    // It is not connected to the SoC transaction path and cannot affect TX.
    UART_RX #(.MAX_1BAUD(UART_BIT_CYCLES)) uart_monitor (
        .clk_50m(clk), .rst(reset), .rx(uart_tx),
        .rx_data(monitor_uart_data), .rx_data_vld(monitor_uart_data_vld),
        .rx_frame_error(monitor_uart_frame_error)
    );

    gpio_mmio gpio (
        .clk(clk), .reset(reset), .gpio_req_valid(gpio_req_valid), .gpio_req_ready(gpio_req_ready),
        .gpio_req_addr(target_req_addr), .gpio_req_write(target_req_write), .gpio_req_wdata(target_req_wdata), .gpio_req_wstrb(target_req_wstrb),
        .gpio_rsp_valid(gpio_rsp_valid), .gpio_rsp_ready(gpio_rsp_ready), .gpio_rsp_rdata(gpio_rsp_rdata), .gpio_rsp_error(gpio_rsp_error),
        .gpio_out(gpio_out)
    );

    task15_test_target app (
        .clk(clk), .reset(reset), .req_valid(app_req_valid), .req_ready(app_req_ready),
        .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb),
        .rsp_valid(app_rsp_valid), .rsp_ready(app_rsp_ready), .rsp_rdata(app_rsp_rdata), .rsp_error(app_rsp_error), .request_count(), .write_count()
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset) begin
            uart_byte_count = 0;
            monitor_frame_error_count = 0;
        end
        else begin
            if (monitor_uart_data_vld && (uart_byte_count < UART_EXPECTED_BYTES)) begin
                uart_bytes[uart_byte_count] = monitor_uart_data;
                uart_byte_count = uart_byte_count + 1;
            end
            if (monitor_uart_frame_error)
                monitor_frame_error_count = monitor_frame_error_count + 1;
        end
    end

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input integer number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS", number);
            else begin
                $display("TEST %0d FAIL: expected=%h actual=%h", number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task expect_byte;
        input [7:0] actual;
        input [7:0] expected;
        input integer number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS: UART byte %0d = %02h", number, number - 3, actual);
            else begin
                $display("TEST %0d FAIL: UART byte %0d expected=%02h actual=%02h", number, number - 3, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        uart_rx = 1'b1;
        failures = 0;
        cycle_count = 0;
        monitor_frame_error_count = 0;
        repeat (2) @(negedge clk);
        reset = 1'b0;

        while ((uart_byte_count < UART_EXPECTED_BYTES) && (cycle_count < 8000)) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        // Let the final sampled data bit settle before evaluating assertions.
        @(negedge clk);

        expect_word(gpio_out, 32'h0000_00AA, 1);
        expect_word(uart_byte_count, UART_EXPECTED_BYTES, 2);
        expect_byte(uart_bytes[0],  "H", 3);
        expect_byte(uart_bytes[1],  "e", 4);
        expect_byte(uart_bytes[2],  "l", 5);
        expect_byte(uart_bytes[3],  "l", 6);
        expect_byte(uart_bytes[4],  "o", 7);
        expect_byte(uart_bytes[5],  " ", 8);
        expect_byte(uart_bytes[6],  "R", 9);
        expect_byte(uart_bytes[7],  "I", 10);
        expect_byte(uart_bytes[8],  "S", 11);
        expect_byte(uart_bytes[9],  "C", 12);
        expect_byte(uart_bytes[10], "-", 13);
        expect_byte(uart_bytes[11], "V", 14);
        expect_byte(uart_bytes[12], "!", 15);
        expect_byte(uart_bytes[13], 8'h0D, 16);
        expect_byte(uart_bytes[14], 8'h0A, 17);
        expect_word(monitor_frame_error_count, 32'd0, 18);
        if (cycle_count < 8000)
            $display("TEST 19 PASS: CPU completed GPIO and UART demo in %0d cycle(s)", cycle_count);
        else begin
            $display("TEST 19 FAIL: timeout waiting for UART output");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("ALL TASK16 SOC HARNESS TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);
        $finish;
    end
endmodule
