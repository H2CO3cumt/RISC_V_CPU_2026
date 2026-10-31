// 机器定时器（Core 外部的 SoC 外设）。
//
// 为什么单独做成一个 Core 外部模块：
//   `docs/trap_contract.md` §4.2 规定 M 模式定时器中断（I-02，mcause=0x80000007）
//   的**来源在 SoC**：Core 只接一根设备无关的 irq_timer_i。定时器的计数、比较、
//   清除和 MMIO 寄存器全部属于这里，Core 里没有、也不允许出现 mtime 之类的名字。
//
// 寄存器地图（窗口 0x1000_3000 ~ 0x1000_30FF，字偏移）：
//   +0x00 mtime_lo     读写，每拍 +1（64 位计数器的低 32 位）
//   +0x04 mtime_hi     读写，进位由 mtime_lo 溢出产生
//   +0x08 mtimecmp_lo  读写
//   +0x0C mtimecmp_hi  读写
//   其余偏移            返回 error（不静默当成某个寄存器）
//
// 中断语义（与 RISC-V MTIP 一致）：
//   irq_timer = (mtime >= mtimecmp)，**电平**有效、由硬件比较产生。
//   软件在 ISR 里重写 mtimecmp 即可清除，不需要额外的“清中断”寄存器——
//   这正是 §4.2 要求的“ISR 中重设 mtimecmp 后可再次触发”。
//   复位后 mtimecmp = 全 1，因此在软件第一次编程之前**不会**产生中断请求。
//
// 握手与 gpio_mmio / uart_mmio 完全一致：IDLE 收请求 → RESP 等响应被接收，
// 同一时刻只处理一笔，符合 docs/interfaces.md §2.2 的单 outstanding 约定。
module timer_mmio (
    input  wire        clk,
    input  wire        reset,

    // 来自互连的请求
    input  wire        timer_req_valid,
    output wire        timer_req_ready,
    input  wire [31:0] timer_req_addr,
    input  wire        timer_req_write,
    input  wire [31:0] timer_req_wdata,
    input  wire [3:0]  timer_req_wstrb,

    // 返回互连的响应
    output wire        timer_rsp_valid,
    input  wire        timer_rsp_ready,
    output wire [31:0] timer_rsp_rdata,
    output wire        timer_rsp_error,

    // 聚合后的定时器中断请求，直接接 Core 的 irq_timer_i
    output wire        irq_timer
);

    localparam IDLE = 1'b0;
    localparam RESP = 1'b1;

    reg        cstate;
    reg [31:0] mtime_lo_q;
    reg [31:0] mtime_hi_q;
    reg [31:0] mtimecmp_lo_q;
    reg [31:0] mtimecmp_hi_q;
    reg [31:0] rsp_rdata_reg;
    reg        rsp_error_reg;

    // 只译码字偏移 [7:2]，窗口低两位必须为 0，否则报错（不静默对齐）。
    wire [5:0] word_offset = timer_req_addr[7:2];
    wire       addr_ok     = (timer_req_addr[1:0] == 2'b00) && (word_offset <= 6'd3);

    assign timer_req_ready = (cstate == IDLE);
    assign timer_rsp_valid = (cstate == RESP);
    assign timer_rsp_rdata = rsp_rdata_reg;
    assign timer_rsp_error = rsp_error_reg;

    // 64 位比较：先比高位，高位相等再比低位。用无符号比较，mtimecmp 初值为全 1，
    // 因此复位后 mtime（从 0 开始）永远小于它，irq_timer 恒为 0。
    assign irq_timer = (mtime_hi_q > mtimecmp_hi_q) ||
                       ((mtime_hi_q == mtimecmp_hi_q) && (mtime_lo_q >= mtimecmp_lo_q));

    // 写哪个寄存器由读数据通路决定：这里用组合选择，保证 READ 与 WRITE 语义对称。
    reg [31:0] read_data;
    always @(*) begin
        case (word_offset)
            6'd0:    read_data = mtime_lo_q;
            6'd1:    read_data = mtime_hi_q;
            6'd2:    read_data = mtimecmp_lo_q;
            6'd3:    read_data = mtimecmp_hi_q;
            default: read_data = 32'b0;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            cstate          <= IDLE;
            mtime_lo_q      <= 32'b0;
            mtime_hi_q      <= 32'b0;
            // 复位后不产生中断请求：§4.2 要求中断在软件显式打开之前必须为 0。
            mtimecmp_lo_q   <= 32'hFFFF_FFFF;
            mtimecmp_hi_q   <= 32'hFFFF_FFFF;
            rsp_rdata_reg   <= 32'b0;
            rsp_error_reg   <= 1'b0;
        end
        else begin
            // mtime 是自由计数器：与中断是否使能、是否有请求都无关，每拍 +1。
            mtime_lo_q <= mtime_lo_q + 32'd1;
            if (mtime_lo_q == 32'hFFFF_FFFF) begin
                mtime_hi_q <= mtime_hi_q + 32'd1;
            end

            case (cstate)
                IDLE: begin
                    if (timer_req_valid && timer_req_ready) begin
                        cstate <= RESP;
                        if (!addr_ok) begin
                            rsp_error_reg <= 1'b1;
                            rsp_rdata_reg <= 32'b0;
                        end
                        else if (timer_req_write) begin
                            rsp_error_reg <= 1'b0;
                            rsp_rdata_reg <= 32'b0;
                            case (word_offset)
                                6'd0: begin
                                    if (timer_req_wstrb[0]) mtime_lo_q[7:0]   <= timer_req_wdata[7:0];
                                    if (timer_req_wstrb[1]) mtime_lo_q[15:8]  <= timer_req_wdata[15:8];
                                    if (timer_req_wstrb[2]) mtime_lo_q[23:16] <= timer_req_wdata[23:16];
                                    if (timer_req_wstrb[3]) mtime_lo_q[31:24] <= timer_req_wdata[31:24];
                                end
                                6'd1: begin
                                    if (timer_req_wstrb[0]) mtime_hi_q[7:0]   <= timer_req_wdata[7:0];
                                    if (timer_req_wstrb[1]) mtime_hi_q[15:8]  <= timer_req_wdata[15:8];
                                    if (timer_req_wstrb[2]) mtime_hi_q[23:16] <= timer_req_wdata[23:16];
                                    if (timer_req_wstrb[3]) mtime_hi_q[31:24] <= timer_req_wdata[31:24];
                                end
                                6'd2: begin
                                    if (timer_req_wstrb[0]) mtimecmp_lo_q[7:0]   <= timer_req_wdata[7:0];
                                    if (timer_req_wstrb[1]) mtimecmp_lo_q[15:8]  <= timer_req_wdata[15:8];
                                    if (timer_req_wstrb[2]) mtimecmp_lo_q[23:16] <= timer_req_wdata[23:16];
                                    if (timer_req_wstrb[3]) mtimecmp_lo_q[31:24] <= timer_req_wdata[31:24];
                                end
                                default: begin
                                    if (timer_req_wstrb[0]) mtimecmp_hi_q[7:0]   <= timer_req_wdata[7:0];
                                    if (timer_req_wstrb[1]) mtimecmp_hi_q[15:8]  <= timer_req_wdata[15:8];
                                    if (timer_req_wstrb[2]) mtimecmp_hi_q[23:16] <= timer_req_wdata[23:16];
                                    if (timer_req_wstrb[3]) mtimecmp_hi_q[31:24] <= timer_req_wdata[31:24];
                                end
                            endcase
                        end
                        else begin
                            rsp_error_reg <= 1'b0;
                            rsp_rdata_reg <= read_data;
                        end
                    end
                end
                default: begin
                    // RESP：响应字段保持不变，直到被下游接收。
                    if (timer_rsp_valid && timer_rsp_ready) begin
                        cstate <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
