
module logic_analyzer_mmio #(
 // 采集深度：2048 点是为了让"上位机发来的一整句报文"能一屏抓完
 // （12 字符 × 10 bit/字符 × 8 点/bit = 960 点，留一倍余量）。
 // capture_engine.v 本身不改，它的独立 TB 仍可自行传 DEPTH=8/16/256。
 parameter DEPTH=2048
)(
 input wire clk,input wire reset,input wire req_valid,output wire req_ready,input wire [31:0] req_addr,input wire req_write,input wire [31:0] req_wdata,input wire [3:0] req_wstrb,
 output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
 input wire [7:0] channels,input wire [7:0] probe_channels,output wire [7:0] sample_outputs
);
 reg [15:0] sample_div,pre_count,post_count,read_index,pattern_div;reg [7:0] channel_mask,trigger_mask,trigger_value,trigger_rise,trigger_fall,pattern_data;reg [1:0]pattern_mode;reg arm,stop,clear,pattern_restart;
 // 采集源选择（双源可选）：0（默认）= channels，即 J8 外部 8 路物理输入，
 // 与加这个功能之前的行为逐位一致；1 = probe_channels，即 Core 外部的
 // 总线/流水线观测点（取指握手、访存握手、停顿、冲刷、提交）。
 // 选择位是 MMIO 可写的（寄存器 18），所以现场切换采集源不需要重新综合——
 // 沿用 docs/application_logic_analyzer.md G11「现场改变配置」的既有验收方式。
 // 约定：在 Arm 之前设置；Arm 之后再改会让同一次采样的前后段来自不同源。
 reg src_sel;
 // 采集源选择的结果**寄存一拍**再送进采集引擎。
 //
 // 为什么必须寄存：spi 模式的 sample_div=0 意味着采集引擎每拍采样，是四种模式里
 // 最吃时序的一条路径。源选择 MUX 直接串在 channels 到引擎之间时，85 MHz 下
 // 这条路径的余量被吃光，实测表现为"SPI 模式一发配置包固件就永久卡死，
 // 之后连 static 也无响应，必须重下位流"——与 2026-09-30 在 90 MHz 上
 // 记录的症状完全一致（见 release/evidence/fmax_ceiling/README.md §4）。
 // 寄存之后，引擎的输入来自寄存器而不是"管脚/MUX 组合"，这条路径比加这个
 // 功能之前**更短**；代价是采样点整体晚 1 个系统时钟，对逻辑分析仪没有意义
 //（窗口整体平移一格，四种模式与镜像模式的判据都与绝对相位无关）。
 reg [7:0] active_channels_q;
 always @(posedge clk) begin
  if(reset) active_channels_q<=8'h00;
  else active_channels_q<=src_sel?probe_channels:channels;
 end
 wire [7:0] active_channels = active_channels_q;
 wire [7:0] read_data;wire armed,triggered,done,overflow;wire [15:0] trigger_index,capture_count;


 capture_engine #(.DEPTH(DEPTH)) cap(.clk(clk),.reset(reset),.channels(active_channels),.arm(arm),.stop(stop),.clear(clear),.sample_div(sample_div),.channel_mask(channel_mask),.trigger_mask(trigger_mask),.trigger_value(trigger_value),.trigger_rise(trigger_rise),.trigger_fall(trigger_fall),.pre_count(pre_count),.post_count(post_count),.read_index(read_index),.read_data(read_data),.armed(armed),.triggered(triggered),.done(done),.overflow(overflow),.trigger_index(trigger_index),.capture_count(capture_count));
 logic_analyzer_pattern_gen pattern(.clk(clk),.reset(reset),.restart(pattern_restart),.mode(pattern_mode),.tick_div(pattern_div),.pattern_data(pattern_data),.pattern_out(sample_outputs));
 assign req_ready=!rsp_valid;
 wire valid_offset=(req_addr[1:0]==2'b00)&&(req_addr[7:2]<=6'd18);
 always @(posedge clk)begin
  if(reset)begin rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;sample_div<=0;channel_mask<=8'hff;trigger_mask<=0;trigger_value<=0;trigger_rise<=0;trigger_fall<=0;pre_count<=0;post_count<=0;read_index<=0;pattern_div<=0;pattern_data<=0;pattern_mode<=0;arm<=0;stop<=0;clear<=0;pattern_restart<=0;src_sel<=0;end
  else begin
   
   stop <= 1'b0;
   arm <= 1'b0;
   clear <= 1'b0;
   pattern_restart <= 1'b0;
   if (rsp_valid && rsp_ready)
    rsp_valid <= 1'b0;
   if (req_valid && req_ready) begin
    rsp_valid <= 1'b1;
    rsp_error <= !valid_offset;
    rsp_rdata <= 32'b0;
    if (valid_offset && !req_write) begin
     case (req_addr[7:2])
      6'd1:  rsp_rdata <= {28'b0,overflow,done,triggered,armed};
      6'd10: rsp_rdata <= {16'b0,trigger_index};
      6'd11: rsp_rdata <= {16'b0,capture_count};
      6'd13: rsp_rdata <= {24'b0,read_data};
      6'd14: rsp_rdata <= {30'b0,pattern_mode};
      6'd15: rsp_rdata <= {16'b0,pattern_div};
      6'd16: rsp_rdata <= {24'b0,pattern_data};
      6'd17: rsp_rdata <= {24'b0,sample_outputs};
      6'd18: rsp_rdata <= {31'b0,src_sel};
      default: rsp_rdata <= 32'b0;
     endcase
    end
    if (req_write) begin
     case (req_addr[7:2])
      6'd0: begin
       if (req_wstrb[0]) begin
        arm <= req_wdata[0];
        stop <= req_wdata[1];
        clear <= req_wdata[2];
       end
      end
      6'd2: begin if(req_wstrb[0])sample_div[7:0]<=req_wdata[7:0];if(req_wstrb[1])sample_div[15:8]<=req_wdata[15:8];end
      6'd3:  if(req_wstrb[0])channel_mask <= req_wdata[7:0];
      6'd4:  if(req_wstrb[0])trigger_mask <= req_wdata[7:0];
      6'd5:  if(req_wstrb[0])trigger_value <= req_wdata[7:0];
      6'd6:  if(req_wstrb[0])trigger_rise <= req_wdata[7:0];
      6'd7:  if(req_wstrb[0])trigger_fall <= req_wdata[7:0];
      6'd8: begin if(req_wstrb[0])pre_count[7:0]<=req_wdata[7:0];if(req_wstrb[1])pre_count[15:8]<=req_wdata[15:8];end
      6'd9: begin if(req_wstrb[0])post_count[7:0]<=req_wdata[7:0];if(req_wstrb[1])post_count[15:8]<=req_wdata[15:8];end
      6'd12:begin if(req_wstrb[0])read_index[7:0]<=req_wdata[7:0];if(req_wstrb[1])read_index[15:8]<=req_wdata[15:8];end
      6'd14:if(req_wstrb[0])begin pattern_mode<=req_wdata[1:0];pattern_restart<=req_wdata[2];end
      6'd15:begin if(req_wstrb[0])pattern_div[7:0]<=req_wdata[7:0];if(req_wstrb[1])pattern_div[15:8]<=req_wdata[15:8];end
      6'd16:if(req_wstrb[0])pattern_data<=req_wdata[7:0];
      6'd18:if(req_wstrb[0])src_sel<=req_wdata[0];
      default: begin end
     endcase
    end
   end
  end
 end
endmodule
