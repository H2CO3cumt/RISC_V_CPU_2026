`timescale 1ns/1ps
// 80 MHz 逻辑分析仪顶层（PLL 版）端到端测试。
// 自测点：
//  1) PLL 必须锁定，且 clk_80m 周期为 12.5 ns（80 MHz），防止 PLL 参数写错导致频点偏移；
//  2) 板级固件在 80 MHz 域仍输出 LA_READY 前缀，UART 分频 694 无帧错误；
//  3) Capture Engine 在 80 MHz 下仍按 pre/trigger/post 精确采集，LED=0x5A、回环=0x01。
// 该测试只验证 RTL 行为，不替代实体板验证。
module tb_logic_analyzer_pll80_board_top;
 localparam UART_BAUD_CYCLES = 80_000_000 / 115200;
 reg clk_50m=0,uart_rx=1; reg [7:0] capture_ch=0;
 wire uart_tx; wire [7:0] led,loopback_tx;
 wire [7:0] d; wire v,e;
 integer cycles=0,bytes=0,errors=0,failures=0;
 integer t_rise_a=0,t_rise_b=0,clk80_period_ps=0;
 reg locked_seen=0;
 real freq_mhz;

 mes50hp_logic_analyzer_pll_top #(.CLK_HZ(80_000_000)) dut(
  .clk_50m(clk_50m),.uart0_rx(uart_rx),.uart0_tx(uart_tx),.led(led),
  .capture_ch(capture_ch),.loopback_tx(loopback_tx));

 // 50 MHz 输入晶振（P20）
 always #10 clk_50m=~clk_50m;

 // PLL 锁定与输出周期检查：连续记录 5 个上升沿，用固定窗口计数求平均周期，
 // 避免单次边沿测量受监视器采样延迟影响。
 integer edge_t [0:5];
 integer edge_n = 0;
 integer k;
 always @(posedge dut.clk_80m) begin
  if(!locked_seen && dut.pll_locked) locked_seen<=1;
  if(locked_seen && edge_n<=5) begin
   edge_t[edge_n]=$time;
   edge_n=edge_n+1;
  end
 end

 // 用 80 MHz 域监视 UART 线路，分频常数与顶层一致
 UART_RX #(.MAX_1BAUD(UART_BAUD_CYCLES)) mon(
  .clk_50m(dut.clk_80m),.rst(dut.u_soc.reset),.rx(uart_tx),
  .rx_data(d),.rx_data_vld(v),.rx_frame_error(e));

 always @(posedge dut.clk_80m) if(!dut.u_soc.reset) begin
  cycles=cycles+1;
  if(v)bytes=bytes+1;
  if(e)errors=errors+1;
  if(dut.u_soc.analyzer.cap.armed) begin
   if(dut.u_soc.analyzer.cap.capture_count<3) capture_ch<=0; else capture_ch<=1;
  end else capture_ch<=0;
 end

 task uart_send_byte;input[7:0]value;integer bit_index;begin
  @(negedge dut.clk_80m);uart_rx=0;repeat(UART_BAUD_CYCLES)@(posedge dut.clk_80m);
  for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
   @(negedge dut.clk_80m);uart_rx=value[bit_index];repeat(UART_BAUD_CYCLES)@(posedge dut.clk_80m);
  end
  @(negedge dut.clk_80m);uart_rx=1;repeat(UART_BAUD_CYCLES)@(posedge dut.clk_80m);
 end endtask

 initial begin
  wait(!dut.u_soc.reset);wait(bytes>=10);repeat(20)@(posedge dut.clk_80m);
  // A5, mode=static, data=1, dividers=0, level trigger bit0=1, pre/post=4, xor=A4.
  uart_send_byte(8'ha5);uart_send_byte(0);uart_send_byte(1);uart_send_byte(0);uart_send_byte(0);
  uart_send_byte(0);uart_send_byte(0);uart_send_byte(0);uart_send_byte(1);uart_send_byte(1);
  uart_send_byte(4);uart_send_byte(4);uart_send_byte(8'ha4);
 end

 initial begin
  while((bytes<13||!dut.u_soc.analyzer.cap.done)&&cycles<400000)@(posedge dut.clk_80m);
  @(negedge dut.clk_80m);
  if(!dut.pll_locked) begin $display("PLL80 LOCK FAIL"); failures=failures+1; end
  else $display("PLL80 LOCK PASS");
  if(edge_n>=3) clk80_period_ps=(edge_t[edge_n-1]-edge_t[0])*1000/(edge_n-1);
  if(clk80_period_ps<12400||clk80_period_ps>12600) begin
   $display("PLL80 FREQ FAIL period_ps=%0d (expect 12500)",clk80_period_ps);
   failures=failures+1;
  end else begin
   freq_mhz=1000000.0/clk80_period_ps;
   $display("PLL80 FREQ PASS period_ps=%0d freq=%0.4f MHz",clk80_period_ps,freq_mhz);
  end
  // 注意：本 TB 测的是 **80m 归档工程**（位流与源码已归档，不含 ch7 镜像抓取），
  // 所以仍按"8 路全部由 pattern_gen 驱动"断言。镜像抓取的断言在
  // tb_logic_analyzer_board_top.v（50m 交互工程）与 tb_logic_analyzer_mirror.v。
  if(led!==8'h5a||loopback_tx!==8'h01) begin
   $display("PLL80 OUTPUT FAIL led=%h loopback=%h",led,loopback_tx); failures=failures+1;
  end
  if(errors!=0) begin $display("PLL80 UART ERRORS %0d",errors); failures=failures+1; end
  if(bytes<13) begin $display("PLL80 UART BYTES FAIL %0d",bytes); failures=failures+1; end
  else $display("PLL80 UART PASS bytes=%0d",bytes);
  if(dut.u_soc.analyzer.cap.done&&dut.u_soc.analyzer.cap.triggered&&dut.u_soc.analyzer.cap.capture_count==9&&dut.u_soc.analyzer.cap.trigger_index==4)
   $display("PLL80 CAPTURE PASS count=%0d",dut.u_soc.analyzer.cap.capture_count);
  else begin
   $display("PLL80 CAPTURE FAIL count=%0d index=%0d",dut.u_soc.analyzer.cap.capture_count,dut.u_soc.analyzer.cap.trigger_index);
   failures=failures+1;
  end
  if(failures==0)$display("ALL LOGIC ANALYZER PLL80 BOARD TOP TEST PASS");
  else $fatal(1,"LOGIC ANALYZER PLL80 BOARD TOP %0d FAIL",failures);
  $finish;
 end
 initial #4000000 $fatal(1,"LOGIC ANALYZER PLL80 BOARD TOP TIMEOUT");
endmodule
