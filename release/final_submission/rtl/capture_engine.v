// 8-channel Raw capture engine.  This is a Core-external peripheral: all
// control/status and sample data cross the generic SoC MMIO port.
module capture_engine #(
 parameter CHANNELS=8, parameter DEPTH=256
)(
 input wire clk,input wire reset,input wire [CHANNELS-1:0] channels,
 input wire arm,input wire stop,input wire clear,
 input wire [15:0] sample_div,input wire [CHANNELS-1:0] channel_mask,
 input wire [CHANNELS-1:0] trigger_mask,input wire [CHANNELS-1:0] trigger_value,
 input wire [CHANNELS-1:0] trigger_rise,input wire [CHANNELS-1:0] trigger_fall,
 input wire [15:0] pre_count,input wire [15:0] post_count,input wire [15:0] read_index,
 output wire [CHANNELS-1:0] read_data,output reg armed,output reg triggered,output reg done,output reg overflow,
 output reg [15:0] trigger_index,output reg [15:0] capture_count
);
 localparam [15:0] DEPTH16=DEPTH;
 reg [CHANNELS-1:0] mem[0:DEPTH-1],previous_sample;reg [15:0]write_ptr,div_count,post_remaining,start_index;integer i;
 wire sample_tick=(sample_div==0)||(div_count>=sample_div);
 wire [CHANNELS-1:0] active_mask=trigger_mask&channel_mask;
 // 至少为触发样本保留一个槽，再从剩余容量分配 post 和 pre。
 // 这样任意软件配置都不会让触发样本或尾部样本被环形写回覆盖。
 wire [15:0] post_used=(post_count>=DEPTH16)?(DEPTH16-1'b1):post_count;
 wire [15:0] pre_capacity=DEPTH16-1'b1-post_used;
 wire [15:0] pre_used=(pre_count>pre_capacity)?pre_capacity:pre_count;
 wire [15:0] available_pre=(capture_count<pre_used)?capture_count:pre_used;
 wire level_hit=(active_mask!=0)&&((channels&active_mask)==(trigger_value&active_mask));
 wire rise_hit=(active_mask!=0)&&(trigger_rise!=0)&&(((~previous_sample)&channels&trigger_rise&active_mask)==(trigger_rise&active_mask));
 wire fall_hit=(active_mask!=0)&&(trigger_fall!=0)&&((previous_sample&~channels&trigger_fall&active_mask)==(trigger_fall&active_mask));
 wire trigger_hit=(trigger_rise!=0||trigger_fall!=0)?(rise_hit||fall_hit):level_hit;
 wire [15:0] logical_addr=start_index+read_index;
 assign read_data=mem[logical_addr%DEPTH];
 always @(posedge clk) begin
  if(reset||clear)begin armed<=0;triggered<=0;done<=0;overflow<=0;trigger_index<=0;capture_count<=0;write_ptr<=0;div_count<=0;post_remaining<=0;start_index<=0;previous_sample<=0;for(i=0;i<DEPTH;i=i+1)mem[i]<=0;end
  else begin
   if(arm)begin armed<=1;triggered<=0;done<=0;overflow<=0;trigger_index<=0;capture_count<=0;write_ptr<=0;div_count<=0;post_remaining<=post_count;start_index<=0;previous_sample<=channels;end
   else if(stop)begin armed<=0;done<=1;end
   else if(armed&&sample_tick)begin
    // 边沿必须相对于“上一有效采样点”判断；若每个系统时钟都更新，
    // 分频采样会在 sample_tick 到来前丢掉仅持续一拍的 rise/fall 标志。
    previous_sample<=channels;
    // Store only enabled channels; disabled inputs cannot leak into the Raw
    // stream and therefore remain deterministic across board revisions.
    mem[write_ptr]<=channels&channel_mask;write_ptr<=(write_ptr==DEPTH-1)?0:write_ptr+1'b1;
    if(capture_count<DEPTH)capture_count<=capture_count+1'b1;else overflow<=1;
    if(!triggered&&trigger_hit)begin
     triggered<=1;
     // 对软件公开的是导出 Raw 流中的逻辑位置，不是会 wrap 的物理地址。
     trigger_index<=available_pre;
     start_index<=(write_ptr>=available_pre)?write_ptr-available_pre:DEPTH16-(available_pre-write_ptr);
     capture_count<=available_pre+1'b1;
     post_remaining<=post_used;
     if(post_used==0)begin armed<=0;done<=1;end
    end
    else if(triggered)begin
     // post_count 精确表示触发样本之后的样本数，remaining=1 的本拍即最后一拍。
     if(post_remaining<=1)begin armed<=0;done<=1;post_remaining<=0;end
     else post_remaining<=post_remaining-1'b1;
    end
    div_count<=0;
   end else if(armed)div_count<=div_count+1'b1;
  end
 end
endmodule
