`timescale 1ns/1ps
// M 扩展（RV32IM）端到端验收：同一份镜像同时跑五级流水 CPU 与单周期
// Reference CPU，逐条比较提交 trace，再比较 x1~x31 与数据 RAM。
//
// 三条判据互相独立，缺一不可：
//   1. 结构一致：两个 CPU 的提交 trace 逐字段相同（PC/指令/写回/访存）；
//   2. 状态一致：x1~x31 与 RAM 相同（与参考模型一致）；
//   3. 数值正确：对 M 指令的结果做**手算常量**断言——只看 (1)(2) 是不够的，
//      两个 CPU 用的是同一个 rtl/mdu.v，一起错也会一起"一致"。
//      算术语义由 tb/tb_mdu.v 的 44 项手算用例独立把关，这里再钉一遍
//      经过完整流水线之后的落地值（含转发与除法停顿的影响）。
module tb_pipeline_m_ext;
`ifdef TB_ME_INIT_FILE
 parameter INIT_FILE=`TB_ME_INIT_FILE;
`else
 parameter INIT_FILE="tmp/mext/m_ext.mem";
`endif
// 程序在 0x9C 处进入自跳转（自跳转本身会一直退休，不计入比较）。
// 前 55 条是**动态**指令数：静态 39 条里含 5 次循环体，循环体 4 条 × 5 轮，
// 因此 39 + 4×4 = 55。写成静态条数会让两个 CPU 在"各自跑到第 N 条"的
// 不同时刻采样，得到假的不一致。
`ifdef TB_ME_TRACE_COUNT
 parameter TRACE_COUNT=`TB_ME_TRACE_COUNT;
`else
 parameter TRACE_COUNT=55;
`endif
`ifdef TB_ME_IMEM_DEPTH
 parameter IMEM_DEPTH=`TB_ME_IMEM_DEPTH;
`else
 parameter IMEM_DEPTH=64;
`endif
`ifdef TB_ME_RANDOM_DELAY
 parameter RANDOM_DELAY=`TB_ME_RANDOM_DELAY;
`else
 parameter RANDOM_DELAY=0;
`endif
// 乘法 EX 占用拍数（rtl/mdu.v 的 MUL_LAT）。默认 3 = 交付基线。
// 改这个只会改"乘法停几拍"，架构结果必须与单周期 Reference 逐条一致——
// 这正是本 TB 存在的意义：延迟变了，trace 不能变。
`ifdef TB_ME_MUL_LAT
 parameter MUL_LAT_CFG=`TB_ME_MUL_LAT;
`else
 parameter MUL_LAT_CFG=2;
