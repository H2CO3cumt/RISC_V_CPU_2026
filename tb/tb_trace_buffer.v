`timescale 1ns/1ps
// trace_buffer 独立 Testbench。
// 判据不是"能跑"，而是逐字段对拍：注入什么字段，回读必须一模一样。
// 只比 count 会放过"位段拼错但条数对"的错误，而那种错误在页面上表现为
// "指令看着对、数据全是乱码"，正是最难查的一类。
//
// 每个用例开始前记下 failures 的快照，结束时只按"本用例是否新增失败"报 PASS，
// 避免前面失败后面还跟着打印一串假 PASS。
module tb_trace_buffer;
 localparam integer DEPTH=16, MARKS=8, AW=4, MW=3;

 reg clk=0, reset=1;
 reg trace_valid=0, trace_rd_we=0, trace_mem_we=0, trace_error=0;
 reg [31:0] trace_pc=0, trace_instruction=0, trace_rd_data=0, trace_mem_addr=0, trace_mem_data=0;
 reg [4:0]  trace_rd_addr=0;
 reg [3:0]  trace_mem_wstrb=0;
 reg arm=0, stop=0, clear=0, mark=0;
 reg [7:0]  mark_value=0;
 reg [15:0] rd_index=0;
 reg [MW-1:0] mark_index=0;
 wire [131:0] rd_record;
 wire [23:0]  rd_mark;
 wire armed, recording, done, overflow;
 wire [15:0] count, mark_count;
 integer failures=0, snap=0;

 trace_buffer #(.DEPTH(DEPTH), .MARKS(MARKS), .AW(AW), .MW(MW)) dut(
  .clk(clk), .reset(reset),
  .trace_valid(trace_valid), .trace_pc(trace_pc), .trace_instruction(trace_instruction),
  .trace_rd_we(trace_rd_we), .trace_rd_addr(trace_rd_addr), .trace_rd_data(trace_rd_data),
  .trace_mem_we(trace_mem_we), .trace_mem_addr(trace_mem_addr), .trace_mem_data(trace_mem_data),
  .trace_mem_wstrb(trace_mem_wstrb), .trace_error(trace_error),
  .arm(arm), .stop(stop), .clear(clear), .mark(mark), .mark_value(mark_value),
  .rd_index(rd_index), .mark_index(mark_index),
  .rd_record(rd_record), .rd_mark(rd_mark),
  .armed(armed), .recording(recording), .done(done), .overflow(overflow),
  .count(count), .mark_count(mark_count)
 );

 always #5 clk=~clk;

 // 喂一条退休记录（一个 trace_valid 脉冲）
 task push;
  input [31:0] pc, inst, rdd, mda, mdd;
  input        rdw, mew, err;
  input [4:0]  rda;
  input [3:0]  wsb;
  begin
   @(negedge clk);
   trace_pc=pc; trace_instruction=inst;
   trace_rd_we=rdw; trace_rd_addr=rda; trace_rd_data=rdd;
   trace_mem_we=mew; trace_mem_addr=mda; trace_mem_data=mdd; trace_mem_wstrb=wsb;
   trace_error=err; trace_valid=1'b1;
   @(posedge clk); #1;
   trace_valid=1'b0;
  end
 endtask

 task pulse_arm;   begin @(negedge clk); arm=1;   @(posedge clk); #1; arm=0;   end endtask
 task pulse_stop;  begin @(negedge clk); stop=1;  @(posedge clk); #1; stop=0;  end endtask
 task pulse_clear; begin @(negedge clk); clear=1; @(posedge clk); #1; clear=0; end endtask
 task pulse_mark;  input [7:0] v;
  begin @(negedge clk); mark=1; mark_value=v; @(posedge clk); #1; mark=0; end
 endtask
 task sel; input integer i; begin @(negedge clk); rd_index=i; @(posedge clk); #1; end endtask
 task selmark; input integer i; begin @(negedge clk); mark_index=i; @(posedge clk); #1; end endtask

 initial begin
  repeat(2) @(posedge clk); reset=0; @(posedge clk); #1;

  // ---- T1 复位状态 ----
  snap=failures;
  if(armed||recording||done||overflow||count!=0||mark_count!=0) begin
   $display("T1 RESET STATE FAIL armed=%b rec=%b done=%b ovf=%b count=%0d marks=%0d",
            armed,recording,done,overflow,count,mark_count); failures=failures+1;
  end
  if(failures==snap) $display("T1 RESET STATE PASS");

  // ---- T2 arm 之后进入记录态 ----
  snap=failures;
  pulse_arm;
  if(armed!==1'b1)   begin $display("T2 arm->armed FAIL %b",armed); failures=failures+1; end
  if(recording!==1'b1) begin $display("T2 arm->recording FAIL %b",recording); failures=failures+1; end
  if(failures==snap) $display("T2 ARM PASS");

  // ---- T3 逐字段对拍三条真实形状的记录 ----
  snap=failures;
  push(32'h000, 32'h00A00513, 32'h0000000A, 32'h0,   32'h0,        1'b1, 1'b0, 1'b0, 5'd10, 4'h0);
  push(32'h004, 32'h00B00593, 32'h0000000B, 32'h0,   32'h0,        1'b1, 1'b0, 1'b0, 5'd11, 4'h0);
  push(32'h008, 32'h00A5A023, 32'h0,        32'h100, 32'h0000000A, 1'b0, 1'b1, 1'b0, 5'd0,  4'hF);
  if(count!==16'd3) begin $display("T3 COUNT FAIL got=%0d want=3",count); failures=failures+1; end

  sel(0);
  if({20'b0,rd_record[11:0]}!==32'h000)     begin $display("T3[0] pc FAIL %h",rd_record[11:0]); failures=failures+1; end
  if(rd_record[43:12]!==32'h00A00513)       begin $display("T3[0] inst FAIL %h",rd_record[43:12]); failures=failures+1; end
  if(rd_record[44]!==1'b1)                  begin $display("T3[0] rd_we FAIL %b",rd_record[44]); failures=failures+1; end
  if({27'b0,rd_record[49:45]}!==32'd10)     begin $display("T3[0] rd_addr FAIL %0d",rd_record[49:45]); failures=failures+1; end
  if(rd_record[81:50]!==32'h0000000A)       begin $display("T3[0] rd_data FAIL %h",rd_record[81:50]); failures=failures+1; end
  if(rd_record[82]!==1'b0)                  begin $display("T3[0] mem_we FAIL %b",rd_record[82]); failures=failures+1; end
  if({20'b0,rd_record[94:83]}!==32'h0)      begin $display("T3[0] mem_addr FAIL %h",rd_record[94:83]); failures=failures+1; end
  if(rd_record[98:95]!==4'h0)               begin $display("T3[0] mem_wstrb FAIL %h",rd_record[98:95]); failures=failures+1; end
  if(rd_record[130:99]!==32'h0)             begin $display("T3[0] mem_data FAIL %h",rd_record[130:99]); failures=failures+1; end
  if(rd_record[131]!==1'b0)                 begin $display("T3[0] error FAIL %b",rd_record[131]); failures=failures+1; end

  sel(2);
  if({20'b0,rd_record[11:0]}!==32'h008)     begin $display("T3[2] pc FAIL %h",rd_record[11:0]); failures=failures+1; end
  if(rd_record[43:12]!==32'h00A5A023)       begin $display("T3[2] inst FAIL %h",rd_record[43:12]); failures=failures+1; end
  if(rd_record[44]!==1'b0)                  begin $display("T3[2] rd_we FAIL %b",rd_record[44]); failures=failures+1; end
  if(rd_record[82]!==1'b1)                  begin $display("T3[2] mem_we FAIL %b",rd_record[82]); failures=failures+1; end
  if({20'b0,rd_record[94:83]}!==32'h100)    begin $display("T3[2] mem_addr FAIL %h",rd_record[94:83]); failures=failures+1; end
  if(rd_record[98:95]!==4'hF)               begin $display("T3[2] mem_wstrb FAIL %h",rd_record[98:95]); failures=failures+1; end
  if(rd_record[130:99]!==32'h0000000A)      begin $display("T3[2] mem_data FAIL %h",rd_record[130:99]); failures=failures+1; end
  if(failures==snap) $display("T3 RECORD FIELDS PASS");

  // ---- T4 没有有效退休时不得凭空多记一条 ----
  snap=failures;
  @(negedge clk); trace_pc=32'hdead; @(posedge clk); repeat(4) @(posedge clk); #1;
  if(count!==16'd3) begin $display("T4 IDLE NO-RECORD FAIL got=%0d want=3",count); failures=failures+1; end
  if(failures==snap) $display("T4 IDLE NO-RECORD PASS");

  // ---- T5 软件打点：索引必须是"打点那一刻已记录的条数" ----
  snap=failures;
  pulse_mark(8'h48); // 'H'
  if(mark_count!==16'd1) begin $display("T5 MARK COUNT FAIL %0d",mark_count); failures=failures+1; end
  selmark(0);
  if(rd_mark[7:0]!==8'h48)   begin $display("T5 mark value FAIL %h",rd_mark[7:0]); failures=failures+1; end
  if(rd_mark[23:8]!==16'd3)  begin $display("T5 mark index FAIL %0d",rd_mark[23:8]); failures=failures+1; end
  if(failures==snap) $display("T5 MARK PASS");

  // ---- T6 stop 之后不再记录 ----
  snap=failures;
  pulse_stop;
  if(recording!==1'b0) begin $display("T6 stop->recording FAIL %b",recording); failures=failures+1; end
  if(done!==1'b1)      begin $display("T6 stop->done FAIL %b",done); failures=failures+1; end
  push(32'h00C, 32'h00C00613, 32'h0000000C, 32'h0, 32'h0, 1'b1, 1'b0, 1'b0, 5'd12, 4'h0);
  if(count!==16'd3) begin $display("T6 STOP NO-RECORD FAIL got=%0d",count); failures=failures+1; end
  if(failures==snap) $display("T6 STOP NO-RECORD PASS");

  // ---- T7 写满自动收尾（DEPTH=16），并检查首尾槽位没有跑偏 ----
  snap=failures;
  pulse_clear;
  pulse_arm;
  push(32'h100, 32'h00000013, 32'h0, 32'h000, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h104, 32'h00000013, 32'h0, 32'h004, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h108, 32'h00000013, 32'h0, 32'h008, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h10C, 32'h00000013, 32'h0, 32'h00C, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h110, 32'h00000013, 32'h0, 32'h010, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h114, 32'h00000013, 32'h0, 32'h014, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h118, 32'h00000013, 32'h0, 32'h018, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h11C, 32'h00000013, 32'h0, 32'h01C, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h120, 32'h00000013, 32'h0, 32'h020, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h124, 32'h00000013, 32'h0, 32'h024, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h128, 32'h00000013, 32'h0, 32'h028, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h12C, 32'h00000013, 32'h0, 32'h02C, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h130, 32'h00000013, 32'h0, 32'h030, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h134, 32'h00000013, 32'h0, 32'h034, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h138, 32'h00000013, 32'h0, 32'h038, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  push(32'h13C, 32'h00000013, 32'h0, 32'h03C, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  if(count!==DEPTH) begin $display("T7 FILL COUNT FAIL got=%0d want=%0d",count,DEPTH); failures=failures+1; end
  if(done!==1'b1)      begin $display("T7 fill->done FAIL %b",done); failures=failures+1; end
  if(recording!==1'b0) begin $display("T7 fill->recording FAIL %b",recording); failures=failures+1; end
  if(overflow!==1'b0)  begin $display("T7 fill->overflow FAIL %b",overflow); failures=failures+1; end
  sel(0);
  if({20'b0,rd_record[11:0]}!==32'h100) begin $display("T7 slot0 pc FAIL %h",rd_record[11:0]); failures=failures+1; end
  sel(15);
  if({20'b0,rd_record[11:0]}!==32'h13C) begin $display("T7 slot15 pc FAIL %h",rd_record[11:0]); failures=failures+1; end
  if(failures==snap) $display("T7 FILL TO FULL PASS");

  // ---- T8 窗口收尾后还有退休指令 → overflow，且 count 不再增长 ----
  snap=failures;
  push(32'h200, 32'h00000013, 32'h0, 32'h0, 32'h0, 1'b0, 1'b0, 1'b0, 5'd0, 4'h0);
  if(overflow!==1'b1) begin $display("T8 overflow FAIL %b",overflow); failures=failures+1; end
  if(count!==DEPTH)   begin $display("T8 count drift FAIL %0d",count); failures=failures+1; end
  if(failures==snap) $display("T8 OVERFLOW FLAG PASS");

  // ---- T9 clear 复位计数与状态 ----
  snap=failures;
  pulse_clear;
  if(count!=0||mark_count!=0||armed||recording||done||overflow) begin
   $display("T9 CLEAR FAIL count=%0d marks=%0d armed=%b rec=%b done=%b ovf=%b",
            count,mark_count,armed,recording,done,overflow); failures=failures+1;
  end
  if(failures==snap) $display("T9 CLEAR PASS");

  // ---- T10 clear 之后可以重新 arm 并重新记录 ----
  snap=failures;
  pulse_arm;
  push(32'h00C, 32'h00C00613, 32'h0000000C, 32'h0, 32'h0, 1'b1, 1'b0, 1'b0, 5'd12, 4'h0);
  sel(0);
  if({20'b0,rd_record[11:0]}!==32'h00C) begin $display("T10 re-arm pc FAIL %h",rd_record[11:0]); failures=failures+1; end
  if(count!==16'd1) begin $display("T10 re-arm count FAIL %0d",count); failures=failures+1; end
  if(failures==snap) $display("T10 RE-ARM PASS");

  if(failures==0) $display("ALL TRACE BUFFER TEST PASS");
  else $fatal(1,"TRACE BUFFER %0d FAIL",failures);
  $finish;
 end
endmodule
