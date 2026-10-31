`timescale 1ns/1ps
// 镜像抓取端到端测试（独立编写的 TB，被测对象是**真实板级顶层 + 真实固件**）。
//
// 测什么：
//   1) 板级顶层把 uart0_rx（上位机经 CP2102 发来的串口线）镜像到 loopback_tx[7]，
//      而 loopback_tx[7] 经 J8 的物理回环（本 TB 用 assign 模拟 31↔32 那根杜邦线）
//      回到 capture_ch[7] —— 这条通路就是"上位机发什么、逻辑分析仪就抓什么"。
//   2) 新增的 0xA7 镜像命令：上位机先发 13 字节命令，固件 Arm 完打印 LA_ARMED，
//      上位机**看到 LA_ARMED 之后**才把字符串发出去，触发点是第一个起始位的下降沿。
//   3) 固件必须把抓到的波形自己解回字符：回包里要同时出现正确的 count、十六进制
//      字节和 ascii 文本 —— 这是"板子从波形里读出了什么"的直接证据。
//
// 两个场景：
//   A 短报文 "HI"（post=255，256 个样本）——快速冒烟，覆盖命令/触发/解码全链路；
//     可用 -DTB_MIR_FAST 只跑这一段。
//   B 整句 "HELLO,RISC-V"（post=2047，2048 个样本）——与交付配置完全一致的验收场景。
//
// 时序约定（本 TB 自己定标，与实板数值无关）：
//   比特周期 = BAUD_CYCLES = 8 拍；采样点周期 = SAMPLE_DIV+1 = 1 拍
//   => 每比特 8 个采样点，与上位机镜像模式算出来的 bit_samples 一致。
// **不要照抄实板的 sample_div=91**：实板比特周期是 737 拍（85 MHz / 115200），
// 仿真里比特只有 8 拍，抄过来会变成 0.8 个采样点/比特，一帧都解不出来（本 TB 实测踩到过）。
module tb_logic_analyzer_mirror;
 localparam BAUD_CYCLES = 8;
 localparam SAMPLE_DIV  = 0;
 localparam BIT_SAMPLES = BAUD_CYCLES / (SAMPLE_DIV + 1);
 localparam GOT_MAX     = 26000;

 reg clk=0, uart_rx=1;
 wire uart_tx;
 wire [7:0] led, loopback_tx, capture_ch;
 wire [7:0] rx_data; wire rx_vld, rx_err;

 reg  [7:0] got[0:GOT_MAX-1];
 integer    got_n=0, cycles=0, errs=0, failures=0;
 // 换行**计数**而不是"见过换行"的粘滞标志：等待任务和采集 always 块在同一个 posedge 上
 // 被唤醒，谁先执行是不确定的。用粘滞标志会漏掉这一拍（然后一直等下一行，实测把仿真拖到
 // 千万拍级别）；用单调计数则最多晚一拍看到，不会丢事件。
 integer    nl_count=0;
 integer    di;

 mes50hp_logic_analyzer_top #(.UART_BAUD_CYCLES(BAUD_CYCLES)) dut(
  .clk_50m(clk),.uart0_rx(uart_rx),.uart0_tx(uart_tx),.led(led),
  .capture_ch(capture_ch),.loopback_tx(loopback_tx));

 // J8 的八对相邻脚：奇数脚输出、偶数脚输入。这里用连续赋值代替杜邦线。
 assign capture_ch = loopback_tx;

 UART_RX #(.MAX_1BAUD(BAUD_CYCLES)) mon(
  .clk_50m(clk),.rst(dut.reset),.rx(uart_tx),
  .rx_data(rx_data),.rx_data_vld(rx_vld),.rx_frame_error(rx_err));

 always #5 clk=~clk;

 always @(posedge clk) begin
  if(!dut.reset) begin
   cycles=cycles+1;
   if(rx_vld) begin
    if(got_n<GOT_MAX) got[got_n]=rx_data;
    got_n=got_n+1;
    if(rx_data==8'h0a) nl_count=nl_count+1;
   end
   if(rx_err) errs=errs+1;
  end
 end

 // 期望出现的文本，右对齐放在 32 字节字段里：取低 len 字节就是模式串本身。
 // **不要用 "\r\n" 写回车换行**：Verilog 标准转义只有 \n \t \\ \" \ddd，没有 \r ——
 // "\r" 会被当成普通字符 'r'，拼出来的模式串与真实回包差一个字节，匹配永远失败
 // （本 TB 第一版就是这样，实测卡在"等不到 LA_ARMED"）。这里用 8'h0D / 8'h0A 直接拼字节。
 localparam [8*32-1:0] M_ARMED = {176'b0, "LA_ARMED", 8'h0D, 8'h0A};
 localparam [8*32-1:0] M_READY = {176'b0, "LA_READY", 8'h0D, 8'h0A};
 localparam [8*32-1:0] M_CNT_A = {144'b0, "count=00000100"};
 localparam [8*32-1:0] M_TXT_A = {192'b0, "ascii=HI"};
 localparam [8*32-1:0] M_CNT_B = {144'b0, "count=00000800"};
 // 固件的十六进制沿用既有约定：每个字节 8 位（和 Raw 样本行一致），不是 2 位。
 // 所以这里只对前三字节 'H','E','L' 的 24 个字符做匹配；整句的可读形式由 ascii= 那一项覆盖。
 localparam [8*32-1:0] M_HEX_B = {64'b0, "00000048000000450000004C"};
 localparam [8*32-1:0] M_ASC_B = {112'b0, "ascii=HELLO,RISC-V"};

 // 流尾部是否正好是某个模式（只在换行后调用，代价 O(len)）
 function tail_has;
  input [8*32-1:0] field; input integer len;
  integer k; reg hit;
  begin
   hit = (got_n>=len);
   for(k=0;k<len;k=k+1)
    if(got[got_n-1-k]!==field[k*8 +: 8]) hit=1'b0;
   tail_has=hit;
  end
 endfunction

 // 在整个回包里搜索模式（每个场景只跑一次，代价 O(n*len)）
 task find_all;
  input [8*32-1:0] field; input integer len; output integer at;
  integer i,k; reg hit;
  begin
   at=-1;
   for(i=0;i+len<=got_n;i=i+1) begin
    hit=1'b1;
    for(k=0;k<len;k=k+1)
     if(got[i+k]!==field[(len-1-k)*8 +: 8]) hit=1'b0;
    if(hit && at<0) at=i;
   end
  end
 endtask

 task send_byte; input [7:0] value; integer b; begin
  @(negedge clk); uart_rx=1'b0; repeat(BAUD_CYCLES) @(posedge clk);
  for(b=0;b<8;b=b+1) begin
   @(negedge clk); uart_rx=value[b]; repeat(BAUD_CYCLES) @(posedge clk);
  end
  @(negedge clk); uart_rx=1'b1; repeat(BAUD_CYCLES) @(posedge clk);
 end endtask

 // 13 字节镜像命令：0xA7 模式下 [2]=每比特采样点数、[10]|[11]=16 位 post。
 task send_ack_packet; input [15:0] post; reg [7:0] cs; begin
  cs = 8'hA7 ^ 8'h04 ^ BIT_SAMPLES[7:0] ^ 8'h00 ^ 8'h00 ^ SAMPLE_DIV[7:0] ^ 8'h00
     ^ 8'h02 ^ 8'h80 ^ 8'h00 ^ post[7:0] ^ post[15:8];
  send_byte(8'hA7); send_byte(8'h04); send_byte(BIT_SAMPLES[7:0]);
  send_byte(8'h00); send_byte(8'h00);
  send_byte(SAMPLE_DIV[7:0]); send_byte(8'h00);
  send_byte(8'h02);            // 触发类型 2 = 下降沿
  send_byte(8'h80);            // 触发通道 = ch7
  send_byte(8'h00);            // 电平触发值（下降沿模式下不用）
  send_byte(post[7:0]); send_byte(post[15:8]);
  send_byte(cs);
 end endtask

 task send_text; input [8*32-1:0] s; input integer len; integer i; begin
  for(i=0;i<len;i=i+1) send_byte(s[(len-1-i)*8 +: 8]);
 end endtask

 // 等回包尾部出现某个标记；只在"新到了一个换行"时做匹配，避免每拍全扫。
 // got_n 超过 GOT_MAX 时 got[] 不再更新而 got_n 继续涨，尾部匹配会读到陈旧字节并**永远失败**
 // （实测把仿真白等 2000 万拍）。所以溢出必须立刻报失败，不能让它悄悄变成"等不到标记"。
 task wait_mark; input [8*32-1:0] field; input integer len; input integer limit;
  integer t; reg ok; integer seen; begin
  t=0; ok=1'b0; seen=nl_count;
  while(t<limit && !ok) begin
   @(posedge clk); t=t+1;
   if(got_n>GOT_MAX) begin
    $display("MIRROR FAIL 回包超出 TB 缓冲 got_n=%0d GOT_MAX=%0d",got_n,GOT_MAX);
    failures=failures+1; t=limit;
   end else if(nl_count!=seen) begin
    seen=nl_count;
    if(tail_has(field,len)) ok=1'b1;
   end
  end
  if(!ok && got_n<=GOT_MAX) begin
   $display("MIRROR FAIL 等不到标记 len=%0d got_n=%0d nl=%0d cycles=%0d",len,got_n,nl_count,cycles);
   failures=failures+1;
  end
 end endtask

 integer at;
 // 注意：任务名不能叫 expect —— 它是 SystemVerilog 保留字，-g2012 下会直接语法错误。
 task check_seq; input [8*32-1:0] field; input integer len; input integer tag; begin
  find_all(field,len,at);
  if(at<0) begin
   $display("MIRROR FAIL CHECK %0d 未命中",tag);
   failures=failures+1;
  end else $display("MIRROR OK   CHECK %0d @%0d",tag,at);
 end endtask

 initial begin
  wait(!dut.reset);
  wait(got_n>=10);                       // 固件上电先发 LA_READY
  repeat(20) @(posedge clk);

  // ---- 场景 A：短报文 "HI"，post=255（256 个样本）----
  // 256 个样本 ÷ 8 点/比特 = 32 bit，够 2 个字符（20 bit）带余量。
  // 注意不能把窗口设成几十个点：那样连一个字节都解不出来，"解出 = 发出去"的判据会假失败。
  send_ack_packet(16'd255);
  wait_mark(M_ARMED,10,200000);          // 必须等到 Arm 生效才发字符串
  send_text("HI",2);
  wait_mark(M_READY,10,2000000);
  check_seq(M_CNT_A,14,1);
  check_seq(M_TXT_A,8,2);
  $display("MIRROR SCENARIO A done got_n=%0d cycles=%0d",got_n,cycles);
  $fflush;

`ifndef TB_MIR_FAST
  // ---- 场景 B：整句 "HELLO,RISC-V"，post=2047（与交付配置一致）----
  // TB_MIR_FAST 只跑场景 A：场景 B 要导出 2048 个样本（约 2.95 ms 串口时间、
  // 三百万拍），单独用来做"交付配置"的验收；日常改一行代码不该等它。
  send_ack_packet(16'd2047);
  wait_mark(M_ARMED,10,200000);
  send_text("HELLO,RISC-V",12);
  wait_mark(M_READY,10,20000000);
  check_seq(M_CNT_B,14,3);
  check_seq(M_HEX_B,24,4);
  check_seq(M_ASC_B,18,5);
  $display("MIRROR SCENARIO B done got_n=%0d cycles=%0d",got_n,cycles);
  $fflush;
`endif

  // 镜像模式只应有 ch7 在动：ch0~ch6 被固件固定成低电平。
  if(loopback_tx[6:0]!==7'h00) begin
   $display("MIRROR FAIL 非镜像通道应为低电平 got=%h",loopback_tx);
   failures=failures+1;
  end
  if(errs!=0) begin
   $display("MIRROR FAIL UART 监控帧错误 %0d",errs);
   failures=failures+1;
  end
  if(failures==0) $display("ALL LOGIC ANALYZER MIRROR TEST PASS");
  else begin
   // 失败时把回包尾部按字符打出来：固件到底回了什么，不该靠猜。
   $write("MIRROR DUMP tail(%0d bytes): ", (got_n>160)?160:got_n);
   for(di=((got_n>160)?got_n-160:0); di<got_n; di=di+1) $write("%c", got[di]);
   $write("\n");
   $fatal(1,"LOGIC ANALYZER MIRROR %0d FAIL",failures);
  end
  $fflush;
  $finish;
 end

 // 兜底超时：整句场景要导出 2048 个样本（约 2.95 ms 串口时间），给足余量。
 initial #120000000 begin
  $display("MIRROR FAIL 超时 cycles=%0d got_n=%0d nl=%0d",cycles,got_n,nl_count);
  $fatal(1,"LOGIC ANALYZER MIRROR TIMEOUT");
 end
endmodule
