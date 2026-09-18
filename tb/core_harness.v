// Test-only SoC shell.  Storage is deliberately outside the Core.
module core_harness #(
    parameter IMEM_DEPTH = 256,
    parameter DMEM_DEPTH = 256,
    parameter IMEM_INIT_FILE = "",
    parameter DMEM_INIT_FILE = ""
) (
    input wire clk, input wire reset,
    output wire trace_valid, output wire [31:0] trace_pc, output wire [31:0] trace_instruction,
    output wire trace_rd_we, output wire [4:0] trace_rd_addr, output wire [31:0] trace_rd_data,
    output wire trace_mem_we, output wire [31:0] trace_mem_addr, output wire [31:0] trace_mem_data,
    output wire [3:0] trace_mem_wstrb
);
    wire iv, ir, rv, rr, ie;
    wire [31:0] ia, idata;
    wire dv, dr, dw, dsv, dsr, de;
    wire [31:0] da, dwd, drd;
    wire [3:0] dst;

    single_cycle_cpu core (
        .clk(clk), .reset(reset),
        .trace_valid(trace_valid), .trace_pc(trace_pc), .trace_instruction(trace_instruction),
        .trace_rd_we(trace_rd_we), .trace_rd_addr(trace_rd_addr), .trace_rd_data(trace_rd_data),
        .trace_mem_we(trace_mem_we), .trace_mem_addr(trace_mem_addr), .trace_mem_data(trace_mem_data), .trace_mem_wstrb(trace_mem_wstrb),
        .i_req_valid(iv), .i_req_ready(ir), .i_req_addr(ia), .i_rsp_valid(rv), .i_rsp_ready(rr), .i_rsp_data(idata), .i_rsp_error(ie),
        .d_req_valid(dv), .d_req_ready(dr), .d_req_addr(da), .d_req_write(dw), .d_req_wdata(dwd), .d_req_wstrb(dst), .d_rsp_valid(dsv), .d_rsp_ready(dsr), .d_rsp_rdata(drd), .d_rsp_error(de)
    );
    // Test harness uses zero/fixed latency; dedicated Task 15 tests cover random backpressure.
    imem_adapter #(.DEPTH(IMEM_DEPTH), .INIT_FILE(IMEM_INIT_FILE), .RANDOM_DELAY(0)) imem (
        .clk(clk), .reset(reset), .req_valid(iv), .req_ready(ir), .req_addr(ia), .rsp_valid(rv), .rsp_ready(rr), .rsp_data(idata), .rsp_error(ie)
    );
    ram_adapter #(.DEPTH(DMEM_DEPTH), .INIT_FILE(DMEM_INIT_FILE), .RANDOM_DELAY(0)) ram (
        .clk(clk), .reset(reset), .req_valid(dv), .req_ready(dr), .req_addr(da), .req_write(dw), .req_wdata(dwd), .req_wstrb(dst), .rsp_valid(dsv), .rsp_ready(dsr), .rsp_rdata(drd), .rsp_error(de), .write_side_effect_count()
    );
endmodule
