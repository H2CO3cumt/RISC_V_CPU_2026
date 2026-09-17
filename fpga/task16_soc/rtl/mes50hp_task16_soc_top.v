// MES50HP board wrapper for the Task 16 single-cycle reference SoC.
// Board pins, reset, RAM and MMIO devices are deliberately all outside Core.
module mes50hp_task16_soc_top #(
    parameter MEM_INIT_FILE = "mem/task16_mmio_demo.mem",
    parameter UART_BAUD_CYCLES = 50_000_000 / 115200
) (
    input wire clk_50m,
    input wire uart0_rx,
    output wire uart0_tx,
    output wire [7:0] led
);
    reg [7:0] por_count = 8'd0;
    reg reset = 1'b1;
    always @(posedge clk_50m) begin
        if (reset) begin
            por_count <= por_count + 1'b1;
            if (&por_count) reset <= 1'b0;
        end
    end

    wire iv, ir, rv, rr, ie, dv, dr, dw, dsv, dsr, de;
    wire [31:0] ia, idata, da, dwd, drd;
    wire [3:0] dst;
    wire ram_v, ram_r, uart_v, uart_r, gpio_v, gpio_r, app_v, app_r;
    wire [31:0] ta, twd, ram_rd, uart_rd, gpio_rd, app_rd;
    wire tw, ram_sv, uart_sv, gpio_sv, app_sv, ram_sr, uart_sr, gpio_sr, app_sr;
    wire [3:0] tws;
    wire ram_se, uart_se, gpio_se, app_se;
    wire [31:0] gpio_out;

    single_cycle_cpu core (
        .clk(clk_50m), .reset(reset), .trace_valid(), .trace_pc(), .trace_instruction(),
        .trace_rd_we(), .trace_rd_addr(), .trace_rd_data(), .trace_mem_we(), .trace_mem_addr(), .trace_mem_data(), .trace_mem_wstrb(),
        .i_req_valid(iv), .i_req_ready(ir), .i_req_addr(ia), .i_rsp_valid(rv), .i_rsp_ready(rr), .i_rsp_data(idata), .i_rsp_error(ie),
        .d_req_valid(dv), .d_req_ready(dr), .d_req_addr(da), .d_req_write(dw), .d_req_wdata(dwd), .d_req_wstrb(dst),
        .d_rsp_valid(dsv), .d_rsp_ready(dsr), .d_rsp_rdata(drd), .d_rsp_error(de)
    );
    soc_fpga_imem #(.INIT_FILE(MEM_INIT_FILE)) imem (
        .clk(clk_50m), .reset(reset), .req_valid(iv), .req_ready(ir), .req_addr(ia), .rsp_valid(rv), .rsp_ready(rr), .rsp_data(idata), .rsp_error(ie));
    soc_data_interconnect xbar (
        .clk(clk_50m), .reset(reset), .cpu_req_valid(dv), .cpu_req_ready(dr), .cpu_req_addr(da), .cpu_req_write(dw), .cpu_req_wdata(dwd), .cpu_req_wstrb(dst), .cpu_rsp_valid(dsv), .cpu_rsp_ready(dsr), .cpu_rsp_rdata(drd), .cpu_rsp_error(de),
        .ram_req_valid(ram_v), .ram_req_ready(ram_r), .uart_req_valid(uart_v), .uart_req_ready(uart_r), .gpio_req_valid(gpio_v), .gpio_req_ready(gpio_r), .app_req_valid(app_v), .app_req_ready(app_r),
        .target_req_addr(ta), .target_req_write(tw), .target_req_wdata(twd), .target_req_wstrb(tws),
        .ram_rsp_valid(ram_sv), .ram_rsp_ready(ram_sr), .ram_rsp_rdata(ram_rd), .ram_rsp_error(ram_se), .uart_rsp_valid(uart_sv), .uart_rsp_ready(uart_sr), .uart_rsp_rdata(uart_rd), .uart_rsp_error(uart_se), .gpio_rsp_valid(gpio_sv), .gpio_rsp_ready(gpio_sr), .gpio_rsp_rdata(gpio_rd), .gpio_rsp_error(gpio_se), .app_rsp_valid(app_sv), .app_rsp_ready(app_sr), .app_rsp_rdata(app_rd), .app_rsp_error(app_se));
    soc_fpga_dmem #(.INIT_FILE(MEM_INIT_FILE)) dmem (.clk(clk_50m), .reset(reset), .req_valid(ram_v), .req_ready(ram_r), .req_addr(ta), .req_write(tw), .req_wdata(twd), .req_wstrb(tws), .rsp_valid(ram_sv), .rsp_ready(ram_sr), .rsp_rdata(ram_rd), .rsp_error(ram_se));
    uart_mmio #(.UART_MAX_1BAUD(UART_BAUD_CYCLES), .UART_RX_MAX_1BAUD(UART_BAUD_CYCLES)) uart (.clk(clk_50m), .reset(reset), .uart_req_valid(uart_v), .uart_req_ready(uart_r), .uart_req_addr(ta), .uart_req_write(tw), .uart_req_wdata(twd), .uart_req_wstrb(tws), .uart_rsp_valid(uart_sv), .uart_rsp_ready(uart_sr), .uart_rsp_rdata(uart_rd), .uart_rsp_error(uart_se), .uart_rx(uart0_rx), .uart_tx(uart0_tx));
    gpio_mmio gpio (.clk(clk_50m), .reset(reset), .gpio_req_valid(gpio_v), .gpio_req_ready(gpio_r), .gpio_req_addr(ta), .gpio_req_write(tw), .gpio_req_wdata(twd), .gpio_req_wstrb(tws), .gpio_rsp_valid(gpio_sv), .gpio_rsp_ready(gpio_sr), .gpio_rsp_rdata(gpio_rd), .gpio_rsp_error(gpio_se), .gpio_out(gpio_out));
    soc_fpga_app_dummy app (.clk(clk_50m), .reset(reset), .req_valid(app_v), .req_ready(app_r), .rsp_valid(app_sv), .rsp_ready(app_sr), .rsp_rdata(app_rd), .rsp_error(app_se));
    // MES50HP LEDs are active high; this demo exposes GPIO[7:0] directly.
    assign led = gpio_out[7:0];
endmodule
