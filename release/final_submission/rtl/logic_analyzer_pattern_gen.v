
module logic_analyzer_pattern_gen(
 input wire clk,input wire reset,input wire restart,input wire [1:0] mode,
 input wire [15:0] tick_div,input wire [7:0] pattern_data,
 output reg [7:0] pattern_out
);
 reg [15:0] div_count;
 reg [7:0] counter_value;
 reg [3:0] uart_bit;
 reg spi_phase,spi_gap;
 reg [2:0] spi_bit;
 wire tick=div_count>=tick_div;
 always @(*) begin
  case(mode)
   2'd0: pattern_out=pattern_data;
   2'd1: pattern_out=counter_value;
   2'd2: begin
    pattern_out=8'hff;//刚开始是8‘b1111_1111,后面只改第1位
    if(uart_bit==0)
    pattern_out[0]=1'b0;//起始位
    else if(uart_bit<=8)
        pattern_out[0]=pattern_data[uart_bit[2:0]-3'd1];//从低到高发送
    else pattern_out[0]=1'b1;
   end
   default: begin
    pattern_out=8'b0;
    pattern_out[2]=spi_gap;
    pattern_out[0]=spi_phase&&!spi_gap;
    pattern_out[1]=pattern_data[7-spi_bit];
   end
  endcase
 end
 always @(posedge clk) begin
  // UART restart 先进入一个完整 idle-high 位。软件随后 Arm 捕获器，
  // 下一次下降沿才是确定的起始位，避免把数据位内部下降沿误判成帧头。
  if(reset||restart)
  begin div_count<=0;
    counter_value<=0;
    uart_bit<=10;
    spi_phase<=0;
    spi_gap<=1;
    spi_bit<=0;end
  else if(tick)begin//脉冲来了
   div_count<=0;
   case(mode)
    2'd1:counter_value<=counter_value+1'b1;
    2'd2:uart_bit<=(uart_bit==10)?0:uart_bit+1'b1;//得先是空闲位，不能是第0位，不然会导致捕捉错误
    2'd3:begin
     if(spi_gap)begin
         spi_gap<=0;
         spi_phase<=0;
         spi_bit<=0;end
     else if(!spi_phase)
        spi_phase<=1;
     else begin spi_phase<=0;
        if(spi_bit==7)begin 
            spi_bit<=0;
            spi_gap<=1;end 
            else spi_bit<=spi_bit+1'b1;end
    end
    default:begin counter_value<=0;
        uart_bit<=0;
        spi_phase<=0;
        spi_gap<=1;
        spi_bit<=0;end
   endcase
  end else div_count<=div_count+1'b1;
 end
endmodule
