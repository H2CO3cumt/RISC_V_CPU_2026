// 性能计数器的 Core 外部 MMIO 只读窗口。地址由 SoC 互连选择，本模块不含
// 固定基地址；每笔请求一个响应，CONTROL[0] 写 1 产生一个 clear 脉冲。
module perf_mmio(
 input wire clk,input wire reset,input wire req_valid,output wire req_ready,input wire [31:0] req_addr,input wire req_write,input wire [31:0] req_wdata,input wire [3:0] req_wstrb,
 output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,output reg clear,
 input wire [63:0] cycle_count,input wire [63:0] instret_count,input wire [63:0] stall_count,input wire [63:0] load_stall_count,input wire [63:0] branch_count,input wire [63:0] branch_taken_count,input wire [63:0] flush_count,
 input wire [63:0] predict_count,input wire [63:0] btb_hit_count,input wire [63:0] mispredict_count
);
 assign req_ready=!rsp_valid;
 wire aligned=(req_addr[1:0]==2'b00);
 wire valid_offset=aligned && ((req_addr[7:2]<=6'd13) ||
                               ((req_addr[7:2]==6'd14) && req_write) ||
                               ((!req_write)&&(req_addr[7:2]>=6'd16)&&(req_addr[7:2]<=6'd21)));
 always @(posedge clk) begin
  if(reset)begin rsp_valid<=0;clear<=0;rsp_rdata<=0;rsp_error<=0;end else begin
   clear<=0;
   if(req_valid&&req_ready)begin
    rsp_valid<=1;
    // Latch response data/error with the accepted request.  The Core may
    // change its address immediately after ready; the response must not.
    rsp_error<=!valid_offset;
    rsp_rdata<=32'b0;
    if(valid_offset && !req_write) begin
     case(req_addr[7:2])
      6'd0: rsp_rdata<=cycle_count[31:0];
      6'd1: rsp_rdata<=cycle_count[63:32];
      6'd2: rsp_rdata<=instret_count[31:0];
      6'd3: rsp_rdata<=instret_count[63:32];
      6'd4: rsp_rdata<=stall_count[31:0];
      6'd5: rsp_rdata<=stall_count[63:32];
      6'd6: rsp_rdata<=load_stall_count[31:0];
      6'd7: rsp_rdata<=load_stall_count[63:32];
      6'd8: rsp_rdata<=branch_count[31:0];
      6'd9: rsp_rdata<=branch_count[63:32];
      6'd10: rsp_rdata<=branch_taken_count[31:0];
      6'd11: rsp_rdata<=branch_taken_count[63:32];
      6'd12: rsp_rdata<=flush_count[31:0];
      6'd13: rsp_rdata<=flush_count[63:32];
      6'd16: rsp_rdata<=predict_count[31:0];
      6'd17: rsp_rdata<=predict_count[63:32];
      6'd18: rsp_rdata<=btb_hit_count[31:0];
      6'd19: rsp_rdata<=btb_hit_count[63:32];
      6'd20: rsp_rdata<=mispredict_count[31:0];
      6'd21: rsp_rdata<=mispredict_count[63:32];
      default: rsp_rdata<=32'b0;
     endcase
    end
    if(valid_offset && req_write && req_wstrb[0] && req_addr[7:2]==6'd14 && req_wdata[0])clear<=1;
   end
   else if(rsp_valid&&rsp_ready)rsp_valid<=0;
  end
 end
endmodule
