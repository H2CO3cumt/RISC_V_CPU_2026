`timescale 1ns/1ps
module tb_pipeline_smoke;
 reg clk=0,reset=1; integer fail=0,cycles=0;
 wire tv; wire [31:0] tpc,tins; wire trw,tmw; wire [4:0] trd; wire [31:0] trdata,tmaddr,tmdata; wire [3:0] tmstrb;
 wire iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de; wire [31:0] ia,idata,da,dwd,drd; wire [3:0] dst;
 pipeline_cpu dut(.clk(clk),.reset(reset),.trace_valid(tv),.trace_pc(tpc),.trace_instruction(tins),.trace_rd_we(trw),.trace_rd_addr(trd),.trace_rd_data(trdata),.trace_mem_we(tmw),.trace_mem_addr(tmaddr),.trace_mem_data(tmdata),.trace_mem_wstrb(tmstrb),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(),.event_load_stall(),.event_branch(),.event_branch_taken(),.event_flush());
 task15_imem_adapter #(.DEPTH(12),.INIT_FILE("tb/data/task11_single_cycle.mem"),.RANDOM_DELAY(0)) im(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 task15_ram_adapter #(.DEPTH(16),.RANDOM_DELAY(0)) dm(.clk(clk),.reset(reset),.req_valid(dv),.req_ready(dr),.req_addr(da),.req_write(dw),.req_wdata(dwd),.req_wstrb(dst),.rsp_valid(dsv),.rsp_ready(dsr),.rsp_rdata(drd),.rsp_error(de),.write_side_effect_count());
 always #5 clk=~clk;
 task ck; input [31:0] got,want; input [8*24-1:0] name; begin if(got!==want)begin $display("TEST %0s FAIL got=%h want=%h",name,got,want);fail=fail+1;end else $display("TEST %0s PASS",name);end endtask
 always @(posedge clk) if(!reset) begin cycles=cycles+1; if(tv)$display("RETIRE pc=%h inst=%h",tpc,tins); end
 initial begin repeat(2)@(negedge clk);reset=0;repeat(180)@(posedge clk); #1;
  ck(dut.rf.regs[1],5,"x1");ck(dut.rf.regs[2],10,"x2");ck(dut.rf.regs[3],15,"x3");ck(dut.rf.regs[4],15,"x4");ck(dut.rf.regs[5],10,"x5");ck(dut.rf.regs[7],40,"x7");ck(dm.mem[0],15,"mem0");ck(dm.mem[1],10,"mem1");
  if(fail==0)$display("ALL PIPELINE SMOKE PASS");else $fatal(1,"PIPELINE SMOKE %0d FAIL",fail);$finish;end
 initial begin #3000;$fatal(1,"PIPELINE SMOKE TIMEOUT");end
endmodule
