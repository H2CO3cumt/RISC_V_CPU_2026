`timescale 1ns/1ps
module tb_hazard_unit;
 reg idv,mr,ifv; reg [4:0] rd; reg [31:0] inst; wire stall; integer failures=0;
 hazard_unit dut(.idex_valid(idv),.idex_memread(mr),.idex_rd(rd),.ifid_valid(ifv),.ifid_instruction(inst),.load_use_stall(stall));
 task check; input want; input [8*28-1:0] name; begin #1;if(stall!==want)begin $display("TEST %0s FAIL got=%b",name,stall);failures=failures+1;end else $display("TEST %0s PASS",name);end endtask
 initial begin idv=1;mr=1;ifv=1;rd=5;
  inst=32'h000282b3;check(1,"R rs1");
  inst=32'h005000b3;check(1,"R rs2");
  inst=32'h00128293;check(1,"ALU-I rs1");
  inst=32'h00502023;check(1,"Store rs2");
  inst=32'h0002a023;check(1,"Store rs1");
  inst=32'h00528463;check(1,"Branch source");
  inst=32'h00500293;check(0,"ALU-I immediate false rs2");
  inst=32'h005002b7;check(0,"LUI no source");
  inst=32'h005002ef;check(0,"JAL no source");
  rd=0;inst=32'h00000033;check(0,"x0 producer excluded");
  rd=5;idv=0;check(0,"invalid producer");idv=1;mr=0;check(0,"non-load producer");
  if(failures==0)$display("ALL HAZARD UNIT TEST PASS");else $fatal(1,"HAZARD UNIT %0d FAIL",failures);$finish;end
endmodule
