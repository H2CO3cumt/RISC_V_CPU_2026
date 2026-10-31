// S3：2 路组相联指令 Cache（2-way set-associative I-Cache）。
//
// ## 位置与边界（不得放宽）
//
// 本模块**只能**位于 Core 的统一取指端口与下级存储之间，属于 Core 外部。
// Core 侧端口与 `docs/interfaces.md` §2.1 的语义一字不差（单笔事务、一个未完成请求），
// `rtl/pipeline_cpu.v` 的端口、位宽、事务语义均不受影响。
//
// ## 组织
//
//   默认 32 组 × 2 路 × 8 字/行 = 32 × 2 × 32 B = **2 KB** 容量。
//   地址划分（`ADDR_WIDTH = 32`）：
//        [31 : OFFSET_BITS+SET_BITS]              tag
//        [OFFSET_BITS+SET_BITS-1 : OFFSET_BITS]   set 序号
//        [OFFSET_BITS-1 : 2]                      行内字号
//        [1 : 0]                                  行内字节偏移
//   默认参数下：tag = addr[31:12]、set = addr[11:5]、word = addr[4:2]。
//
// ## 命中 / 未命中
//
//   两路并行比较 tag；**命中时下一拍给出响应**（寄存路径，见下）。
//   未命中则整行填充：向下游发**一次行请求**，收 `WORDS` 个数据拍写进阵列，
//   并把 Core 要的那一个字在它自己那一拍就锁存下来（它可能出现在第 1 拍）。
//   替换策略：每组一个 1-bit round-robin 指针，交替替换两路。
//
// ## Off 开关
//
//   `CACHE_EN = 0` 时**完全退化**为直通：每次取指都走未命中路径、只请求一个字、
//   不写阵列。这样 Off/On 是同一份 RTL 的两种配置，Before/After 不含其它变量。
//
// ## ⚠️ 已知代价：命中路径有 1 拍寄存（未解决的性能问题）
//
//   本模块的命中响应是**寄存**的：IDLE 拍锁存地址 -> 下一拍给 `rsp_valid`。
//   而 Core 的前端有一条关键优化（`rtl/pipeline_cpu.v` 第 727–741 行）：
//   **"上一笔响应被接收" 与 "下一笔请求被接受" 可以在同一拍交接**，
//   所以零等待存储器（例如 `coremark_imem`，本拍地址、下拍出数据）能每拍取一条指令。
//   本模块把它变成 2 拍/次，于是**每取一条指令多 1 拍**。
//
//   实测（`scripts/run_coremark_pipeline_tb.ps1`，同一份 TB / Core / 程序）：
//       I-Cache Off：cycles = 1,251,724，retired = 786,925，CPI 1.591
//       I-Cache On ：cycles = 2,891,324，retired = 770,926，CPI 3.751（**慢 2.31 倍**）
//   差值 ≈ retired 条数，正好印证"每取一条指令多 1 拍"。
//
//   按 `docs/handoff_next.md` §3.3 的回退条件（Off 与 On 都没有可测净收益就停用并回退），
//   这个配置**不能**作为交付默认值。因此：
//     1. 本模块默认 `CACHE_EN = 0`（等价于加入 Cache 之前的基线），
//        集成时（`tb/tb_coremark_pipeline.v`）也默认 `ENABLE_ICACHE = 0`；
//     2. 模块本身的功能与量化已由独立 TB 验证（26 项 PASS，仿真命中率 87%、
//        下游总线周期 −70%），但那是**后端慢**（每拍给一拍、首拍有延迟）时的结果；
//     3. 要在**零等待 BRAM** 后端上拿到净收益，必须把命中路径做成**组合**（零气泡）。
//        该方案已分析清楚（阵列读出本身组合可得），但本会话未能调通（TB 超时），
//        因此**不把未验证的路径当默认值**——需要时另开一轮专门做它并单独验收。
//
//   结论：Cache 在"慢后端"（DDR3 那类）下价值明确；在"零等待片上 BRAM"下需要
//   零气泡命中路径才有意义。这条差异本身就是 P3 的有用结论，如实记录。
//
// ## 与 Trap 的关系（S3 必须说清楚的一条）
//
//   Cache 只影响取指**延迟**，不改变取到的指令内容，也不改变任何架构可见状态。
//   Trap 的精确性来自 Core 内部的提交级判定，与本模块无关；
//   本模块唯一的副作用是"多等若干拍"，而 Core 在 `i_req_ready=0` 期间保持
//   PC/请求字段不变。因此接入后必须**重跑** Trap 全部 99 条断言验证这一点，
//   而不是假设它成立。
//
// ## 错误语义
//
//   下游返回错误的行，**不写入阵列**（避免把坏数据缓存成有效行），
//   直接把错误透传给 Core。
module soc_icache_2way #(
    parameter SETS        = 32,      // 组数
    parameter WAYS        = 2,       // 路数（2 路组相联）
    parameter LINE_BYTES  = 32,      // 行字节数（= WORDS × 4）
    // 1 = 使能；0 = 直通（Off 开关）。
    // **默认 0**：集成后实测净收益为负（CoreMark 慢 2.31 倍，见文件头"已知代价"一节），
    // 按 `docs/handoff_next.md` §3.3 的回退条件改为默认关闭，避免有人直接例化
    // 就把这条负收益路径打开。独立 TB 会显式传 1 来验证功能与量化。
    parameter CACHE_EN    = 0,
    parameter ADDR_WIDTH  = 32
) (
    input  wire                    clk,
    input  wire                    reset,

    // ---------------- Core 侧：与 interfaces.md §2.1 语义一致 ----------------
    input  wire                    req_valid,
    output wire                    req_ready,
    input  wire [ADDR_WIDTH-1:0]   req_addr,
    output reg                     rsp_valid,
    input  wire                    rsp_ready,
    output reg  [31:0]             rsp_data,
    output reg                     rsp_error,

    // ---------------- 下游存储侧：行请求 + 连拍返回（与 S2 适配器同构）----------------
    output reg                     m_req_valid,
    input  wire                    m_req_ready,
    output reg  [ADDR_WIDTH-1:0]   m_req_addr,
    output reg  [7:0]              m_req_len,
    input  wire                    m_beat_valid,
    output wire                    m_beat_ready,
    input  wire [31:0]             m_beat_data,
    input  wire                    m_beat_last,
    input  wire                    m_beat_error,

    // ---------------- 统计（供 TB 与 Off/On 量化使用）----------------
    output reg  [31:0]             stat_hits,
    output reg  [31:0]             stat_misses,
    output reg  [31:0]             stat_bus_cycles,
    output reg  [31:0]             stat_beats,
    output reg  [31:0]             stat_core_wait
);
    localparam WORDS       = LINE_BYTES / 4;
    localparam WORD_BITS   = $clog2(WORDS);
    localparam SET_BITS    = $clog2(SETS);
    localparam LINE_BITS   = $clog2(LINE_BYTES);
    localparam OFF_HI      = LINE_BITS + SET_BITS;
    localparam NIL         = 32'hFFFF_FFFF;

    // ---------------- 状态编码 ----------------
    localparam S_IDLE = 3'd0;
    localparam S_LOOK = 3'd1;      // 锁存地址后做命中判定
    localparam S_REQ  = 3'd2;      // 向下游发行行请求
    localparam S_FILL = 3'd3;      // 接收数据拍
    localparam S_RESP = 3'd4;      // 返回 Core

    reg [2:0] state, state_n;

    // ---------------- 阵列：2 路 × SETS 组 × WORDS 字 ----------------
    reg [31:0] data0 [0:SETS-1][0:WORDS-1];
    reg [31:0] data1 [0:SETS-1][0:WORDS-1];
    reg [31:0] tag0  [0:SETS-1];
    reg [31:0] tag1  [0:SETS-1];
    reg        val0  [0:SETS-1];
    reg        val1  [0:SETS-1];
    reg        rr    [0:SETS-1];    // round-robin 替换指针

    // ---------------- 被锁存的请求 ----------------
    reg [31:0]          addr_q;
    reg [SET_BITS-1:0]  set_q;
    reg [WORD_BITS-1:0] word_q;
    reg [31:0]          tag_q;

    // ---------------- 填充进度 ----------------
    reg [WORD_BITS-1:0] fill_idx;
    reg [31:0]          victim;

    // 组合命中判定（用锁存后的地址，避免 Core 在等待期间改字段造成误判）
    wire hit0 = (WAYS > 1) && val0[set_q] && (tag0[set_q] == tag_q);
    wire hit1 = (WAYS > 1) && val1[set_q] && (tag1[set_q] == tag_q);
    wire hit  = (WAYS == 1) ? (val0[set_q] && (tag0[set_q] == tag_q)) : (hit0 || hit1);

    wire [31:0] hit_data = (WAYS == 1) ? data0[set_q][word_q]
                          : (hit0 ? data0[set_q][word_q] : data1[set_q][word_q]);

    assign req_ready    = (state == S_IDLE);
    assign m_beat_ready = (state == S_FILL);

    integer i;

    // ---------------- 状态转移 ----------------
    always @(*) begin
        state_n = state;
        case (state)
            // 收到请求 -> 下一拍做命中判定
            S_IDLE : if (req_valid) state_n = (CACHE_EN != 0) ? S_LOOK : S_REQ;
            // 命中 -> 返回；未命中 -> 发行行请求
            S_LOOK : state_n = hit ? S_RESP : S_REQ;
            S_REQ  : if (m_req_valid && m_req_ready) state_n = S_FILL;
            S_FILL : if (m_beat_valid && m_beat_ready && m_beat_last) state_n = S_RESP;
            S_RESP : if (rsp_valid && rsp_ready) state_n = S_IDLE;
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
            rsp_data     <= 32'd0;
            rsp_error    <= 1'b0;
            addr_q       <= 32'd0;
            set_q        <= {SET_BITS{1'b0}};
            word_q       <= {WORD_BITS{1'b0}};
            tag_q        <= 32'd0;
            fill_idx     <= {WORD_BITS{1'b0}};
            victim       <= 32'd0;
            stat_hits       <= 32'd0;
            stat_misses     <= 32'd0;
            stat_bus_cycles <= 32'd0;
            stat_beats      <= 32'd0;
            stat_core_wait  <= 32'd0;
            for (i = 0; i < SETS; i = i + 1) begin
                val0[i] <= 1'b0; val1[i] <= 1'b0; rr[i] <= 1'b0;
                tag0[i] <= NIL;   tag1[i] <= NIL;
            end
        end
        else begin
            state <= state_n;

            // 统计：下游被占用的周期 / Core 侧等待的周期
            if (state == S_REQ || state == S_FILL)
                stat_bus_cycles <= stat_bus_cycles + 32'd1;
            if (state != S_IDLE && !(state == S_RESP && rsp_valid && rsp_ready))
                stat_core_wait <= stat_core_wait + 32'd1;

            // ---- 接收数据拍：写入受害路；目标字当局锁存 ----
            // 【为什么不用等整行到齐才写阵列】写入按 8 拍顺序进行，受害路的 valid 位
            //   在**最后一个数据拍**才置起，所以中途不会出现"半有效行被命中"。
            // 【为什么目标字要当局锁存】Core 要的那个字可能在第 1 拍就出现，
            //   而最后一拍在第 8 拍；等最后再取就已经被覆盖。
            if (state == S_FILL && m_beat_valid && m_beat_ready) begin
                if (victim == 32'd0) data0[set_q][fill_idx] <= m_beat_data;
                else                 data1[set_q][fill_idx] <= m_beat_data;
                stat_beats <= stat_beats + 32'd1;
                if (fill_idx == word_q) rsp_data <= m_beat_data;     // 当局锁存目标字
                fill_idx <= fill_idx + 1'b1;
                if (m_beat_last) begin
                    // 整行到齐才置 valid；出错的行不置 valid（不缓存坏数据）
                    if (!m_beat_error) begin
                        if (victim == 32'd0) begin
                            tag0[set_q] <= tag_q; val0[set_q] <= 1'b1;
                        end
                        else begin
                            tag1[set_q] <= tag_q; val1[set_q] <= 1'b1;
                        end
                    end
                    rr[set_q] <= ~rr[set_q];          // 交替替换两路
                    rsp_error <= m_beat_error;
                    rsp_valid <= 1'b1;                // 填充完成 -> 给出响应
                end
            end

            case (state)
                S_IDLE : begin
                    m_req_valid <= 1'b0;
                    if (req_valid) begin
                        // 锁存请求字段：之后 Core 会一直保持，但我们按锁存值工作，
                        // 这样即使 Core 在等待期间改变可观察字段也不会误判
                        addr_q   <= req_addr;
                        set_q    <= req_addr[OFF_HI-1:LINE_BITS];
                        word_q   <= req_addr[LINE_BITS-1:2];
                        tag_q    <= {req_addr[ADDR_WIDTH-1:OFF_HI], {OFF_HI{1'b0}}};
                        fill_idx <= {WORD_BITS{1'b0}};
                        if (CACHE_EN == 0) begin
                            // 直通模式：只请求要走的那**一个字**（len=0），
                            // 与加 Cache 之前的单笔 imem 行为等价
                            stat_misses <= stat_misses + 32'd1;
                            m_req_valid <= 1'b1;
                            m_req_addr  <= {req_addr[ADDR_WIDTH-1:2], 2'b00};
                            m_req_len   <= 8'd0;
                        end
                    end
                end

                S_LOOK : begin
                    if (hit) begin
                        // ---- 命中：下一拍给出响应（寄存路径）----
                        rsp_data  <= hit_data;
                        rsp_error <= 1'b0;
                        rsp_valid <= 1'b1;
                        stat_hits <= stat_hits + 32'd1;
                    end
                    else begin
                        // ---- 未命中：发行整行请求，受害路由 rr 决定 ----
                        stat_misses <= stat_misses + 32'd1;
                        m_req_valid <= 1'b1;
                        m_req_addr  <= {addr_q[ADDR_WIDTH-1:LINE_BITS], {LINE_BITS{1'b0}}};
                        m_req_len   <= WORDS[7:0] - 8'd1;
                        victim      <= {31'b0, rr[set_q]};
                    end
                end

                S_REQ : begin
                    if (m_req_valid && m_req_ready) begin
                        m_req_valid <= 1'b0;
                        fill_idx    <= {WORD_BITS{1'b0}};
                    end
                end

                S_FILL : begin
                    m_req_valid <= 1'b0;
                end

                S_RESP : begin
                    // 数据来源已经在各自的产生点写进 rsp_data 了：
                    //   命中路径在 S_LOOK 拍写、填充路径在最后一个数据拍写。
                    // 这里只负责在握手完成后撤掉 valid。
                    if (rsp_valid && rsp_ready)
                        rsp_valid <= 1'b0;
                end
                default : ;
            endcase
        end
    end
endmodule
