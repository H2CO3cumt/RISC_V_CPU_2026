`timescale 1ns/1ps
// 提交级 trace 端到端闭环测试：**真实 SoC 顶层 + 真实固件 + 真实 trace 外设**。
//
// 为什么必须有这一层：模块级 TB（tb_trace_buffer / tb_core_trace_mmio）只证明了
// "寄存器读写对、记录位段对"。真正会翻车的是**整条链**：
//   Core 的 trace_* -> trace_buffer 记录 -> MMIO 5 字读出 -> 固件逐条打印 -> UART -> 上位机解析
// 任何一环（固件少读一个字、地址译码差 4 字节、mark 索引口径不一致）都只在
// 这一层暴露。
//
// 判据分两层：
//   1) 本 TB 只看**结构**：导出行数 = 头部报的条数、打点数 = 字符数、固件自己解出的
//      大写结果与统计值正确、UART 无帧错误、STATUS 收尾位正确。
//   2) 语义层（pc 与镜像是否同源、依赖图的边对不对、mark 锚点是否真的指向那条指令）
//      交给 python/trace_view.py 用**同一份日志**判——那才是"判据与标注同源"。
//      本 TB 负责把未经加工的回包字节原样写进日志文件供 Python 直接吃。
module tb_core_trace_soc;
 localparam BAUD_CYCLES = 8;
 localparam GOT_MAX     = 65536;
 // 仿真深度 1024：足够覆盖 8 个字符的处理窗口，又不必让 iverilog 模拟 8192x132 的阵列。
 // 真实位流用 8192（fpga/trace85/rtl/mes50hp_trace_top.v 的 TRACE_DEPTH 默认值）。
 localparam TRACE_DEPTH = 1024;
 localparam TRACE_AW    = 10;

 reg clk=0, uart_rx=1;
 wire uart_tx;
 wire [7:0] led, loopback_tx, capture_ch;
 wire [7:0] rx_data; wire rx_vld, rx_err;

 reg  [7:0] got[0:GOT_MAX-1];
 integer got_n=0, cycles=0, errs=0, failures=0, nl_count=0;
 integer logf;
 reg [8*256-1:0] logpath;

 mes50hp_trace_top #(.UART_BAUD_CYCLES(BAUD_CYCLES),.TRACE_DEPTH(TRACE_DEPTH),.TRACE_AW(TRACE_AW)) dut(
  .clk_50m(clk),.uart0_rx(uart_rx),.uart0_tx(uart_tx),.led(led),
  .capture_ch(capture_ch),.loopback_tx(loopback_tx));
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
    if(logf) $fwrite(logf,"%c",rx_data);
    got_n=got_n+1;
    if(rx_data==8'h0a) begin
     nl_count=nl_count+1;
     // 每行刷一次盘：仿真被中途杀掉时，日志里已有"到哪一步为止"的证据，
     // 不用靠猜（2026-10-21 实测：不刷盘时日志停在上一个场景，分不清是挂住还是缓冲）。
     if(logf) $fflush(logf);
    end
   end
   if(rx_err) errs=errs+1;
  end
 end

 // 模式串一律用 8'h0D/8'h0A 拼：Verilog 标准转义没有 \r，写 "\r\n" 会变成 'r''\n'。
 localparam [8*40-1:0] M_ARMED = {216'b0, "TRACE_ARMED", 8'h0D, 8'h0A};
 localparam [8*40-1:0] M_DONE  = {248'b0, "TRACE_DONE", 8'h0D, 8'h0A};
 localparam [8*40-1:0] M_READY = {216'b0, "LA_READY", 8'h0D, 8'h0A};
 localparam [8*40-1:0] M_RAW   = {192'b0, "TRACE RAW count="};
 localparam [8*40-1:0] M_MARK  = {216'b0, "TRACE MARK n="};
 // 0xAB 组合命令的波形块（2026-10-24 新增）。注意 "LA RAW count=" 是 **13** 个字符，
 // 少数字符串长度是这类结构判据最容易错的地方（第一次就写成 15，标记永远匹配不上）。
 localparam [8*40-1:0] M_LAWAVE = {216'b0, "LA RAW count="};
 localparam [8*40-1:0] M_LAWED  = {264'b0, "LA_DONE"};

 function integer hexval; input [7:0] ch; begin
  if(ch>=8'h30&&ch<=8'h39) hexval=ch-8'h30;
  else if(ch>=8'h41&&ch<=8'h46) hexval=ch-8'h37;
  else hexval=-1;
 end endfunction

 function tail_has;
  input [8*40-1:0] field; input integer len;
  integer k; reg hit;
  begin
   hit = (got_n>=len);
   for(k=0;k<len;k=k+1)
    if(got[got_n-1-k]!==field[k*8 +: 8]) hit=1'b0;
   tail_has=hit;
  end
 endfunction

 task find_all;
  input [8*40-1:0] field; input integer len; output integer at;
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

 // 0xAA：4 字节 [0]=cmd [1]=字符数 [2]=阶段 [3]=XOR([1..2])
 task send_trace_cmd; input [7:0] n; input [7:0] phase; reg [7:0] cs; begin
  cs = 8'hAA ^ n ^ phase;
  send_byte(8'hAA); send_byte(n); send_byte(phase); send_byte(cs);
 end endtask

 task send_text; input [8*40-1:0] s; input integer len; integer i; begin
  for(i=0;i<len;i=i+1) send_byte(s[(len-1-i)*8 +: 8]);
 end endtask

 // 0xAB：4 字节 [0]=cmd [1]=字符数 [2]=窗口档 [3]=XOR([1..2])
 // 与 0xAA 的时序差别：这条命令没有 ARMED 握手——固件收完 4 字节后立刻阻塞
 // 等那 n 个字符（收字符发生在两个窗口打开之前），所以命令与文本必须连着发。
 task send_wave_cmd; input [7:0] n; input [7:0] win; reg [7:0] cs; begin
  cs = 8'hAB ^ n ^ win;
  send_byte(8'hAB); send_byte(n); send_byte(win); send_byte(cs);
 end endtask

 task wait_mark; input [8*40-1:0] field; input integer len; input integer limit;
  integer t; reg ok; integer seen; begin
  t=0; ok=1'b0; seen=nl_count;
  while(t<limit && !ok) begin
   @(posedge clk); t=t+1;
   if(got_n>GOT_MAX) begin
    $display("TRACE SOC FAIL 回包超出 TB 缓冲 got_n=%0d",got_n);
    failures=failures+1; t=limit;
   end else if(nl_count!=seen) begin
    seen=nl_count;
    if(tail_has(field,len)) ok=1'b1;
   end
  end
  if(!ok && got_n<=GOT_MAX) begin
   $display("TRACE SOC FAIL 等不到标记 len=%0d got_n=%0d nl=%0d cycles=%0d",len,got_n,nl_count,cycles);
   failures=failures+1;
  end
 end endtask

 task check_seq; input [8*40-1:0] field; input integer len; input integer tag; integer at; begin
  find_all(field,len,at);
  if(at<0) begin
   $display("TRACE SOC FAIL CHECK %0d 未命中",tag);
   failures=failures+1;
  end else $display("TRACE SOC OK   CHECK %0d @%0d",tag,at);
 end endtask

 // 结构判据：头部报的 count 必须等于两条标记行之间实际导出的记录行数。
 // 只查"有没有 count=" 是不够的——条数对不上时页面会把别人的指令画到这一枪上。
 task check_count_matches; input integer tag; output integer ok;
  integer at, mat, i, declared, lines, p; reg [31:0] v; reg [7:0] ch;
  begin
   ok=0;
   find_all(M_RAW,16,at);
   find_all(M_MARK,13,mat);
   if(at<0||mat<0||mat<at) begin
    $display("TRACE SOC FAIL %0d 找不到 count/MARK 标记",tag);
   end else begin
    v=0;
    for(i=0;i<8;i=i+1) begin
     ch=got[at+16+i];
     v=v*16;
     if(ch>=8'h30&&ch<=8'h39) v=v+(ch-8'h30);
     else if(ch>=8'h41&&ch<=8'h46) v=v+(ch-8'h37);
     else begin $display("TRACE SOC FAIL %0d count 字段不是十六进制 %c",tag,ch); i=8; v=32'hFFFFFFFF; end
    end
    declared=v;
    p=at; while(p<mat && got[p]!=8'h0a) p=p+1; p=p+1;
    lines=0;
    for(i=p;i<mat;i=i+1) if(got[i]==8'h0a) lines=lines+1;
    $display("TRACE SOC INFO %0d declared=%0d lines=%0d",tag,declared,lines);
    if(declared<=0) begin $display("TRACE SOC FAIL %0d 一条记录都没抓到",tag); end
    else if(lines!=declared) begin $display("TRACE SOC FAIL %0d 导出行数与 count 不符",tag); end
    else ok=1;
   end
  end
 endtask

 integer rl_ok;

 // 0xAB 波形块的结构判据：头部 count 必须等于实际打出来的样本个数。
 // 样本是"8 位十六进制 + 一个分隔符"逐个打的（最后一个用 '\n'），
 // 所以样本区的字节数必须**正好**等于 count*9。这比"有没有 LA RAW"强得多：
 // 固件少打一个样本、或分隔符少一个，页面上的"第 k 拍"就会整体错位。
 task check_wave_samples; input integer tag; output integer ok;
  integer at, ed, body, hi, n, i; reg hx;
  begin
   ok=0;
   find_all(M_LAWAVE,13,at);
   find_all(M_LAWED,7,ed);
   if(at<0||ed<0||ed<at) begin
    $display("TRACE SOC FAIL %0d 找不到 0xAB 的波形块",tag);
   end else begin
    body=at+13; n=0; hx=1'b1;
    for(i=0;i<8;i=i+1) begin
     if(hexval(got[body+i])<0) hx=1'b0;
     else n=n*16+hexval(got[body+i]);
    end
    hi=body+8;
    while(hi<ed && got[hi]!=8'h0a) hi=hi+1;
    hi=hi+1;
    $display("TRACE SOC INFO %0d wave_count=%0d sample_bytes=%0d",tag,n,ed-hi);
    if(!hx) $display("TRACE SOC FAIL %0d 波形 count 不是十六进制",tag);
    else if(n<=0) $display("TRACE SOC FAIL %0d 波形一条样本都没有",tag);
    else if((ed-hi) != n*9) $display("TRACE SOC FAIL %0d 样本字节数 %0d != count*9",tag,ed-hi);
    else ok=1;
   end
  end endtask

 initial begin
  if(!$value$plusargs("LOG=%s", logpath)) logpath = "results/trace85_sim/uart.log";
  logf=$fopen(logpath,"w");
  wait(!dut.reset);
  wait(got_n>=10);
  repeat(20) @(posedge clk);

  // ---- 场景 1（phase=0）：整句 "hello,rv" 只记录**处理过程** ----
  $display("TRACE SOC STAGE 1 begin cycles=%0d", cycles); $fflush;
  send_trace_cmd(8'd8, 8'd0);
  wait_mark(M_ARMED,11,400000);
  send_text("hello,rv",8);
  wait_mark(M_DONE,10,3000000);
  check_seq({224'b0, "marks=00000008 status=00000004"},30,1);
  check_seq({192'b0, "ascii=HELLO,RV"},14,2);
  check_seq({168'b0, "up=00000007"},11,3);
  check_seq({176'b0, "chars=00000008"},14,4);
  check_count_matches(1, rl_ok);
  if(!rl_ok) failures=failures+1;
  $display("TRACE SOC SCENARIO 1 done got_n=%0d cycles=%0d",got_n,cycles);
  $fflush;
`ifdef TB_ONLY1
  $fclose(logf);
  if(failures==0) $display("ALL CORE TRACE SOC TEST PASS (scenario 1 only)");
  else $fatal(1,"CORE TRACE SOC %0d FAIL",failures);
  $finish;
