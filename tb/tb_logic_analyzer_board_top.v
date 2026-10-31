`timescale 1ns/1ps
// 交互式板级顶层端到端测试：UART 协议 + 采集窗口 + ch7 镜像（上位机串口线）。
// 仪器面板已按用户要求移除，LED 回到 gpio_out，所以这里断言 led==0x5A。
module tb_logic_analyzer_board_top;
 reg clk=0,uart_rx=1; reg [7:0]capture_ch=0; wire uart_tx; wire [7:0]led,loopback_tx; wire [7:0]d;wire v,e; integer cycles=0,bytes=0,errors=0,failures=0,mirror_errors=0;
 mes50hp_logic_analyzer_top #(.UART_BAUD_CYCLES(16)) dut(.clk_50m(clk),.uart0_rx(uart_rx),.uart0_tx(uart_tx),.led(led),.capture_ch(capture_ch),.loopback_tx(loopback_tx));
 UART_RX #(.MAX_1BAUD(16)) mon(.clk_50m(clk),.rst(dut.reset),.rx(uart_tx),.rx_data(d),.rx_data_vld(v),.rx_frame_error(e));
 always #5 clk=~clk;
 task uart_send_byte;input[7:0]value;integer bit_index;begin
  @(negedge clk);uart_rx=0;repeat(16)@(posedge clk);
  for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin @(negedge clk);uart_rx=value[bit_index];repeat(16)@(posedge clk);end
  @(negedge clk);uart_rx=1;repeat(16)@(posedge clk);
 end endtask
 always @(posedge clk) if(!dut.reset) begin cycles=cycles+1;if(v)bytes=bytes+1;if(e)errors=errors+1;if(dut.analyzer.cap.armed)begin if(dut.analyzer.cap.capture_count<3)capture_ch<=0;else capture_ch<=1;end else capture_ch<=0;
  // ch7 必须每拍都镜像 uart0_rx（组合直连）：整包 13 字节传输期间持续检查，
  // 这样才能证明"上位机发什么，J8-31 就出什么"，而不只是在某一拍碰巧对上。
  if(loopback_tx[7]!==uart_rx)mirror_errors=mirror_errors+1;end
 initial begin
  wait(!dut.reset);wait(bytes>=10);repeat(20)@(posedge clk);
  // A5, mode=static, data=1, dividers=0, level trigger bit0=1, pre/post=4, xor=A4.
  uart_send_byte(8'ha5);uart_send_byte(0);uart_send_byte(1);uart_send_byte(0);uart_send_byte(0);
  uart_send_byte(0);uart_send_byte(0);uart_send_byte(0);uart_send_byte(1);uart_send_byte(1);
  uart_send_byte(4);uart_send_byte(4);uart_send_byte(8'ha4);
 end
 initial begin
  while((bytes<13||!dut.analyzer.cap.done)&&cycles<200000)@(posedge clk);
  @(negedge clk);
  if(cycles>=200000)begin $display("LOGIC ANALYZER BOARD TOP FAIL TIMEOUT");failures=failures+1;end
  if(led!==8'h5a||loopback_tx[6:0]!==7'h01||loopback_tx[7]!==uart_rx)begin
   $display("LOGIC ANALYZER BOARD TOP OUTPUT FAIL led=%h loopback=%h uart_rx=%b",led,loopback_tx,uart_rx);failures=failures+1;
  end else $display("LOGIC ANALYZER BOARD TOP MIRROR PASS led=%h loopback=%h (ch7=uart_rx)",led,loopback_tx);
  if(mirror_errors!=0)begin $display("LOGIC ANALYZER BOARD TOP MIRROR FAIL samples=%0d",mirror_errors);failures=failures+1;end
  if(errors!=0)begin $display("LOGIC ANALYZER BOARD TOP UART ERRORS %0d",errors);failures=failures+1;end
  if(bytes<13)begin $display("LOGIC ANALYZER BOARD TOP UART BYTES FAIL %0d",bytes);failures=failures+1;end
  else $display("LOGIC ANALYZER BOARD TOP UART PASS bytes=%0d",bytes);
  if(dut.analyzer.cap.done&&dut.analyzer.cap.triggered&&dut.analyzer.cap.capture_count==9&&dut.analyzer.cap.trigger_index==4)
   $display("LOGIC ANALYZER BOARD TOP CAPTURE PASS count=%0d",dut.analyzer.cap.capture_count);
  else begin
   $display("LOGIC ANALYZER BOARD TOP CAPTURE FAIL count=%0d index=%0d",dut.analyzer.cap.capture_count,dut.analyzer.cap.trigger_index);failures=failures+1;
  end
  if(failures==0)$display("ALL LOGIC ANALYZER BOARD TOP TEST PASS");else $fatal(1,"LOGIC ANALYZER BOARD TOP %0d FAIL",failures);
  $finish;
 end
 initial #2200000 $fatal(1,"LOGIC ANALYZER BOARD TOP TIMEOUT");
endmodule