`endif
 localparam TRACE_MAX=64;
 reg clk=0, reset=1; integer failures=0, i, ref_n=0, pipe_n=0;
 reg [31:0] ref_pc[0:TRACE_MAX-1],ref_inst[0:TRACE_MAX-1],ref_rddata[0:TRACE_MAX-1],ref_maddr[0:TRACE_MAX-1],ref_mdata[0:TRACE_MAX-1];
 reg ref_rwe[0:TRACE_MAX-1],ref_mwe[0:TRACE_MAX-1]; reg [4:0] ref_rd[0:TRACE_MAX-1]; reg [3:0] ref_mstrb[0:TRACE_MAX-1];
 reg [31:0] pipe_pc[0:TRACE_MAX-1],pipe_inst[0:TRACE_MAX-1],pipe_rddata[0:TRACE_MAX-1],pipe_maddr[0:TRACE_MAX-1],pipe_mdata[0:TRACE_MAX-1];
 reg pipe_rwe[0:TRACE_MAX-1],pipe_mwe[0:TRACE_MAX-1]; reg [4:0] pipe_rd[0:TRACE_MAX-1]; reg [3:0] pipe_mstrb[0:TRACE_MAX-1];
 wire rtv,rrwe,rmwe; wire [31:0] rtpc,rtinst,rtrddata,rtmaddr,rtmdata; wire [4:0] rtrd; wire [3:0] rtmstrb;
 core_harness #(.IMEM_DEPTH(IMEM_DEPTH),.DMEM_DEPTH(16),.IMEM_INIT_FILE(INIT_FILE)) ref_core(.clk(clk),.reset(reset),.trace_valid(rtv),.trace_pc(rtpc),.trace_instruction(rtinst),.trace_rd_we(rrwe),.trace_rd_addr(rtrd),.trace_rd_data(rtrddata),.trace_mem_we(rmwe),.trace_mem_addr(rtmaddr),.trace_mem_data(rtmdata),.trace_mem_wstrb(rtmstrb));
 wire ptv,prwe,pmwe,iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de,stall_event,flush_event;
 wire [31:0] ptpc,ptinst,ptrddata,pmaddr,pmdata,ia,idata,da,dwd,drd;
 wire [4:0] ptrd; wire [3:0] pmstrb,dst;
 integer stall_count=0, div_stall_cycles=0; reg ihold=0,dhold=0; reg [31:0] held_ia,held_da,held_dwd; reg held_dw; reg [3:0] held_dst;
 pipeline_cpu #(.MDU_MUL_LAT(MUL_LAT_CFG)) pipe(.clk(clk),.reset(reset),.trace_valid(ptv),.trace_pc(ptpc),.trace_instruction(ptinst),.trace_rd_we(prwe),.trace_rd_addr(ptrd),.trace_rd_data(ptrddata),.trace_mem_we(pmwe),.trace_mem_addr(pmaddr),.trace_mem_data(pmdata),.trace_mem_wstrb(pmstrb),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),.event_stall(stall_event),.event_load_stall(),.event_branch(),.event_branch_taken(),.event_flush(flush_event),.event_predict(),.event_btb_hit(),.event_mispredict(),.event_control_redirect(),.event_trap(),.event_trap_return(),.event_illegal(),.event_misaligned(),.event_bus_error());
 pipeline_imem_adapter #(.DEPTH(IMEM_DEPTH),.INIT_FILE(INIT_FILE),.RANDOM_DELAY(RANDOM_DELAY),.FILL_WORD(32'h0000_006f)) pim(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 ram_adapter #(.DEPTH(16),.RANDOM_DELAY(RANDOM_DELAY)) pram(.clk(clk),.reset(reset),.req_valid(dv),.req_ready(dr),.req_addr(da),.req_write(dw),.req_wdata(dwd),.req_wstrb(dst),.rsp_valid(dsv),.rsp_ready(dsr),.rsp_rdata(drd),.rsp_error(de),.write_side_effect_count());
 always #5 clk=~clk;

 // 除法停顿计数：每出现 M 扩展的除法指令（funct7=0000001 且 funct3=1xx），
 // 必须正好占用 EX **34 拍**：1 拍起拍（IDLE→RUN）+ 32 拍迭代 + 1 拍提交
 //（S_DONE 当拍 busy 落下、指令带着结果进入 EX/MEM，而这一拍它仍在 ID/EX）。
 // 这条断言把"除法停顿是有限的、确定的"钉死，防止将来改 mdu 时把流水线卡住。
 reg [31:0] prev_inst=32'b0; reg in_div=1'b0; integer div_insn_count=0; reg [31:0] cur_pc=32'b0;
 task expect_div_stall;
  begin
   if(div_stall_cycles!==34) begin
    $display("DIV STALL FAIL insn=%h cycles=%0d want=34", prev_inst, div_stall_cycles);
    failures=failures+1;
   end else $display("DIV STALL PASS pc=%h cycles=34", cur_pc);
  end
 endtask

 always @(posedge clk) if(!reset) begin
  if(rtv&&ref_n<TRACE_COUNT) begin ref_pc[ref_n]=rtpc;ref_inst[ref_n]=rtinst;ref_rwe[ref_n]=rrwe;ref_rd[ref_n]=rtrd;ref_rddata[ref_n]=rtrddata;ref_mwe[ref_n]=rmwe;ref_maddr[ref_n]=rtmaddr;ref_mdata[ref_n]=rtmdata;ref_mstrb[ref_n]=rtmstrb;ref_n=ref_n+1;end
  if(ptv&&pipe_n<TRACE_COUNT) begin pipe_pc[pipe_n]=ptpc;pipe_inst[pipe_n]=ptinst;pipe_rwe[pipe_n]=prwe;pipe_rd[pipe_n]=ptrd;pipe_rddata[pipe_n]=ptrddata;pipe_mwe[pipe_n]=pmwe;pipe_maddr[pipe_n]=pmaddr;pipe_mdata[pipe_n]=pmdata;pipe_mstrb[pipe_n]=pmstrb;pipe_n=pipe_n+1;end
  if(pipe_n<TRACE_COUNT) begin
    if(stall_event) stall_count=stall_count+1;
    // 停顿窗口以 ID/EX 上那条指令的译码结果为准（就是正在 EX 执行的那条）。
    // 背靠背的两条除法之间 "是除法" 这个条件不会落下，所以还要用 PC 区分
    // "换了新的一条"——只数电平变化会把 4 组连续除法当成 1 条。
    if(pipe.idex_valid && pipe.idex_mdu_en && pipe.idex_mdu_op[2]) begin
      if(!in_div || pipe.idex_pc!==cur_pc) begin
        if(in_div) begin expect_div_stall; div_insn_count=div_insn_count+1; end
        in_div=1'b1; cur_pc=pipe.idex_pc; div_stall_cycles=1; prev_inst=pipe.idex_inst;
      end else div_stall_cycles=div_stall_cycles+1;
    end else if(in_div) begin
      in_div=1'b0; div_insn_count=div_insn_count+1; expect_div_stall; div_stall_cycles=0;
    end
  end
  // 取指/访存请求字段稳定性（与既有 TB 同一判据，见 docs/interfaces.md §3）。
  if(ihold)begin
    if(!iv)begin ihold=0;end
    else if(ia!==held_ia)begin $display("I REQUEST STABILITY FAIL addr=%h held=%h",ia,held_ia);failures=failures+1;ihold=0;end
    else if(ir)ihold=0;
  end
  else if(iv&&!ir)begin ihold=1;held_ia=ia;end
  if(dhold)begin if(!dv||da!==held_da||dw!==held_dw||dwd!==held_dwd||dst!==held_dst)begin $display("D REQUEST STABILITY FAIL addr=%h held=%h",da,held_da);failures=failures+1;dhold=0;end else if(dr)dhold=0;end else if(dv&&!dr)begin dhold=1;held_da=da;held_dw=dw;held_dwd=dwd;held_dst=dst;end
 end

 // M 指令落地值的手算断言（在流水线 CPU 的寄存器堆上检查）。
 task expect_reg;
  input [4:0]  idx;
  input [31:0] want;
  input [8*24-1:0] name;
  begin
   if(pipe.rf.regs[idx]!==want) begin
    $display("M VALUE FAIL x%0d %0s got=%h want=%h", idx, name, pipe.rf.regs[idx], want);
    failures=failures+1;
   end else $display("M VALUE PASS x%0d %0s = %h", idx, name, want);
  end
 endtask

 initial begin repeat(2)@(negedge clk);reset=0;
  wait(ref_n==TRACE_COUNT); wait(pipe_n==TRACE_COUNT); repeat(16)@(posedge clk); #1;

  for(i=0;i<TRACE_COUNT;i=i+1) begin
   if(pipe_pc[i]!==ref_pc[i]||pipe_inst[i]!==ref_inst[i]||pipe_rwe[i]!==ref_rwe[i]||pipe_rd[i]!==ref_rd[i]||pipe_rddata[i]!==ref_rddata[i]||pipe_mwe[i]!==ref_mwe[i]||pipe_maddr[i]!==ref_maddr[i]||pipe_mdata[i]!==ref_mdata[i]||pipe_mstrb[i]!==ref_mstrb[i]) begin
    $display("TRACE %0d FAIL pipe pc=%h inst=%h rw=%b rd=%0d data=%h | ref pc=%h inst=%h rw=%b rd=%0d data=%h",i,pipe_pc[i],pipe_inst[i],pipe_rwe[i],pipe_rd[i],pipe_rddata[i],ref_pc[i],ref_inst[i],ref_rwe[i],ref_rd[i],ref_rddata[i]);
    failures=failures+1;
   end
  end
  if(failures==0) $display("TRACE 0..%0d ALL MATCH REFERENCE", TRACE_COUNT-1);

  for(i=1;i<32;i=i+1) if(pipe.rf.regs[i]!==ref_core.core.u_regfile.regs[i]) begin $display("STATE x%0d FAIL pipe=%h ref=%h",i,pipe.rf.regs[i],ref_core.core.u_regfile.regs[i]); failures=failures+1; end
  for(i=0;i<16;i=i+1) if(pram.mem[i]!==ref_core.ram.mem[i]) begin $display("STATE mem[%0d] FAIL pipe=%h ref=%h",i,pram.mem[i],ref_core.ram.mem[i]);failures=failures+1;end
  if(failures==0) $display("STATE x1..x31 AND RAM MATCH REFERENCE");

  // 手算常量（与 tb/programs/m_ext.S 的注释一一对应）
  expect_reg(5'd3,  32'h0000_0078, "mul 20*6");
  expect_reg(5'd4,  32'h0000_0000, "mulh 20*6");
  expect_reg(5'd5,  32'h0000_0000, "mulhsu 20*6");
  expect_reg(5'd6,  32'h0000_0000, "mulhu 20*6");
  expect_reg(5'd7,  32'h0000_0003, "div 20/6");
  expect_reg(5'd8,  32'h0000_0002, "rem 20%6");
  expect_reg(5'd9,  32'h0000_0003, "divu 20/6");
  expect_reg(5'd10, 32'h0000_0002, "remu 20%6");
  expect_reg(5'd12, 32'hFFFF_FF88, "mul -20*6");
  expect_reg(5'd13, 32'hFFFF_FFFF, "mulh -20*6");
  expect_reg(5'd14, 32'hFFFF_FFFD, "div -20/6");
  expect_reg(5'd15, 32'hFFFF_FFFE, "rem -20%6");
  expect_reg(5'd16, 32'h2AAA_AAA7, "divu 0xFFFFFFEC/6");
  expect_reg(5'd17, 32'h0000_0002, "remu 0xFFFFFFEC%6");
  expect_reg(5'd18, 32'hFFFF_FFFF, "div by zero");
  expect_reg(5'd19, 32'h0000_0014, "rem by zero");
  expect_reg(5'd22, 32'h8000_0000, "div overflow");
  expect_reg(5'd23, 32'h0000_0000, "rem overflow");
  expect_reg(5'd24, 32'h0000_02D0, "mul raw 120*6");
  expect_reg(5'd25, 32'h0000_02E4, "add raw 720+20");
  expect_reg(5'd26, 32'h0000_007B, "div raw 740/6");
  expect_reg(5'd27, 32'h0000_007B, "add raw after div");
  expect_reg(5'd28, 32'h0000_0064, "loop acc");
  expect_reg(5'd29, 32'h0000_0000, "loop counter");
  expect_reg(5'd30, 32'h0000_0258, "loop mul");
  expect_reg(5'd1,  32'h0000_0014, "x1");
  expect_reg(5'd2,  32'h0000_0006, "x2");
  expect_reg(5'd11, 32'hFFFF_FFEC, "x11");
  expect_reg(5'd20, 32'h8000_0000, "lui");
  expect_reg(5'd21, 32'hFFFF_FFFF, "addi -1");

  // 数据 RAM 的最终内容（Store 走的是 M 结果 -> EX/MEM -> 访存这条路）
  if(pram.mem[0]!==32'h0000_0078) begin $display("RAM[0] FAIL got=%h",pram.mem[0]);failures=failures+1;end
  if(pram.mem[1]!==32'h0000_0003) begin $display("RAM[1] FAIL got=%h",pram.mem[1]);failures=failures+1;end
  if(pram.mem[2]!==32'hFFFF_FFFD) begin $display("RAM[2] FAIL got=%h",pram.mem[2]);failures=failures+1;end
  if(pram.mem[3]!==32'h8000_0000) begin $display("RAM[3] FAIL got=%h",pram.mem[3]);failures=failures+1;end
  if(pram.mem[4]!==32'h0000_0064) begin $display("RAM[4] FAIL got=%h",pram.mem[4]);failures=failures+1;end
  if(pram.mem[5]!==32'h0000_0258) begin $display("RAM[5] FAIL got=%h",pram.mem[5]);failures=failures+1;end
  if(pram.mem[0]===32'h0000_0078&&pram.mem[5]===32'h0000_0258) $display("STORE RAM[0..5] PASS");

  if(div_insn_count!==13) begin $display("DIV INSN COUNT FAIL got=%0d want=13",div_insn_count);failures=failures+1;end
  else $display("DIV INSN COUNT PASS = 13");

  if(failures==0)$display("ALL M EXTENSION PIPELINE TEST PASS");else $fatal(1,"M EXTENSION PIPELINE TEST %0d FAIL",failures);
  $finish; end
 initial begin #2000000;$fatal(1,"M EXTENSION TIMEOUT");end
endmodule
