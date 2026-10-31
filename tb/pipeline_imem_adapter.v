// 单 outstanding 的流水取指模型。响应被 Core 接受的同一拍可以接收下一请求，
// 用于验证 IF 的满速交接；随机模式仍可独立延迟请求和响应。
module pipeline_imem_adapter #(
    parameter DEPTH=256,
    parameter INIT_FILE="",
    parameter RANDOM_DELAY=0,
    // 程序区之外那些没有被 INIT_FILE 覆盖到的字填什么。
    // 默认 0（保持既有行为）；需要"程序跑完就停住"的 Testbench 传 32'h0000_006f
    // （jal x0,0 自跳转），否则前端会一路顺序取到未初始化的 0 字——那是非法指令，
    // 引入 Trap 之后会精确陷入、把 PC 交给 mtvec（默认 0）并**重启整个程序**，
    // 于是"程序结束后的架构状态"就不再是程序的终态（实测 forward 用例的 x9 对不上）。
    parameter [31:0] FILL_WORD=32'h0
)(
    input wire clk,input wire reset,
    input wire req_valid,output wire req_ready,input wire [31:0] req_addr,
    output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_data,output reg rsp_error
);
 reg [31:0] mem[0:DEPTH-1]; reg pending; reg [1:0] delay_count; reg [7:0] lfsr; integer i;
 wire address_ok=(req_addr[1:0]==2'b00)&&(req_addr[31:2]<DEPTH);
 assign req_ready=!pending&&(!rsp_valid||rsp_ready)&&(RANDOM_DELAY?lfsr[0]:1'b1);
 initial begin for(i=0;i<DEPTH;i=i+1)mem[i]=FILL_WORD;if(INIT_FILE!="")$readmemh(INIT_FILE,mem);end
 always @(posedge clk) begin
  if(reset)begin pending<=0;delay_count<=0;rsp_valid<=0;rsp_data<=0;rsp_error<=0;lfsr<=8'h5a;end
  else begin
   lfsr<={lfsr[6:0],lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(pending)begin if(delay_count==0)begin pending<=0;rsp_valid<=1;end else delay_count<=delay_count-1'b1;end
   if(req_valid&&req_ready)begin
    rsp_data<=address_ok?mem[req_addr[31:2]]:0;rsp_error<=!address_ok;
    if(RANDOM_DELAY&&lfsr[2:1]!=0)begin pending<=1;delay_count<=lfsr[2:1]-1'b1;end
    else begin pending<=0;rsp_valid<=1;end
   end
  end
 end
endmodule
