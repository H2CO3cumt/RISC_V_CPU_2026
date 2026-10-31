// S4：2 路组相联数据 Cache（2-way set-associative D-Cache，写穿 + 写缓冲）。
//
// ## 位置与边界（不得放宽）
//
// 本模块**只能**位于 Core 的统一数据端口与 SoC 互连之间，属于 Core 外部。
// Core 侧端口与 `docs/interfaces.md` §2.2 的语义一字不差（单笔事务、一个未完成请求），
// `rtl/pipeline_cpu.v` 的端口、位宽、事务语义均不受影响。
//
// ## 组织
//
//   默认 32 组 × 2 路 × 8 字/行 = 2 KB。地址划分与 I-Cache 一致：
//     tag = addr[31:12]、set = addr[11:5]、word = addr[4:2]。
//   替换策略：每组 1-bit round-robin。
//
// ## 写策略：写穿 + 写缓冲（**不做写回**）
//
//   为什么不做写回：写回会在"脏行未落盘"时与 Trap/精确异常语义纠缠
//   （异常点必须对应架构可见状态），复杂度差一个量级，而 `handoff_next.md` §3.3
//   明确要求"先做写穿 + 写缓冲"。因此：
//     - 写命中：按 `wstrb` 逐字节合并进本行，**同时**把整笔写发往下游（写穿）；
//     - 写未命中：**不分配**（no-write-allocate），直接发往下游；
//     - 写缓冲：单条目。**写是 posted 的**——Core 的完成响应在写被接受时就给出，
//       写本身的下推由 `S_WBUF` 状态负责；缓冲占满期间 `req_ready=0` 让 Core 等待，
//       从而保证"写顺序"与"响应即表示已被接受"的语义。
//
// ## MMIO 强制绕行（S4 必做项）
//
//   `docs/interfaces.md` §3.2：RAM 是 `0x0000_0000 ~ RAM_LAST_ADDR`，其余
//   （`0x1000_0000` 起的 UART/GPIO/APP/TIMER 及未映射区）**一律不进 Cache**：
//     - 不查表、不分配、不更新行；读直连下游，写直接下推；
//     - 因此 MMIO 的副作用（读清标志、写触发）不会被缓存、合并或重复。
//   `CACHEABLE_LAST_ADDR` 默认 `0x0000_FFFF`（与 CoreMark / 逻辑分析仪工程的 RAM 窗口一致）。
//
// ## Store -> Load 转发（两条来源都必须覆盖）
//
//   1. **已写穿但仍在写缓冲里的那一笔**：地址同字且 `wstrb` 与之相交时，
//      用缓冲里的字节覆盖读回的字节（未选中的字节保持原值）；
//   2. **写命中已就地更新的行**：命中路径读到的本来就是新值。
//   缺任何一条都会出现"读到旧值"的经典错误。
//
// ## 错误语义
//
//   下游返回错误的行**不写入阵列**（不把坏数据缓存成有效行），错误直接透传 Core。
module soc_dcache_2way #(
    parameter SETS              = 32,
    parameter WAYS              = 2,
    parameter LINE_BYTES        = 32,
    // 1 = 使能；0 = 完全直通（Off 开关）。默认 0：未经集成量化前不作为默认配置。
    parameter CACHE_EN          = 0,
    // 可缓存地址上界；严格大于它的地址一律绕行（MMIO）。
    parameter [31:0] CACHEABLE_LAST_ADDR = 32'h0000_FFFF,
    parameter ADDR_WIDTH        = 32
) (
    input  wire                    clk,
    input  wire                    reset,

    // ---------------- Core 侧：与 interfaces.md §2.2 语义一致 ----------------
    input  wire                    req_valid,
    output wire                    req_ready,
    input  wire [ADDR_WIDTH-1:0]   req_addr,
    input  wire                    req_write,
    input  wire [31:0]             req_wdata,
    input  wire [3:0]              req_wstrb,
    output reg                     rsp_valid,
    input  wire                    rsp_ready,
    output reg  [31:0]             rsp_rdata,
    output reg                     rsp_error,

    // ---------------- 下游存储侧 ----------------
    // 读：行请求 + 连拍返回（行读 len=WORDS-1；直连单字读 len=0）
    output reg                     m_rd_valid,
    input  wire                    m_rd_ready,
    output reg  [ADDR_WIDTH-1:0]   m_rd_addr,
    output reg  [7:0]              m_rd_len,
    input  wire                    m_beat_valid,
    output wire                    m_beat_ready,
    input  wire [31:0]             m_beat_data,
    input  wire                    m_beat_last,
    input  wire                    m_beat_error,
    // 写：单笔
    output reg                     m_wr_valid,
    input  wire                    m_wr_ready,
    output reg  [ADDR_WIDTH-1:0]   m_wr_addr,
    output reg  [31:0]             m_wr_data,
    output reg  [3:0]              m_wr_strb,

    // ---------------- 统计 ----------------
    output reg  [31:0]             stat_hits,
    output reg  [31:0]             stat_misses,
    output reg  [31:0]             stat_bypass,       // MMIO 绕行次数
    output reg  [31:0]             stat_writes,
    output reg  [31:0]             stat_forward,      // Store->Load 转发命中次数
    output reg  [31:0]             stat_bus_cycles,
    output reg  [31:0]             stat_core_wait,
    // 诊断用：被 Core 接受（rsp_valid && rsp_ready）的响应笔数。
    // 用来判定集成时"Cache 收走了响应、但 Core 说没收到"到底发生在哪一侧。
    output reg  [31:0]             stat_rsp_accepted
);
    localparam WORDS     = LINE_BYTES / 4;
    localparam WORD_BITS = $clog2(WORDS);
    localparam SET_BITS  = $clog2(SETS);
    localparam LINE_BITS = $clog2(LINE_BYTES);
    localparam OFF_HI    = LINE_BITS + SET_BITS;
    localparam NIL       = 32'hFFFF_FFFF;

    localparam S_IDLE = 3'd0;   // 等 Core 请求 / 判断可缓存性
    localparam S_LOOK = 3'd1;   // 命中判定
    localparam S_RREQ = 3'd2;   // 发行读请求
    localparam S_RFIL = 3'd3;   // 接收读数据
    localparam S_RESP = 3'd4;   // 返回 Core（读）
    localparam S_WBUF = 3'd5;   // 下推写缓冲
    localparam S_RESP_W = 3'd6; // 返回 Core（写事务的完成响应）

    reg [2:0] state, state_n;

    // ---------------- 阵列 ----------------
    reg [31:0] data0 [0:SETS-1][0:WORDS-1];
    reg [31:0] data1 [0:SETS-1][0:WORDS-1];
    reg [31:0] tag0  [0:SETS-1];
    reg [31:0] tag1  [0:SETS-1];
    reg        val0  [0:SETS-1];
    reg        val1  [0:SETS-1];
    reg        rr    [0:SETS-1];

    // ---------------- 被锁存的请求 ----------------
    reg [31:0]          addr_q;
    reg                 write_q;
    reg [31:0]          wdata_q;
    reg [3:0]           wstrb_q;
    reg [SET_BITS-1:0]  set_q;
    reg [WORD_BITS-1:0] word_q;
    reg [31:0]          tag_q;
    reg                 cacheable_q;

    // ---------------- 填充进度 ----------------
    reg [WORD_BITS-1:0] fill_idx;
    reg [31:0]          victim;

    // ---------------- 写缓冲（单条目）----------------
    reg                 wb_valid;
    reg [31:0]          wb_addr;
    reg [31:0]          wb_data;
    reg [3:0]           wb_strb;
    reg                 wb_cacheable;

    // ---------------- 被暂存的请求（skid buffer）----------------
    // 【为什么必须有它 —— 这是把 D-Cache 接进 CoreMark 时卡死的根因】
    //   Core 的 `d_req_valid` 由它自己的 `dstate` 驱动，**不是"保持到被接受"**：
    //   请求被接受的那一拍 `dstate` 就切到 D_RSP，下一拍 `d_req_valid` 立刻落下。
    //   所以下游**不允许"这一拍我不收、你等下再给我"** —— 拒收就等于丢请求。
    //   而写缓冲排空需要 1~2 拍，正好会撞上这个窗口。实测追踪
    //   （`tb/tb_dcache_core_drive.v`）：
    //       [985000] st=5（写缓冲还在排空）
    //       [995000] Core 举出请求，而我们给了 `req_ready=0`
    //       [1005000] 我们排空后放行，可 Core 已经把请求撤了
    //                -> Core 永久停在 D_RSP，Cache 停在 S_IDLE，双方互等
    //   修法：**只要请求在场就立刻收下并暂存字段**，真正处理（查表/填充/写穿）
    //   由内部状态机稍后进行。这样即使写缓冲没排空，也不会丢请求。
    reg                 pend_valid;      // 已收下、待处理的请求
    reg [31:0]          pend_addr;
    reg                 pend_write;
    reg [31:0]          pend_wdata;
    reg [3:0]           pend_wstrb;
    reg                 pend_cacheable;

    wire req_taken = req_valid && req_ready;

    // ---------------- 命中判定（用锁存地址）----------------
    wire hit0 = (WAYS > 1) && val0[set_q] && (tag0[set_q] == tag_q);
    wire hit1 = (WAYS > 1) && val1[set_q] && (tag1[set_q] == tag_q);
    wire hit  = (WAYS == 1) ? (val0[set_q] && (tag0[set_q] == tag_q)) : (hit0 || hit1);
    wire [31:0] hit_word = (WAYS == 1) ? data0[set_q][word_q]
                         : (hit0 ? data0[set_q][word_q] : data1[set_q][word_q]);

    // ---------------- Store -> Load 转发 ----------------
    // 【为什么必须做】写缓冲里那一笔还没到下游，内存里还是旧值；
    //   此时 Load 同一字就会读到旧值，违反 RV32I 单线程内存模型。
    //   只有 `wstrb` 选中的字节才用缓冲的值覆盖，未选中的保持读回值。
    wire        fwd_same_word = wb_valid && (wb_addr[31:2] == addr_q[31:2]);
    wire [31:0] fwd_from_line = {
        wb_strb[3] ? wb_data[31:24] : hit_word[31:24],
        wb_strb[2] ? wb_data[23:16] : hit_word[23:16],
        wb_strb[1] ? wb_data[15:8]  : hit_word[15:8],
        wb_strb[0] ? wb_data[7:0]   : hit_word[7:0]
    };
    wire [31:0] fwd_from_mem = {
        wb_strb[3] ? wb_data[31:24] : m_beat_data[31:24],
        wb_strb[2] ? wb_data[23:16] : m_beat_data[23:16],
        wb_strb[1] ? wb_data[15:8]  : m_beat_data[15:8],
        wb_strb[0] ? wb_data[7:0]   : m_beat_data[7:0]
    };

    // 【为什么还要 `!rsp_valid`】不允许"响应还挂着的同时接受新请求"。
    //   Core 的数据端口是单笔事务：它在 D_RSP 等响应、收到后才回 D_IDLE。
    //   若本模块一边举着响应、一边又接受下一笔请求，双方对"响应到底有没有交接"
    //   的判断会错位（实测集成到 CoreMark 后 Core 永久停在 D_RSP、`dsv` 恒 0，
    //   而本模块以为已经收走了）。加上这一条就把两种状态彻底错开。
    // 【还能不能收新请求】只要写缓冲没占着、而且我们没在返回响应，就收。
    // **不再要求 `state == S_IDLE`**：请求收下后暂存，处理可以稍后进行。
    assign req_ready    = !wb_valid && !rsp_valid;
    assign m_beat_ready = (state == S_RFIL);

    wire req_cacheable = (req_addr <= CACHEABLE_LAST_ADDR) && (CACHE_EN != 0);

    integer i;

    // ---------------- 状态转移 ----------------
    always @(*) begin
        state_n = state;
        case (state)
            // 有暂存的请求就立刻处理（不再依赖"当时的状态"）
            S_IDLE  : if (pend_valid) state_n = S_LOOK;
            S_LOOK  : if (write_q)          state_n = S_RESP_W;   // 写：直接给完成响应
                      else if (hit)         state_n = S_RESP;     // 读命中
                      else                  state_n = S_RREQ;     // 读未命中 / 直连读
            S_RREQ  : if (m_rd_valid && m_rd_ready) state_n = S_RFIL;
            S_RFIL  : if (m_beat_valid && m_beat_ready && m_beat_last) state_n = S_RESP;
            S_RESP  : if (rsp_valid && rsp_ready) state_n = wb_valid ? S_WBUF : S_IDLE;
            S_RESP_W: if (rsp_valid && rsp_ready) state_n = S_WBUF;   // 写完必然要下推
            S_WBUF  : if (m_wr_valid && m_wr_ready) state_n = S_IDLE;
            default : state_n = S_IDLE;
        endcase
    end

    // ---------------- 时序逻辑 ----------------
    always @(posedge clk) begin
        if (reset) begin
            state       <= S_IDLE;
            m_rd_valid  <= 1'b0;
            m_rd_addr   <= {ADDR_WIDTH{1'b0}};
            m_rd_len    <= 8'd0;
            m_wr_valid  <= 1'b0;
            m_wr_addr   <= {ADDR_WIDTH{1'b0}};
            m_wr_data   <= 32'd0;
            m_wr_strb   <= 4'd0;
            rsp_valid   <= 1'b0;
            rsp_rdata   <= 32'd0;
            rsp_error   <= 1'b0;
            addr_q      <= 32'd0;
            write_q     <= 1'b0;
            wdata_q     <= 32'd0;
            wstrb_q     <= 4'd0;
            set_q       <= {SET_BITS{1'b0}};
            word_q      <= {WORD_BITS{1'b0}};
            tag_q       <= 32'd0;
            cacheable_q <= 1'b0;
            fill_idx    <= {WORD_BITS{1'b0}};
            victim      <= 32'd0;
            wb_valid    <= 1'b0;
            wb_addr     <= 32'd0;
            wb_data     <= 32'd0;
            wb_strb     <= 4'd0;
            wb_cacheable<= 1'b0;
            pend_valid  <= 1'b0;
            pend_addr   <= 32'd0;
            pend_write  <= 1'b0;
            pend_wdata  <= 32'd0;
            pend_wstrb  <= 4'd0;
            pend_cacheable <= 1'b0;
            stat_hits       <= 32'd0;
            stat_misses     <= 32'd0;
            stat_bypass     <= 32'd0;
            stat_writes     <= 32'd0;
            stat_forward    <= 32'd0;
            stat_bus_cycles <= 32'd0;
            stat_core_wait  <= 32'd0;
            stat_rsp_accepted <= 32'd0;
            for (i = 0; i < SETS; i = i + 1) begin
                val0[i] <= 1'b0; val1[i] <= 1'b0; rr[i] <= 1'b0;
                tag0[i] <= NIL;   tag1[i] <= NIL;
            end
        end
        else begin
            state <= state_n;

            if (state == S_RREQ || state == S_RFIL || state == S_WBUF)
                stat_bus_cycles <= stat_bus_cycles + 32'd1;
            if (state != S_IDLE && !(state == S_RESP && rsp_valid && rsp_ready) &&
                !(state == S_RESP_W && rsp_valid && rsp_ready))
                stat_core_wait <= stat_core_wait + 32'd1;

            // ---- 写缓冲下推 ----
            if (state == S_WBUF) begin
                if (m_wr_valid && m_wr_ready) begin
                    m_wr_valid <= 1'b0;
                    wb_valid   <= 1'b0;
                end
                else begin
                    m_wr_addr <= wb_addr;
                    m_wr_data <= wb_data;
                    m_wr_strb <= wb_strb;
                    m_wr_valid <= 1'b1;
                end
            end

            // ---- 接收读数据：写入受害路；目标字当局锁存 ----
            if (state == S_RFIL && m_beat_valid && m_beat_ready) begin
if (cacheable_q) begin
                    if (victim == 32'd0) data0[set_q][fill_idx] <= m_beat_data;
                    else                 data1[set_q][fill_idx] <= m_beat_data;
                end
                // 目标字当局锁存；同时做 Store->Load 转发（写缓冲里同字的未落盘字节）
                if (fill_idx == word_q) begin
                    if (fwd_same_word) begin
                        rsp_rdata    <= fwd_from_mem;
                        stat_forward <= stat_forward + 32'd1;
                    end
                    else begin
                        rsp_rdata <= m_beat_data;
                    end
                end
                fill_idx <= fill_idx + 1'b1;
                if (m_beat_last) begin
                    // 出错的行不置 valid；不可缓存地址不分配
                    if (!m_beat_error && cacheable_q) begin
                        if (victim == 32'd0) begin
                            tag0[set_q] <= tag_q; val0[set_q] <= 1'b1;
                        end
                        else begin
                            tag1[set_q] <= tag_q; val1[set_q] <= 1'b1;
                        end
                    end
                    rr[set_q] <= ~rr[set_q];
                    rsp_error <= m_beat_error;
                    rsp_valid <= 1'b1;
                end
            end

            // 响应握手完成计数（放在 case 之外，覆盖读/写两条路径）
            if (rsp_valid && rsp_ready)
                stat_rsp_accepted <= stat_rsp_accepted + 32'd1;

            // ---- 收下请求（skid）：只要请求在场就立刻暂存，绝不"拒收后让对方再给" ----
            if (req_taken) begin
                pend_valid     <= 1'b1;
                pend_addr      <= req_addr;
                pend_write     <= req_write;
                pend_wdata     <= req_wdata;
                pend_wstrb     <= req_wstrb;
                pend_cacheable <= req_cacheable;
            end
            else if (state == S_LOOK) begin
                pend_valid <= 1'b0;      // 已被取走处理
            end

            case (state)
                S_IDLE : begin
                    m_rd_valid <= 1'b0;
                    if (pend_valid) begin
                        // 从暂存区取出请求并锁存成"当前事务"字段
                        addr_q      <= pend_addr;
                        write_q     <= pend_write;
                        wdata_q     <= pend_wdata;
                        wstrb_q     <= pend_wstrb;
                        cacheable_q <= pend_cacheable;
                        set_q       <= pend_addr[OFF_HI-1:LINE_BITS];
                        word_q      <= pend_cacheable ? pend_addr[LINE_BITS-1:2] : {WORD_BITS{1'b0}};
                        tag_q       <= {pend_addr[ADDR_WIDTH-1:OFF_HI], {OFF_HI{1'b0}}};
                        fill_idx    <= {WORD_BITS{1'b0}};
                        if (!pend_cacheable) stat_bypass <= stat_bypass + 32'd1;
                        if (pend_write) stat_writes <= stat_writes + 32'd1;
                    end
                end

                S_LOOK : begin
                    if (write_q) begin
                        // ================= 写：写穿 + 写缓冲 =================
                        // 可缓存且命中 -> 先按 wstrb 就地合并进本行（未选中字节保持原值）
                        if (cacheable_q && hit) begin
                            if (hit0) begin
                                data0[set_q][word_q][7:0]   <= wstrb_q[0] ? wdata_q[7:0]   : data0[set_q][word_q][7:0];
                                data0[set_q][word_q][15:8]  <= wstrb_q[1] ? wdata_q[15:8]  : data0[set_q][word_q][15:8];
                                data0[set_q][word_q][23:16] <= wstrb_q[2] ? wdata_q[23:16] : data0[set_q][word_q][23:16];
                                data0[set_q][word_q][31:24] <= wstrb_q[3] ? wdata_q[31:24] : data0[set_q][word_q][31:24];
                            end
                            else begin
                                data1[set_q][word_q][7:0]   <= wstrb_q[0] ? wdata_q[7:0]   : data1[set_q][word_q][7:0];
                                data1[set_q][word_q][15:8]  <= wstrb_q[1] ? wdata_q[15:8]  : data1[set_q][word_q][15:8];
                                data1[set_q][word_q][23:16] <= wstrb_q[2] ? wdata_q[23:16] : data1[set_q][word_q][23:16];
                                data1[set_q][word_q][31:24] <= wstrb_q[3] ? wdata_q[31:24] : data1[set_q][word_q][31:24];
                            end
                        end
                        // 无论命中与否，整笔写都要写穿到下游（写未命中也压缓冲，不分配行）
                        wb_valid     <= 1'b1;
                        wb_addr      <= addr_q;
                        wb_data      <= wdata_q;
                        wb_strb      <= wstrb_q;
                        wb_cacheable <= cacheable_q;
                        // 写事务不返回数据，但仍必须给一个完成响应
                        rsp_rdata <= 32'd0;
                        rsp_error <= 1'b0;
                        rsp_valid <= 1'b1;
                    end
                    else if (cacheable_q && hit) begin
                        // ================= 读命中 =================
                        if (fwd_same_word) begin
                            rsp_rdata    <= fwd_from_line;
                            stat_forward <= stat_forward + 32'd1;
                        end
                        else begin
                            rsp_rdata <= hit_word;
                        end
                        rsp_error <= 1'b0;
                        rsp_valid <= 1'b1;
                        stat_hits <= stat_hits + 32'd1;
                    end
                    else begin
                        // ================= 读未命中 / 直连读 =================
                        stat_misses <= stat_misses + 32'd1;
                        m_rd_valid  <= 1'b1;
                        m_rd_len    <= cacheable_q ? (WORDS[7:0] - 8'd1) : 8'd0;
                        m_rd_addr   <= cacheable_q
                                     ? {addr_q[ADDR_WIDTH-1:LINE_BITS], {LINE_BITS{1'b0}}}
                                     : {addr_q[ADDR_WIDTH-1:2], 2'b00};
                        victim      <= {31'b0, rr[set_q]};
                    end
                end

                S_RREQ : begin
                    if (m_rd_valid && m_rd_ready) begin
                        m_rd_valid <= 1'b0;
                        fill_idx   <= {WORD_BITS{1'b0}};
                    end
                end

                S_RFIL : begin
                    m_rd_valid <= 1'b0;
                end

                S_RESP : begin
                    if (rsp_valid && rsp_ready)
                        rsp_valid <= 1'b0;
                end

                S_RESP_W : begin
                    if (rsp_valid && rsp_ready)
                        rsp_valid <= 1'b0;
                end

                S_WBUF : ;      // 由上面的公共段驱动
                default : ;
            endcase
        end
    end
endmodule
