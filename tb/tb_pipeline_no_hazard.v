`timescale 1ns/1ps
// Task 19 baseline: every RAW producer/consumer pair has three explicit
// NOPs.  This checks the five-stage transport before using any Hazard result.
module tb_pipeline_no_hazard;
 parameter RANDOM_DELAY=0;
 parameter TRACE_COUNT=17;
 parameter IMEM_DEPTH=17;
 parameter INIT_FILE="tb/data/no_hazard.mem";
 parameter EXPECT_LOAD_STALL=-1;
 parameter EXPECT_FLUSH=-1;
 parameter EXPECT_STORES=-1;
 reg clk=0, reset=1; integer failures=0, i, ref_n=0, pipe_n=0;
 reg [31:0] ref_pc[0:31],ref_inst[0:31],ref_rddata[0:31],ref_maddr[0:31],ref_mdata[0:31]; reg ref_rwe[0:31],ref_mwe[0:31]; reg [4:0] ref_rd[0:31]; reg [3:0] ref_mstrb[0:31];
 reg [31:0] pipe_pc[0:31],pipe_inst[0:31],pipe_rddata[0:31],pipe_maddr[0:31],pipe_mdata[0:31]; reg pipe_rwe[0:31],pipe_mwe[0:31]; reg [4:0] pipe_rd[0:31]; reg [3:0] pipe_mstrb[0:31];
 wire rtv,rrwe,rmwe; wire [31:0] rtpc,rtinst,rtrddata,rtmaddr,rtmdata; wire [4:0] rtrd; wire [3:0] rtmstrb;
 core_harness #(.IMEM_DEPTH(IMEM_DEPTH),.DMEM_DEPTH(16),.IMEM_INIT_FILE(INIT_FILE)) ref_core(.clk(clk),.reset(reset),.trace_valid(rtv),.trace_pc(rtpc),.trace_instruction(rtinst),.trace_rd_we(rrwe),.trace_rd_addr(rtrd),.trace_rd_data(rtrddata),.trace_mem_we(rmwe),.trace_mem_addr(rtmaddr),.trace_mem_data(rtmdata),.trace_mem_wstrb(rtmstrb));
 wire ptv,prwe,pmwe,iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de,load_stall_event,flush_event; wire [31:0] ptpc,ptinst,ptrddata,pmaddr,pmdata,ia,idata,da,dwd,drd,pwrite_count; wire [4:0] ptrd; wire [3:0] pmstrb,dst; integer load_stall_count=0,flush_count=0,store_trace_count=0; reg ihold=0,dhold=0; reg [31:0] held_ia,held_da,held_dwd; reg held_dw; reg [3:0] held_dst;
 pipeline_cpu pipe(.clk(clk),.reset(reset),.trace_valid(ptv),.trace_pc(ptpc),.trace_instruction(ptinst),.trace_rd_we(prwe),.trace_rd_addr(ptrd),.trace_rd_data(ptrddata),.trace_mem_we(pmwe),.trace_mem_addr(pmaddr),.trace_mem_data(pmdata),.trace_mem_wstrb(pmstrb),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(),.event_load_stall(load_stall_event),.event_branch(),.event_branch_taken(),.event_flush(flush_event));
 pipeline_imem_adapter #(.DEPTH(IMEM_DEPTH),.INIT_FILE(INIT_FILE),.RANDOM_DELAY(RANDOM_DELAY)) pim(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 ram_adapter #(.DEPTH(16),.RANDOM_DELAY(RANDOM_DELAY)) pram(.clk(clk),.reset(reset),.req_valid(dv),.req_ready(dr),.req_addr(da),.req_write(dw),.req_wdata(dwd),.req_wstrb(dst),.rsp_valid(dsv),.rsp_ready(dsr),.rsp_rdata(drd),.rsp_error(de),.write_side_effect_count(pwrite_count));
 always #5 clk=~clk;
 always @(posedge clk) if(!reset) begin
  if(rtv&&ref_n<TRACE_COUNT) begin ref_pc[ref_n]=rtpc;ref_inst[ref_n]=rtinst;ref_rwe[ref_n]=rrwe;ref_rd[ref_n]=rtrd;ref_rddata[ref_n]=rtrddata;ref_mwe[ref_n]=rmwe;ref_maddr[ref_n]=rtmaddr;ref_mdata[ref_n]=rtmdata;ref_mstrb[ref_n]=rtmstrb;ref_n=ref_n+1;end
  if(ptv&&pipe_n<TRACE_COUNT) begin pipe_pc[pipe_n]=ptpc;pipe_inst[pipe_n]=ptinst;pipe_rwe[pipe_n]=prwe;pipe_rd[pipe_n]=ptrd;pipe_rddata[pipe_n]=ptrddata;pipe_mwe[pipe_n]=pmwe;pipe_maddr[pipe_n]=pmaddr;pipe_mdata[pipe_n]=pmdata;pipe_mstrb[pipe_n]=pmstrb;pipe_n=pipe_n+1;end
  if(load_stall_event) load_stall_count=load_stall_count+1;
  if(flush_event) flush_count=flush_count+1;
  if(ptv&&pmwe) store_trace_count=store_trace_count+1;
  // valid 等待 ready 时字段必须逐拍稳定；失败直接报告首个接口错误。
  if(ihold)begin if(!iv||ia!==held_ia)begin $display("I REQUEST STABILITY FAIL addr=%h held=%h",ia,held_ia);failures=failures+1;ihold=0;end else if(ir)ihold=0;end else if(iv&&!ir)begin ihold=1;held_ia=ia;end
  if(dhold)begin if(!dv||da!==held_da||dw!==held_dw||dwd!==held_dwd||dst!==held_dst)begin $display("D REQUEST STABILITY FAIL addr=%h held=%h",da,held_da);failures=failures+1;dhold=0;end else if(dr)dhold=0;end else if(dv&&!dr)begin dhold=1;held_da=da;held_dw=dw;held_dwd=dwd;held_dst=dst;end
 end
 task check_trace; input integer n; begin
  if(ptpc!==ref_pc[n]||ptinst!==ref_inst[n]||prwe!==ref_rwe[n]||ptrd!==ref_rd[n]||ptrddata!==ref_rddata[n]||pmwe!==ref_mwe[n]||pmaddr!==ref_maddr[n]||pmdata!==ref_mdata[n]||pmstrb!==ref_mstrb[n]) begin $display("TRACE %0d FAIL pipe pc=%h inst=%h ref pc=%h inst=%h",n,ptpc,ptinst,ref_pc[n],ref_inst[n]); failures=failures+1; end else $display("TRACE %0d PASS",n); end endtask
 initial begin repeat(2)@(negedge clk);reset=0; wait(ref_n==TRACE_COUNT); wait(pipe_n==TRACE_COUNT); #1;
  for(i=0;i<TRACE_COUNT;i=i+1) begin if(pipe_pc[i]!==ref_pc[i]||pipe_inst[i]!==ref_inst[i]||pipe_rwe[i]!==ref_rwe[i]||pipe_rd[i]!==ref_rd[i]||pipe_rddata[i]!==ref_rddata[i]||pipe_mwe[i]!==ref_mwe[i]||pipe_maddr[i]!==ref_maddr[i]||pipe_mdata[i]!==ref_mdata[i]||pipe_mstrb[i]!==ref_mstrb[i]) begin $display("TRACE %0d FAIL pipe pc=%h inst=%h ref pc=%h inst=%h",i,pipe_pc[i],pipe_inst[i],ref_pc[i],ref_inst[i]);failures=failures+1;end else $display("TRACE %0d PASS",i);end
  for(i=1;i<32;i=i+1) if(pipe.rf.regs[i]!==ref_core.core.u_regfile.regs[i]) begin $display("STATE x%0d FAIL pipe=%h ref=%h",i,pipe.rf.regs[i],ref_core.core.u_regfile.regs[i]); failures=failures+1; end
  for(i=0;i<16;i=i+1) if(pram.mem[i]!==ref_core.ram.mem[i]) begin $display("STATE mem[%0d] FAIL pipe=%h ref=%h",i,pram.mem[i],ref_core.ram.mem[i]);failures=failures+1;end
  if(EXPECT_LOAD_STALL>=0 && load_stall_count!==EXPECT_LOAD_STALL) begin $display("LOAD STALL COUNT FAIL got=%0d want=%0d",load_stall_count,EXPECT_LOAD_STALL);failures=failures+1;end
  if(EXPECT_FLUSH>=0 && flush_count!==EXPECT_FLUSH) begin $display("FLUSH COUNT FAIL got=%0d want=%0d",flush_count,EXPECT_FLUSH);failures=failures+1;end
  if(EXPECT_STORES>=0 && (store_trace_count!==EXPECT_STORES || pwrite_count!==EXPECT_STORES)) begin $display("STORE COUNT FAIL trace=%0d side_effect=%0d want=%0d",store_trace_count,pwrite_count,EXPECT_STORES);failures=failures+1;end
  if(failures==0)$display("ALL PIPELINE REFERENCE COMPARISON PASS");else $fatal(1,"PIPELINE REFERENCE COMPARISON %0d FAIL",failures); $finish; end
 initial begin #10000;$fatal(1,"PIPELINE TIMEOUT");end
endmodule
