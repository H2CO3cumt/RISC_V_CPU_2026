
module pipeline_cpu #(
    parameter ENABLE_BRANCH_PREDICTOR = 1,
    // ?????(rtl/ras.v)?0 = ??(??,?????????);
    // 1 = ??:BTB ???? PC ? ret ?,???? RAS ???
    parameter ENABLE_RAS = 0,
    parameter RAS_DEPTH  = 8,
    // 乘法占用 ID/EX 的拍数（见 rtl/mdu.v 的 MUL_LAT）：
    //   3 = 旧基线（两级串联 16x32 部分积，挡 2 拍）
    //   2 = 并行 16x16 部分积 + 加法树（挡 1 拍）—— **当前默认**，已过 85 MHz 时序
    //   1 = 全组合（挡 0 拍）—— 实测 85 MHz 违例（WNS −4.471 ns），仅保留为对照
    parameter MDU_MUL_LAT = 2
)(
    input  wire        clk,
    input  wire        reset,

    output wire        trace_valid,
    output wire [31:0] trace_pc,
    output wire [31:0] trace_instruction,
    output wire        trace_rd_we,
    output wire [4:0]  trace_rd_addr,
    output wire [31:0] trace_rd_data,
    output wire        trace_mem_we,
    output wire [31:0] trace_mem_addr,
    output wire [31:0] trace_mem_data,
    output wire [3:0]  trace_mem_wstrb,
    output wire        trace_error,

    output wire        i_req_valid,
    input  wire        i_req_ready,
    output wire [31:0] i_req_addr,
    input  wire        i_rsp_valid,
    output wire        i_rsp_ready,
    input  wire [31:0] i_rsp_data,
    input  wire        i_rsp_error,

    output wire        d_req_valid,
    input  wire        d_req_ready,
    output wire [31:0] d_req_addr,
    output wire        d_req_write,
    output wire [31:0] d_req_wdata,
    output wire [3:0]  d_req_wstrb,
    input  wire        d_rsp_valid,
    output wire        d_rsp_ready,
    input  wire [31:0] d_rsp_rdata,
    input  wire        d_rsp_error,

    // 通用中断输入（docs/trap_contract.md §4.2）：
    // Core 只接这三根设备无关的电平信号，中断源、使能、优先级与聚合全部属于 SoC。
    // 设计中不得出现设备名、设备地址或设备状态机。
    input  wire        irq_software_i,
    input  wire        irq_timer_i,
    input  wire        irq_external_i,

    output wire        event_stall,
    output wire        event_load_stall,
    output wire        event_branch,
    output wire        event_branch_taken,
    output wire        event_flush,
    output wire        event_predict,
    output wire        event_btb_hit,
    output wire        event_mispredict,
    output wire        event_control_redirect,
    output wire        event_trap,
    output wire        event_trap_return,
    output wire        event_illegal,
    output wire        event_misaligned,
    output wire        event_bus_error
);

    //-------------------------------------------------------------------------
    // 取指（IF）状态
    //-------------------------------------------------------------------------
    reg [31:0] fetch_pc;
    reg [31:0] fetch_req_pc;
    reg [31:0] if_req_addr_reg;
    reg        if_req;
    reg        if_arm;
    reg        if_rsp;
    reg        if_discard;
    reg        if_req_discard;
    // Redirect/Trap 后的取指前端重启标志：静默一拍，把在途的过期响应收干，
    // 再让请求从新的 fetch_pc 重新开始（见顺序块末尾的说明）。
    reg        if_req_pred_hit;
    reg        if_req_pred_taken;
    reg [31:0] if_req_pred_target;
    reg        fetch_req_pred_hit;
    reg        fetch_req_pred_taken;
    reg [31:0] fetch_req_pred_target;

    //-------------------------------------------------------------------------
    // IF/ID
    //-------------------------------------------------------------------------
    reg        ifid_valid;
    reg        ifid_pred_hit;
    reg        ifid_pred_taken;
    reg        ifid_error;
    reg [31:0] ifid_pc;
    reg [31:0] ifid_inst;
    reg [31:0] ifid_pred_target;

    //-------------------------------------------------------------------------
    // ID/EX
    //-------------------------------------------------------------------------
    reg        idex_valid;
    reg        idex_pred_hit;
    reg        idex_pred_taken;
    reg        idex_error;
    reg [31:0] idex_pc;
    reg [31:0] idex_inst;
    reg [31:0] idex_a;
    reg [31:0] idex_b;
    reg [31:0] idex_imm;
    reg [31:0] idex_pred_target;
    reg [4:0]  idex_rs1;
    reg [4:0]  idex_rs2;
    reg [4:0]  idex_rd;
    reg [2:0]  idex_f3;
    reg        idex_regwrite;
    reg        idex_memread;
    reg        idex_memwrite;
    reg        idex_branch;
    reg        idex_jump;
    reg        idex_jalr;
    reg        idex_asa;
    reg        idex_asb;
    reg [3:0]  idex_alu;
    reg [1:0]  idex_result;
    // ---- Zicsr / SYSTEM 与"异常记录"（见 docs/trap_contract.md）----
    // 异常原因编码与 localparam EXC_* 一致；EXC_NONE=0 表示本条指令到目前为止没出错。
    reg        idex_illegal;
    reg        idex_csr_en;
    reg        idex_csr_imm;
    reg [1:0]  idex_csr_funct;
    reg        idex_trap_ecall;
    reg        idex_trap_ebreak;
    reg        idex_trap_mret;
    reg [3:0]  idex_exc_cause;
    // ---- M 扩展（docs/architecture.md 的存储/执行单元一节）----
    // idex_mdu_en：本条指令由 rtl/mdu.v 执行；idex_mdu_op[2]=1 表示它属于
    // div/divu/rem/remu（迭代 32 拍，需要把 ID/EX 冻住），=0 表示 MUL 组
    // （组合乘法，当拍出结果，不停顿）。
    reg        idex_mdu_en;
    reg [2:0]  idex_mdu_op;

    //-------------------------------------------------------------------------
    // EX/MEM
    //-------------------------------------------------------------------------
    reg        exmem_valid;
    reg        exmem_error;
    reg [31:0] exmem_pc;
    reg [31:0] exmem_inst;
    reg [31:0] exmem_alu;
    reg [31:0] exmem_store;
    reg [31:0] exmem_imm;
    reg [4:0]  exmem_rd;
    reg [2:0]  exmem_f3;
    reg        exmem_regwrite;
    reg        exmem_memread;
    reg        exmem_memwrite;
    reg [1:0]  exmem_result;
    // 随指令前进的异常记录与"恢复地址"；MRET 也要真的走到退休才生效。
    reg [3:0]  exmem_exc_cause;
    reg [31:0] exmem_next_pc;
    reg        exmem_trap_mret;
    // EX/MEM 里那条指令**是否已经形成 MEM/WB 记录**。
    // 为什么需要它：访存指令的"完成"由握手定义（dstate 从 D_RSP 回到 D_IDLE 只发生一次），
    // 而 MEM→WB 的转移原来与"ID/EX 换入 EX/MEM"是同一拍原子发生的。
    // 引入除法停顿后这两件事会被拆开（EX/MEM 不能换入，但 MEM 级必须能排空），
    // 于是 mem_done 会在握手结束后落下、mem_block 永久为 1 —— 实测就是整机死锁在
    // 一条 lbu 上（CoreMark rv32im 跑到 306637 条后再也不动）。
    // 本标记让"这条 EX/MEM 记录已经退休过"独立于换入，MEM 级因此可以安全排空。
    reg        exmem_retired;

    //-------------------------------------------------------------------------
    // 数据侧总线状态机
    //-------------------------------------------------------------------------
    reg [1:0] dstate;

    localparam D_IDLE = 2'd0;
    localparam D_REQ  = 2'd1;
    localparam D_RSP  = 2'd2;

    //-------------------------------------------------------------------------
    // MEM/WB
    //-------------------------------------------------------------------------
    reg        memwb_valid;
    reg        memwb_regwrite;
    reg        memwb_memwrite;
    reg        memwb_error;
    reg [31:0] memwb_pc;
    reg [31:0] memwb_inst;
    reg [31:0] memwb_alu;
    reg [31:0] memwb_mem;
    reg [31:0] memwb_imm;
    reg [31:0] memwb_sdata;
    reg [3:0]  memwb_wstrb;
    reg [4:0]  memwb_rd;
    reg [1:0]  memwb_result;
    // 退休点的异常记录：Trap 只在 WB 这一处被接受，因此"较老指令完成、
    // 较年轻指令取消"由这一个点统一保证。
    reg        memwb_exc_valid;
    reg [3:0]  memwb_exc_cause;
    reg [31:0] memwb_next_pc;
    reg        memwb_trap_mret;

    //-------------------------------------------------------------------------
    // ID 级：译码
    //-------------------------------------------------------------------------
    wire [31:0] dec_imm;
    wire [31:0] rf_a;
    wire [31:0] rf_b;
    wire        dec_rw;
    wire        dec_asa;
    wire        dec_asb;
    wire        dec_mr;
    wire        dec_mw;
    wire        dec_br;
    wire        dec_jmp;
    wire        dec_jalr;
    wire        dec_illegal;
    wire [3:0]  dec_alu;
    wire [1:0]  dec_result;
    wire        dec_csr_en;
    wire        dec_csr_wen;
    wire        dec_csr_imm;
    wire [1:0]  dec_csr_funct;
    wire        dec_trap_ecall;
    wire        dec_trap_ebreak;
    wire        dec_trap_mret;
    wire        dec_mdu_en;
    wire [2:0]  dec_mdu_op;

    decoder #(.ENABLE_SYSTEM(1)) dec(
        .instruction(ifid_inst),
        .reg_write(dec_rw),
        .alu_src_a(dec_asa),
        .alu_src_b(dec_asb),
        .alu_ctrl(dec_alu),
        .mem_read(dec_mr),
        .mem_write(dec_mw),
        .result_src(dec_result),
        .branch(dec_br),
        .jump(dec_jmp),
        .jalr(dec_jalr),
        .illegal(dec_illegal),
        .csr_en(dec_csr_en),
        .csr_wen(dec_csr_wen),
        .csr_imm(dec_csr_imm),
        .csr_funct(dec_csr_funct),
        .trap_ecall(dec_trap_ecall),
        .trap_ebreak(dec_trap_ebreak),
        .trap_mret(dec_trap_mret),
        .mdu_en(dec_mdu_en),
        .mdu_op(dec_mdu_op)
    );

    imm_gen ig(
        .instruction(ifid_inst),
        .imm(dec_imm)
    );

    wire [4:0] dec_rs1 = ifid_inst[19:15];
    wire [4:0] dec_rs2 = ifid_inst[24:20];
    wire [4:0] dec_rd  = ifid_inst[11:7];
    wire [2:0] dec_f3  = ifid_inst[14:12];

    //-------------------------------------------------------------------------
    // WB 写回值与写回有效
    //-------------------------------------------------------------------------
    wire [31:0] wb_value = (memwb_result == 2'd0) ? memwb_alu :
                           (memwb_result == 2'd1) ? memwb_mem :
                           (memwb_result == 2'd2) ? memwb_pc + 32'd4 :
                                                     memwb_imm;
    // 进入 Trap 的那一拍，WB 上的记录属于被打断的指令：不得写回、不得形成提交记录。
    // 进入 Trap 的那一拍，WB 上的记录属于被打断的指令：不得写回、不得形成提交记录。
    // 但"中断"是异步事件：语义上它发生在 WB 这条指令**提交之后**，所以必须照常退休；
    // 只有同步异常才取消出错指令本身（§5.1 第 3 条）。
    // 被取消的指令之后的所有指令都不得产生任何架构副作用（第 2 条）。
    wire wb_cancel = trap_take && (wb_exc_cause != EXC_NONE);
    wire wb_fire   = memwb_valid && !wb_cancel;

    regfile rf(
        .clk(clk),
        .rd_we(wb_fire && memwb_regwrite && !memwb_error),
        .rd_addr(memwb_rd),
        .rd_data(wb_value),
        .rs1_addr(dec_rs1),
        .rs2_addr(dec_rs2),
        .rs1_data(rf_a),
        .rs2_data(rf_b)
    );

    //-------------------------------------------------------------------------
    // ID 级操作数（含 WB->ID 旁路）
    //-------------------------------------------------------------------------
    wire [31:0] id_a = (wb_fire && memwb_regwrite && !memwb_error &&
                        memwb_rd != 0 && memwb_rd == dec_rs1) ? wb_value : rf_a;

    wire [31:0] id_b = (wb_fire && memwb_regwrite && !memwb_error &&
                        memwb_rd != 0 && memwb_rd == dec_rs2) ? wb_value : rf_b;

    //-------------------------------------------------------------------------
    // EX 级：Forwarding 与 ALU
    //-------------------------------------------------------------------------
    wire [31:0] exmem_forward = (exmem_result == 2'd0) ? exmem_alu :
                                (exmem_result == 2'd2) ? exmem_pc + 32'd4 :
                                                         exmem_imm;

    wire [1:0] forward_a;
    wire [1:0] forward_b;

    forward_unit fu(
        .idex_rs1(idex_rs1),
        .idex_rs2(idex_rs2),
        .exmem_valid(exmem_valid),
        .exmem_regwrite(exmem_regwrite),
        .exmem_memread(exmem_memread),
        .exmem_rd(exmem_rd),
        .memwb_valid(memwb_valid),
        .memwb_regwrite(memwb_regwrite),
        .memwb_error(memwb_error),
        .memwb_rd(memwb_rd),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    wire [31:0] srca0 = (forward_a == 2'b10) ? exmem_forward :
                        (forward_a == 2'b01) ? wb_value : idex_a;

    wire [31:0] srcb0 = (forward_b == 2'b10) ? exmem_forward :
                        (forward_b == 2'b01) ? wb_value : idex_b;

    wire [31:0] ex_a;
    wire [31:0] ex_b;
    wire [31:0] ex_alu;

    assign ex_a = idex_asa ? idex_pc  : srca0;
    assign ex_b = idex_asb ? idex_imm : srcb0;

    alu exalu(
        .a(ex_a),
        .b(ex_b),
        .alu_ctrl(idex_alu),
        .result(ex_alu)
    );

    //-------------------------------------------------------------------------
    // M 扩展：乘除法单元（rtl/mdu.v）
    //
    // 操作数取 srca0/srcb0（已经过前递的源操作数），与 ALU 用的是同一份，
    // 所以 MUL 组的前递/写回时序和 add/sub 完全一致，不需要任何停顿。
    //
    // run 只在"ID/EX 上确实是一条除法指令"时成立，它同时是状态机的起拍条件
    // 和取消条件：指令被 Trap/Redirect 清掉时 idex_valid 落下，run 随之落下，
    // 迭代立刻中止且不留副作用（见 mdu.v 的 S_RUN 分支）。
    //
    // mdu_block：除法还没算完 -> 把 ID/EX 冻在 EX，且不许它进入 EX/MEM。
    // 注意它是"EX 级"的暂停，与"MEM 级"的 mem_block 是两回事：
    // 两者都不允许同时改写 ID/EX，所以下面统一用 pipe_hold 表达。
    //-------------------------------------------------------------------------
    wire [31:0] mdu_result;
    wire        mdu_busy;
    // run 覆盖两组（乘法 MDU_MUL_LAT 拍、除法 32 拍）：具体怎么走由 mdu 内部按 op[2] 决定。
    wire        mdu_run = idex_valid && idex_mdu_en;

    // ID/EX -> EX/MEM 的转移条件（与下面 always 块里的判据必须逐项一致）：
    // 这一拍就是"这条 M 指令被消费"的那一拍，mdu 用它回到空闲，
    // 否则背靠背的两条同类指令会共用同一次运算结果。
    wire idex_to_exmem = !mem_block && !trap_take &&
                         ((mem_done || !exmem_valid) && !mdu_block);
    wire mdu_ack = idex_to_exmem && mdu_run;

    mdu #(.MUL_LAT(MDU_MUL_LAT)) mdu_unit(
        .clk(clk),
        .reset(reset),
        .run(mdu_run),
        .op(idex_mdu_op),
        .a(srca0),
        .b(srcb0),
        .ack(mdu_ack),
        .busy(mdu_busy),
        .result(mdu_result)
    );

    wire        mdu_block  = mdu_busy;

    wire branch_taken;

    branch_unit bu(
        .a(srca0),
        .b(srcb0),
        .funct3(idex_f3),
        .taken(branch_taken)
    );

    // 跳转目标只由 ALU 结果决定：CSR 指令永远不是跳转，因此这里不能用 ex_result
    // （它对本条 CSR 指令会被换成 CSR 旧值）。
    wire [31:0] ex_target = idex_jalr ? (ex_alu & 32'hfffffffe) : ex_alu;

    //-------------------------------------------------------------------------
    // EX 级未对齐访存判定
    //
    // 为什么要在 EX 判：未对齐异常只要地址算出来就能确定，把它和非法指令、
    // ECALL/EBREAK 放在同一级，异常记录就能走同一条"先到先得"通路；
    // 若只在 MEM 判，异常记录会晚一级进流水，Trap 的接受点与 mepc 都会跟着偏。
    //
    // 为什么直接再例化一个 load_store_unit 而不是手写一份比较规则：
    // 判定规则只能有一个出处，否则日后改了一处漏一处，EX 与 MEM 的
    // "要不要发总线事务"与"要不要报未对齐"就会互相矛盾。
    // 本实例只取 misaligned，数据/掩码输出全部悬空。
    //-------------------------------------------------------------------------
    wire ex_misaligned;
    load_store_unit lsu_ex(
        .addr_low(ex_alu[1:0]),
        .funct3(idex_f3),
        .mem_rdata(32'b0),
        .store_data(32'b0),
        .is_load(idex_memread),
        .is_store(idex_memwrite),
        .load_data(),
        .store_wdata(),
        .store_wstrb(),
        .misaligned(ex_misaligned)
    );

    //-------------------------------------------------------------------------
    // 异常原因编码与"异常记录"
    //
    // 每条指令携带一条 4-bit 异常记录沿流水线前进，规则只有一条：**先到先得**。
    // 只在进入某一级时填一次，已经有记录就不再覆盖。由于指令按程序序逐级推进，
    // 先填进去的必然是程序序更早的那个异常，因此天然满足§5.2 的优先级要求。
    //
    // 记录只存原因码；mtval 不单独存，因为它的语义是"出错的地址或指令码"，
    // 这两样本来就躺在流水寄存器里（exmem_alu / memwb_inst）。
    //-------------------------------------------------------------------------
    localparam [3:0] EXC_NONE       = 4'd0;
    localparam [3:0] EXC_IFETCH_ERR = 4'd1;
    localparam [3:0] EXC_ILLEGAL    = 4'd2;
    localparam [3:0] EXC_EBREAK     = 4'd3;
    localparam [3:0] EXC_LOAD_MIS   = 4'd4;
    localparam [3:0] EXC_STORE_MIS  = 4'd6;
    localparam [3:0] EXC_LOAD_ACC   = 4'd5;
    localparam [3:0] EXC_STORE_ACC  = 4'd7;
    localparam [3:0] EXC_ECALL      = 4'd11;
    // 注意：EXC_INSTR_MIS 的 4-bit 取值 12 只是**内部记录编码**，不是 RISC-V 的 mcause。
    // §4.1 规定 E-01（指令地址未对齐）的 mcause 是 0，而 0 已经被 EXC_NONE 占用，
    // 4-bit 记录里放不下，所以在写 mcause 时单独映射回 0（见 trap_cause_value）。
    // 12 在标准 RISC-V 里是 instruction page fault，本项目没有 MMU，绝不能原样写进 mcause。
    localparam [3:0] EXC_INSTR_MIS  = 4'd12;

    // IF/ID → ID/EX 边界：取指错误与取指地址未对齐在 IF 级就能确定
    // 取指错误与取指地址未对齐都归到 E-08/E-09，mcause=1（§4.1）。
    // 不要写成 EXC_INSTR_MIS：那条编码属于 E-01（跳转目标未对齐，mcause=0），
    // 两者是不同原因，混用会让取指路径报出错误的原因码。
    wire [3:0] ifid_exc_cause = (ifid_error || (ifid_pc[1:0] != 2'b00)) ? EXC_IFETCH_ERR
                                                                       : EXC_NONE;

    // EX 级本条指令新发现的异常（不含 CSR 合法性，它走独立通路）。
    // ECALL/EBREAK 在译码时已保证 illegal=0，因此三条互斥。
    // 未对齐判据必须用**未清 bit0** 的 ALU 结果 ex_alu：JALR 的目标在 ex_target 里
    // 已经被抹掉 bit0，用 ex_target[1] 判断会漏掉"末位被清零之后才对齐"的情况
    //（实测 jalr 跳向 0x1D 完全检测不到 E-01，一路当成正常跳转执行下去）。
    wire [3:0] ex_exc_new = (idex_jump && ex_alu[1]) ? EXC_INSTR_MIS :
                            idex_illegal                ? EXC_ILLEGAL   :
                            csr_illegal_q               ? EXC_ILLEGAL   :
                            idex_trap_ecall             ? EXC_ECALL     :
                            idex_trap_ebreak            ? EXC_EBREAK    :
                            ex_misaligned               ? (idex_memwrite ? EXC_STORE_MIS
                                                                            : EXC_LOAD_MIS) :
                                                          EXC_NONE;

    // 合并：ID/EX 里已有更老的记录就保持，否则接受本条指令的新异常
    wire [3:0] ex_exc_cause = (idex_exc_cause != EXC_NONE) ? idex_exc_cause
                                                           : ex_exc_new;

    // MEM 级访存错误：地址未对齐在 EX 组合路径即可判定，访问错误要等下游响应。
    // 必须带 !exmem_retired：mem_done 现在在退休之后仍保持 1（见 exmem_retired 的说明），
    // 少了这一项会让一条已经退休的访存错误被反复计入。
    wire mem_access_error_now = mem_done && !exmem_retired && exmem_valid && exmem_access &&
                                !ls_misaligned && d_rsp_error;

    wire [3:0] mem_exc_cause = mem_access_error_now
                               ? (exmem_memwrite ? EXC_STORE_ACC : EXC_LOAD_ACC)
                               : EXC_NONE;

    // 写入 WB 的原因：本条指令更早记录的异常优先，否则采用 MEM 级刚发现的访存错误。
    // 注意不要写成 `wire memwb_exc_cause = memwb_exc_cause_q;`——那会让
    // `memwb_exc_cause <= memwb_exc_cause;` 退化成自赋值，记录永远传不到 WB。
    wire [3:0] wb_exc_next = (exmem_exc_cause != EXC_NONE) ? exmem_exc_cause
                                                           : mem_exc_cause;

    // 退休点异常：只有 memwb 记录有效时才成立
    wire [3:0] wb_exc_cause = memwb_exc_valid ? memwb_exc_cause : EXC_NONE;

    //-------------------------------------------------------------------------
    // CSR 读改写（EX 级单周期完成）
    //
    // CSRRS/CSRRC 用 x0（或 uimm=0）时是纯读，不产生写副作用；这条判定必须留着，
    // 否则"读一个只读 CSR"会被误判成非法指令。
    //-------------------------------------------------------------------------
    wire [11:0] ex_csr_addr = idex_inst[31:20];
    wire [4:0]  ex_csr_uimm = idex_inst[19:15];
    wire        ex_csr_src_is_zero = idex_csr_imm ? (ex_csr_uimm == 5'b0)
                                                  : (idex_rs1 == 5'b0);
    wire        ex_csr_read_only_op = (idex_csr_funct == 2'b01) ||
                                      (idex_csr_funct == 2'b10);
    wire        ex_csr_write = idex_csr_en &&
                               !(ex_csr_read_only_op && ex_csr_src_is_zero);
    wire [31:0] ex_csr_src = idex_csr_imm ? {27'b0, ex_csr_uimm} : srca0;

    wire [31:0] csr_rdata;
    wire [31:0] csr_wdata = (idex_csr_funct == 2'b01) ? (csr_rdata |  ex_csr_src) :
                            (idex_csr_funct == 2'b10) ? (csr_rdata & ~ex_csr_src) :
                                                        ex_csr_src;

    // EX 级的"写回候选值"：CSR 指令写回的是 CSR 旧值（csr_rdata），M 扩展指令
    // 写回的是乘除法单元的结果（mdu_result），其余指令写回 ALU 结果。
    // 必须放在这里而不是 ALU 之前：csr_rdata 由下面的 csr_unit 组合给出，
    // mdu_result 由上面的 mdu 例化给出。
    // 它同时进入 EX/MEM 的 exmem_alu，也就是 load/store 的地址来源；
    // CSR 与 M 指令都不访存，两者不会冲突。
    wire [31:0] ex_result = idex_csr_en ? csr_rdata :
                            idex_mdu_en ? mdu_result : ex_alu;

    wire        csr_illegal_q;
    wire [31:0] csr_epc_out;
    wire        csr_mstatus_mie;
    wire        csr_mie_msie;
    wire        csr_mie_mtie;
    wire        csr_mie_meie;
    wire [31:0] csr_mtvec_base;

    //-------------------------------------------------------------------------
    // 中断
    //
    // mip 是只读窗口，直接反映外部输入电平；只有 mstatus.MIE 与对应 mie 位
    // 同时为 1 才算"已使能的中断请求"。三根线的优先级只在 Core 内固定为
    // external > software > timer，且只决定"同一拍多源同时到达时 mcause 记哪一个"。
    //-------------------------------------------------------------------------
    wire irq_ext_ready = csr_mstatus_mie && csr_mie_meie && irq_external_i;
    wire irq_sw_ready  = csr_mstatus_mie && csr_mie_msie && irq_software_i;
    wire irq_tim_ready = csr_mstatus_mie && csr_mie_mtie && irq_timer_i;

    wire [31:0] irq_cause = irq_ext_ready ? 32'h8000_000B :
                            irq_sw_ready  ? 32'h8000_0003 :
                                            32'h8000_0007;

    wire irq_ext_first = irq_ext_ready;
    wire irq_sw_first  = !irq_ext_ready && irq_sw_ready;
    wire irq_tim_first = !irq_ext_ready && !irq_sw_ready && irq_tim_ready;
    wire irq_grant     = irq_ext_first || irq_sw_first || irq_tim_first;

    //-------------------------------------------------------------------------
    // Trap 接受点：退休边界（WB）
    //
    // 只在"本条指令不需要再等访存响应"且 WB 真的有一条退休记录时接受，
    // 这样 mepc 的两个来源（memwb_pc / memwb_next_pc）一定是有效的。
    // 同步异常优先于中断；Trap 与 MRET 同拍时 Trap 优先（MRET 被取消、无副作用）。
    //-------------------------------------------------------------------------
    wire trap_ready = !mem_block;

    // 中断是异步事件：语义上发生在 WB 这条指令**提交之后**，因此它不取消这条指令。
    wire trap_is_irq = (wb_exc_cause == EXC_NONE) && irq_grant;

    wire trap_take = trap_ready && memwb_valid &&
                     ((wb_exc_cause != EXC_NONE) || irq_grant);

    // 恢复地址（写进 mepc）：
    //  - 同步异常：出错指令自己的 PC（§5.1 第 3 条，不是 PC+4）。
    //    唯一例外是"已经发出去并被下游接受"的 Store 访问错误：那条 Store 架构上
    //    视为在 Trap 之前完成，回退到它的 PC 会把它再做一遍，因此推进到 PC+4
    //    （§5.1 第 4 条）。
    //  - 中断：要回到"还没执行的那条指令"，即本条指令程序序上的下一条。
    //    它由 ex_next_pc 随指令一起流过流水线，不能用 exmem_pc 顶替：
    //    跳转/分支重定向当拍，EX/MEM 里可能正是一个气泡。
    wire [31:0] trap_resume_pc = trap_is_irq                    ? memwb_next_pc :
                                 (wb_exc_cause == EXC_STORE_ACC) ? (memwb_pc + 32'd4) :
                                                                   memwb_pc;

    // 入口地址：只实现 Direct 模式
    wire [31:0] trap_target = csr_mtvec_base;

    // E-01（指令地址未对齐）在规范里的 mcause 是 0，而内部记录用 12 表示，这里映射回去。
    wire [31:0] trap_cause_value = (wb_exc_cause == EXC_NONE)      ? irq_cause :
                                   (wb_exc_cause == EXC_INSTR_MIS) ? 32'd0 :
                                                                     {28'b0, wb_exc_cause};

    // mtval：非法指令/EBREAK → 指令码；ECALL 与中断 → 0；其余 → 出错地址。
    // mtval（§4.3）：非法指令/EBREAK → 指令码；ECALL 与中断 → 0；
    // 取指错误/未对齐 → 出错取指地址；访存未对齐/访问错误 → 出错访存地址。
    wire [31:0] trap_value = trap_is_irq                      ? 32'b0 :
                             (wb_exc_cause == EXC_ILLEGAL)    ? memwb_inst :
                             (wb_exc_cause == EXC_EBREAK)     ? memwb_inst :
                             (wb_exc_cause == EXC_ECALL)      ? 32'b0 :
                             (wb_exc_cause == EXC_IFETCH_ERR) ? memwb_pc :
                             // E-01 的 mtval 是"未对齐的目标地址"，也就是 ALU 算出来的跳转目标。
                             (wb_exc_cause == EXC_INSTR_MIS)  ? memwb_alu :
                                                                memwb_alu;

    // MRET 必须真的走到退休才生效；被同拍 Trap 取消时不得改 mstatus 或 PC
    wire wb_trap_return = memwb_valid && memwb_trap_mret && !trap_take;

    //-------------------------------------------------------------------------
    // CSR 单元（机器模式 CSR 状态 + Trap 进入/返回）
    //
    // 写入优先级：Trap 进入 > MRET > 普通 CSR 写。这里用
    // csr_we = ex_csr_write && idex_valid && !trap_take 把"同拍 Trap 优先"落到信号上，
    // 使被取消的 CSR 写不留下任何副作用（§3.3 第 3 条）。
    //-------------------------------------------------------------------------
    csr_unit csr(
        .clk(clk),
        .reset(reset),
        .csr_addr(ex_csr_addr),
        .csr_rdata(csr_rdata),
        // csr_illegal_q 是"本条 CSR 指令自身非法"的组合判据：非法时绝不能改 CSR，
        // 否则非法指令会留下副作用（§3.3）。它同时经 EX 级异常记录进入 Trap。
        .csr_we(ex_csr_write && idex_valid && !csr_illegal_q && !trap_take),
        .csr_waddr(ex_csr_addr),
        .csr_wdata(csr_wdata),
        .csr_check_en(idex_valid && idex_csr_en),
        .csr_check_addr(ex_csr_addr),
        .csr_check_write(ex_csr_write),
        .csr_illegal(csr_illegal_q),
        .trap_enter(trap_take),
        .trap_cause(trap_cause_value),
        .trap_value(trap_value),
        .epc_next(trap_resume_pc),
        .trap_return(wb_trap_return),
        .irq_sw_pending(irq_software_i),
        .irq_timer_pending(irq_timer_i),
        .irq_ext_pending(irq_external_i),
        // minstret 统计的是"真正形成提交记录"的那一拍，因此直接用 wb_fire：
        // 被 Trap 取消的出错指令、气泡、以及未退休的指令都不计数。
        .retire(wb_fire),
        .mstatus_mie(csr_mstatus_mie),
        .mie_mtie(csr_mie_mtie),
        .mie_meie(csr_mie_meie),
        .mie_msie(csr_mie_msie),
        .mtvec_base(csr_mtvec_base),
        .epc_out(csr_epc_out)
    );

    // 退休事件已由 wb_fire 统一表达（见文件上方定义），此处不再需要单独推导。
    //-------------------------------------------------------------------------
    // Load-Use 冒险
    //-------------------------------------------------------------------------
    wire load_use;
    hazard_unit hu(
        .idex_valid(idex_valid),
        .idex_memread(idex_memread),
        .idex_rd(idex_rd),
        .ifid_valid(ifid_valid),
        .ifid_instruction(ifid_inst),
        .load_use_stall(load_use)
    );

    //-------------------------------------------------------------------------
    // 访存单元
    //-------------------------------------------------------------------------
    wire        exmem_access = exmem_memread || exmem_memwrite;
    wire [31:0] ls_load;
    wire [31:0] ls_store;
    wire [3:0]  ls_wstrb;
    wire        ls_misaligned;

    load_store_unit lsu(
        .addr_low(exmem_alu[1:0]),
        .funct3(exmem_f3),
        .mem_rdata(d_rsp_rdata),
        .store_data(exmem_store),
        .is_load(exmem_memread),
        .is_store(exmem_memwrite),
        .load_data(ls_load),
        .store_wdata(ls_store),
        .store_wstrb(ls_wstrb),
        .misaligned(ls_misaligned)
    );

    wire mem_done  = exmem_valid && (exmem_retired || !exmem_access || ls_misaligned ||
                                     (dstate == D_RSP && d_rsp_valid && d_rsp_ready));
    wire mem_block = exmem_valid && !mem_done;

    //-------------------------------------------------------------------------
    // 控制流解析与重定向
    //
    // 只有“预测错了”才需要重定向。预测对的时候（预测方向与真实方向一致、
    // 并且真实跳转的目标等于 BTB 给出的目标）IF 已经沿着正确路径取指，
    // 这里再重定向一次纯属把前端三条指令白扔掉。
    //
    // 三类控制指令的方向来源不同：
    //  - 条件分支：方向由 branch_unit 比较得出，可能 taken 也可能 not-taken；
    //  - JAL：恒 taken。`idex_jump_taken` 为 1，目标由 PC + J 立即数确定，
    //         而立即数来自指令位，因此第一次执行就必然算对；
    //  - JALR：恒 taken。`idex_jump_taken` 为 1，目标依赖 rs1 的值，
    //         所以“方向必然跳”但“目标不一定等于上次记下的目标”，
    //         必须靠 control_mispredict 的目标比较兜底。
    //
    // 对不写寄存器的非控制指令，idex_branch/idex_jump 都为 0，
    // control_resolve 为 0，下面所有比较都不会触发。
    //-------------------------------------------------------------------------
    // CSR / MRET / ECALL / EBREAK 不是分支也不是跳转，不得进入分支预测统计；
    // 它们不改变 PC 顺序（MRET 除外，它走 trap_return 通路），所以显式排除。
    wire control_resolve = idex_valid && !idex_csr_en && !idex_trap_mret &&
                           !idex_trap_ecall && !idex_trap_ebreak &&
                           (idex_branch || idex_jump) && !mem_block;

    // 真实“跳走”与否：分支看比较结果，跳转恒为真。
    wire control_taken = idex_branch ? branch_taken : 1'b1;

    // 预测方向。方向预测对了才进一步比较目标；方向本身就错时，
    // 目标比较没有意义（通常是 not-taken，BTB 里的目标与本次无关）。
    wire pred_direction_ok = (idex_pred_taken == control_taken);

    wire pred_target_ok = !control_taken ||
                          (idex_pred_taken && (idex_pred_target == ex_target));

    wire control_mispredict = control_resolve &&
                              !(pred_direction_ok && pred_target_ok);

    // Trap 也是 PC 重定向来源，而且优先级高于任何预测修正：一旦进入 Trap，
    // 同拍的分支/跳转修正被取消（§5.2 第 7 条）。
    // MRET 的 PC 重定向：MRET 在 EX 级解析，PC 必须回到 mepc。
    // 它和分支/跳转不同——目标来自 CSR 而不是指令位，所以是独立的一条通路。
    // Trap 同拍优先：此时 MRET 被取消，既不改 PC 也不改 mstatus（§5.2 第 6 条）。
    wire mret_redirect = idex_valid && idex_trap_mret && !mem_block && !trap_take;

    wire ex_redirect = control_mispredict || mret_redirect || trap_take;

    // id_advance ???????:RAS ? push/pop ??? BTB ?????"??"??,
    // ????? IF ???,?????????????
    wire id_advance  = !mem_block && !mdu_block && !load_use && !ex_redirect;

    // 本条指令"程序序的下一条 PC"。中断的恢复地址必须用它：
    // exmem_pc 在跳转/分支重定向当拍可能正落在气泡上，而这条值随指令一起
    // 流过流水线，始终等于"本条指令退休之后该执行的那条地址"。
    wire [31:0] ex_next_pc = (idex_jump || (idex_branch && branch_taken))
                             ? ex_target : (idex_pc + 32'd4);

    // 重定向目标：真跳走时用真实目标（分支和跳转都一样），
    // 否则回到这条指令的下一条。
    // 重定向目标优先级：Trap / MRET 是"控制流被外部或特权指令改写"，
    // 高于普通分支预测修正；普通重定向保持 A1 的口径不变。
    wire [31:0] redirect_pc = trap_take     ? trap_target :
                              mret_redirect ? csr_epc_out :
                              control_taken ? ex_target :
                                              (idex_pc + 32'd4);

    // 观测事件：本条控制指令方向与目标都已被预测命中，因此不需要重定向。
    // 它正是 A1 优化“省下来的那几次 flush”，与 event_flush 互斥。
    wire control_pred_ok = control_resolve && pred_direction_ok && pred_target_ok;

    //-------------------------------------------------------------------------
    // 分支预测器
    //-------------------------------------------------------------------------
    wire        predictor_hit;
    wire        predictor_taken;
    wire [31:0] predictor_target;

    branch_predictor predictor(
        .clk(clk),
        .reset(reset),
        .enable(ENABLE_BRANCH_PREDICTOR != 0),
        .query_pc(fetch_pc),
        .query_hit(predictor_hit),
        .predicted_taken(predictor_taken),
        .predicted_target(predictor_target),
        .update_valid(control_resolve),
        .update_pc(idex_pc),
        .update_taken(control_taken),
        .update_is_jump(idex_jump),
        .update_target(ex_target)
    );

    //-------------------------------------------------------------------------
    // ?????(RAS):?? BTB ? `ret` ?????
    //
    // ???? RAS:BTB ?? PC ???? target,???? `ret` ????
    // ?????(CoreMark ???? ret 49 ? / call 158 ?),????????
    // RAS ???????????,??"??????"?
    //
    // ??(RISC-V ???? call/ret,???????):
    //   call = dec_jmp && rd == x1              -> push ifid_pc + 4
    //   ret  = dec_jalr && rd == x0 && rs1 == x1 -> pop
    // ????? ID ????(id_advance ??):EX ??? 1~2 ?,???
    // `ret` ???????;?????????????? id_advance,
    // ????????????
    //
    // is_ret ??? BTB ???(16 ? = pc[5:2]):IF ?????????
    // ????,??"????? ret"??????????????????
    // ?? branch_predictor,?????????? TB ??????
    //-------------------------------------------------------------------------
    wire        ras_fire     = id_advance && ifid_valid && !dec_illegal;
    wire        ras_push     = ras_fire && dec_jmp && (dec_rd == 5'd1);
    wire        ras_pop      = ras_fire && dec_jalr && (dec_rd == 5'd0) && (dec_rs1 == 5'd1);
    wire [31:0] ras_ret_addr = ifid_pc + 32'd4;
    wire        ras_valid;
    wire [31:0] ras_top;
    wire [3:0]  ras_level;   // ????(Core ?????,????)

    ras #(.DEPTH(RAS_DEPTH)) ras_unit (
        .clk      (clk),
        .reset    (reset),
        .enable   (ENABLE_RAS != 0),
        .push     (ras_push),
        .ret_addr (ras_ret_addr),
        .pop      (ras_pop),
        .top      (ras_top),
        .valid    (ras_valid),
        .level    (ras_level)
    );

    // ? PC ??? ret(? BTB ?????????)
    reg [15:0] btb_is_ret;
    always @(posedge clk) begin
        if (reset) begin
            btb_is_ret <= 16'b0;
        end
        else if (control_resolve) begin
            // ?????? predictor_hit ?? tag ??,??????????
            btb_is_ret[idex_pc[5:2]] <= idex_jalr && (idex_rd == 5'd0) && (idex_rs1 == 5'd1);
        end
    end

    wire pred_is_ret = predictor_hit && btb_is_ret[fetch_pc[5:2]];
    // ??????:ret ?????? -> ? RAS ??;??? BTB ??? target
    wire [31:0] predictor_target_eff =
        (pred_is_ret && ras_valid) ? ras_top : predictor_target;

    //-------------------------------------------------------------------------
    // 取指请求的展示形式有两种，二者在对外语义上完全等价（都是一个单 outstanding 的取指事务）：
    //  - if_req：请求已锁存在 if_req_addr_reg 中，等待下游 ready；
    //  - if_arm：刚刚接受完上一笔请求，本拍直接用已经寄存的 fetch_pc 展示下一笔请求。
    // if_arm 的存在是为了消除“接受后一拍没有请求在场”的空洞：旧请求的响应在 T 拍被接收时，
    // 新请求已经在本拍展示，因此可以在同一拍完成“旧响应接收 + 新请求接受”的交接，
    // 达到 docs/interfaces.md §3 要求的每拍一条连续取指。展示地址直接来自 fetch_pc 寄存器，
    // 不引入额外的地址寄存级，因此不改变“valid 且 !ready 时地址保持稳定”这一要求。
    //-------------------------------------------------------------------------
    wire        if_present        = if_req || if_arm;
    // if_arm 展示的地址必须寄存后再展示，不能直接用 fetch_pc：
    // Redirect/Trap 当拍 fetch_pc 会被改成新目标，若此时 if_arm 正在等待 ready，
    // 直接用 fetch_pc 会让"valid && !ready 时字段稳定"这一要求当场失效。
    // if_arm_addr_reg 在武装那一拍锁存，之后保持到该请求被接受或转入 if_req。
    wire [31:0] if_present_addr   = if_req ? if_req_addr_reg : fetch_pc;
    wire        if_present_pred_hit    = if_req ? if_req_pred_hit    : predictor_hit;
    wire        if_present_pred_taken  = if_req ? if_req_pred_taken  : predictor_taken;
    wire [31:0] if_present_pred_target = if_req ? if_req_pred_target : predictor_target_eff;

    // A held EX/MEM entry owns the external request.  Once accepted, valid drops
    // while the entry remains until the one matching response is consumed.
    assign d_req_valid = exmem_valid && exmem_access && !ls_misaligned && (dstate == D_REQ);
    assign d_req_addr  = exmem_alu;
    assign d_req_write = exmem_memwrite;
    assign d_req_wdata = ls_store;
    assign d_req_wstrb = ls_wstrb;
    assign d_rsp_ready = exmem_valid && exmem_access && !ls_misaligned && (dstate == D_RSP);

    // IF 允许“旧响应完成 + 新请求接受”在同一拍交接，因此零等待存储器可持续
    // 每拍取一条，同时任意时刻仍只有一笔未完成事务。IF/ID 当拍被 ID 消费时
    // 也可由新响应替换，避免人为插入空泡。
    wire ifid_available = !ifid_valid || id_advance || ex_redirect;

    assign i_rsp_ready = if_rsp && !mem_block &&
                         (if_discard || ex_redirect || ifid_available);

    wire if_accept = i_rsp_valid && i_rsp_ready;

    // if_req/if_arm 一旦对外可见，即使随后发生 Stall/Redirect 也不能撤回；Redirect
    // 只把该请求标成错误路径，待其正常握手并返回后丢弃。因此只有在下游明确
    // 未接收（!if_accept 且无 if_rsp 未完成响应）时才允许展示新请求。
    assign i_req_valid = if_present && (!if_rsp || if_accept);
    assign i_req_addr  = if_present_addr;

    wire if_request_accept = i_req_valid && i_req_ready;

    wire front_hold        = mem_block || mdu_block || load_use;

    //-------------------------------------------------------------------------
    // 事件输出
    //-------------------------------------------------------------------------
    // event_branch 只统计条件分支，保持 CoreMark/性能报告的既有口径不变；
    // 跳转单独由 event_control_* 统计，避免历史数据与新材料口径混用。
    assign event_stall        = front_hold;
    assign event_load_stall   = load_use && !mem_block;
    assign event_branch       = control_resolve && idex_branch;
    assign event_branch_taken = control_resolve && idex_branch && branch_taken;
    assign event_flush        = ex_redirect;
    assign event_predict      = control_resolve;
    assign event_btb_hit      = control_resolve && idex_pred_hit;
    assign event_mispredict   = control_mispredict;
    // 预测命中的跳转/分支不再重定向：A1 优化省下的正是这些“白扔的前端”。
    assign event_control_redirect = control_pred_ok && (idex_jump || branch_taken);
    // Trap 相关观察事件（只读，由 Core 外部的性能监视器/ILA 消费）
    assign event_trap         = trap_take;
    assign event_trap_return  = wb_trap_return;
    // event_illegal 的口径与 A1 保持一致：只在 ID 级译码到非法指令的那一拍计数一次。
    // 不要再加上"EX 级 idex_illegal"——同一条指令会在两级各计一次，
    // 而既有观测性 Testbench 断言的是恰好 1 次（实测加上后会变成 2 次）。
    // Trap 同拍说明这条非法指令属于被冲刷的错误路径，不计入。
    assign event_illegal      = id_advance && ifid_valid && !ifid_error &&
                                dec_illegal && !trap_take;
    assign event_misaligned   = mem_done && !exmem_retired && exmem_access && ls_misaligned;
    assign event_bus_error    = (if_accept && i_rsp_error) ||
                                (mem_done && !exmem_retired && exmem_access && !ls_misaligned && d_rsp_error);

    always @(posedge clk) begin
        if (reset) begin
            fetch_pc                <= 0;
            fetch_req_pc            <= 0;
            if_req_addr_reg         <= 0;
            if_req                  <= 0;
            if_arm                  <= 0;
            if_rsp                  <= 0;
            if_discard              <= 0;
            if_req_discard          <= 0;
            if_req_pred_hit         <= 0;
            if_req_pred_taken       <= 0;
            if_req_pred_target      <= 0;
            fetch_req_pred_hit      <= 0;
            fetch_req_pred_taken    <= 0;
            fetch_req_pred_target   <= 0;
            ifid_valid              <= 0;
            ifid_pred_hit           <= 0;
            ifid_pred_taken         <= 0;
            ifid_pred_target        <= 0;
            ifid_error              <= 0;
            idex_valid              <= 0;
            idex_pred_hit           <= 0;
            idex_pred_taken         <= 0;
            idex_pred_target        <= 0;
            idex_error              <= 0;
            idex_illegal            <= 0;
            idex_csr_en             <= 0;
            idex_csr_imm            <= 0;
            idex_csr_funct          <= 2'b00;
            idex_trap_ecall         <= 0;
            idex_trap_ebreak        <= 0;
            idex_trap_mret          <= 0;
            idex_exc_cause          <= EXC_NONE;
            idex_mdu_en             <= 0;
            idex_mdu_op             <= 3'b000;
            exmem_valid             <= 0;
            exmem_retired           <= 0;
            exmem_error             <= 0;
            exmem_exc_cause         <= EXC_NONE;
            exmem_next_pc           <= 0;
            exmem_trap_mret         <= 0;
            dstate                  <= D_IDLE;
            memwb_valid             <= 0;
            memwb_exc_valid         <= 0;
            memwb_exc_cause         <= EXC_NONE;
            memwb_next_pc           <= 0;
            memwb_trap_mret         <= 0;
        end else begin
            // WB is single-cycle: a retired valid record must not be replayed.
            // 异常记录与 valid 一样必须每拍清一次：若只在 mem_done 时赋值，
            // 一旦 mem_done 落下（EX/MEM 被 Redirect 清空或访存停住），
            // memwb_exc_valid 会**永久保持 1**，于是一条陈旧异常被反复接受，
            // 每拍进一次 Trap（实测无异常的控制流程序被计成 17 次 flush）。
            memwb_valid     <= 0;
            memwb_exc_valid <= 0;

            // Trap 接受当拍不得再把 EX/MEM 的指令送进 WB：那条属于出错指令的后继，
            // 必须整体取消（§5.1 第 2 条）。
            // mdu_block 同理必须挡住这次转移：除法停顿期间 EX/MEM 被冻住不前进，
            // 若这里照常每拍把同一条记录送进 WB，它就会**每拍退休一次**
            //（实测：一条 mulhu 被重复退休 33 次，寄存器写、提交 trace 与
            // minstret 全部被放大）。停顿期间 WB 应当空着，等停顿结束后
            // EX/MEM 那条指令再退休一次。
            if (mem_done && !trap_take && !exmem_retired) begin
                // 异常记录**不能**被 trap_take 门控：Trap 的接受点就在 WB，
                // 判据正是本次要写入的 wb_exc_next。这里若一起清掉就会死锁
                // （"永远判不出异常"）。被 trap_take 门控的只允许是产生架构
                // 副作用的信号——提交记录与写回，见 wb_fire 的定义。
                memwb_valid    <= exmem_valid;
                memwb_pc       <= exmem_pc;
                memwb_inst     <= exmem_inst;
                memwb_alu      <= exmem_alu;
                memwb_imm      <= exmem_imm;
                memwb_rd       <= exmem_rd;
                memwb_result   <= exmem_result;
                memwb_regwrite <= exmem_regwrite;
                memwb_memwrite <= exmem_memwrite;
                memwb_sdata    <= ls_store;
                memwb_wstrb    <= ls_wstrb;
                memwb_mem      <= ls_load;
                memwb_error    <= exmem_error || (exmem_access && (ls_misaligned || d_rsp_error));
                // 只有"本条指令自己"记录的异常才随它进入 WB。若本条没有异常，
                // 即使 exmem 处于等待状态也不能借用别人的原因码。
                // 判据必须用合并后的 wb_exc_next，而不是只比 exmem_exc_cause：
                // 访存访问错误（E-05/E-07）是在 MEM 级等下游响应回来才知道的，
                // exmem 里的记录一直是 NONE；只比 exmem 会让它永远进不了 WB，
                // 于是访问错误既不陷入 Trap、也不取消写回，反而照常提交
                // （实测 lw 越界后 rf.regs[3] 被写、mcause 停留在上一个原因）。
                memwb_exc_valid <= exmem_valid && (wb_exc_next != EXC_NONE);
                memwb_exc_cause <= wb_exc_next;
                memwb_next_pc   <= exmem_next_pc;
                memwb_trap_mret <= exmem_trap_mret;
                // 这条 EX/MEM 记录已经退休过，不许再退休第二次。
                exmem_retired   <= 1'b1;
            end

            // EX/MEM 因访存响应而停住时，ID/EX 也必须保持。若这期间生产者在
            // WB 退休，只靠瞬时 Forwarding 会在解除暂停后丢失该值；因此把 WB
            // 结果吸收到被保持的操作数中，保证 Store/Branch/JALR 等都不会回退
            // 到进入 ID/EX 时读到的旧 RegFile 值。
            if (mem_block && idex_valid && wb_fire && memwb_regwrite && !memwb_error && memwb_rd != 0) begin
                if (memwb_rd == idex_rs1) begin
                    idex_a <= wb_value;
                end
                if (memwb_rd == idex_rs2) begin
                    idex_b <= wb_value;
                end
            end

            if (exmem_valid && exmem_access) begin
                if (dstate == D_REQ && d_req_ready) begin
                    dstate <= D_RSP;
                end
                if (dstate == D_RSP && d_rsp_valid && d_rsp_ready) begin
                    dstate <= D_IDLE;
                end
            end

            if (!mem_block) begin
                if (trap_take) begin
                    // Trap 接受当拍，EX/MEM 里那条更年轻的指令必须被清掉。
                    // 只门控"进入 EX/MEM 的那一条"是不够的：EX/MEM 中**已经在场**的
                    // 那条指令下一拍照样会进入 WB 退休（实测表现为"出错指令的后继
                    // 指令仍然写寄存器"，§5.1 第 2 条不满足）。
                    exmem_valid <= 0;
                    exmem_retired <= 1'b0;
                end else if ((mem_done || !exmem_valid) && !mdu_block) begin
                    exmem_valid    <= idex_valid;
                    // 新指令换进来，退休标记随之清零（本行必须在上面的 MEM→WB 之后，
                    // 非阻塞赋值后写者优先，同拍换入时以"新指令还没退休"为准）。
                    exmem_retired  <= 1'b0;
                    exmem_error    <= idex_error;
                    exmem_pc       <= idex_pc;
                    exmem_inst     <= idex_inst;
                    exmem_alu      <= ex_result;
                    exmem_store    <= srcb0;
                    exmem_imm      <= idex_imm;
                    exmem_rd       <= idex_rd;
                    exmem_f3       <= idex_f3;
                    exmem_regwrite <= idex_regwrite;
                    exmem_memread  <= idex_memread;
                    exmem_memwrite <= idex_memwrite;
                    // CSR 指令的写回值就是 CSR 旧值：ex_result 在 EX 级已经按
                    // idex_csr_en 换成了 csr_rdata（见 csr_rdata 附近的定义）。
                    exmem_result   <= idex_result;
                    // 异常记录"先到先得"：本条指令已有的更老异常优先
                    exmem_exc_cause <= idex_valid ? ex_exc_cause : EXC_NONE;
                    // 出错指令的恢复地址默认就是它自己的 PC（它不会退休）；
                    // 唯一的例外是访存访问错误——那条指令可能已经完成总线写，
                    // 此时把恢复地址推进到 PC+4（§4.1）。
                    // 恢复地址一律取本条指令自己的 PC；唯一的例外（Store 访问错误
                    // 已经完成总线写）在 WB 级按 wb_exc_cause 单独处理，
                    // 因为那要等下游响应才知道，EX 级判不出来。
                    exmem_next_pc   <= ex_next_pc;
                    exmem_trap_mret <= idex_valid && idex_trap_mret;
                    if (idex_valid && (idex_memread || idex_memwrite)) begin
                        dstate <= D_REQ;
                    end
                end

                if (ex_redirect || trap_take) begin
                    // Redirect / Trap 当拍必须把 ID/EX 整条清成气泡，而不只是把
                    // valid 拉低。原因：ID/EX 的译码字段（illegal/ebreak/ecall/csr_en）
                    // 是寄存器，只清 valid 会让它们一直停在旧值上；一旦有路径漏读
                    // 一次 valid，这些陈旧字段就会被当成"真指令"执行——实测表现是
                    // "被跳转跳过的 EBREAK 仍然触发 Trap"。字段一起清零后，即使
                    // valid 再次被漏读，ID/EX 看起来也只是一条 NOP。
                    idex_valid <= 0;
                    idex_pc    <= 0;
                    idex_inst  <= 0;
                    idex_error <= 0;
                    idex_regwrite    <= 0;
                    idex_memread     <= 0;
                    idex_memwrite    <= 0;
                    idex_branch      <= 0;
                    idex_jump        <= 0;
                    idex_jalr        <= 0;
                    idex_illegal     <= 0;
                    idex_csr_en      <= 0;
                    idex_csr_imm     <= 0;
                    idex_csr_funct   <= 2'b00;
                    idex_trap_ecall  <= 0;
                    idex_trap_ebreak <= 0;
                    idex_trap_mret   <= 0;
                    idex_exc_cause   <= EXC_NONE;
                    idex_mdu_en      <= 0;
                    idex_mdu_op      <= 3'b000;
                    ifid_valid <= 0;
                    fetch_pc   <= redirect_pc;
                    if (if_rsp && !if_accept) begin
                        if_discard <= 1;
                    end
                    // 注意：这里**绝对不能**改写 if_req_addr_reg。
                    // 如果本拍 if_req 已经把一笔请求锁存在 if_req_addr_reg 中等待 ready，
                    // 而 if_present_addr 又选择它作为对外展示地址，那么改写它就会让
                    // "valid && !ready 时请求字段保持稳定"这条要求当场破掉
                    // （实测报 I REQUEST STABILITY FAIL addr=00000000 held=0000004c）。
                    // 已锁存的那笔请求属于错误路径，只把它标记成丢弃即可；
                    // 重定向目标地址已经写进 fetch_pc，等这笔请求收干后由
                    // 下面的"重新登记"用它建立新请求。
                    if (if_arm && !if_request_accept) begin
                        // 把"正在展示的 if_arm 请求"转成"已锁存的 if_req 请求"。
                        // 锁存它当前展示的地址（if_arm_addr_reg），而不是改写后的
                        // fetch_pc：Redirect 当拍 fetch_pc 已经变成重定向目标，
                        // 若在这里锁存新目标，对外展示的地址会在 valid 仍为 1、
                        // ready 仍为 0 的情况下从旧值跳到新值，当场破掉
                        // interfaces.md §3 的请求稳定性要求
                        // （实测 I REQUEST STABILITY FAIL addr=00000000 held=0000004c）。
                        if_req             <= 1;
                        if_req_addr_reg    <= fetch_pc;
                        if_req_pred_hit    <= predictor_hit;
                        if_req_pred_taken  <= predictor_taken;
                        if_req_pred_target <= predictor_target_eff;
                    end
                    if (if_arm) begin
                        if_arm <= 0;
                    end
                    if (if_req || if_arm) begin
                        if_req_discard <= 1;
                    end
                end else if (load_use) begin
                    idex_valid <= 0;
                end else if (mdu_block) begin
                    // 除法迭代期间把 ID/EX 原地冻住：既不写新指令进来，也不把
                    // 它送进 EX/MEM（上面那条转移已被 !mdu_block 挡住）。
                    // IF/ID 同样保持（ifid_valid 不在这里改），因此下游返回的
                    // 取指响应不会被接收——与前递无关，纯粹是为了让这条指令
                    // 原样留在 EX 等 32 拍结果。
                end else begin
                    idex_valid        <= ifid_valid;
                    idex_error        <= ifid_error || dec_illegal;
                    idex_pc           <= ifid_pc;
                    idex_inst         <= ifid_inst;
                    idex_a            <= id_a;
                    idex_b            <= id_b;
                    idex_imm          <= dec_imm;
                    idex_rs1          <= dec_rs1;
                    idex_rs2          <= dec_rs2;
                    idex_rd           <= dec_rd;
                    idex_f3           <= dec_f3;
                    idex_pred_hit     <= ifid_pred_hit;
                    idex_pred_taken   <= ifid_pred_taken;
                    idex_pred_target  <= ifid_pred_target;
                    idex_regwrite     <= dec_rw && !dec_illegal;
                    idex_memread      <= dec_mr && !dec_illegal;
                    idex_memwrite     <= dec_mw && !dec_illegal;
                    idex_branch       <= dec_br && !dec_illegal;
                    idex_jump         <= dec_jmp && !dec_illegal;
                    idex_jalr         <= dec_jalr && !dec_illegal;
                    idex_asa          <= dec_asa;
                    idex_asb          <= dec_asb;
                    idex_alu          <= dec_alu;
                    idex_result       <= dec_result;
                    // Zicsr / SYSTEM 控制位：非法指令一律不带这些位，保证
                    // "未实现编码只产生非法指令异常，不做任何 CSR 访问"。
                    idex_illegal      <= dec_illegal;
                    idex_csr_en       <= dec_csr_en && !dec_illegal;
                    idex_csr_imm      <= dec_csr_imm;
                    idex_csr_funct    <= dec_csr_funct;
                    idex_trap_ecall   <= dec_trap_ecall && !dec_illegal;
                    idex_trap_ebreak  <= dec_trap_ebreak && !dec_illegal;
                    idex_trap_mret    <= dec_trap_mret && !dec_illegal;
                    // M 扩展控制位与 Zicsr 同理：非法指令一律不带，保证"未实现
                    // 编码只产生非法指令异常"，不会顺手做一次乘除法。
                    idex_mdu_en       <= dec_mdu_en && !dec_illegal;
                    idex_mdu_op       <= dec_mdu_op;
                    // 异常记录"先到先得"：IF/ID 已带异常就保持，EX 级不得覆盖
                    idex_exc_cause    <= ifid_exc_cause;
                    ifid_valid        <= 0;
                end
            end

            if (if_accept) begin
                if_rsp <= 0;
                if (if_discard || ex_redirect || trap_take) begin
                    if_discard <= 0;
                end else begin
                    ifid_valid         <= 1;
                    ifid_error         <= i_rsp_error;
                    ifid_pc            <= fetch_req_pc;
                    ifid_inst          <= i_rsp_error ? 0 : i_rsp_data;
                    ifid_pred_hit      <= fetch_req_pred_hit;
                    ifid_pred_taken    <= fetch_req_pred_taken;
                    ifid_pred_target   <= fetch_req_pred_target;
                end
            end

            if (if_request_accept) begin
                if_req                <= 0;
                if_arm                <= 0;
                fetch_req_pc          <= if_present_addr;
                fetch_req_pred_hit    <= if_present_pred_hit;
                fetch_req_pred_taken  <= if_present_pred_taken;
                fetch_req_pred_target <= if_present_pred_target;
                if_rsp                <= 1;
                if (if_req_discard || ex_redirect || trap_take) begin
                    if_discard     <= 1;
                    if_req_discard <= 0;
                end else begin
                    fetch_pc <= if_present_pred_taken ? if_present_pred_target
                                                      : (if_present_addr + 4);
                    // 关键：请求被接收的当拍立刻武装下一笔请求，使下一拍直接以 fetch_pc 展示它。
                    // 这样“旧响应被接收”的那一拍同时就是“新请求被接受”的那一拍，取指达到每拍一条。
                    // 展示地址同时锁进 if_arm_addr_reg，之后 Redirect 改 fetch_pc 也不会
                    // 影响这笔已在场请求对外展示的地址（请求稳定性要求）。
                    if_arm   <= 1;
                end
            end

            // 冷启动 / Redirect / Trap 后的重新登记：没有请求在场时，下一拍用 fetch_pc 建立请求。
            // 这里**只**用 ex_redirect：A3 的 ex_redirect 已经包含 trap_take 与 mret_redirect，
            // 再写一次 trap_take 是冗余条件，容易让人误以为两者可以不同。
            if (!if_req && !if_arm && !ex_redirect) begin
                if_req             <= 1;
                if_req_addr_reg    <= fetch_pc;
                if_req_pred_hit    <= predictor_hit;
                if_req_pred_taken  <= predictor_taken;
                if_req_pred_target <= predictor_target_eff;
                if_req_discard     <= 0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Trace 输出
    //-------------------------------------------------------------------------
    assign trace_valid       = wb_fire;
    assign trace_error       = wb_fire && memwb_error;
    assign trace_pc          = wb_fire ? memwb_pc  : 0;
    assign trace_instruction = wb_fire ? memwb_inst : 0;
    assign trace_rd_we       = wb_fire && memwb_regwrite && !memwb_error && memwb_rd != 0;
    assign trace_rd_addr     = trace_rd_we ? memwb_rd : 0;
    assign trace_rd_data     = trace_rd_we ? wb_value  : 0;
    assign trace_mem_we      = wb_fire && memwb_memwrite && !memwb_error;
    assign trace_mem_addr    = trace_mem_we ? memwb_alu    : 0;
    assign trace_mem_data    = trace_mem_we ? memwb_sdata  : 0;
    assign trace_mem_wstrb   = trace_mem_we ? memwb_wstrb  : 0;

endmodule