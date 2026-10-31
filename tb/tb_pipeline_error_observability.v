`timescale 1ns/1ps
// 错误可观测性 + 精确 Trap 的联合验收。
//
// 本 Testbench 的用途有两层：
//  1. 错误事件（event_illegal / event_misaligned / event_bus_error）必须仍然可被
//     Core 外部观测到，且出错指令不产生任何架构副作用（不写寄存器、不发数据事务）；
//  2. 这些错误必须按 docs/trap_contract.md 精确陷入：mcause/mepc 正确，
//     出错指令自己不形成提交记录（trace），handler 之后的程序能继续跑完。
//
// 程序布局（tb/data/pipeline_error_observability.mem，12 字，0x00～0x2C）：
//   0x00 addi x1, x0, 0x20   建立 mtvec
//   0x04 csrrw x0, mtvec, x1
//   0x08 addi x1, x0, 1      x1 = 1，制造未对齐基址
//   0x0C ffffffff            错误①：非法指令（mcause=2）
//   0x10 lw x2, 0(x1)        错误②：未对齐 Load（mcause=4），地址 = 1
//   0x14 lw x3, 16(x0)       错误③：访问错误（mcause=5），DMEM 只有 4 字
//   0x18 addi x4, x0, 4      哨兵：三条错误指令都被跳过才会执行到这里
//   0x1C jal x0, 0           halt
//   0x20 csrrs x5, mepc, x0  handler：读 mepc
//   0x24 addi x5, x5, 4
//   0x28 csrrw x0, mepc, x5  写回 mepc+4（跳过出错指令）
//   0x2C mret
//
// 为什么必须自带 handler：Trap 之后 mepc 指向出错指令本身，而 mtvec 默认是 0，
// 不推进 mepc 就会反复执行同一条出错指令（实测表现为仿真超时）。
module tb_pipeline_error_observability;
 reg clk=0,reset=1; integer failures=0,cycles=0,illegal_count=0,misaligned_count=0,bus_error_count=0,trap_count=0,data_requests=0,bad_register_writes=0,fault_commits=0;
 wire tv,trace_error,trace_rd_we,iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de,event_illegal,event_misaligned,event_bus_error;wire [4:0] trace_rd_addr;wire [31:0] trace_pc;
 wire [31:0] ia,idata,da,dwd,drd; wire [3:0] dst;
 pipeline_cpu dut(.clk(clk),.reset(reset),.trace_valid(tv),.trace_pc(trace_pc),.trace_instruction(),.trace_rd_we(trace_rd_we),.trace_rd_addr(trace_rd_addr),.trace_rd_data(),.trace_mem_we(),.trace_mem_addr(),.trace_mem_data(),.trace_mem_wstrb(),.trace_error(trace_error),
  .i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),
  .d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),
  .irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),
  .event_stall(),.event_load_stall(),.event_branch(),.event_branch_taken(),.event_flush(),.event_predict(),.event_btb_hit(),.event_mispredict(),.event_control_redirect(),.event_trap(),.event_trap_return(),.event_illegal(event_illegal),.event_misaligned(event_misaligned),.event_bus_error(event_bus_error));
 imem_adapter #(.DEPTH(12),.INIT_FILE("tb/data/pipeline_error_observability.mem"),.RANDOM_DELAY(0)) im(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 ram_adapter #(.DEPTH(4),.RANDOM_DELAY(0)) dm(.clk(clk),.reset(reset),.req_valid(dv),.req_ready(dr),.req_addr(da),.req_write(dw),.req_wdata(dwd),.req_wstrb(dst),.rsp_valid(dsv),.rsp_ready(dsr),.rsp_rdata(drd),.rsp_error(de),.write_side_effect_count());
 always #5 clk=~clk;
 always @(posedge clk) if(!reset)begin
  cycles=cycles+1;
  if(event_illegal)illegal_count=illegal_count+1;
  if(event_misaligned)misaligned_count=misaligned_count+1;
  if(event_bus_error)bus_error_count=bus_error_count+1;
  if(dut.trap_take)trap_count=trap_count+1;
  if(dv&&dr)data_requests=data_requests+1;
  if(trace_rd_we&&(trace_rd_addr==2||trace_rd_addr==3))bad_register_writes=bad_register_writes+1;
  // 三条出错指令的 PC 上都不允许出现提交记录（§5.1 第 3 条）。
  if(tv&&(trace_pc==32'h0c||trace_pc==32'h10||trace_pc==32'h14))fault_commits=fault_commits+1;
 end
 initial begin
  repeat(2)@(negedge clk);reset=0;wait(dut.rf.regs[4]==4);repeat(6)@(posedge clk);#1;
  if(illegal_count!=1)begin $display("TEST illegal event FAIL count=%0d",illegal_count);failures=failures+1;end else $display("TEST illegal event PASS");
  if(misaligned_count!=1)begin $display("TEST misaligned event FAIL count=%0d",misaligned_count);failures=failures+1;end else $display("TEST misaligned event PASS");
  if(bus_error_count<1)begin $display("TEST bus error event FAIL count=%0d",bus_error_count);failures=failures+1;end else $display("TEST bus error event PASS count=%0d",bus_error_count);
  if(trap_count!=3)begin $display("TEST trap count FAIL count=%0d",trap_count);failures=failures+1;end else $display("TEST trap count PASS count=%0d",trap_count);
  if(fault_commits!=0)begin $display("TEST fault commit suppression FAIL count=%0d",fault_commits);failures=failures+1;end else $display("TEST fault commit suppression PASS");
  if(dut.csr.mcause_q!=32'd5)begin $display("TEST last mcause FAIL value=%0d",dut.csr.mcause_q);failures=failures+1;end else $display("TEST last mcause PASS (load access fault)");
  if(dut.csr.mepc_q!=32'h18)begin $display("TEST mepc FAIL value=%h",dut.csr.mepc_q);failures=failures+1;end else $display("TEST mepc PASS (handler advanced to 0x18)");
  if(data_requests!=1)begin $display("TEST misaligned request suppression FAIL requests=%0d",data_requests);failures=failures+1;end else $display("TEST misaligned request suppression PASS");
  if(bad_register_writes!=0)begin $display("TEST error write suppression FAIL writes=%0d",bad_register_writes);failures=failures+1;end else $display("TEST error write suppression PASS");
  if(failures==0)$display("ALL PIPELINE ERROR OBSERVABILITY TEST PASS");else $fatal(1,"PIPELINE ERROR OBSERVABILITY %0d FAIL",failures);$finish;
 end
 initial begin #5000;$fatal(1,"PIPELINE ERROR OBSERVABILITY TIMEOUT");end
endmodule
