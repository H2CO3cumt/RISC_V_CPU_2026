// RV32I five-stage in-order core.  Storage, address decode and peripherals are
// deliberately outside this module; only the generic transaction ports cross
// the Core/SoC boundary.
module pipeline_cpu #(
 parameter ENABLE_BRANCH_PREDICTOR = 1
)(
 input wire clk,input wire reset,
 output wire trace_valid,output wire [31:0] trace_pc,output wire [31:0] trace_instruction,
 output wire trace_rd_we,output wire [4:0] trace_rd_addr,output wire [31:0] trace_rd_data,
 output wire trace_mem_we,output wire [31:0] trace_mem_addr,output wire [31:0] trace_mem_data,output wire [3:0] trace_mem_wstrb,output wire trace_error,
 output wire i_req_valid,input wire i_req_ready,output wire [31:0] i_req_addr,input wire i_rsp_valid,output wire i_rsp_ready,input wire [31:0] i_rsp_data,input wire i_rsp_error,
 output wire d_req_valid,input wire d_req_ready,output wire [31:0] d_req_addr,output wire d_req_write,output wire [31:0] d_req_wdata,output wire [3:0] d_req_wstrb,input wire d_rsp_valid,output wire d_rsp_ready,input wire [31:0] d_rsp_rdata,input wire d_rsp_error,
 output wire event_stall,output wire event_load_stall,output wire event_branch,output wire event_branch_taken,output wire event_flush,
 output wire event_predict,output wire event_btb_hit,output wire event_mispredict,
 output wire event_illegal,output wire event_misaligned,output wire event_bus_error);

 reg [31:0] fetch_pc,fetch_req_pc,if_req_addr_reg; reg if_req,if_arm,if_rsp,if_discard,if_req_discard;
 reg if_req_pred_hit,if_req_pred_taken,fetch_req_pred_hit,fetch_req_pred_taken;
 reg [31:0] if_req_pred_target,fetch_req_pred_target;
 reg ifid_valid,ifid_pred_hit,ifid_pred_taken,ifid_error; reg [31:0] ifid_pc,ifid_inst,ifid_pred_target;
 reg idex_valid,idex_pred_hit,idex_pred_taken,idex_error; reg [31:0] idex_pc,idex_inst,idex_a,idex_b,idex_imm,idex_pred_target; reg [4:0] idex_rs1,idex_rs2,idex_rd; reg [2:0] idex_f3;
 reg idex_regwrite,idex_memread,idex_memwrite,idex_branch,idex_jump,idex_jalr,idex_asa,idex_asb; reg [3:0] idex_alu; reg [1:0] idex_result;
 reg exmem_valid,exmem_error; reg [31:0] exmem_pc,exmem_inst,exmem_alu,exmem_store,exmem_imm; reg [4:0] exmem_rd; reg [2:0] exmem_f3; reg exmem_regwrite,exmem_memread,exmem_memwrite; reg [1:0] exmem_result;
 reg [1:0] dstate; localparam D_IDLE=2'd0,D_REQ=2'd1,D_RSP=2'd2;
 reg memwb_valid,memwb_regwrite,memwb_memwrite,memwb_error; reg [31:0] memwb_pc,memwb_inst,memwb_alu,memwb_mem,memwb_imm,memwb_sdata; reg [3:0] memwb_wstrb; reg [4:0] memwb_rd; reg [1:0] memwb_result;

 wire [31:0] dec_imm,rf_a,rf_b; wire dec_rw,dec_asa,dec_asb,dec_mr,dec_mw,dec_br,dec_jmp,dec_jalr,dec_illegal; wire [3:0] dec_alu; wire [1:0] dec_result;
 decoder dec(.instruction(ifid_inst),.reg_write(dec_rw),.alu_src_a(dec_asa),.alu_src_b(dec_asb),.alu_ctrl(dec_alu),.mem_read(dec_mr),.mem_write(dec_mw),.result_src(dec_result),.branch(dec_br),.jump(dec_jmp),.jalr(dec_jalr),.illegal(dec_illegal));
 imm_gen ig(.instruction(ifid_inst),.imm(dec_imm));
 wire [4:0] dec_rs1=ifid_inst[19:15],dec_rs2=ifid_inst[24:20],dec_rd=ifid_inst[11:7]; wire [2:0] dec_f3=ifid_inst[14:12];
 wire [31:0] wb_value=(memwb_result==2'd0)?memwb_alu:(memwb_result==2'd1)?memwb_mem:(memwb_result==2'd2)?memwb_pc+32'd4:memwb_imm;
 wire wb_fire=memwb_valid;
 regfile rf(.clk(clk),.rd_we(wb_fire&&memwb_regwrite&&!memwb_error),.rd_addr(memwb_rd),.rd_data(wb_value),.rs1_addr(dec_rs1),.rs2_addr(dec_rs2),.rs1_data(rf_a),.rs2_data(rf_b));
 // The register file writes on this edge while ID captures operands on the
 // same edge.  Explicit bypass makes that architectural WB->ID ordering
 // independent of simulator scheduling and FPGA RAM implementation details.
 wire [31:0] id_a=(wb_fire&&memwb_regwrite&&!memwb_error&&memwb_rd!=0&&memwb_rd==dec_rs1)?wb_value:rf_a;
 wire [31:0] id_b=(wb_fire&&memwb_regwrite&&!memwb_error&&memwb_rd!=0&&memwb_rd==dec_rs2)?wb_value:rf_b;

 wire [31:0] exmem_forward=(exmem_result==2'd0)?exmem_alu:(exmem_result==2'd2)?exmem_pc+32'd4:exmem_imm;
 wire [1:0] forward_a,forward_b;
 forward_unit fu(.idex_rs1(idex_rs1),.idex_rs2(idex_rs2),.exmem_valid(exmem_valid),.exmem_regwrite(exmem_regwrite),.exmem_memread(exmem_memread),.exmem_rd(exmem_rd),.memwb_valid(memwb_valid),.memwb_regwrite(memwb_regwrite),.memwb_error(memwb_error),.memwb_rd(memwb_rd),.forward_a(forward_a),.forward_b(forward_b));
 wire [31:0] srca0=(forward_a==2'b10)?exmem_forward:(forward_a==2'b01)?wb_value:idex_a;
 wire [31:0] srcb0=(forward_b==2'b10)?exmem_forward:(forward_b==2'b01)?wb_value:idex_b;
 wire [31:0] ex_a; wire [31:0] ex_b; wire [31:0] ex_result;
 assign ex_a=idex_asa?idex_pc:srca0; assign ex_b=idex_asb?idex_imm:srcb0;
 alu exalu(.a(ex_a),.b(ex_b),.alu_ctrl(idex_alu),.result(ex_result));
 wire branch_taken; branch_unit bu(.a(srca0),.b(srcb0),.funct3(idex_f3),.taken(branch_taken));
 wire [31:0] ex_target=idex_jalr?(ex_result&32'hfffffffe):ex_result;
 wire load_use;
 hazard_unit hu(.idex_valid(idex_valid),.idex_memread(idex_memread),.idex_rd(idex_rd),.ifid_valid(ifid_valid),.ifid_instruction(ifid_inst),.load_use_stall(load_use));

 wire exmem_access=exmem_memread||exmem_memwrite;
 wire [31:0] ls_load; wire [31:0] ls_store; wire [3:0] ls_wstrb; wire ls_misaligned;
 load_store_unit lsu(.addr_low(exmem_alu[1:0]),.funct3(exmem_f3),.mem_rdata(d_rsp_rdata),.store_data(exmem_store),.is_load(exmem_memread),.is_store(exmem_memwrite),.load_data(ls_load),.store_wdata(ls_store),.store_wstrb(ls_wstrb),.misaligned(ls_misaligned));
 wire mem_done=exmem_valid&&(!exmem_access||ls_misaligned||(dstate==D_RSP&&d_rsp_valid&&d_rsp_ready));
 wire mem_block=exmem_valid&&!mem_done;
 wire branch_resolve=idex_valid&&idex_branch&&!mem_block;
 wire branch_mispredict=branch_resolve&&
                        ((idex_pred_taken!=branch_taken)||
                         (branch_taken&&(idex_pred_target!=ex_target)));
 wire ex_redirect=(idex_valid&&!mem_block)&&
                  (idex_jump||branch_mispredict);
 wire [31:0] redirect_pc=idex_jump?ex_target:
                         (branch_taken?ex_target:(idex_pc+32'd4));
 wire predictor_hit;
 wire predictor_taken;
 wire [31:0] predictor_target;
 branch_predictor predictor(
  .clk(clk),.reset(reset),.enable(ENABLE_BRANCH_PREDICTOR!=0),
  .query_pc(fetch_pc),.query_hit(predictor_hit),.predicted_taken(predictor_taken),.predicted_target(predictor_target),
  .update_valid(branch_resolve),.update_pc(idex_pc),.update_taken(branch_taken),.update_target(ex_target));
 // 取指请求的展示形式有两种，二者在对外语义上完全等价（都是一个单 outstanding 的取指事务）：
 //  - if_req：请求已冻结在 if_req_addr_reg 中，等待下游 ready；
 //  - if_arm：刚刚接受完上一笔请求，本拍直接用已经寄存的 fetch_pc 展示下一笔请求。
 // if_arm 的存在是为了消除“接受后一拍没有请求在场”的空洞：旧请求的响应在 T 拍被接收时，
 // 新请求已经在本拍展示，因此可以在同一拍完成“旧响应接收 + 新请求接受”的交接，
 // 达到 docs/interfaces.md §3 要求的每拍一条连续取指。展示地址直接来自 fetch_pc 寄存器，
 // 不引入额外的地址寄存级，因此不改变“valid 且 !ready 时地址保持稳定”的契约。
 wire if_present=if_req||if_arm;
 wire [31:0] if_present_addr=if_req?if_req_addr_reg:fetch_pc;
 wire if_present_pred_hit=if_req?if_req_pred_hit:predictor_hit;
 wire if_present_pred_taken=if_req?if_req_pred_taken:predictor_taken;
 wire [31:0] if_present_pred_target=if_req?if_req_pred_target:predictor_target;
 // A held EX/MEM entry owns the external request.  Once accepted, valid drops
 // while the entry remains until the one matching response is consumed.
 assign d_req_valid=exmem_valid&&exmem_access&&!ls_misaligned&&(dstate==D_REQ);
 assign d_req_addr=exmem_alu; assign d_req_write=exmem_memwrite;
 assign d_req_wdata=ls_store; assign d_req_wstrb=ls_wstrb; assign d_rsp_ready=exmem_valid&&exmem_access&&!ls_misaligned&&(dstate==D_RSP);

 // IF 允许“旧响应完成 + 新请求接受”在同一拍交接，因此零等待存储器可持续
 // 每拍取一条，同时任意时刻仍只有一笔未完成事务。IF/ID 当拍被 ID 消费时
 // 也可由新响应替换，避免人为插入空泡。
 wire id_advance=!mem_block&&!load_use&&!ex_redirect;
 wire ifid_available=!ifid_valid||id_advance||ex_redirect;
 assign i_rsp_ready=if_rsp&&!mem_block&&(if_discard||ex_redirect||ifid_available);
 wire if_accept=i_rsp_valid&&i_rsp_ready;
 // if_req/if_arm 一旦对外可见，即使随后发生 Stall/Redirect 也不能撤回；Redirect
 // 只把该请求标成错误路径，待其正常握手并返回后丢弃。因此只有在下游明确
 // 未接收（!if_accept 且无 if_rsp 未完成响应）时才允许展示新请求。
 assign i_req_valid=if_present&&(!if_rsp||if_accept);
 assign i_req_addr=if_present_addr;
 wire if_request_accept=i_req_valid&&i_req_ready;
 wire front_hold=mem_block||load_use;
 assign event_stall=front_hold; assign event_load_stall=load_use&&!mem_block; assign event_branch=branch_resolve; assign event_branch_taken=branch_resolve&&branch_taken; assign event_flush=ex_redirect;
 assign event_predict=branch_resolve; assign event_btb_hit=branch_resolve&&idex_pred_hit; assign event_mispredict=branch_mispredict;
 assign event_illegal=id_advance&&ifid_valid&&!ifid_error&&dec_illegal;
 assign event_misaligned=mem_done&&exmem_access&&ls_misaligned;
 assign event_bus_error=(if_accept&&i_rsp_error)||(mem_done&&exmem_access&&!ls_misaligned&&d_rsp_error);

 always @(posedge clk) begin
  if(reset) begin fetch_pc<=0;fetch_req_pc<=0;if_req_addr_reg<=0;if_req<=0;if_arm<=0;if_rsp<=0;if_discard<=0;if_req_discard<=0;if_req_pred_hit<=0;if_req_pred_taken<=0;if_req_pred_target<=0;fetch_req_pred_hit<=0;fetch_req_pred_taken<=0;fetch_req_pred_target<=0;ifid_valid<=0;ifid_pred_hit<=0;ifid_pred_taken<=0;ifid_pred_target<=0;ifid_error<=0;idex_valid<=0;idex_pred_hit<=0;idex_pred_taken<=0;idex_pred_target<=0;idex_error<=0;exmem_valid<=0;exmem_error<=0;dstate<=D_IDLE;memwb_valid<=0; end else begin
   // WB is single-cycle: a retired valid record must not be replayed.
   memwb_valid<=0;
   if(mem_done) begin memwb_valid<=exmem_valid; memwb_pc<=exmem_pc;memwb_inst<=exmem_inst;memwb_alu<=exmem_alu;memwb_imm<=exmem_imm;memwb_rd<=exmem_rd;memwb_result<=exmem_result;memwb_regwrite<=exmem_regwrite;memwb_memwrite<=exmem_memwrite;memwb_sdata<=ls_store;memwb_wstrb<=ls_wstrb;memwb_mem<=ls_load;memwb_error<=exmem_error||(exmem_access&&(ls_misaligned||d_rsp_error)); end
   // EX/MEM 因访存响应而停住时，ID/EX 也必须保持。若这期间生产者在
   // WB 退休，只靠瞬时 Forwarding 会在解除暂停后丢失该值；因此把 WB
   // 结果吸收到被保持的操作数中，保证 Store/Branch/JALR 等都不会回退
   // 到进入 ID/EX 时读到的旧 RegFile 值。
   if(mem_block&&idex_valid&&wb_fire&&memwb_regwrite&&!memwb_error&&memwb_rd!=0) begin
    if(memwb_rd==idex_rs1) idex_a<=wb_value;
    if(memwb_rd==idex_rs2) idex_b<=wb_value;
   end
   if(exmem_valid&&exmem_access) begin if(dstate==D_REQ&&d_req_ready)dstate<=D_RSP; if(dstate==D_RSP&&d_rsp_valid&&d_rsp_ready)dstate<=D_IDLE; end
   if(!mem_block) begin
    if(mem_done||!exmem_valid) begin exmem_valid<=idex_valid;exmem_error<=idex_error;exmem_pc<=idex_pc;exmem_inst<=idex_inst;exmem_alu<=ex_result;exmem_store<=srcb0;exmem_imm<=idex_imm;exmem_rd<=idex_rd;exmem_f3<=idex_f3;exmem_regwrite<=idex_regwrite;exmem_memread<=idex_memread;exmem_memwrite<=idex_memwrite;exmem_result<=idex_result;if(idex_valid&&(idex_memread||idex_memwrite))dstate<=D_REQ; end
    if(ex_redirect) begin idex_valid<=0;ifid_valid<=0;fetch_pc<=redirect_pc;if(if_rsp&&!if_accept)if_discard<=1;if(if_arm&&!if_request_accept)begin if_req<=1;if_req_addr_reg<=fetch_pc;if_req_pred_hit<=predictor_hit;if_req_pred_taken<=predictor_taken;if_req_pred_target<=predictor_target;end if(if_arm)if_arm<=0;if(if_req||if_arm)if_req_discard<=1; end else if(load_use) begin idex_valid<=0; end else begin idex_valid<=ifid_valid; idex_error<=ifid_error||dec_illegal;idex_pc<=ifid_pc;idex_inst<=ifid_inst;idex_a<=id_a;idex_b<=id_b;idex_imm<=dec_imm;idex_rs1<=dec_rs1;idex_rs2<=dec_rs2;idex_rd<=dec_rd;idex_f3<=dec_f3;idex_pred_hit<=ifid_pred_hit;idex_pred_taken<=ifid_pred_taken;idex_pred_target<=ifid_pred_target;idex_regwrite<=dec_rw&&!dec_illegal;idex_memread<=dec_mr&&!dec_illegal;idex_memwrite<=dec_mw&&!dec_illegal;idex_branch<=dec_br&&!dec_illegal;idex_jump<=dec_jmp&&!dec_illegal;idex_jalr<=dec_jalr&&!dec_illegal;idex_asa<=dec_asa;idex_asb<=dec_asb;idex_alu<=dec_alu;idex_result<=dec_result;ifid_valid<=0; end
   end
   if(if_accept) begin if_rsp<=0;if(if_discard||ex_redirect)if_discard<=0;else begin ifid_valid<=1;ifid_error<=i_rsp_error;ifid_pc<=fetch_req_pc;ifid_inst<=i_rsp_error?0:i_rsp_data;ifid_pred_hit<=fetch_req_pred_hit;ifid_pred_taken<=fetch_req_pred_taken;ifid_pred_target<=fetch_req_pred_target;end end
   if(if_request_accept) begin
    if_req<=0;if_arm<=0;fetch_req_pc<=if_present_addr;fetch_req_pred_hit<=if_present_pred_hit;fetch_req_pred_taken<=if_present_pred_taken;fetch_req_pred_target<=if_present_pred_target;if_rsp<=1;
    if(if_req_discard||ex_redirect)begin if_discard<=1;if_req_discard<=0;end
    else begin
     fetch_pc<=if_present_pred_taken?if_present_pred_target:(if_present_addr+4);
     // 关键：请求被接收的当拍立刻武装下一笔请求，使下一拍直接以 fetch_pc 展示它。
     // 这样“旧响应被接收”的那一拍同时就是“新请求被接收”的那一拍，取指达到每拍一条。
     if_arm<=1;
    end
   end
   // 冷启动/Redirect 后的重新登记：没有请求在场时，下一拍用 fetch_pc 建立请求。
   if(!if_req&&!if_arm&&!ex_redirect)begin if_req<=1;if_req_addr_reg<=fetch_pc;if_req_pred_hit<=predictor_hit;if_req_pred_taken<=predictor_taken;if_req_pred_target<=predictor_target;if_req_discard<=0;end
  end
 end
 assign trace_valid=wb_fire;assign trace_error=wb_fire&&memwb_error;assign trace_pc=wb_fire?memwb_pc:0;assign trace_instruction=wb_fire?memwb_inst:0;assign trace_rd_we=wb_fire&&memwb_regwrite&&!memwb_error&&memwb_rd!=0;assign trace_rd_addr=trace_rd_we?memwb_rd:0;assign trace_rd_data=trace_rd_we?wb_value:0;assign trace_mem_we=wb_fire&&memwb_memwrite&&!memwb_error;assign trace_mem_addr=trace_mem_we?memwb_alu:0;assign trace_mem_data=trace_mem_we?memwb_sdata:0;assign trace_mem_wstrb=trace_mem_we?memwb_wstrb:0;
endmodule
