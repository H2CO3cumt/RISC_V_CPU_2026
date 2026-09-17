module UART_TX(
input wire clk_50m,
input wire rst,
input wire tx_data_vld,
input wire [7:0] tx_data,
output wire ready,
output reg tx
);
  localparam CLOCK=50_000_000;//系统时钟频率
  localparam BAUD=115200;//波特率
  localparam CHECK_BIT="None";
  parameter MAX_1BAUD=CLOCK/BAUD;//发送一波特数据需要多少个系统时钟
  parameter IDLE=5'b00000;
  parameter START=5'b00001;
  parameter DATA=5'b00010;
  parameter CHECK=5'b00100;
  parameter STOP=5'b01000;
  reg [4:0]cstate;
  reg [4:0]nstate;
  reg [15:0]cnt_baud;
  reg [3:0]cnt_bit;
  reg [3:0]max_bit;
  reg [7:0]tx_data_r;//暂时数据寄存器，防止发送数据的过程中，系统输入的tx_data发生变化，导致tx无法正确输出
  wire add_baud;
  wire end_baud;
  wire add_bit;
  wire end_bit;
  wire check_val;
  // 即使本届固定为 8N1，仍给不可达的校验位状态一个确定值，避免综合器
  // 将其报告为悬空网络；奇/偶校验的表达式也便于以后独立复用 UART。
  assign check_val = (CHECK_BIT == "Odd") ? ~^tx_data_r : ^tx_data_r;
  wire IDLE_START=(cstate==IDLE) && tx_data_vld;
  wire START_DATA=(cstate==START) && end_bit;
  wire DATA_CHECK=(cstate==DATA) && end_bit && (CHECK_BIT!="None");
  wire DATA_STOP=(cstate==DATA) && end_bit && (CHECK_BIT=="None");
  wire CHECK_STOP=(cstate==CHECK) && end_bit;
  wire STOP_IDLE=(cstate==STOP)&& end_bit;
  always @ ( posedge clk_50m or posedge rst )
  begin 
  	if(rst)
      cnt_baud<=0;
      else begin
      		if(add_baud) begin
              if(end_baud)
              		cnt_baud<=0;
              else cnt_baud<=cnt_baud+1;
                       end
           else cnt_baud<=0;
      end 
  end
  assign add_baud=cstate!=IDLE;//只要不在空闲位，就开始计算
  assign end_baud=add_baud && (cnt_baud==MAX_1BAUD-1);
  always @ ( posedge clk_50m or posedge rst )
  begin 
  	if(rst)
      cnt_bit<=0;
      else begin
      		if(add_bit) begin
              if(end_bit)
              		cnt_bit<=0;
              else cnt_bit<=cnt_bit+1;
                       end
      end 
  end
  assign add_bit=end_baud;//上一个bit的波特率计算结束，就开始下一bit的计算
  assign end_bit=add_bit && (cnt_bit==max_bit-1);
  always @ (*  )
  begin case( cstate)
  	IDLE:max_bit=0;
      START:max_bit=1;
      DATA:max_bit=8;
      CHECK:max_bit=1;
      STOP:max_bit=1;
      default: max_bit=0;
  endcase
  end
  always @ (posedge clk_50m or posedge rst  )
  begin 
  	if(rst)
      		cstate<=IDLE;
      else cstate<=nstate;
  end
  always @ (*  )
  begin case(cstate )
  	IDLE:if(IDLE_START)
      			nstate<=START;
           else nstate<=cstate;
       START:if(START_DATA)
      			nstate<=DATA;
            else nstate<=cstate;
       DATA:if(DATA_CHECK)
      			nstate<=CHECK;
             else begin if(DATA_STOP)
          				nstate<=STOP;
                   else nstate<=cstate;
                  end
        CHECK:if(CHECK_STOP)
      				nstate<=STOP;
              else nstate<=cstate;
         STOP:if(STOP_IDLE)
      				nstate<=IDLE;
               else nstate<=cstate;
      default:nstate<=IDLE;//防止锁存
  endcase
  end
  always @ ( posedge clk_50m or posedge rst )
  begin if(rst)
  		tx_data_r<=0;
          else begin if(tx_data_vld && ready)
          		tx_data_r<=tx_data;
                  else tx_data_r<=tx_data_r;
                  end
  end
  always @ (  *)
  begin case( cstate)
  	IDLE:tx=1;
      START:tx=0;
      // DATA 状态只会到 0..7；显式截断索引可消除工具对 4-bit 索引越界的误报。
      DATA:tx=tx_data_r[cnt_bit[2:0]];
      CHECK:tx=check_val;
      STOP:tx=1;
      default:  tx=0;
  endcase
  end
  assign ready=(cstate==IDLE);
endmodule    //UART_TX
