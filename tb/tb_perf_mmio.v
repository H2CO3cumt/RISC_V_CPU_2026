`timescale 1ns/1ps
module tb_perf_mmio;
 reg clk=0,reset=1,valid=0,write=0,ready_rsp=0;reg [31:0]addr,wdata;reg [3:0]wstrb;wire ready,rspv,err,clear;wire [31:0]rdata;integer failures=0;
 reg [63:0]cyc=64'h00000002_00000001,ins=64'h00000004_00000003,st=64'h6,ls=64'h7,br=64'h8,tak=64'h9,fl=64'ha,pred=64'hb,hit=64'hc,miss=64'hd;
 perf_mmio dut(.clk(clk),.reset(reset),.req_valid(valid),.req_ready(ready),.req_addr(addr),.req_write(write),.req_wdata(wdata),.req_wstrb(wstrb),.rsp_valid(rspv),.rsp_ready(ready_rsp),.rsp_rdata(rdata),.rsp_error(err),.clear(clear),.cycle_count(cyc),.instret_count(ins),.stall_count(st),.load_stall_count(ls),.branch_count(br),.branch_taken_count(tak),.flush_count(fl),.predict_count(pred),.btb_hit_count(hit),.mispredict_count(miss));
 always #5 clk=~clk;
 task do_read;input [31:0] a;input [31:0] want;input [8*20-1:0] name;begin
  addr=a;write=0;valid=1;@(posedge clk);#1;valid=0;addr=32'hdeadbeef;repeat(2)@(posedge clk);
  if(!rspv||err||rdata!==want)begin $display("TEST %0s FAIL r=%h e=%b",name,rdata,err);failures=failures+1;end else $display("TEST %0s PASS",name);
  ready_rsp=1;@(posedge clk);#1;ready_rsp=0;end endtask
 initial begin repeat(2)@(posedge clk);reset=0;do_read(0,1,"cycle lo");do_read(8,3,"inst lo");do_read(40,9,"taken lo");do_read(64,11,"predict lo");do_read(72,12,"btb hit lo");do_read(80,13,"mispredict lo");addr=32'h3c;valid=1;@(posedge clk);#1;if(!err||!rspv)begin $display("TEST bad offset FAIL");failures=failures+1;end else $display("TEST bad offset PASS");valid=0;ready_rsp=1;@(posedge clk);wait(rspv===0);ready_rsp=0;@(negedge clk);addr=56;wdata=1;wstrb=4'b0001;write=1;valid=1;@(posedge clk);#1;if(!clear)begin $display("TEST clear FAIL req_ready=%b rsp=%b",ready,rspv);failures=failures+1;end else $display("TEST clear PASS");valid=0;ready_rsp=1;@(posedge clk);ready_rsp=0;if(failures==0)$display("ALL PERF MMIO TEST PASS");else $fatal(1,"PERF MMIO %0d FAIL",failures);$finish;end
endmodule
