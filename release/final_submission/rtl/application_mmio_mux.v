
module application_mmio_mux(
 input wire clk,input wire reset,
 input wire req_valid,output wire req_ready,input wire [31:0] req_addr,
 input wire req_write,input wire [31:0] req_wdata,input wire [3:0] req_wstrb,
 output wire rsp_valid,input wire rsp_ready,output wire [31:0] rsp_rdata,output wire rsp_error,
 output wire perf_req_valid,input wire perf_req_ready,output wire [31:0] perf_req_addr,
 output wire perf_req_write,output wire [31:0] perf_req_wdata,output wire [3:0] perf_req_wstrb,
 input wire perf_rsp_valid,output wire perf_rsp_ready,input wire [31:0] perf_rsp_rdata,input wire perf_rsp_error,
 output wire la_req_valid,input wire la_req_ready,output wire [31:0] la_req_addr,
 output wire la_req_write,output wire [31:0] la_req_wdata,output wire [3:0] la_req_wstrb,
 input wire la_rsp_valid,output wire la_rsp_ready,input wire [31:0] la_rsp_rdata,input wire la_rsp_error
);
 wire perf_sel = (req_addr[11:8] == 4'h0);
 wire la_sel   = (req_addr[11:8] == 4'h1);
 reg bad_rsp_valid;
 wire endpoint_busy = perf_rsp_valid || la_rsp_valid;
 assign req_ready = !bad_rsp_valid && !endpoint_busy &&
                    (perf_sel ? perf_req_ready : la_sel ? la_req_ready : 1'b1);
 assign perf_req_valid = req_valid && req_ready && perf_sel;
 assign la_req_valid   = req_valid && req_ready && la_sel;
 assign perf_req_addr  = {24'b0,req_addr[7:0]};
 assign la_req_addr    = {24'b0,req_addr[7:0]};//模块化，la和perf不用关系自己到底挂在那里
 assign perf_req_write = req_write; assign la_req_write = req_write;
 assign perf_req_wdata = req_wdata; assign la_req_wdata = req_wdata;
 assign perf_req_wstrb = req_wstrb; assign la_req_wstrb = req_wstrb;//数据可以广播，但是valid决定谁真正在用
 assign rsp_valid = bad_rsp_valid || perf_rsp_valid || la_rsp_valid;
 assign rsp_rdata = bad_rsp_valid ? 32'b0 : (perf_rsp_valid ? perf_rsp_rdata : la_rsp_rdata);
 assign rsp_error = bad_rsp_valid ? 1'b1 : (perf_rsp_valid ? perf_rsp_error : la_rsp_error);
 assign perf_rsp_ready = rsp_ready && !bad_rsp_valid && perf_rsp_valid;
 assign la_rsp_ready   = rsp_ready && !bad_rsp_valid && !perf_rsp_valid && la_rsp_valid;
 always @(posedge clk) begin
  if (reset) bad_rsp_valid <= 1'b0;
  else begin
   if (req_valid && req_ready && !perf_sel && !la_sel)
    bad_rsp_valid <= 1'b1;
   else if (bad_rsp_valid && rsp_ready)
    bad_rsp_valid <= 1'b0;
  end
 end
endmodule