`else

  // ---- 场景 2（phase=1）：Arm 在接收之前，窗口里包含串口轮询 ----
  $display("TRACE SOC STAGE 2 begin cycles=%0d", cycles); $fflush;
  // 必须先等固件回到命令循环（它会先打印 LA_READY）再发下一条命令。
  // 2026-10-21 实测踩到：场景 1 的 TRACE_DONE 一出现就发命令，此时固件还在
  // 阻塞发 LA_READY，而 UART RX 没有接收 FIFO —— 命令字节被后来的字节覆盖，
  // 固件再也收不到命令，仿真白等 300 万拍。这不是 RTL 缺陷，是**上位机时序**纪律。
  wait_mark(M_READY,10,400000);
  got_n=0; nl_count=0;
  send_trace_cmd(8'd3, 8'd1);
  wait_mark(M_ARMED,11,400000);
  send_text("ABC",3);
  wait_mark(M_DONE,10,12000000);
  check_seq({224'b0, "marks=00000003 status=00000004"},30,5);
  check_seq({192'b0, "ascii=ABC"},9,6);
  check_seq({168'b0, "up=00000000"},11,7);
  check_count_matches(2, rl_ok);
  if(!rl_ok) failures=failures+1;
  $display("TRACE SOC SCENARIO 2 done got_n=%0d cycles=%0d",got_n,cycles);
  $fflush;
`endif

  // ---- 场景 3（0xAB）：一次运行同时抓"每拍波形"和"每条指令" -----------------
  // 判据只到结构层：波形块的 count 与样本字节数自洽、指令流块自洽、两块都在。
  // "第 k 拍 ↔ 第几条记录"的对齐由 python/trace_view.align_wave() 用同一份日志算，
  // 并用"数据访问脉冲数 = 区间内 load+store 条数"交叉校验（判据与标注同源）。
  $display("TRACE SOC STAGE 3 begin cycles=%0d", cycles); $fflush;
  wait_mark(M_READY,10,800000);
  got_n=0; nl_count=0;
  send_wave_cmd(8'd8, 8'd1);     // 8 个字符、512 个后触发样本
  send_text("hello,rv",8);
  // 注意：wait_mark 只认"以 \r\n 收尾的整行"标记，所以这里等到 TRACE_DONE 收尾，
  // LA 块与 TRACE 块的结构判据全部用 find_all 做（check_seq / check_wave_samples）。
  wait_mark(M_DONE,10,20000000);
  check_seq({216'b0, "LA RAW count="},13,8);
  check_seq({192'b0, " window=00000200"},16,9);
  check_seq({264'b0, "LA_DONE"},7,10);
  check_wave_samples(3, rl_ok);
  if(!rl_ok) failures=failures+1;
  check_seq({224'b0, "marks=00000008"},14,11);
  check_seq({192'b0, "ascii=HELLO,RV"},14,12);
  check_count_matches(3, rl_ok);
  if(!rl_ok) failures=failures+1;
  $display("TRACE SOC SCENARIO 3 done got_n=%0d cycles=%0d",got_n,cycles);
  $fflush;

  if(errs!=0) begin
   $display("TRACE SOC FAIL UART 监控帧错误 %0d",errs);
   failures=failures+1;
  end
  $fclose(logf);
  if(failures==0) $display("ALL CORE TRACE SOC TEST PASS");
  else $fatal(1,"CORE TRACE SOC %0d FAIL",failures);
  $fflush;
  $finish;
 end

 initial #200000000 begin
  $display("TRACE SOC FAIL 超时 cycles=%0d got_n=%0d",cycles,got_n);
  $fatal(1,"CORE TRACE SOC TIMEOUT");
 end
endmodule
