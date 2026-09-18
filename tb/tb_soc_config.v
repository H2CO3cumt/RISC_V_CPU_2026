`timescale 1ns/1ps

// Task 17 configuration-level reference harness.  Compile exactly one of
// SOC_CONFIG_GPIO_ONLY or SOC_CONFIG_UART_ONLY.  The CPU RTL is unchanged; this file
// only chooses Core-external targets and exports reproducible evidence.
module tb_soc_config;
`ifdef SOC_CONFIG_GPIO_ONLY
    localparam [31:0] FINAL_ADDR = 32'h1000_1000;
    localparam [31:0] FINAL_DATA = 32'h0000_00A5;
    localparam [3:0]  FINAL_STRB = 4'b1111;
`define SOC_CONFIG_IMAGE "software/gpio_only/build/gpio_only.mem"
`elsif SOC_CONFIG_UART_ONLY
    localparam [31:0] FINAL_ADDR = 32'h1000_0000;
    localparam [31:0] FINAL_DATA = 32'h0000_000A;
    localparam [3:0]  FINAL_STRB = 4'b1111;
`define SOC_CONFIG_IMAGE "software/uart_only/build/uart_only.mem"
`else
    initial $fatal(1, "Define SOC_CONFIG_GPIO_ONLY or SOC_CONFIG_UART_ONLY");
`endif

    reg clk, reset;
    integer failures, cycle_count, retired_count, trace_file, state_file, perf_file;
    integer i;
    reg snapshot_taken;
    reg [31:0] snapshot_regs [0:31];
    reg [31:0] snapshot_ram_300;

    wire trace_valid, trace_rd_we, trace_mem_we;
    wire [31:0] trace_pc, trace_instruction, trace_rd_data, trace_mem_addr, trace_mem_data;
    wire [4:0] trace_rd_addr;
    wire [3:0] trace_mem_wstrb;
    wire i_req_valid, i_req_ready, i_rsp_valid, i_rsp_ready, i_rsp_error;
    wire [31:0] i_req_addr, i_rsp_data;
    wire d_req_valid, d_req_ready, d_req_write, d_rsp_valid, d_rsp_ready, d_rsp_error;
    wire [31:0] d_req_addr, d_req_wdata, d_rsp_rdata;
    wire [3:0] d_req_wstrb;
    wire ram_req_valid, ram_req_ready, uart_req_valid, uart_req_ready, gpio_req_valid, gpio_req_ready, app_req_valid, app_req_ready;
    wire [31:0] target_req_addr, target_req_wdata;
    wire target_req_write;
    wire [3:0] target_req_wstrb;
    wire ram_rsp_valid, ram_rsp_ready, ram_rsp_error, uart_rsp_valid, uart_rsp_ready, uart_rsp_error;
    wire gpio_rsp_valid, gpio_rsp_ready, gpio_rsp_error, app_rsp_valid, app_rsp_ready, app_rsp_error;
    wire [31:0] ram_rsp_rdata, uart_rsp_rdata, gpio_rsp_rdata, app_rsp_rdata;
    wire [31:0] gpio_out;

    single_cycle_cpu core (
        .clk(clk), .reset(reset),
        .trace_valid(trace_valid), .trace_pc(trace_pc), .trace_instruction(trace_instruction),
        .trace_rd_we(trace_rd_we), .trace_rd_addr(trace_rd_addr), .trace_rd_data(trace_rd_data),
        .trace_mem_we(trace_mem_we), .trace_mem_addr(trace_mem_addr), .trace_mem_data(trace_mem_data), .trace_mem_wstrb(trace_mem_wstrb),
        .i_req_valid(i_req_valid), .i_req_ready(i_req_ready), .i_req_addr(i_req_addr),
        .i_rsp_valid(i_rsp_valid), .i_rsp_ready(i_rsp_ready), .i_rsp_data(i_rsp_data), .i_rsp_error(i_rsp_error),
        .d_req_valid(d_req_valid), .d_req_ready(d_req_ready), .d_req_addr(d_req_addr), .d_req_write(d_req_write),
        .d_req_wdata(d_req_wdata), .d_req_wstrb(d_req_wstrb), .d_rsp_valid(d_rsp_valid), .d_rsp_ready(d_rsp_ready),
        .d_rsp_rdata(d_rsp_rdata), .d_rsp_error(d_rsp_error)
    );

    imem_adapter #(.DEPTH(256), .INIT_FILE(`SOC_CONFIG_IMAGE), .RANDOM_DELAY(0)) imem (
        .clk(clk), .reset(reset), .req_valid(i_req_valid), .req_ready(i_req_ready), .req_addr(i_req_addr),
        .rsp_valid(i_rsp_valid), .rsp_ready(i_rsp_ready), .rsp_data(i_rsp_data), .rsp_error(i_rsp_error));

    soc_data_interconnect u_interconnect (
        .clk(clk), .reset(reset), .cpu_req_valid(d_req_valid), .cpu_req_ready(d_req_ready), .cpu_req_addr(d_req_addr),
        .cpu_req_write(d_req_write), .cpu_req_wdata(d_req_wdata), .cpu_req_wstrb(d_req_wstrb),
        .cpu_rsp_valid(d_rsp_valid), .cpu_rsp_ready(d_rsp_ready), .cpu_rsp_rdata(d_rsp_rdata), .cpu_rsp_error(d_rsp_error),
        .ram_req_valid(ram_req_valid), .ram_req_ready(ram_req_ready), .uart_req_valid(uart_req_valid), .uart_req_ready(uart_req_ready),
        .gpio_req_valid(gpio_req_valid), .gpio_req_ready(gpio_req_ready), .app_req_valid(app_req_valid), .app_req_ready(app_req_ready),
        .target_req_addr(target_req_addr), .target_req_write(target_req_write), .target_req_wdata(target_req_wdata), .target_req_wstrb(target_req_wstrb),
        .ram_rsp_valid(ram_rsp_valid), .ram_rsp_ready(ram_rsp_ready), .ram_rsp_rdata(ram_rsp_rdata), .ram_rsp_error(ram_rsp_error),
        .uart_rsp_valid(uart_rsp_valid), .uart_rsp_ready(uart_rsp_ready), .uart_rsp_rdata(uart_rsp_rdata), .uart_rsp_error(uart_rsp_error),
        .gpio_rsp_valid(gpio_rsp_valid), .gpio_rsp_ready(gpio_rsp_ready), .gpio_rsp_rdata(gpio_rsp_rdata), .gpio_rsp_error(gpio_rsp_error),
        .app_rsp_valid(app_rsp_valid), .app_rsp_ready(app_rsp_ready), .app_rsp_rdata(app_rsp_rdata), .app_rsp_error(app_rsp_error));

    ram_adapter #(.DEPTH(256), .INIT_FILE(`SOC_CONFIG_IMAGE), .RANDOM_DELAY(0)) ram (
        .clk(clk), .reset(reset), .req_valid(ram_req_valid), .req_ready(ram_req_ready), .req_addr(target_req_addr),
        .req_write(target_req_write), .req_wdata(target_req_wdata), .req_wstrb(target_req_wstrb), .rsp_valid(ram_rsp_valid),
        .rsp_ready(ram_rsp_ready), .rsp_rdata(ram_rsp_rdata), .rsp_error(ram_rsp_error), .write_side_effect_count());

