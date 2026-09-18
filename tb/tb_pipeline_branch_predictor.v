`timescale 1ns/1ps
module tb_pipeline_branch_predictor;
 reg clk=0,reset=1; integer cycles=0,on_done=0,off_done=0,on_cycle=0,off_cycle=0,failures=0;
 wire on_tv,on_tmw,off_tv,off_tmw; wire [31:0] on_tmaddr,off_tmaddr,on_tmdata,off_tmdata;
 wire on_iv,on_ir,on_rv,on_rr,on_ie,on_dv,on_dr,on_dw,on_dsv,on_dsr,on_de;
 wire off_iv,off_ir,off_rv,off_rr,off_ie,off_dv,off_dr,off_dw,off_dsv,off_dsr,off_de;
 wire [31:0] on_ia,on_idata,on_da,on_dwd,on_drd,off_ia,off_idata,off_da,off_dwd,off_drd;
 wire [3:0] on_dst,off_dst; wire on_predict,on_hit,on_miss,off_predict,off_hit,off_miss;
 integer on_predicts=0,on_hits=0,on_misses=0,off_hits=0;

 pipeline_cpu #(.ENABLE_BRANCH_PREDICTOR(1)) on_core(
  .clk(clk),.reset(reset),.trace_valid(on_tv),.trace_pc(),.trace_instruction(),.trace_rd_we(),.trace_rd_addr(),.trace_rd_data(),.trace_mem_we(on_tmw),.trace_mem_addr(on_tmaddr),.trace_mem_data(on_tmdata),.trace_mem_wstrb(),.trace_error(),
  .i_req_valid(on_iv),.i_req_ready(on_ir),.i_req_addr(on_ia),.i_rsp_valid(on_rv),.i_rsp_ready(on_rr),.i_rsp_data(on_idata),.i_rsp_error(on_ie),
  .d_req_valid(on_dv),.d_req_ready(on_dr),.d_req_addr(on_da),.d_req_write(on_dw),.d_req_wdata(on_dwd),.d_req_wstrb(on_dst),.d_rsp_valid(on_dsv),.d_rsp_ready(on_dsr),.d_rsp_rdata(on_drd),.d_rsp_error(on_de),
  .event_stall(),.event_load_stall(),.event_branch(),.event_branch_taken(),.event_flush(),.event_predict(on_predict),.event_btb_hit(on_hit),.event_mispredict(on_miss),.event_illegal(),.event_misaligned(),.event_bus_error());
 pipeline_cpu #(.ENABLE_BRANCH_PREDICTOR(0)) off_core(
  .clk(clk),.reset(reset),.trace_valid(off_tv),.trace_pc(),.trace_instruction(),.trace_rd_we(),.trace_rd_addr(),.trace_rd_data(),.trace_mem_we(off_tmw),.trace_mem_addr(off_tmaddr),.trace_mem_data(off_tmdata),.trace_mem_wstrb(),.trace_error(),
  .i_req_valid(off_iv),.i_req_ready(off_ir),.i_req_addr(off_ia),.i_rsp_valid(off_rv),.i_rsp_ready(off_rr),.i_rsp_data(off_idata),.i_rsp_error(off_ie),
  .d_req_valid(off_dv),.d_req_ready(off_dr),.d_req_addr(off_da),.d_req_write(off_dw),.d_req_wdata(off_dwd),.d_req_wstrb(off_dst),.d_rsp_valid(off_dsv),.d_rsp_ready(off_dsr),.d_rsp_rdata(off_drd),.d_rsp_error(off_de),
  .event_stall(),.event_load_stall(),.event_branch(),.event_branch_taken(),.event_flush(),.event_predict(off_predict),.event_btb_hit(off_hit),.event_mispredict(off_miss),.event_illegal(),.event_misaligned(),.event_bus_error());
 imem_adapter #(.DEPTH(8),.INIT_FILE("tmp/branch_predictor/loop.mem"),.RANDOM_DELAY(0)) on_im(.clk(clk),.reset(reset),.req_valid(on_iv),.req_ready(on_ir),.req_addr(on_ia),.rsp_valid(on_rv),.rsp_ready(on_rr),.rsp_data(on_idata),.rsp_error(on_ie));
 imem_adapter #(.DEPTH(8),.INIT_FILE("tmp/branch_predictor/loop.mem"),.RANDOM_DELAY(0)) off_im(.clk(clk),.reset(reset),.req_valid(off_iv),.req_ready(off_ir),.req_addr(off_ia),.rsp_valid(off_rv),.rsp_ready(off_rr),.rsp_data(off_idata),.rsp_error(off_ie));
 ram_adapter #(.DEPTH(4),.RANDOM_DELAY(0)) on_dm(.clk(clk),.reset(reset),.req_valid(on_dv),.req_ready(on_dr),.req_addr(on_da),.req_write(on_dw),.req_wdata(on_dwd),.req_wstrb(on_dst),.rsp_valid(on_dsv),.rsp_ready(on_dsr),.rsp_rdata(on_drd),.rsp_error(on_de),.write_side_effect_count());
 ram_adapter #(.DEPTH(4),.RANDOM_DELAY(0)) off_dm(.clk(clk),.reset(reset),.req_valid(off_dv),.req_ready(off_dr),.req_addr(off_da),.req_write(off_dw),.req_wdata(off_dwd),.req_wstrb(off_dst),.rsp_valid(off_dsv),.rsp_ready(off_dsr),.rsp_rdata(off_drd),.rsp_error(off_de),.write_side_effect_count());
 always #5 clk=~clk;
 always @(posedge clk) if(!reset) begin
  cycles=cycles+1;
  if(on_predict)on_predicts=on_predicts+1;if(on_hit)on_hits=on_hits+1;if(on_miss)on_misses=on_misses+1;if(off_hit)off_hits=off_hits+1;
  if(!on_done&&on_tmw&&on_tmaddr==0)begin on_done=1;on_cycle=cycles;end
  if(!off_done&&off_tmw&&off_tmaddr==0)begin off_done=1;off_cycle=cycles;end
 end
 initial begin
  repeat(2)@(negedge clk);reset=0;
  wait(on_done&&off_done);#1;
  if(on_dm.mem[0]!==32||off_dm.mem[0]!==32)begin $display("TEST predictor architectural result FAIL on=%0d off=%0d",on_dm.mem[0],off_dm.mem[0]);failures=failures+1;end else $display("TEST predictor architectural result PASS");
  if(on_hits<20||on_misses!=2||off_hits!=0)begin $display("TEST predictor events FAIL hit=%0d miss=%0d off_hit=%0d",on_hits,on_misses,off_hits);failures=failures+1;end else $display("TEST predictor events PASS predict=%0d hit=%0d miss=%0d",on_predicts,on_hits,on_misses);
  if(on_cycle>=off_cycle)begin $display("TEST predictor cycle reduction FAIL on=%0d off=%0d",on_cycle,off_cycle);failures=failures+1;end else $display("TEST predictor cycle reduction PASS on=%0d off=%0d saved=%0d",on_cycle,off_cycle,off_cycle-on_cycle);
  if(failures==0)$display("ALL PIPELINE BRANCH PREDICTOR TEST PASS");else $fatal(1,"PIPELINE BRANCH PREDICTOR %0d FAIL",failures);$finish;
 end
 initial begin #20000;$fatal(1,"PIPELINE BRANCH PREDICTOR TIMEOUT");end
endmodule
