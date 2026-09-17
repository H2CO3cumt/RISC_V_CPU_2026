`timescale 1ns/1ps
module tb_pipeline_reset_abort;
 reg clk=0,reset=1,allow_data=0; integer failures=0,side_effects=0,store_traces=0;
 wire tv,tmw,iv,ir,rv,rr,ie,dv,dw,dsr; wire [31:0] tpc,tinst,tmaddr,tmdata,ia,idata,da,dwd; wire [3:0] tmstrb,dst; wire trw; wire [4:0] trd; wire [31:0] trdata;
 reg dsv=0; reg [31:0] drd=0; reg de=0; reg [31:0] mem0=0;
 wire dr=allow_data&&!dsv;
 pipeline_cpu dut(.clk(clk),.reset(reset),.trace_valid(tv),.trace_pc(tpc),.trace_instruction(tinst),.trace_rd_we(trw),.trace_rd_addr(trd),.trace_rd_data(trdata),.trace_mem_we(tmw),.trace_mem_addr(tmaddr),.trace_mem_data(tmdata),.trace_mem_wstrb(tmstrb),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(),.event_load_stall(),.event_branch(),.event_branch_taken(),.event_flush());
 pipeline_imem_adapter #(.DEPTH(3),.INIT_FILE("tb/data/task23_reset_abort.mem")) imem(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 always #5 clk=~clk;
 always @(posedge clk) begin
  if(reset)dsv<=0;else begin
   if(dsv&&dsr)dsv<=0;
   if(dv&&dr)begin side_effects=side_effects+1;if(dst[0])mem0[7:0]<=dwd[7:0];if(dst[1])mem0[15:8]<=dwd[15:8];if(dst[2])mem0[23:16]<=dwd[23:16];if(dst[3])mem0[31:24]<=dwd[31:24];dsv<=1;end
  end
  if(!reset&&tv&&tmw)store_traces=store_traces+1;
 end
 initial begin
  repeat(2)@(negedge clk);reset=0;
  wait(dv===1'b1); repeat(3)begin @(posedge clk);#1;if(!dv||side_effects!=0)begin $display("RESET WAIT STABILITY FAIL");failures=failures+1;end end
  reset=1;@(posedge clk);#1;if(dv||dsr||tv||side_effects!=0)begin $display("RESET ABORT FAIL dv=%b dsr=%b tv=%b effects=%0d",dv,dsr,tv,side_effects);failures=failures+1;end else $display("TEST reset abort unaccepted store PASS");
  @(negedge clk);reset=0;allow_data=1;wait(store_traces==1);#1;
  if(side_effects!==1||mem0!==32'h0000005a)begin $display("TEST restart single store FAIL effects=%0d mem=%h",side_effects,mem0);failures=failures+1;end else $display("TEST restart single store PASS");
  if(failures==0)$display("ALL PIPELINE RESET ABORT TEST PASS");else $fatal(1,"RESET ABORT %0d FAIL",failures);$finish;
 end
 initial begin #5000;$fatal(1,"RESET ABORT TIMEOUT");end
endmodule