`ifdef SOC_CONFIG_GPIO_ONLY
    gpio_mmio gpio (
        .clk(clk), .reset(reset), .gpio_req_valid(gpio_req_valid), .gpio_req_ready(gpio_req_ready), .gpio_req_addr(target_req_addr),
        .gpio_req_write(target_req_write), .gpio_req_wdata(target_req_wdata), .gpio_req_wstrb(target_req_wstrb),
        .gpio_rsp_valid(gpio_rsp_valid), .gpio_rsp_ready(gpio_rsp_ready), .gpio_rsp_rdata(gpio_rsp_rdata), .gpio_rsp_error(gpio_rsp_error), .gpio_out(gpio_out));
    assign uart_req_ready = 1'b1; assign uart_rsp_valid = 1'b0; assign uart_rsp_rdata = 32'b0; assign uart_rsp_error = 1'b0;
`else
    reg uart_rx;
    wire uart_tx, monitor_valid, monitor_error;
    wire [7:0] monitor_data;
    integer uart_byte_count;
    reg [7:0] uart_bytes [0:1];
    uart_mmio #(.UART_MAX_1BAUD(16), .UART_RX_MAX_1BAUD(16)) uart (
        .clk(clk), .reset(reset), .uart_req_valid(uart_req_valid), .uart_req_ready(uart_req_ready), .uart_req_addr(target_req_addr),
        .uart_req_write(target_req_write), .uart_req_wdata(target_req_wdata), .uart_req_wstrb(target_req_wstrb), .uart_rsp_valid(uart_rsp_valid),
        .uart_rsp_ready(uart_rsp_ready), .uart_rsp_rdata(uart_rsp_rdata), .uart_rsp_error(uart_rsp_error), .uart_rx(uart_rx), .uart_tx(uart_tx));
    UART_RX #(.MAX_1BAUD(16)) monitor (.clk_50m(clk), .rst(reset), .rx(uart_tx), .rx_data(monitor_data), .rx_data_vld(monitor_valid), .rx_frame_error(monitor_error));
    assign gpio_req_ready = 1'b1; assign gpio_rsp_valid = 1'b0; assign gpio_rsp_rdata = 32'b0; assign gpio_rsp_error = 1'b0; assign gpio_out = 32'b0;
