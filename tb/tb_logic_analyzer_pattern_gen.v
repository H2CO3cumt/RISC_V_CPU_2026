`timescale 1ns/1ps
module tb_logic_analyzer_pattern_gen;
 reg clk=0,reset=1,restart=0;reg [1:0]mode=0;reg [15:0]tick_div=0;reg [7:0]data=0;wire [7:0]out;integer failures=0,i;reg [7:0]decoded;
 logic_analyzer_pattern_gen dut(.clk(clk),.reset(reset),.restart(restart),.mode(mode),.tick_div(tick_div),.pattern_data(data),.pattern_out(out));
 always #5 clk=~clk;
 task check;input condition;input[255:0]name;begin if(condition)$display("PATTERN %0s PASS",name);else begin $display("PATTERN %0s FAIL out=%02h",name,out);failures=failures+1;end end endtask
 task pulse_restart;begin restart=1;@(posedge clk);#1;restart=0;end endtask
 initial begin
  repeat(2)@(posedge clk);#1;reset=0;data=8'ha5;#1;check(out==8'ha5,"static");
  mode=1;pulse_restart;@(posedge clk);#1;check(out==1,"counter first");@(posedge clk);#1;check(out==2,"counter second");
  mode=2;data=8'ha5;pulse_restart;#1;check(out[0]==1,"uart restart idle");
  @(posedge clk);#1;check(out[0]==0,"uart start");decoded=0;
  for(i=0;i<8;i=i+1)begin @(posedge clk);#1;decoded[i]=out[0];end
  @(posedge clk);#1;check(decoded==8'ha5&&out[0]==1,"uart 8n1");
  mode=3;data=8'ha5;pulse_restart;decoded=0;@(posedge clk);#1;
  for(i=7;i>=0;i=i-1)begin @(posedge clk);#1;check(out[0]==1,"spi rising");decoded[i]=out[1];@(posedge clk);#1;end
  check(decoded==8'ha5,"spi byte");check(out[2]==1,"spi cs gap");
  reset=1;@(posedge clk);#1;check(out[2]==1,"reset deterministic");
  if(failures==0)$display("ALL LOGIC ANALYZER PATTERN TEST PASS");else $fatal(1,"PATTERN %0d FAIL",failures);$finish;
 end
endmodule
