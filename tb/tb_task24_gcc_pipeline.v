`timescale 1ns/1ps
module tb_task24_gcc_pipeline;
 parameter RANDOM_DELAY=0;
`ifdef TASK24_C_SMOKE
`define TASK24_IMAGE "software/task14_c_smoke/build/task14_sum.mem"
 localparam [31:0] FINAL_ADDR=32'h00000200,FINAL_DATA=32'd45;
`elsif TASK24_ARRAY_CONTROL
`define TASK24_IMAGE "software/task14_array_control/build/task14_array_control_imem.mem"
 localparam [31:0] FINAL_ADDR=32'h00000208,FINAL_DATA=32'hffffffff;
`else
 initial $fatal(1,"Define TASK24_C_SMOKE or TASK24_ARRAY_CONTROL");
`endif
 reg clk=0,reset=1,done=0;integer cycles=0,retired=0,trace_file,state_file,perf_file,i;
 wire tv,rw,mw,iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de;wire [31:0] pc,inst,rddata,maddr,mdata,ia,idata,da,dwd,drd,writes;wire [4:0] rd;wire [3:0] wstrb,dst;wire ev_stall,ev_load,ev_branch,ev_taken,ev_flush;wire [63:0] perf_cycles,perf_instret,perf_stalls,perf_loads,perf_branches,perf_taken,perf_flushes;
 pipeline_cpu dut(.clk(clk),.reset(reset),.trace_valid(tv),.trace_pc(pc),.trace_instruction(inst),.trace_rd_we(rw),.trace_rd_addr(rd),.trace_rd_data(rddata),.trace_mem_we(mw),.trace_mem_addr(maddr),.trace_mem_data(mdata),.trace_mem_wstrb(wstrb),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(ev_stall),.event_load_stall(ev_load),.event_branch(ev_branch),.event_branch_taken(ev_taken),.event_flush(ev_flush));
 perf_monitor perf(.clk(clk),.reset(reset),.clear(1'b0),.enable(1'b1),.event_retire(tv),.event_stall(ev_stall),.event_load_stall(ev_load),.event_branch(ev_branch),.event_branch_taken(ev_taken),.event_flush(ev_flush),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken),.flush_count(perf_flushes));
 pipeline_imem_adapter #(.DEPTH(256),.INIT_FILE(`TASK24_IMAGE),.RANDOM_DELAY(RANDOM_DELAY)) imem(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 task15_ram_adapter #(.DEPTH(256),.INIT_FILE(""),.RANDOM_DELAY(RANDOM_DELAY)) ram(.clk(clk),.reset(reset),.req_valid(dv),.req_ready(dr),.req_addr(da),.req_write(dw),.req_wdata(dwd),.req_wstrb(dst),.rsp_valid(dsv),.rsp_ready(dsr),.rsp_rdata(drd),.rsp_error(de),.write_side_effect_count(writes));
 always #5 clk=~clk;
 always @(posedge clk)if(!reset&&!done)begin cycles=cycles+1;if(tv)begin $fdisplay(trace_file,"%0d %08h %08h %0d %0d %08h %0d %08h %08h %01h",retired,pc,inst,rw,rd,rddata,mw,maddr,mdata,wstrb);retired=retired+1;if(mw&&maddr==FINAL_ADDR&&mdata==FINAL_DATA)done=1;end end
 initial begin
  trace_file=$fopen("tmp/task24/trace.actual","w");state_file=$fopen("tmp/task24/state.actual","w");perf_file=$fopen("tmp/task24/perf.actual","w");
`ifdef TASK24_C_SMOKE
  #1;ram.mem[128]=32'hdeadbeef;
`else
  #1;$readmemh("software/task14_array_control/build/task14_array_control_dmem.mem",ram.mem);ram.mem[129]=32'hdeadbeef;ram.mem[130]=32'hcafebabe;
`endif
  repeat(2)@(negedge clk);reset=0;wait(done);@(negedge clk);#1;
  for(i=1;i<32;i=i+1)$fdisplay(state_file,"x%0d=%08h",i,dut.rf.regs[i]);
  $fdisplay(state_file,"ram[00000200]=%08h",ram.mem[128]);$fdisplay(state_file,"ram[00000204]=%08h",ram.mem[129]);$fdisplay(state_file,"ram[00000208]=%08h",ram.mem[130]);$fdisplay(state_file,"ram[000003fc]=%08h",ram.mem[255]);
  $fdisplay(perf_file,"cycles=%0d",cycles);$fdisplay(perf_file,"retired_instructions=%0d",retired);$fdisplay(perf_file,"cpi_x1000=%0d",(1000*cycles)/retired);$fdisplay(perf_file,"perf_cycle_count=%0d",perf_cycles);$fdisplay(perf_file,"perf_instret_count=%0d",perf_instret);$fdisplay(perf_file,"perf_stall_count=%0d",perf_stalls);$fdisplay(perf_file,"perf_load_stall_count=%0d",perf_loads);$fdisplay(perf_file,"perf_branch_count=%0d",perf_branches);$fdisplay(perf_file,"perf_branch_taken_count=%0d",perf_taken);$fdisplay(perf_file,"perf_flush_count=%0d",perf_flushes);
  $fclose(trace_file);$fclose(state_file);$fclose(perf_file);$display("TASK24 GCC PIPELINE RUN PASS cycles=%0d retired=%0d",cycles,retired);$finish;
 end
 initial begin #200000;$fatal(1,"TASK24 GCC PIPELINE TIMEOUT");end
endmodule
