`timescale 1ns/1ps
module tb_logic_analyzer;
 reg clk=0,reset=1,valid=0,write=0,rsp_ready=0;reg [31:0]addr,wdata;reg [3:0]wstrb=4'hf;reg [7:0]channels=0;reg [7:0]probe_channels=0;wire req_ready,rsp_valid,rsp_error;wire [31:0]rdata;wire [7:0]outs;integer failures=0,i;
 logic_analyzer_mmio dut(.clk(clk),.reset(reset),.req_valid(valid),.req_ready(req_ready),.req_addr(addr),.req_write(write),.req_wdata(wdata),.req_wstrb(wstrb),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_rdata(rdata),.rsp_error(rsp_error),.channels(channels),.probe_channels(probe_channels),.sample_outputs(outs));
 always #5 clk=~clk;
 // 看门狗：任何一个 wait(dut.done) 死等时，仿真曾经会无声空转烧满一个核
 // （2026-10-14 实测：vvp 单线程 CPU 时间 = 挂钟时间，且 stdout 块缓冲不刷新，
 // 外层回归也看不到"跑到哪了"）。这里设一个远大于正常用时的上限，
 // 超时就打印状态并按 FAIL 退出，让失败变成"有输出、有退出码"的确定性结果。
 integer cyc=0;
 always @(posedge clk) cyc<=cyc+1;
 initial begin
  #10000000;
  $display("LOGIC ANALYZER TIMEOUT after %0d cycles at t=%0t",cyc,$time);
  $display("  valid=%b write=%b rsp_ready=%b req_ready=%b rsp_valid=%b rsp_error=%b",valid,write,rsp_ready,req_ready,rsp_valid,rsp_error);
  $display("  armed=%b triggered=%b done=%b overflow=%b capture_count=%0d trigger_index=%0d",dut.armed,dut.triggered,dut.done,dut.overflow,dut.capture_count,dut.trigger_index);
  $display("  src_sel=%b channels=%h probe_channels=%h active_channels=%h",dut.src_sel,channels,probe_channels,dut.active_channels);
  $display("  channel_mask=%h trigger_mask=%h trigger_value=%h trigger_rise=%h trigger_fall=%h",dut.channel_mask,dut.trigger_mask,dut.trigger_value,dut.trigger_rise,dut.trigger_fall);
  $fatal(1,"LOGIC ANALYZER TIMEOUT (wait never satisfied)");
 end
 task wr;input [31:0]a,v;begin
  @(negedge clk); addr=a; wdata=v; write=1; valid=1; rsp_ready=1;
  wait(req_ready); @(posedge clk); #1; valid=0; write=0;
 wait(!rsp_valid); rsp_ready=0;
 end endtask
 task wrbe;input [31:0]a,v;input[3:0]be;begin wstrb=be;wr(a,v);wstrb=4'hf;end endtask
 task rd;input [31:0]a;output [31:0]v;begin
  @(negedge clk); addr=a; write=0; valid=1; rsp_ready=0;
  wait(req_ready); @(posedge clk); #1; valid=0; addr=32'hdeadbeef;
  repeat(2) @(posedge clk); rsp_ready=1; wait(rsp_valid); @(posedge clk); #1; v=rdata; rsp_ready=0;
 end endtask
 reg [31:0]rv;initial begin repeat(2)@(posedge clk);reset=0;
 wrbe(8,32'h1234,4'b0001);wrbe(8,32'hab00,4'b0010);wrbe(8,32'hffff,4'b0000);if(dut.sample_div!==16'hab34)begin $display("BYTE ENABLE FAIL %h",dut.sample_div);failures=failures+1;end else $display("BYTE ENABLE PASS");
 wr(64,8'ha5);wr(60,0);wr(56,4);rd(68,rv);if(rv[7:0]!==8'ha5)begin $display("PATTERN MMIO FAIL %h",rv);failures=failures+1;end else $display("PATTERN MMIO PASS");
 wr(8,2);wr(12,8'hff);wr(16,8'h01);wr(20,8'h01);wr(24,0);wr(28,0);wr(32,2);wr(36,3);wr(0,1);channels=8'h00;for(i=0;i<20;i=i+1)begin @(negedge clk);if(i==3)channels=8'h01;else if(i>3)channels=8'h03;end wait(dut.done);rd(4,rv);if(!rv[2]||!rv[1])begin $display("STATUS FAIL %h",rv);failures=failures+1;end else $display("STATUS PASS");rd(40,rv);if(rv[15:0]==0)begin $display("CAPTURE COUNT FAIL");failures=failures+1;end else $display("CAPTURE COUNT PASS %0d",rv[15:0]);wr(48,0);rd(52,rv);if(rv[7:0]!==8'h00)begin $display("READ DATA FAIL %h",rv);failures=failures+1;end else $display("READ DATA PASS");
// ---- 采集源"双源可选"（MMIO 寄存器 18 = 偏移 72）----
// 判据分三步，缺一不可：
//  1. 复位后默认必须是 0（J8 外部），否则加了这个功能就会改变既有行为；
//  2. 写 1 之后读回必须是 1；
//  3. 真的换源：让 channels 与 probe_channels 取**不同**的值，采回来的数据
//     必须跟着 probe_channels 走——只查读回位是查不出"读回来了但没用上"的。
rd(72,rv);if(rv[0]!==1'b0)begin $display("SRC DEFAULT FAIL %h",rv);failures=failures+1;end else $display("SRC DEFAULT PASS (J8)");
channels=8'h00;probe_channels=8'h01;
wr(72,1);rd(72,rv);if(rv[0]!==1'b1)begin $display("SRC SELECT FAIL %h",rv);failures=failures+1;end else $display("SRC SELECT PASS");
wr(8,0);wr(12,8'hff);wr(16,8'h01);wr(20,8'h01);wr(24,0);wr(28,0);wr(32,2);wr(36,3);wr(0,1);
// Arm 之后必须**显式**驱动一次 ch0 的 0->1 边沿（trigger_rise=0x01）再等 done。
// 为什么：trigger_rise 是边沿触发，probe_channels 在这段测试里恒为 0x01，arm 之后
// 不会自己产生任何边沿。旧写法把 wait(dut.done) 紧跟在 arm 后面，它读到的是上一个
// 场景残留的 done=1（wait 不消耗状态、也不认边沿），于是立刻返回、读到的
// capture_count 其实是上一次采样的——那一条 "PASS" 是假 PASS（2026-10-14 定位）。
// 现在的写法保证 done 必定由本场景的 arm + 边沿置起。
channels=8'h00;for(i=0;i<8;i=i+1)begin @(negedge clk);if(i==3)channels=8'h01;end
wait(dut.done);wr(48,0);rd(52,rv);
if(rv[7:0]!==8'h01)begin $display("SRC CORE CAPTURE FAIL got=%h want=01",rv[7:0]);failures=failures+1;end else $display("SRC CORE CAPTURE PASS");
// 切回 J8：同一组激励下必须重新跟着 channels 走（channels 现在仍为 0x00）。
wr(72,0);wr(0,4);
// 同一组显式边沿激励：先 arm 再驱动 ch0 的 0->1，done 才必然由本场景置起。
// 旧写法只 arm 不驱动边沿，J8 源恒为 0x00，触发永不发生，wait(dut.done) 无限空转
// （2026-10-14 实测：vvp 满核空转 24 分钟，导致最终回归整轮卡死）。
// 判据说明：read_index=0 读的是窗口内最旧的一个样本。必须**先**把 J8 的 channels 复位成
// 空闲 0x00 再 arm，否则 arm 前的那些 0x01 采样会把窗口填满 01（2026-10-14 实测 mem=01...）；
// 若源没有真正切回 J8 而仍是 core probe，同一个位置同样会是 0x01——所以这一条能验源。
channels=8'h00;probe_channels=8'h01;wr(0,1);for(i=0;i<8;i=i+1)begin @(negedge clk);if(i==3)channels=8'h01;end
wait(dut.done);wr(48,0);rd(52,rv);
if(rv[7:0]!==8'h00)begin $display("SRC BACK TO J8 FAIL got=%h want=00",rv[7:0]);failures=failures+1;end else $display("SRC BACK TO J8 PASS");if(failures==0)$display("ALL LOGIC ANALYZER TEST PASS");else $fatal(1,"LOGIC ANALYZER %0d FAIL",failures);$finish;end
endmodule
