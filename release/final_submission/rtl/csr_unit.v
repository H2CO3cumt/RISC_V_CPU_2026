// 机器模式 CSR（控制状态寄存器）单元 —— RV32I + Zicsr 的机器模式子集。
//
// 支持矩阵、异常原因编码、优先级和验收条目以 `docs/trap_contract.md` 为唯一契约；
// 本文件只实现契约里"必须实现"的表，未列出的 CSR 一律按未定义处理：
// 读或写都产生非法指令异常，绝不静默读 0 或静默忽略写。
//
// 为什么把 CSR 单独做成一个模块：
//  1. 它是纯架构状态（reset 后必须回到确定初值），与流水线时序解耦，可以独立 Testbench 验收；
//  2. 流水线里所有"要不要进入 Trap"的判断都只是组合查询 `trap_take`，
//     真正动状态只发生在 `trap_enter` / `trap_return` 这两个单周期脉冲上。
//
// 关于 mepc 的取值口径（容易搞错，先写清楚）：
//  进入 Trap 时 `epc_next` 取的是**下一条将要执行的指令地址**（上层在
//  异常/中断那一刻组合计算好），而不是"出错指令的 PC"。
//  这样两种情形都自动正确：
//    - 同步异常：异常指令被取消、没有退休，上层给出的"下一条"就是它自己的 PC；
//    - 中断：中断点之前那条指令正常退休，上层给出的"下一条"就是还没执行的指令，
//      MRET 之后从那里继续，不会重复执行。
module csr_unit (
    input  wire        clk,
    input  wire        reset,

    // CSR 读（组合）
    input  wire [11:0] csr_addr,
    output reg  [31:0] csr_rdata,

    // CSR 写（单周期脉冲，已经由上层做过优先级筛选）
    input  wire        csr_we,
    input  wire [11:0] csr_waddr,
    input  wire [31:0] csr_wdata,

    // CSR 合法性：为 0 表示地址未实现或只读却要写 → 上层产生非法指令异常
    input  wire        csr_check_en,
    input  wire [11:0] csr_check_addr,
    input  wire        csr_check_write,
    output wire        csr_illegal,

    // Trap 进入 / 返回（单周期脉冲，互斥）
    input  wire        trap_enter,
    input  wire [31:0] trap_cause,
    input  wire [31:0] trap_value,
    input  wire [31:0] epc_next,
    input  wire        trap_return,

    // 中断挂起位（由 Core 外部中断输入驱动，只读）
    input  wire        irq_sw_pending,
    input  wire        irq_timer_pending,
    input  wire        irq_ext_pending,

    // 退休事件，用于 minstret
    input  wire        retire,

    // 对上层暴露的若干状态
    output wire        mstatus_mie,
    output wire        mie_mtie,
    output wire        mie_meie,
    output wire        mie_msie,
    output wire [31:0] mtvec_base,
    output wire [31:0] epc_out
);

    //-------------------------------------------------------------------------
    // CSR 编号
    //-------------------------------------------------------------------------
    localparam [11:0] CSR_MSTATUS  = 12'h300;
    localparam [11:0] CSR_MISA     = 12'h301;
    localparam [11:0] CSR_MIE      = 12'h304;
    localparam [11:0] CSR_MTVEC    = 12'h305;
    localparam [11:0] CSR_MSCRATCH = 12'h340;
    localparam [11:0] CSR_MEPC     = 12'h341;
    localparam [11:0] CSR_MCAUSE   = 12'h342;
    localparam [11:0] CSR_MTVAL    = 12'h343;
    localparam [11:0] CSR_MIP      = 12'h344;
    localparam [11:0] CSR_CYCLE    = 12'hC00;
    localparam [11:0] CSR_CYCLEH   = 12'hC80;
    localparam [11:0] CSR_INSTRET  = 12'hC02;
    localparam [11:0] CSR_INSTRETH = 12'hC82;

    //-------------------------------------------------------------------------
    // 架构状态
    //-------------------------------------------------------------------------
    reg        mstatus_mie_q;
    reg        mstatus_mpie_q;
    reg        mie_msie_q;
    reg        mie_mtie_q;
    reg        mie_meie_q;
    reg [31:0] mtvec_q;
    reg [31:0] mscratch_q;
    reg [31:0] mepc_q;
    reg [31:0] mcause_q;
    reg [31:0] mtval_q;
    reg [63:0] mcycle_q;
    reg [63:0] minstret_q;

    // mstatus 只实现 MIE[3] / MPIE[7] / MPP[12:11]，MPP 恒 00（只有 M 模式）。
    // 位段必须逐个对齐写死：{19, 2(MPP), 4(10:7), MPIE(7), 3(6:4), MIE(3), 3(2:0)}。
    wire [31:0] mstatus_rdata = {19'b0, 2'b00, 4'b0, mstatus_mpie_q,
                                 3'b0, mstatus_mie_q, 3'b0};

    // mie 只实现 MSIE[3] / MTIE[7] / MEIE[11]。
    // 位段：{20, MEIE(11), 3(10:8), MTIE(7), 3(6:4), MSIE(3), 3(2:0)}。
    wire [31:0] mie_rdata = {20'b0, mie_meie_q, 3'b0, mie_mtie_q,
                             3'b0, mie_msie_q, 3'b0};

    // mip 是只读窗口，直接反映 Core 外部的中断输入电平，不锁存、不清除。
    // 位段与 mie 对齐。
    wire [31:0] mip_rdata = {20'b0, irq_ext_pending, 3'b0, irq_timer_pending,
                             3'b0, irq_sw_pending, 3'b0};

    // misa：MXL=1（32-bit），只有 I 扩展（bit 8）。只读。
    wire [31:0] misa_rdata = 32'h4000_0100;

    // mtvec：只支持 Direct 模式，mode[1:0] 写入后被强制为 00。
    wire [31:0] mtvec_rdata = {mtvec_q[31:2], 2'b00};

    //-------------------------------------------------------------------------
    // CSR 读：组合，供 EX 级使用
    //-------------------------------------------------------------------------
    always @(*) begin
        case (csr_addr)
            CSR_MSTATUS:  csr_rdata = mstatus_rdata;
            CSR_MISA:     csr_rdata = misa_rdata;
            CSR_MIE:      csr_rdata = mie_rdata;
            CSR_MTVEC:    csr_rdata = mtvec_rdata;
            CSR_MSCRATCH: csr_rdata = mscratch_q;
            CSR_MEPC:     csr_rdata = mepc_q;
            CSR_MCAUSE:   csr_rdata = mcause_q;
            CSR_MTVAL:    csr_rdata = mtval_q;
            CSR_MIP:      csr_rdata = mip_rdata;
            CSR_CYCLE:    csr_rdata = mcycle_q[31:0];
            CSR_CYCLEH:   csr_rdata = mcycle_q[63:32];
            CSR_INSTRET:  csr_rdata = minstret_q[31:0];
            CSR_INSTRETH: csr_rdata = minstret_q[63:32];
            default:      csr_rdata = 32'b0;
        endcase
    end

    // 只读 CSR：写它们必须报非法指令异常，且不得改动任何状态。
    wire addr_read_only = (csr_check_addr == CSR_MISA) ||
                          (csr_check_addr == CSR_MIP) ||
                          (csr_check_addr == CSR_CYCLE) ||
                          (csr_check_addr == CSR_CYCLEH) ||
                          (csr_check_addr == CSR_INSTRET) ||
                          (csr_check_addr == CSR_INSTRETH);

    wire addr_implemented = (csr_check_addr == CSR_MSTATUS) ||
                            (csr_check_addr == CSR_MISA) ||
                            (csr_check_addr == CSR_MIE) ||
                            (csr_check_addr == CSR_MTVEC) ||
                            (csr_check_addr == CSR_MSCRATCH) ||
                            (csr_check_addr == CSR_MEPC) ||
                            (csr_check_addr == CSR_MCAUSE) ||
                            (csr_check_addr == CSR_MTVAL) ||
                            (csr_check_addr == CSR_MIP) ||
                            (csr_check_addr == CSR_CYCLE) ||
                            (csr_check_addr == CSR_CYCLEH) ||
                            (csr_check_addr == CSR_INSTRET) ||
                            (csr_check_addr == CSR_INSTRETH);

    assign csr_illegal = csr_check_en &&
                         (!addr_implemented ||
                          (csr_check_write && addr_read_only));

    //-------------------------------------------------------------------------
    // 状态更新
    //
    // 优先级（同周期只会有一个动作，顺序写在这里是为了让"谁优先"一目了然）：
    //   1. reset：所有 CSR 回到确定初值，中断使能必须是关的；
    //   2. trap_return（MRET）：MIE <- MPIE，MPIE <- 1，并从 mepc 继续；
    //   3. trap_enter：MIE <- 0（关中断，避免 Trap entry 立刻被同一中断再打断），
    //      MPIE <- 旧 MIE，MPP <- 00；mcause/mtval/mepc 按上层给出的值写入；
    //   4. 普通 CSR 写：按掩码更新，未实现位读 0、写忽略。
    //-------------------------------------------------------------------------
    // 写掩码同样按位段对齐：只抽取实现位的值，其余位写忽略。
    wire mstatus_mie_in  = csr_wdata[3];
    wire mstatus_mpie_in = csr_wdata[7];
    wire mie_msie_in     = csr_wdata[3];
    wire mie_mtie_in     = csr_wdata[7];
    wire mie_meie_in     = csr_wdata[11];
    wire [31:0] mtvec_write = {csr_wdata[31:2], 2'b00};

    always @(posedge clk) begin
        if (reset) begin
            mstatus_mie_q  <= 1'b0;
            mstatus_mpie_q <= 1'b0;
            mie_msie_q     <= 1'b0;
            mie_mtie_q     <= 1'b0;
            mie_meie_q     <= 1'b0;
            mtvec_q        <= 32'b0;
            mscratch_q     <= 32'b0;
            mepc_q         <= 32'b0;
            mcause_q       <= 32'b0;
            mtval_q        <= 32'b0;
            mcycle_q       <= 64'b0;
            minstret_q     <= 64'b0;
        end
        else begin
            mcycle_q <= mcycle_q + 64'd1;

            if (retire) begin
                minstret_q <= minstret_q + 64'd1;
            end

            if (trap_return) begin
                mstatus_mie_q  <= mstatus_mpie_q;
                mstatus_mpie_q <= 1'b1;
            end
            else if (trap_enter) begin
                mstatus_mie_q  <= 1'b0;
                mstatus_mpie_q <= mstatus_mie_q;
                mepc_q         <= epc_next;
                mcause_q       <= trap_cause;
                mtval_q        <= trap_value;
            end
            else if (csr_we) begin
                case (csr_waddr)
                    CSR_MSTATUS: begin
                        mstatus_mie_q  <= mstatus_mie_in;
                        mstatus_mpie_q <= mstatus_mpie_in;
                    end
                    CSR_MIE: begin
                        mie_msie_q <= mie_msie_in;
                        mie_mtie_q <= mie_mtie_in;
                        mie_meie_q <= mie_meie_in;
                    end
                    CSR_MTVEC:    mtvec_q    <= mtvec_write;
                    CSR_MSCRATCH: mscratch_q <= csr_wdata;
                    CSR_MEPC:     mepc_q     <= {csr_wdata[31:1], 1'b0};
                    CSR_MCAUSE:   mcause_q   <= csr_wdata;
                    CSR_MTVAL:    mtval_q    <= csr_wdata;
                    default: begin
                        // 只读或未实现地址在 csr_illegal 已经被拦住，这里不再动作。
                    end
                endcase
            end
        end
    end

    assign mstatus_mie = mstatus_mie_q;
    assign mie_msie    = mie_msie_q;
    assign mie_mtie    = mie_mtie_q;
    assign mie_meie    = mie_meie_q;
    assign mtvec_base  = mtvec_rdata;
    assign epc_out     = mepc_q;

endmodule
