`timescale 1ns/1ps
// core_trace_mmio + application_mmio_mux3 的联合 Testbench。
//
// 一起测的理由：这两个模块的正确性各有一半在"边界"上——
//   · core_trace_mmio 单独测只能证明寄存器读写对；
//   · 真正会翻车的是 mux3 包一层之后，既有 perf/la 两个子窗口是否被改变。
// 所以这里把三个目标全部接上：perf/la 用能回响地址的桩，trace 用真模块，
// 然后从 **CPU 那一侧的统一事务端口** 发请求。
module tb_core_trace_mmio;
 localparam integer DEPTH=16, MARKS=8, AW=4, MW=3;

 reg clk=0, reset=1;
 reg valid=0, write=0, rsp_ready=0;
 reg [31:0] addr=0, wdata=0;
 reg [3:0] wstrb=4'hf;
 wire req_ready, rsp_valid, rsp_error;
 wire [31:0] rdata;

 // trace 输入端（模拟 Core 的提交级 trace 输出）
 reg t_valid=0, t_rd_we=0, t_mem_we=0, t_error=0;
 reg [31:0] t_pc=0, t_inst=0, t_rd_data=0, t_mem_addr=0, t_mem_data=0;
 reg [4:0]  t_rd_addr=0;
 reg [3:0]  t_mem_wstrb=0;

 // mux3 三路输出
 wire p_v, l_v, tr_v, p_r, l_r, tr_r, p_sv, l_sv, tr_sv, p_sr, l_sr, tr_sr, p_se, l_se, tr_se;
 wire [31:0] p_a, p_wd, p_rd, l_a, l_wd, l_rd, tr_a, tr_wd, tr_rd;
 wire [3:0] p_ws, l_ws, tr_ws;
 wire p_w, l_w, tr_w;

 // perf / la 桩：把窗口内 offset 回声进数据，用来证明 mux3 没有截走它们的请求。
 // 地址必须在**接受请求的那一拍**锁存：请求握手之后 Core 立刻改地址，
 // 组合跟随会把残值（0x…EF）当成响应数据回上来。
 reg p_rsp_v=0, l_rsp_v=0;
 reg [31:0] p_addr_q=0, l_addr_q=0;
 always @(posedge clk) begin
  if(reset) begin p_rsp_v<=1'b0; l_rsp_v<=1'b0; p_addr_q<=32'd0; l_addr_q<=32'd0; end
  else begin
   if(p_v && p_r) begin p_rsp_v<=1'b1; p_addr_q<=p_a; end
   else if(p_rsp_v && p_sr) p_rsp_v<=1'b0;
   if(l_v && l_r) begin l_rsp_v<=1'b1; l_addr_q<=l_a; end
   else if(l_rsp_v && l_sr) l_rsp_v<=1'b0;
  end
 end
 assign p_r  = !p_rsp_v;  assign p_sv = p_rsp_v;
 assign p_rd = 32'h2E00_0000 | {24'b0,p_addr_q[7:0]};
 assign p_se = 1'b0;
 assign l_r  = !l_rsp_v;  assign l_sv = l_rsp_v;
 assign l_rd = 32'h1A00_0000 | {24'b0,l_addr_q[7:0]};
 assign l_se = 1'b0;

 application_mmio_mux3 u_mux(
  .clk(clk),.reset(reset),
  .req_valid(valid),.req_ready(req_ready),.req_addr(addr),
  .req_write(write),.req_wdata(wdata),.req_wstrb(wstrb),
  .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_rdata(rdata),.rsp_error(rsp_error),
  .perf_req_valid(p_v),.perf_req_ready(p_r),.perf_req_addr(p_a),.perf_req_write(p_w),
  .perf_req_wdata(p_wd),.perf_req_wstrb(p_ws),.perf_rsp_valid(p_sv),.perf_rsp_ready(p_sr),
  .perf_rsp_rdata(p_rd),.perf_rsp_error(p_se),
  .la_req_valid(l_v),.la_req_ready(l_r),.la_req_addr(l_a),.la_req_write(l_w),
  .la_req_wdata(l_wd),.la_req_wstrb(l_ws),.la_rsp_valid(l_sv),.la_rsp_ready(l_sr),
  .la_rsp_rdata(l_rd),.la_rsp_error(l_se),
  .tr_req_valid(tr_v),.tr_req_ready(tr_r),.tr_req_addr(tr_a),.tr_req_write(tr_w),
  .tr_req_wdata(tr_wd),.tr_req_wstrb(tr_ws),.tr_rsp_valid(tr_sv),.tr_rsp_ready(tr_sr),
  .tr_rsp_rdata(tr_rd),.tr_rsp_error(tr_se)
 );

 core_trace_mmio #(.DEPTH(DEPTH),.MARKS(MARKS),.AW(AW),.MW(MW)) u_tr(
  .clk(clk),.reset(reset),
  .req_valid(tr_v),.req_ready(tr_r),.req_addr(tr_a),.req_write(tr_w),
  .req_wdata(tr_wd),.req_wstrb(tr_ws),.rsp_valid(tr_sv),.rsp_ready(tr_sr),
  .rsp_rdata(tr_rd),.rsp_error(tr_se),
  .trace_valid(t_valid),.trace_pc(t_pc),.trace_instruction(t_inst),
  .trace_rd_we(t_rd_we),.trace_rd_addr(t_rd_addr),.trace_rd_data(t_rd_data),
  .trace_mem_we(t_mem_we),.trace_mem_addr(t_mem_addr),.trace_mem_data(t_mem_data),
  .trace_mem_wstrb(t_mem_wstrb),.trace_error(t_error)
 );

 always #5 clk=~clk;
 integer failures=0, snap=0;
 localparam [31:0] BASE = 32'h1000_2200;
 reg [31:0] rv; reg re;

 task wr; input [31:0] a,v; begin
  @(negedge clk); addr=a; wdata=v; write=1; valid=1; rsp_ready=1;
  wait(req_ready); @(posedge clk); #1; valid=0; write=0;
  wait(!rsp_valid); rsp_ready=0;
 end endtask
 task wrbe; input [31:0] a,v; input [3:0] be; begin wstrb=be; wr(a,v); wstrb=4'hf; end endtask
 // 读任务：**必须在 rsp_valid && rsp_ready 的那一拍取 rdata**。
 // 晚一拍取会读到"响应已经撤掉之后"的 MUX 状态——因为 rsp_rdata 是按当前
 // rsp_valid 选的，谁撤了 valid 就轮到别人的残留值。2026-10-21 这个 TB 第一版
 // 就是在握手的下一拍才取，结果每次读都拿到 LA 桩的残留值（0x1A0000EF）。
 task rd; input [31:0] a; output [31:0] v; begin
  @(negedge clk); addr=a; write=0; valid=1; rsp_ready=0;
  wait(req_ready); @(posedge clk); #1; valid=0; addr=32'hdeadbeef;
  @(negedge clk); rsp_ready=1;
  wait(rsp_valid); v=rdata;            // 同拍取样：mux 此刻才选的是被读的那个目标
  @(posedge clk); #1; rsp_ready=0;
 end endtask
 task rderr; input [31:0] a; output e; begin
  @(negedge clk); addr=a; write=0; valid=1; rsp_ready=0;
  wait(req_ready); @(posedge clk); #1; valid=0; addr=32'hdeadbeef;
  @(negedge clk); rsp_ready=1;
  wait(rsp_valid); e=rsp_error;
  @(posedge clk); #1; rsp_ready=0;
 end endtask
 task push; input [31:0] pc,inst,rdd,mda,mdd; input rdw,mew,err; input [4:0] rda; input [3:0] wsb; begin
  @(negedge clk);
  t_pc=pc; t_inst=inst; t_rd_we=rdw; t_rd_addr=rda; t_rd_data=rdd;
  t_mem_we=mew; t_mem_addr=mda; t_mem_data=mdd; t_mem_wstrb=wsb; t_error=err; t_valid=1'b1;
  @(posedge clk); #1; t_valid=1'b0;
 end endtask

 // 一条记录按 MMIO 的 5 个字拼回来的形状（132 位，最高字只有 4 位有效），供整条对拍
 reg [131:0] exp_rec;

 // 按 RD_INDEX + RD_W0..W4 完整读回一条记录
 task readrec; input [15:0] idx; output [131:0] rec; reg [31:0] x; begin
  wr(BASE+32'h10,{16'b0,idx});
  rd(BASE+32'h14,x); rec[31:0]   = x;
  rd(BASE+32'h18,x); rec[63:32]  = x;
  rd(BASE+32'h1c,x); rec[95:64]  = x;
  rd(BASE+32'h20,x); rec[127:96] = x;
  rd(BASE+32'h30,x); rec[131:128]= x[3:0];
 end endtask

 initial begin
  repeat(2) @(posedge clk); reset=0; @(posedge clk); #1;

  // ---- T1 复位：STATUS/COUNT 全零 ----
  snap=failures;
  rd(BASE+32'h04,rv); if(rv[3:0]!==4'b0000) begin $display("T1 STATUS FAIL %h",rv); failures=failures+1; end
  rd(BASE+32'h08,rv); if(rv[15:0]!==16'd0)  begin $display("T1 COUNT FAIL %0d",rv); failures=failures+1; end
  if(failures==snap) $display("T1 RESET PASS");

  // ---- T2 写 CTRL.arm → armed/recording ----
  snap=failures;
  wr(BASE+32'h00,32'h1);
  rd(BASE+32'h04,rv);
  if(rv[0]!==1'b1||rv[1]!==1'b1) begin $display("T2 ARM FAIL %h",rv); failures=failures+1; end
  if(failures==snap) $display("T2 ARM PASS");

  // ---- T3 零 strobe 写不得产生副作用（先 stop，再零 strobe 写 arm）----
  snap=failures;
  wr(BASE+32'h00,32'h2);
  wrbe(BASE+32'h00,32'h1,4'b0000);
  rd(BASE+32'h04,rv);
  if(rv[0]!==1'b0||rv[1]!==1'b0) begin $display("T3 ZERO-STROBE FAIL %h",rv); failures=failures+1; end
  if(failures==snap) $display("T3 ZERO-STROBE NO-SIDE-EFFECT PASS");

  // ---- T4 读 CTRL 地址不得顺手 arm ----
  snap=failures;
  rd(BASE+32'h00,rv);
  rd(BASE+32'h04,rv);
  if(rv[0]!==1'b0) begin $display("T4 READ-NO-SIDE-EFFECT FAIL %h",rv); failures=failures+1; end
  if(failures==snap) $display("T4 READ-NO-SIDE-EFFECT PASS");

  // ---- T5 记录三条并读回 COUNT ----
  snap=failures;
  wr(BASE+32'h00,32'h1);   // arm
  push(32'h000, 32'h00A00513, 32'h0000000A, 32'h0,   32'h0,        1'b1,1'b0,1'b0, 5'd10, 4'h0);
  push(32'h004, 32'h00B00593, 32'h0000000B, 32'h0,   32'h0,        1'b1,1'b0,1'b0, 5'd11, 4'h0);
  push(32'h008, 32'h00A5A023, 32'h0,        32'h100, 32'h0000000A, 1'b0,1'b1,1'b0, 5'd0,  4'hF);
  rd(BASE+32'h08,rv);
  if(rv[15:0]!==16'd3) begin $display("T5 COUNT FAIL %0d",rv); failures=failures+1; end
  if(failures==snap) $display("T5 COUNT PASS");

  // ---- T6 RD_INDEX + 5 个字拼回整条记录，与期望值逐位对拍 ----
  // 这一条同时验证"记录位段"与"MMIO 字映射"两件事，缺任一件页面上的字段就会错位。
  snap=failures;
  readrec(16'd2,exp_rec);
  if(exp_rec !== {1'b0, 32'h0000_000A, 4'hF, 12'h100, 1'b1, 32'd0, 5'd0, 1'b0, 32'h00A5_A023, 12'h008})
   begin $display("T6 RECORD[2] FAIL got=%h want=0A1F1000_0000_0000_0000A5A0_2300_8",exp_rec); failures=failures+1; end
  readrec(16'd0,exp_rec);
  if(exp_rec !== {1'b0, 32'd0, 4'h0, 12'h000, 1'b0, 32'h0000_000A, 5'd10, 1'b1, 32'h00A0_0513, 12'h000})
   begin $display("T6 RECORD[0] FAIL got=%h",exp_rec); failures=failures+1; end
  if(failures==snap) $display("T6 RECORD READOUT PASS");

  // ---- T7 打点 ----
  snap=failures;
  rd(BASE+32'h0c,rv); if(rv[15:0]!==16'd0) begin $display("T7 MARKCOUNT before FAIL %0d",rv); failures=failures+1; end
  wr(BASE+32'h2c,32'h48);              // 打一个 'H'
  rd(BASE+32'h0c,rv); if(rv[15:0]!==16'd1) begin $display("T7 MARKCOUNT FAIL %0d",rv); failures=failures+1; end
  rd(BASE+32'h28,rv);
  if(rv[7:0]!==8'h48)   begin $display("T7 mark value FAIL %h",rv[7:0]); failures=failures+1; end
  if(rv[23:8]!==16'd3)  begin $display("T7 mark index FAIL %0d",rv[23:8]); failures=failures+1; end
  if(failures==snap) $display("T7 MARK PASS");

  // ---- T8 stop → done ----
  snap=failures;
  wr(BASE+32'h00,32'h2);
  rd(BASE+32'h04,rv);
  if(rv[2]!==1'b1||rv[1]!==1'b0) begin $display("T8 STOP FAIL %h",rv); failures=failures+1; end
  if(failures==snap) $display("T8 STOP PASS");

  // ---- T9 越界 / 非对齐 offset 必须报错，不得静默成功 ----
  snap=failures;
  rderr(BASE+32'h40,re);
  if(re!==1'b1) begin $display("T9 OOR OFFSET FAIL err=%b",re); failures=failures+1; end
  rderr(BASE+32'h02,re);
  if(re!==1'b1) begin $display("T9 MISALIGNED FAIL err=%b",re); failures=failures+1; end
  if(failures==snap) $display("T9 ERROR RESPONSE PASS");

  // ---- T10 包一层之后既有两个子窗口必须原样工作 ----
  snap=failures;
  rd(32'h1000_2000,rv);
  if(rv!==32'h2E00_0000) begin $display("T10 PERF WINDOW FAIL %h",rv); failures=failures+1; end
  rd(32'h1000_2024,rv);
  if(rv!==32'h2E00_0024) begin $display("T10 PERF OFFSET FAIL %h",rv); failures=failures+1; end
  rd(32'h1000_2100,rv);
  if(rv!==32'h1A00_0000) begin $display("T10 LA WINDOW FAIL %h",rv); failures=failures+1; end
  rd(32'h1000_2144,rv);
  if(rv!==32'h1A00_0044) begin $display("T10 LA OFFSET FAIL %h",rv); failures=failures+1; end
  if(failures==snap) $display("T10 LEGACY SUBWINDOWS PASS");

  // ---- T11 子窗口 3 仍然报未映射 ----
  snap=failures;
  rderr(32'h1000_2300,re);
  if(re!==1'b1) begin $display("T11 UNMAPPED FAIL err=%b",re); failures=failures+1; end
  if(failures==snap) $display("T11 UNMAPPED SUBWINDOW PASS");

  if(failures==0) $display("ALL CORE TRACE MMIO TEST PASS");
  else $fatal(1,"CORE TRACE MMIO %0d FAIL",failures);
  $finish;
 end
endmodule
