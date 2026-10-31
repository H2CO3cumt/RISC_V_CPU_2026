// S2：Core 外部的「行式突发」适配器（line-burst adapter）。
//
// ## 这个模块解决什么问题
//
// 现状：`soc_fpga_memory.v` 里的 imem/dmem 是**单笔事务**存储——Core 取一个字，
// 下游用 1 拍给出响应。一次 32 B 的行填充 = 8 次独立事务 = 8 次「请求 + 响应」往返。
// 换成 DDR3 之后，每一次往返都要付 DDR 的行激活/命令开销，8 次往返非常贵。
//
// 本模块在 **Core 与下游存储之间**（都在 Core 外部）做两件事：
//   1. 把 Core 的单字请求翻译成「一次行请求 + 连拍返回」；
//   2. 用一个**行缓冲**（line buffer）把整行 8 个字都接住，后续落在同一行的访问直接命中，
//      不必再走下游。
//
// ## Core 侧接口：一个字都没改
//
// 请求/响应字段与 `docs/interfaces.md` §2 的语义完全一致（单笔、一个未完成事务、
// `valid/ready` 握手）。Core 的端口名、位宽、事务语义与 `rtl/pipeline_cpu.v` 均不受影响。
// 突发只发生在**本模块与下游之间**。
//
// ## 为什么用同一个模块做 Before/After
//
// `BURST_LEN` 参数控制本模块对下游的发包方式：
//   - `BURST_LEN = 1`：逐字模式（逐字发 `LINE_WORDS` 次独立的单笔请求）——即"Before"；
//   - `BURST_LEN > 1`：突发模式（一次行请求 + `LINE_WORDS` 个数据拍）——即"After"。
// 两种模式共用同一套 Core 侧逻辑与同一个行缓冲，只有"下游发包状态机"不同，
// 因此测出的总线周期差就是突发本身带来的收益，不含其它变量。
//
// ## 下游（存储侧）握手约定
//
//   请求：`m_req_valid` / `m_req_ready` / `m_req_addr`（行首地址）/ `m_req_len`（拍数-1）
//   数据：`m_beat_valid` / `m_beat_ready` / `m_beat_data` / `m_beat_last`
//   错误：`m_beat_error`（与 `m_beat_last` 同拍有效）
//
// 约定：一次突发一旦被接受，数据拍按序返回；`m_beat_last` 标记最后一拍。
// 逐字模式下 `m_req_len` 恒为 0，每笔只有 1 拍、`m_beat_last` 恒为 1——于是下游看到的
// 就是 8 次独立的单笔事务，与现状一致。
//
// ## 时序（关键路径逐拍说明）
//
//   S_IDLE      : Core 侧无请求时等待；有请求先查行缓冲
//   S_HIT       : 行缓冲命中 -> 当拍组合选出数据，下一拍 `rsp_valid`
//   S_MISS_REQ  : 向下游发行请求（逐字模式下每拍发一笔，共 LINE_WORDS 笔）
//   S_FILL      : 接收数据拍，写入行缓冲对应字
//   S_RESP      : 把 Core 请求的那一个字返回；若该字在填充途中就到达，则填到即回
//
// 行缓冲是本模块唯一的存储，`LINE_WORDS` 默认 8（32 B / 4 B）。
module soc_line_burst_adapter #(
    parameter LINE_BYTES = 32,          // 一行字节数（默认 32 B）
    parameter BURST_LEN  = 8,           // 对下游的发包方式：1=逐字(Before)，>1=突发(After)
    parameter ADDR_WIDTH = 32
) (
    input  wire                    clk,
    input  wire                    reset,

    // ---------------- Core 侧：与 interfaces.md §2 语义一致，单笔事务 ----------------
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

    // ---------------- 下游存储侧：行请求 + 连拍返回 ----------------
    output reg                     m_req_valid,
    input  wire                    m_req_ready,
    output reg  [ADDR_WIDTH-1:0]   m_req_addr,
    output reg  [7:0]              m_req_len,      // 拍数-1
    input  wire                    m_beat_valid,
    output wire                    m_beat_ready,
    input  wire [31:0]             m_beat_data,
    input  wire                    m_beat_last,
    input  wire                    m_beat_error,

    // ---------------- 统计（供 TB 与"总线周期"量化使用）----------------
    output reg  [31:0]             stat_bus_cycles,   // 下游侧被占用的周期数
    output reg  [31:0]             stat_burst_reqs,   // 发出的行/单笔请求数
    output reg  [31:0]             stat_data_beats,   // 收到的数据拍数
    output reg  [31:0]             stat_hits,         // 行缓冲命中次数
    output reg  [31:0]             stat_misses
);
    localparam WORDS      = LINE_BYTES / 4;
    localparam WORD_BITS  = (WORDS <= 1) ? 1 : $clog2(WORDS);
    localparam OFFSET_BITS = (LINE_BYTES <= 1) ? 1 : $clog2(LINE_BYTES);
    // 逐字模式：对下游每拍只发 1 拍；突发模式：一次发满 WORDS 拍
    localparam REQ_BEATS  = (BURST_LEN <= 1) ? 1 : WORDS;

    // ---------------- 状态编码 ----------------
    localparam S_IDLE     = 3'd0;
    localparam S_MISS_REQ = 3'd1;
    localparam S_FILL     = 3'd2;
    localparam S_RESP     = 3'd3;

    reg [2:0]  state;
    reg [2:0]  state_n;

    // ---------------- 行缓冲 ----------------
    reg [31:0] line_data [0:WORDS-1];
    reg [31:0] line_tag;                 // 行首地址（含 tag + index）
    reg        line_valid;               // 行缓冲是否有效

    // ---------------- 被锁存的 Core 请求 ----------------
    reg [ADDR_WIDTH-1:0] req_addr_q;
    reg                  req_write_q;
    reg [31:0]           req_wdata_q;
    reg [3:0]            req_wstrb_q;
    reg [WORD_BITS-1:0]  want_word;      // 本次想要第几个字

    // ---------------- 填充进度 ----------------
    reg [WORD_BITS-1:0]  fill_idx;       // 已收到几拍
    reg [WORD_BITS-1:0]  req_idx;        // 逐字模式下已发出几笔
    reg [31:0]           resp_word;      // 待返回的字（在填充途中锁存）
    reg                  is_write_op;    // 本次事务是否为写（决定填充结束后是否回读数据）

    // 组合：本拍 Core 请求落在行缓冲的哪一行、哪一个字
    wire [ADDR_WIDTH-1:0] line_base    = {req_addr[ADDR_WIDTH-1:OFFSET_BITS],
                                          {OFFSET_BITS{1'b0}}};
    wire [WORD_BITS-1:0]  word_in_line = req_addr[OFFSET_BITS-1:2];
    wire line_hit = line_valid && (line_tag == line_base);

    // 逐字模式下，行请求的"长度"字段恒 0；突发模式下一次性发满
    wire [7:0] req_len_now = (REQ_BEATS == 1) ? 8'd0 : (WORDS[7:0] - 8'd1);

    assign req_ready   = (state == S_IDLE);
    assign m_beat_ready = (state == S_FILL);

    // 行缓冲命中时，数据当拍就能给出
    wire [31:0] hit_word = line_data[word_in_line];

    integer k;

    // ---------------- 状态转移（组合）----------------
    always @(*) begin
        state_n = state;
        case (state)
            // 有请求时：命中直接回，未命中先发行请求。
            // 【为什么写操作不走缓存】S2 阶段不做 D-Cache，写一律直通下游；
            // 缓存/写缓冲属于 S4，届时在此处加旁路判断。
            S_IDLE : begin
                if (req_valid) begin
                    if (req_write)        state_n = S_MISS_REQ;  // 写：直通
                    else if (line_hit)    state_n = S_RESP;      // 读命中
                    else                  state_n = S_MISS_REQ;  // 读未命中
                end
            end
            // 向下游发行请求；逐字模式下要发 WORDS 笔
            S_MISS_REQ : begin
                if (m_req_valid && m_req_ready) begin
                    if (REQ_BEATS == 1 && req_idx != (WORDS[WORD_BITS-1:0] - 1'b1))
                        state_n = S_MISS_REQ;   // 还有下一笔单字请求
                    else
                        state_n = S_FILL;       // 请求发完，开始收数据拍
                end
            end
            // 收数据拍；收满最后一拍转入返回
            S_FILL : begin
                if (m_beat_valid && m_beat_ready && m_beat_last)
                    state_n = S_RESP;
            end
            // 返回 Core，握手即回空闲
            S_RESP : begin
                if (rsp_valid && rsp_ready)
                    state_n = S_IDLE;
            end
            default : state_n = S_IDLE;
        endcase
    end

    // ---------------- 时序逻辑 ----------------
    always @(posedge clk) begin
        if (reset) begin
            state        <= S_IDLE;
            m_req_valid  <= 1'b0;
            m_req_addr   <= {ADDR_WIDTH{1'b0}};
            m_req_len    <= 8'd0;
            rsp_valid    <= 1'b0;
            rsp_rdata    <= 32'd0;
            rsp_error    <= 1'b0;
            line_valid   <= 1'b0;
            line_tag     <= {ADDR_WIDTH{1'b0}};
            fill_idx     <= {WORD_BITS{1'b0}};
            req_idx      <= {WORD_BITS{1'b0}};
            resp_word    <= 32'd0;
            req_addr_q   <= {ADDR_WIDTH{1'b0}};
            req_write_q  <= 1'b0;
            req_wdata_q  <= 32'd0;
            req_wstrb_q  <= 4'd0;
            want_word    <= {WORD_BITS{1'b0}};
            is_write_op  <= 1'b0;
            stat_bus_cycles <= 32'd0;
            stat_burst_reqs <= 32'd0;
            stat_data_beats <= 32'd0;
            stat_hits       <= 32'd0;
            stat_misses     <= 32'd0;
            for (k = 0; k < WORDS; k = k + 1) line_data[k] <= 32'd0;
        end
        else begin
            state <= state_n;

            // ---- 统计：只要下游侧处于"请求或填充"状态就计一个总线周期 ----
            if (state == S_MISS_REQ || state == S_FILL)
                stat_bus_cycles <= stat_bus_cycles + 32'd1;

            // ---- 数据拍接收：写入行缓冲；若是本次要的字，锁存以便计数后返回 ----
            // 【注意 1】读请求的目标字**必须在它那一拍就锁存**：它可能出现在第 1 拍，
            //   而最后一拍在第 8 拍，等到 last 再取就已经被覆盖了。
            // 【注意 2】`rsp_valid` 必须在这里拉高。第一版漏了这两点，
            //   TB 直接超时卡在 S_RESP（状态机进了返回态却从没给出响应）。
            // 【注意 3】写事务也要回一个响应（Core 的数据端口要求"每笔请求一个完成响应"），
            //   所以不能用 `if (!is_write_op)` 跳过——那是第二个同源 bug。
            if (state == S_FILL && m_beat_valid && m_beat_ready) begin
                line_data[fill_idx] <= m_beat_data;
                stat_data_beats <= stat_data_beats + 32'd1;
                if (fill_idx == want_word && !is_write_op)
                    rsp_rdata <= m_beat_data;      // 当局锁存目标字
                fill_idx <= fill_idx + 1'b1;
                if (m_beat_last) begin
                    // 整行到齐，行缓冲转有效（写事务不更新行缓冲内容，但地址仍然可用；
                    // 为保守起见写事务不置 line_valid，避免把"写过的行"当成有效缓存）
                    if (!is_write_op) begin
                        line_valid <= 1'b1;
                        line_tag   <= {req_addr_q[ADDR_WIDTH-1:OFFSET_BITS],
                                       {OFFSET_BITS{1'b0}}};
                    end
                    rsp_error  <= m_beat_error;
                    rsp_valid  <= 1'b1;            // 填充结束 -> 给出完成响应
                end
            end

            case (state)
                S_IDLE : begin
                    m_req_valid <= 1'b0;
                    req_idx     <= {WORD_BITS{1'b0}};
                    fill_idx    <= {WORD_BITS{1'b0}};
                    if (req_valid) begin
                        // 锁存请求：后续若干拍里 Core 可能已经改变请求字段
                        req_addr_q  <= req_addr;
                        req_write_q <= req_write;
                        req_wdata_q <= req_wdata;
                        req_wstrb_q <= req_wstrb;
                        want_word   <= word_in_line;
                        is_write_op <= req_write;
                        if (req_write) begin
                            // 写直通：产生下行写请求（突发模式下长度按 REQ_BEATS 算）
                            m_req_valid <= 1'b1;
                            m_req_addr  <= line_base;
                            m_req_len   <= req_len_now;
                            stat_burst_reqs <= stat_burst_reqs + 32'd1;
                            stat_misses     <= stat_misses + 32'd1;
                        end
                        else if (line_hit) begin
                            // 读命中：当拍数据已在手上，下一拍就能回
                            rsp_rdata <= hit_word;
                            rsp_valid <= 1'b1;
                            rsp_error <= 1'b0;
                            stat_hits <= stat_hits + 32'd1;
                        end
                        else begin
                            m_req_valid <= 1'b1;
                            m_req_addr  <= line_base;
                            m_req_len   <= req_len_now;
                            stat_burst_reqs <= stat_burst_reqs + 32'd1;
                            stat_misses     <= stat_misses + 32'd1;
                        end
                    end
                end

                S_MISS_REQ : begin
                    if (m_req_valid && m_req_ready) begin
                        if (REQ_BEATS == 1 && req_idx != (WORDS[WORD_BITS-1:0] - 1'b1)) begin
                            // 逐字模式：接着发下一笔单字请求，地址逐字递增
                            req_idx     <= req_idx + 1'b1;
                            m_req_addr  <= line_base + ((req_idx + 1'b1) << 2);
                            m_req_valid <= 1'b1;
                            m_req_len   <= 8'd0;
                            stat_burst_reqs <= stat_burst_reqs + 32'd1;
                        end
                        else begin
                            // 请求已全部发出，撤掉 valid 并等数据
                            m_req_valid <= 1'b0;
                            fill_idx    <= {WORD_BITS{1'b0}};
                        end
                    end
                end

                S_FILL : begin
                    m_req_valid <= 1'b0;
                end

                S_RESP : begin
                    if (rsp_valid && rsp_ready)
                        rsp_valid <= 1'b0;
                end
                default : ;
            endcase
        end
    end
endmodule
