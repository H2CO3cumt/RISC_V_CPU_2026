`timescale 1ns/1ps
module tb_logic_analyzer;
 reg clk=0,reset=1,valid=0,write=0,rsp_ready=0;reg [31:0]addr,wdata;reg [3:0]wstrb=4'hf;reg [7:0]channels=0;wire req_ready,rsp_valid,rsp_error;wire [31:0]rdata;wire [7:0]outs;integer failures=0,i;
 logic_analyzer_mmio dut(.clk(clk),.reset(reset),.req_valid(valid),.req_ready(req_ready),.req_addr(addr),.req_write(write),.req_wdata(wdata),.req_wstrb(wstrb),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_rdata(rdata),.rsp_error(rsp_error),.channels(channels),.sample_outputs(outs));
 always #5 clk=~clk;
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
 wr(8,2);wr(12,8'hff);wr(16,8'h01);wr(20,8'h01);wr(24,0);wr(28,0);wr(32,2);wr(36,3);wr(0,1);for(i=0;i<20;i=i+1)begin @(negedge clk);if(i==3)channels=8'h01;else if(i>3)channels=8'h03;else channels=0;end wait(dut.done);rd(4,rv);if(!rv[2]||!rv[1])begin $display("STATUS FAIL %h",rv);failures=failures+1;end else $display("STATUS PASS");rd(40,rv);if(rv[15:0]==0)begin $display("CAPTURE COUNT FAIL");failures=failures+1;end else $display("CAPTURE COUNT PASS %0d",rv[15:0]);wr(48,0);rd(52,rv);if(rv[7:0]!==8'h00)begin $display("READ DATA FAIL %h",rv);failures=failures+1;end else $display("READ DATA PASS");if(failures==0)$display("ALL LOGIC ANALYZER TEST PASS");else $fatal(1,"LOGIC ANALYZER %0d FAIL",failures);$finish;end
endmodule
