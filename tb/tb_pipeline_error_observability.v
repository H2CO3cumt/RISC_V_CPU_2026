`timescale 1ns/1ps
module tb_pipeline_error_observability;
 reg clk=0,reset=1; integer failures=0,cycles=0,illegal_count=0,misaligned_count=0,bus_error_count=0,trace_error_count=0,data_requests=0,bad_register_writes=0;
 wire tv,trace_error,trace_rd_we,iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de,event_illegal,event_misaligned,event_bus_error;wire [4:0] trace_rd_addr;
 wire [31:0] ia,idata,da,dwd,drd; wire [3:0] dst;
 pipeline_cpu dut(.clk(clk),.reset(reset),.trace_valid(tv),.trace_pc(),.trace_instruction(),.trace_rd_we(trace_rd_we),.trace_rd_addr(trace_rd_addr),.trace_rd_data(),.trace_mem_we(),.trace_mem_addr(),.trace_mem_data(),.trace_mem_wstrb(),.trace_error(trace_error),
  .i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),
  .d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),
  .event_stall(),.event_load_stall(),.event_branch(),.event_branch_taken(),.event_flush(),.event_predict(),.event_btb_hit(),.event_mispredict(),.event_illegal(event_illegal),.event_misaligned(event_misaligned),.event_bus_error(event_bus_error));
 imem_adapter #(.DEPTH(5),.INIT_FILE("tb/data/pipeline_error_observability.mem"),.RANDOM_DELAY(0)) im(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 ram_adapter #(.DEPTH(4),.RANDOM_DELAY(0)) dm(.clk(clk),.reset(reset),.req_valid(dv),.req_ready(dr),.req_addr(da),.req_write(dw),.req_wdata(dwd),.req_wstrb(dst),.rsp_valid(dsv),.rsp_ready(dsr),.rsp_rdata(drd),.rsp_error(de),.write_side_effect_count());
 always #5 clk=~clk;
 always @(posedge clk) if(!reset)begin
  cycles=cycles+1;if(event_illegal)illegal_count=illegal_count+1;if(event_misaligned)misaligned_count=misaligned_count+1;if(event_bus_error)bus_error_count=bus_error_count+1;if(trace_error)trace_error_count=trace_error_count+1;if(dv&&dr)data_requests=data_requests+1;if(trace_rd_we&&(trace_rd_addr==2||trace_rd_addr==3))bad_register_writes=bad_register_writes+1;
 end
 initial begin
  repeat(2)@(negedge clk);reset=0;wait(dut.rf.regs[4]==4);repeat(4)@(posedge clk);#1;
  if(illegal_count!=1)begin $display("TEST illegal event FAIL count=%0d",illegal_count);failures=failures+1;end else $display("TEST illegal event PASS");
  if(misaligned_count!=1)begin $display("TEST misaligned event FAIL count=%0d",misaligned_count);failures=failures+1;end else $display("TEST misaligned event PASS");
  if(bus_error_count<1)begin $display("TEST bus error event FAIL count=%0d",bus_error_count);failures=failures+1;end else $display("TEST bus error event PASS count=%0d",bus_error_count);
  if(trace_error_count<3)begin $display("TEST trace error FAIL count=%0d",trace_error_count);failures=failures+1;end else $display("TEST trace error PASS count=%0d",trace_error_count);
  if(data_requests!=1)begin $display("TEST misaligned request suppression FAIL requests=%0d",data_requests);failures=failures+1;end else $display("TEST misaligned request suppression PASS");
  if(bad_register_writes!=0)begin $display("TEST error write suppression FAIL writes=%0d",bad_register_writes);failures=failures+1;end else $display("TEST error write suppression PASS");
  if(failures==0)$display("ALL PIPELINE ERROR OBSERVABILITY TEST PASS");else $fatal(1,"PIPELINE ERROR OBSERVABILITY %0d FAIL",failures);$finish;
 end
 initial begin #5000;$fatal(1,"PIPELINE ERROR OBSERVABILITY TIMEOUT");end
endmodule
