`timescale 1ns/1ps
// S4 集成用：把 D-Cache 接在 Core 数据端口与 SoC 互连之间，并可选地让 RAM 后端变慢。
//
// ## 为什么需要这一层
//
// `rtl/soc_dcache_2way.v` 的下游侧是"行读 + 连拍 + 单笔写"，
// 而工程的 `soc_data_interconnect` 是"单笔 read / 单笔 write"。这层薄适配把两者接起来。
// 它完全位于 **Core 外部**，不改变 Core 的任何接口。
//
// ## 为什么做成纯组合（重要，踩过坑）
//
// 第一版用了一个 `AD_IDLE/AD_RD` 状态机 + 延迟计数器来"逐字取行"，
// 结果 CoreMark 卡死在第一条分支上（`retired=7`，pc=0x18 反复重试）。
// 排查后确认：**问题在那层多余的握手层次自己引入的死锁**，不是 Cache 的问题
// ——同一份 TB 在 `ENABLE_DCACHE=0` 下 cycles=1,251,724，与加入之前完全一致。
//
// 所以这里改成**纯组合转发**：Cache 的 `m_rd_valid` 直接接到互连，
// 地址由一个组合维护的读指针给出，收到一个响应就前进一个字。
// "连拍"于是自然产生：请求保持有效、响应逐拍返回，整行取完后由 Cache 撤下 `m_rd_valid`。
//
// ## 为什么要有 SLOW_RD_LATENCY
//
// S3 的教训：评价 Cache 必须**说明后端有多慢**。
//   - `SLOW_RD_LATENCY = 0`：与工程现有 `ram_adapter` 等价的零等待后端；
//   - `> 0`：每次读多等若干拍，代表 DDR3 那类真实慢后端。
// 同一次 CoreMark 跑两遍（D-Cache Off / On），就能在**真实程序**上得到 Off/On。
module dcache_coremark_adapter #(
    parameter CACHE_EN        = 0,
    parameter SLOW_RD_LATENCY = 0,      // 仅用于文档说明；实际延迟由 slow_ram_adapter 实现
    parameter SETS            = 32,
    parameter [31:0] CACHEABLE_LAST_ADDR = 32'h0000_FFFF
) (
    input  wire        clk,
    input  wire        reset,
    // ---- Core 侧（与 soc_data_interconnect 的 cpu_* 端口同构）----
    input  wire        cpu_req_valid,
    output wire        cpu_req_ready,
    input  wire [31:0] cpu_req_addr,
    input  wire        cpu_req_write,
    input  wire [31:0] cpu_req_wdata,
    input  wire [3:0]  cpu_req_wstrb,
    output wire        cpu_rsp_valid,
    input  wire        cpu_rsp_ready,
    output wire [31:0] cpu_rsp_rdata,
    output wire        cpu_rsp_error,
    // ---- 下行：发往互连的 RAM 目标端口 ----
    output wire        ram_req_valid,
    input  wire        ram_req_ready,
    output wire [31:0] ram_req_addr,
    output wire        ram_req_write,
    output wire [31:0] ram_req_wdata,
    output wire [3:0]  ram_req_wstrb,
    input  wire        ram_rsp_valid,
    output wire        ram_rsp_ready,
    input  wire [31:0] ram_rsp_rdata,
    input  wire        ram_rsp_error,
    // ---- 统计 ----
    output wire [31:0] stat_hits,
    output wire [31:0] stat_misses,
    output wire [31:0] stat_bypass,
    output wire [31:0] stat_forward
);
    // Cache 下行侧
    wire        c_rd_valid, c_rd_ready, c_beat_valid, c_beat_ready;
    wire        c_beat_last, c_beat_error;
    wire [31:0] c_rd_addr, c_beat_data;
    wire [7:0]  c_rd_len;
    wire        c_wr_valid, c_wr_ready;
    wire [31:0] c_wr_addr, c_wr_wdata;
    wire [3:0]  c_wr_strb;

    soc_dcache_2way #(
        .SETS(SETS), .WAYS(2), .LINE_BYTES(32),
        .CACHE_EN(CACHE_EN), .CACHEABLE_LAST_ADDR(CACHEABLE_LAST_ADDR)
    ) u_cache (
        .clk(clk), .reset(reset),
        .req_valid(cpu_req_valid), .req_ready(cpu_req_ready), .req_addr(cpu_req_addr),
        .req_write(cpu_req_write), .req_wdata(cpu_req_wdata), .req_wstrb(cpu_req_wstrb),
        .rsp_valid(cpu_rsp_valid), .rsp_ready(cpu_rsp_ready), .rsp_rdata(cpu_rsp_rdata),
        .rsp_error(cpu_rsp_error),
        .m_rd_valid(c_rd_valid), .m_rd_ready(c_rd_ready), .m_rd_addr(c_rd_addr),
        .m_rd_len(c_rd_len),
        .m_beat_valid(c_beat_valid), .m_beat_ready(c_beat_ready),
        .m_beat_data(c_beat_data), .m_beat_last(c_beat_last),
        .m_beat_error(c_beat_error),
        .m_wr_valid(c_wr_valid), .m_wr_ready(c_wr_ready), .m_wr_addr(c_wr_addr),
        .m_wr_data(c_wr_wdata), .m_wr_strb(c_wr_strb),
        .stat_hits(stat_hits), .stat_misses(stat_misses), .stat_bypass(stat_bypass),
        .stat_writes(), .stat_forward(stat_forward),
        .stat_bus_cycles(), .stat_core_wait(), .stat_rsp_accepted()
    );

    // =========================================================================
    // 读：把"行请求"接成互连上的连续单笔读
    // =========================================================================
    // ## 与 Cache 的真实协议（两级都踩过坑，务必看清）
    //
    // Cache 侧的 `m_rd_*` 语义是：**举一拍的"行请求"，然后等下游把整行喂完**：
    //   1. `m_rd_valid` 抬起、`m_rd_ready` 被接受 -> Cache 离开 S_REQ 进 S_RFIL，
    //      **并立刻撤下 `m_rd_valid`**（它认为行请求已经"交付"给下游了）；
    //   2. 之后它只等 `m_beat_valid` 逐拍送数据，直到 `m_beat_last`。
    //
    // 于是一个"逐字向互连取 8 拍"的适配器**不能**直接把 `m_rd_valid` 接到互连上
    //   —— 请求只举一拍，互连侧根本没机会把 8 个字取完。
    // 正确做法：**适配器自己先把整行取进一个行缓冲，再逐拍喂给 Cache**。
    //   （这正是 S2 的 `soc_line_burst_adapter` 干的事；
    //     真正的硬件里这一层本该由 DDR3 控制器/HMIC 的行突发接口承担，
    //     这里的适配器是"用单笔互连模拟行后端"的测试用替代品。）
    //
    // ## 状态
    //   LF_IDLE : 等 Cache 的行请求
    //   LF_FETCH: 逐字向互连取满一整行，写进行缓冲
    //   LF_FEED : 把行缓冲逐拍喂给 Cache（等 Cache 进 S_RFIL 收数据）
    parameter LINE_WORDS = 8;

    localparam LF_IDLE  = 2'd0;
    localparam LF_FETCH = 2'd1;
    localparam LF_FEED  = 2'd2;

    reg [1:0]      lf_state;
    reg [31:0]     lf_base;
    reg [31:0]     lf_ptr;
    reg [3:0]      lf_idx;          // 已取到第几个字
    reg [3:0]      lf_feed;
    reg [7:0]      lf_len;          // 本次请求要取几个字 - 1（= Cache 的 m_rd_len）         // 已喂到第几个字
    reg [31:0]     lf_buf [0:LINE_WORDS-1];
    reg            lf_err;
    reg            lf_rsp_pending;  // 已向互连发出一次读，等响应

    // 行缓冲的组合读出口
    wire [31:0] lf_out = lf_buf[lf_feed];
    wire [7:0]  lf_words = lf_len + 8'd1;   // 本次要取/要喂的字数

    // Cache 行请求被接受：进入取行
    wire lf_start = c_rd_valid && c_rd_ready;

    assign c_rd_ready = (lf_state == LF_IDLE);

    // 取行阶段的读请求
    wire lf_fetching = (lf_state == LF_FETCH) && !lf_rsp_pending;

    // 下行端口仲裁：写优先（写只在 LF_IDLE 时可能到来，Cache 不会在填充期间写）
    assign ram_req_valid = c_wr_valid | lf_fetching;
    assign ram_req_addr  = c_wr_valid ? c_wr_addr : lf_ptr;
    assign ram_req_write = c_wr_valid;
    assign ram_req_wdata = c_wr_wdata;
    assign ram_req_wstrb = c_wr_strb;
    assign ram_rsp_ready = 1'b1;
    assign c_wr_ready    = ram_req_ready && (lf_state == LF_IDLE);

    // 喂给 Cache 的数据拍（只在 LF_FEED 阶段）
    assign c_beat_valid = (lf_state == LF_FEED);
    assign c_beat_data  = lf_out;
    assign c_beat_error = lf_err;
    assign c_beat_last  = (lf_state == LF_FEED) && (lf_feed == (lf_words - 8'd1));

    integer j;

    always @(posedge clk) begin
        if (reset) begin
            lf_state       <= LF_IDLE;
            lf_base        <= 32'd0;
            lf_ptr         <= 32'd0;
            lf_idx         <= 4'd0;
            lf_feed        <= 4'd0;
            lf_len         <= 8'd0;
            lf_err         <= 1'b0;
            lf_rsp_pending <= 1'b0;
            for (j = 0; j < LINE_WORDS; j = j + 1) lf_buf[j] <= 32'd0;
        end
        else begin
            case (lf_state)
                LF_IDLE : begin
                    if (lf_start) begin
                        lf_base        <= c_rd_addr;
                        lf_ptr         <= c_rd_addr;
                        lf_idx         <= 4'd0;
                        lf_feed        <= 4'd0;
                        lf_len         <= c_rd_len;
                        lf_err         <= 1'b0;
                        lf_rsp_pending <= 1'b0;
                        lf_state       <= LF_FETCH;
                    end
                end
                LF_FETCH : begin
                    if (!lf_rsp_pending && ram_req_ready) begin
                        // 接受一次读请求，等它的响应
                        lf_rsp_pending <= 1'b1;
                    end
                    else if (ram_rsp_valid) begin
                        lf_buf[lf_idx] <= ram_rsp_rdata;
                        lf_err         <= ram_rsp_error;
                        lf_rsp_pending <= 1'b0;
                        if (lf_idx == (lf_words - 8'd1)) begin
                            lf_state <= LF_FEED;        // 整行取完 -> 开始喂
                            lf_feed  <= 4'd0;
                        end
                        else begin
                            lf_idx <= lf_idx + 4'd1;
                            lf_ptr <= lf_ptr + 32'd4;
                        end
                    end
                end
                LF_FEED : begin
                    // Cache 在 S_RFIL 会一直给 m_beat_ready；这里逐拍推进
                    if (c_beat_valid && c_beat_ready) begin
                        if (lf_feed == (lf_words - 8'd1)) begin
                            lf_state <= LF_IDLE;        // 整行喂完
                        end
                        else begin
                            lf_feed <= lf_feed + 4'd1;
                        end
                    end
                end
                default : lf_state <= LF_IDLE;
            endcase
        end
    end
endmodule

// =============================================================================
// 慢速 RAM 模型：与 ram_adapter 同接口，但每次读可多等 SLOW_RD_LATENCY 拍。
// 用来在同一份 CoreMark 上分别模拟"零等待片上 BRAM"与"慢后端（DDR3 那类）"。
// =============================================================================
module slow_ram_adapter #(
    parameter DEPTH           = 16384,
    parameter INIT_FILE       = "",
    parameter SLOW_RD_LATENCY = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire        req_write,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wstrb,
    output reg         rsp_valid,
    input  wire        rsp_ready,
    output reg  [31:0] rsp_rdata,
    output reg         rsp_error,
    output reg  [31:0] write_side_effect_count
);
    reg [31:0] mem [0:DEPTH-1];
    reg        busy;
    reg [7:0]  wait_cnt;
    reg [31:0] latched;
    reg        latched_err;
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'd0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    assign req_ready = !busy && !rsp_valid;

    always @(posedge clk) begin
        if (reset) begin
            busy    <= 1'b0;
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'd0;
            rsp_error <= 1'b0;
            wait_cnt  <= 8'd0;
            write_side_effect_count <= 32'd0;
        end
        else begin
            if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;

            if (busy) begin
                if (wait_cnt != 0) begin
                    wait_cnt <= wait_cnt - 8'd1;
                end
                else begin
                    busy      <= 1'b0;
                    rsp_valid <= 1'b1;
                    rsp_rdata <= latched;
                    rsp_error <= latched_err;
                end
            end
            else if (req_valid && req_ready) begin
                busy        <= 1'b1;
                wait_cnt    <= SLOW_RD_LATENCY[7:0];
                latched_err <= (req_addr[31:2] >= DEPTH);
                if (req_write) begin
                    write_side_effect_count <= write_side_effect_count + 32'd1;
                    latched <= 32'd0;
                    if (req_wstrb[0]) mem[req_addr[31:2]][7:0]   <= req_wdata[7:0];
                    if (req_wstrb[1]) mem[req_addr[31:2]][15:8]  <= req_wdata[15:8];
                    if (req_wstrb[2]) mem[req_addr[31:2]][23:16] <= req_wdata[23:16];
                    if (req_wstrb[3]) mem[req_addr[31:2]][31:24] <= req_wdata[31:24];
                end
                else begin
                    latched <= (req_addr[31:2] >= DEPTH) ? 32'd0 : mem[req_addr[31:2]];
                end
            end
        end
    end
endmodule
