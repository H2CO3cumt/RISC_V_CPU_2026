// Core 外部性能监视器。计数器只消费通用退休/流水事件，不含任何 MMIO 地址
// 或外设状态；SoC 若需要软件读取，可在外部把这些只读计数器映射为寄存器。
// CoreMark/逻辑分析仪 布局布线后最差 setup 路径全部是
// `core/rf/regs/iGopDrm -> core/exalu -> ex_result -> N161.eq_* (16 级相等比较)
// -> N164/perf_mispredict -> N172/perf_flush (fanout=46) -> flush_count[24..60]
// 的 10 级进位链`，26 级逻辑、arrival 22.789 ns、slack +1.805 ns（50 MHz 约束）。
// 路径尾部“事件 -> 64-bit 计数器进位链”这一段约 2.5~3.4 ns 纯属观测逻辑；
// 先把事件在寄存器里锁一拍，组合路径就从“事件分类 + 计数器进位链”变成
// “只走计数器进位链”，等于把这段组合深度整段砍掉。
// 所有输出都是只读统计量，不参与 IF/ID/EX/MEM/WB、Hazard、
// Forwarding、提交或任何架构状态；积分的只是“哪一拍 +1”，因此事件整体
// 晚一拍只影响计数时刻，不改变程序行为、提交 trace 或最终计数值。
// clear 那一拍被寄存器吃掉的事件不计数（运行期统计可忽略）。
// 端口与计数器宽度不变，SoC/Testbench 无需修改。
module perf_monitor(
    input wire clk,input wire reset,input wire clear,input wire enable,
    input wire event_retire,input wire event_stall,input wire event_load_stall,
    input wire event_branch,input wire event_branch_taken,input wire event_flush,
    input wire event_predict,input wire event_btb_hit,input wire event_mispredict,
    input wire event_control_redirect,
    output reg [63:0] cycle_count,output reg [63:0] instret_count,
    output reg [63:0] stall_count,output reg [63:0] load_stall_count,
    output reg [63:0] branch_count,output reg [63:0] branch_taken_count,
    output reg [63:0] flush_count,output reg [63:0] predict_count,
    output reg [63:0] btb_hit_count,output reg [63:0] mispredict_count,
    output reg [63:0] control_redirect_count
);
 // 事件暂存级：把 Core 侧的长组合事件分类结果先锁存，切断事件到计数器进位链的组合路径。
 reg q_retire,q_stall,q_load_stall,q_branch,q_branch_taken,q_flush,q_predict,q_btb_hit,q_mispredict,q_ctrl_ok;
 always @(posedge clk) begin
  if(reset||clear)begin q_retire<=0;q_stall<=0;q_load_stall<=0;q_branch<=0;q_branch_taken<=0;q_flush<=0;q_predict<=0;q_btb_hit<=0;q_mispredict<=0;q_ctrl_ok<=0;end
  else if(enable)begin
   q_retire<=event_retire;q_stall<=event_stall;q_load_stall<=event_load_stall;
   q_branch<=event_branch;q_branch_taken<=event_branch_taken;q_flush<=event_flush;
   q_predict<=event_predict;q_btb_hit<=event_btb_hit;q_mispredict<=event_mispredict;
   q_ctrl_ok<=event_control_redirect;
  end
 end
 always @(posedge clk) begin
  if(reset||clear)begin cycle_count<=0;instret_count<=0;stall_count<=0;load_stall_count<=0;branch_count<=0;branch_taken_count<=0;flush_count<=0;predict_count<=0;btb_hit_count<=0;mispredict_count<=0;control_redirect_count<=0;end
  else if(enable)begin
   cycle_count<=cycle_count+1'b1;if(q_retire)instret_count<=instret_count+1'b1;
   if(q_stall)stall_count<=stall_count+1'b1;if(q_load_stall)load_stall_count<=load_stall_count+1'b1;
   if(q_branch)branch_count<=branch_count+1'b1;if(q_branch_taken)branch_taken_count<=branch_taken_count+1'b1;
   if(q_flush)flush_count<=flush_count+1'b1;
   if(q_predict)predict_count<=predict_count+1'b1;
   if(q_btb_hit)btb_hit_count<=btb_hit_count+1'b1;
   if(q_mispredict)mispredict_count<=mispredict_count+1'b1;
   if(q_ctrl_ok)control_redirect_count<=control_redirect_count+1'b1;
  end
 end
endmodule