`endif
    assign app_req_ready = 1'b1; assign app_rsp_valid = 1'b0; assign app_rsp_rdata = 32'b0; assign app_rsp_error = 1'b0;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0; retired_count <= 0; snapshot_taken <= 1'b0;
`ifdef SOC_CONFIG_UART_ONLY
            uart_byte_count <= 0;
`endif
        end else begin
            cycle_count <= cycle_count + 1;
            if (trace_valid && !snapshot_taken) begin
                retired_count <= retired_count + 1;
                $fdisplay(trace_file, "%0d %08h %08h %0d %0d %08h %0d %08h %08h %01h", retired_count, trace_pc, trace_instruction, trace_rd_we, trace_rd_addr, trace_rd_data, trace_mem_we, trace_mem_addr, trace_mem_data, trace_mem_wstrb);
            end
`ifdef SOC_CONFIG_UART_ONLY
            if (monitor_valid && uart_byte_count < 2) begin uart_bytes[uart_byte_count] <= monitor_data; uart_byte_count <= uart_byte_count + 1; end
            if (monitor_error) failures <= failures + 1;
`endif
            if (trace_valid && trace_mem_we && trace_mem_addr == FINAL_ADDR && trace_mem_data == FINAL_DATA && trace_mem_wstrb == FINAL_STRB && !snapshot_taken) begin
                snapshot_taken <= 1'b1;
                for (i = 0; i < 32; i = i + 1) snapshot_regs[i] <= core.u_regfile.regs[i];
                snapshot_ram_300 <= ram.mem[192];
            end
        end
    end

    task write_evidence;
        begin
            for (i = 1; i < 32; i = i + 1) $fdisplay(state_file, "x%0d=%08h", i, snapshot_regs[i]);
            $fdisplay(state_file, "ram[00000300]=%08h", snapshot_ram_300);
            $fdisplay(state_file, "gpio_out=%08h", gpio_out);
            $fdisplay(perf_file, "cycles=%0d", cycle_count);
            $fdisplay(perf_file, "retired_instructions=%0d", retired_count);
            $fdisplay(perf_file, "cpi_x1000=%0d", (1000 * cycle_count) / retired_count);
        end
    endtask

    initial begin
        clk = 0; reset = 1; failures = 0; cycle_count = 0; retired_count = 0; snapshot_taken = 0;
`ifdef SOC_CONFIG_UART_ONLY
        uart_rx = 1; uart_byte_count = 0;
        trace_file = $fopen("tmp/gcc_evidence/uart_only_trace.actual", "w"); state_file = $fopen("tmp/gcc_evidence/uart_only_state.actual", "w"); perf_file = $fopen("tmp/gcc_evidence/uart_only_perf.actual", "w");
`else
        trace_file = $fopen("tmp/gcc_evidence/gpio_only_trace.actual", "w"); state_file = $fopen("tmp/gcc_evidence/gpio_only_state.actual", "w"); perf_file = $fopen("tmp/gcc_evidence/gpio_only_perf.actual", "w");
`endif
        repeat (2) @(negedge clk); reset = 0;
        wait(snapshot_taken); @(negedge clk); #1;
`ifdef SOC_CONFIG_GPIO_ONLY
        if (gpio_out !== 32'h000000A5) begin $display("GPIO CONFIG FAIL: gpio_out=%h", gpio_out); failures = failures + 1; end
`else
        wait(uart_byte_count == 2); @(negedge clk);
        if (uart_bytes[0] !== "U" || uart_bytes[1] !== 8'h0A) begin $display("UART CONFIG FAIL: bytes=%h %h", uart_bytes[0], uart_bytes[1]); failures = failures + 1; end
`endif
        write_evidence; $fclose(trace_file); $fclose(state_file); $fclose(perf_file);
        if (failures == 0) $display("SOC CONFIGURATION HARNESS PASS"); else $fatal(1, "SOC CONFIGURATION HARNESS FAIL: %0d", failures);
        $finish;
    end
    initial begin #200000; $fatal(1, "SOC configuration harness timeout"); end
endmodule
