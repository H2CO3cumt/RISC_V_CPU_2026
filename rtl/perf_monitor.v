// Core 外部性能监视器。计数器只消费通用退休/流水事件，不含任何 MMIO 地址
// 或外设状态；SoC 若需要软件读取，可在外部把这些只读计数器映射为寄存器。
module perf_monitor(
    input wire clk,input wire reset,input wire clear,input wire enable,
    input wire event_retire,input wire event_stall,input wire event_load_stall,
    input wire event_branch,input wire event_branch_taken,input wire event_flush,
    input wire event_predict,input wire event_btb_hit,input wire event_mispredict,
    output reg [63:0] cycle_count,output reg [63:0] instret_count,
    output reg [63:0] stall_count,output reg [63:0] load_stall_count,
    output reg [63:0] branch_count,output reg [63:0] branch_taken_count,
    output reg [63:0] flush_count,output reg [63:0] predict_count,
    output reg [63:0] btb_hit_count,output reg [63:0] mispredict_count
);
 always @(posedge clk) begin
  if(reset||clear)begin cycle_count<=0;instret_count<=0;stall_count<=0;load_stall_count<=0;branch_count<=0;branch_taken_count<=0;flush_count<=0;predict_count<=0;btb_hit_count<=0;mispredict_count<=0;end
  else if(enable)begin
   cycle_count<=cycle_count+1'b1;if(event_retire)instret_count<=instret_count+1'b1;
   if(event_stall)stall_count<=stall_count+1'b1;if(event_load_stall)load_stall_count<=load_stall_count+1'b1;
   if(event_branch)branch_count<=branch_count+1'b1;if(event_branch_taken)branch_taken_count<=branch_taken_count+1'b1;
   if(event_flush)flush_count<=flush_count+1'b1;
   if(event_predict)predict_count<=predict_count+1'b1;
   if(event_btb_hit)btb_hit_count<=btb_hit_count+1'b1;
   if(event_mispredict)mispredict_count<=mispredict_count+1'b1;
  end
 end
endmodule
