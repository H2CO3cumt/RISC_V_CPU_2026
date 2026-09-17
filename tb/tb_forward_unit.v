`timescale 1ns/1ps
module tb_forward_unit;
 reg [4:0] rs1,rs2,exrd,wbrd; reg exv,exw,exload,wbv,wbw,wberr; wire [1:0] fa,fb; integer failures=0;
 forward_unit dut(.idex_rs1(rs1),.idex_rs2(rs2),.exmem_valid(exv),.exmem_regwrite(exw),.exmem_memread(exload),.exmem_rd(exrd),.memwb_valid(wbv),.memwb_regwrite(wbw),.memwb_error(wberr),.memwb_rd(wbrd),.forward_a(fa),.forward_b(fb));
 task check; input [1:0] a,b; input [8*24-1:0] name; begin if(fa!==a||fb!==b)begin $display("TEST %0s FAIL a=%b b=%b",name,fa,fb);failures=failures+1;end else $display("TEST %0s PASS",name);end endtask
 initial begin
  rs1=1;rs2=2;exrd=0;wbrd=0;exv=0;exw=0;exload=0;wbv=0;wbw=0;wberr=0;#1;check(0,0,"no producer");
  wbv=1;wbw=1;wbrd=1;#1;check(1,0,"wb rs1"); wbrd=2;#1;check(0,1,"wb rs2");
  exv=1;exw=1;exrd=1;wbrd=2;#1;check(2,1,"mixed sources"); exrd=2;#1;check(0,2,"ex rs2");
  rs1=3;rs2=3;exrd=3;wbrd=3;#1;check(2,2,"dual newest priority");
  exload=1;#1;check(1,1,"load excluded from exmem");
  exload=0;exrd=0;wbrd=0;#1;check(0,0,"x0 excluded");
  exrd=3;wbrd=3;wberr=1;exv=0;#1;check(0,0,"error wb excluded");
  if(failures==0)$display("ALL FORWARD UNIT TEST PASS");else $fatal(1,"FORWARD UNIT %0d FAIL",failures);$finish;
 end
endmodule
