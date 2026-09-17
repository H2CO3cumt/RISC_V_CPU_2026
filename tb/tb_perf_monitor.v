`timescale 1ns/1ps
module tb_perf_monitor;
 reg clk=0,reset=1,clear=0,enable=1,retire=0,stall=0,load_stall=0,branch=0,taken=0,flush=0,predict=0,hit=0,mispredict=0; integer failures=0;
 wire [63:0] cycles,instret,stalls,loads,branches,takens,flushes,predicts,hits,misses;
 perf_monitor dut(.clk(clk),.reset(reset),.clear(clear),.enable(enable),.event_retire(retire),.event_stall(stall),.event_load_stall(load_stall),.event_branch(branch),.event_branch_taken(taken),.event_flush(flush),.event_predict(predict),.event_btb_hit(hit),.event_mispredict(mispredict),.cycle_count(cycles),.instret_count(instret),.stall_count(stalls),.load_stall_count(loads),.branch_count(branches),.branch_taken_count(takens),.flush_count(flushes),.predict_count(predicts),.btb_hit_count(hits),.mispredict_count(misses));
 always #5 clk=~clk;
 task check; input [63:0] got,want;input [8*24-1:0] name;begin if(got!==want)begin $display("TEST %0s FAIL got=%0d want=%0d",name,got,want);failures=failures+1;end else $display("TEST %0s PASS",name);end endtask
 initial begin
  repeat(2)@(posedge clk);reset=0;@(negedge clk);retire=1;stall=1;load_stall=1;branch=1;taken=1;flush=1;predict=1;hit=1;mispredict=1;
  @(posedge clk);#1;retire=0;stall=0;load_stall=0;branch=0;taken=0;flush=0;predict=0;hit=0;mispredict=0;
  repeat(2)@(posedge clk);#1;check(cycles,3,"cycle count");check(instret,1,"instret count");check(stalls,1,"stall count");check(loads,1,"load stall count");check(branches,1,"branch count");check(takens,1,"taken count");check(flushes,1,"flush count");check(predicts,1,"predict count");check(hits,1,"btb hit count");check(misses,1,"mispredict count");
  clear=1;@(posedge clk);#1;clear=0;check(cycles,0,"clear cycle");check(instret,0,"clear instret");
  enable=0;repeat(2)@(posedge clk);#1;check(cycles,0,"disabled hold");
  if(failures==0)$display("ALL PERF MONITOR TEST PASS");else $fatal(1,"PERF MONITOR %0d FAIL",failures);$finish;end
endmodule
