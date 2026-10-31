// 取指预取队列（Fetch Prefetch FIFO）
//
// ---------------------------------------------------------------------------
// 为什么要有这个模块
// ---------------------------------------------------------------------------
// 借鉴 lowRISC/ibex 的做法（rtl/ibex_prefetch_buffer.sv + rtl/ibex_fetch_fifo.sv）：
//   1. 取指与执行之间放一个**容量大于 1** 的队列，而不是只靠 IF/ID 那一个寄存器；
//   2. 队列带 **feedthrough（直通）**：队列空的时候，新进来的一条立刻出现在输出端，
//      所以"每拍一条"的连续取指**不会因为多了一级缓冲而多花一拍**；
//   3. 每条指令随行携带它自己的 PC 与预测元数据（pred_hit/pred_taken/pred_target），
//      出队时原样交还，下游不需要回头再查任何东西。
//
// 它解决的不是"握手太慢"，而是"没地方放"：
//   只有 IF/ID 一个格子时，ID 停住 -> ifid 无处可写 -> i_rsp_ready=0 ->
//   存储器响应被顶住 -> req_ready 落 0 -> 取指连请求都发不出去，前端整条冻住。
//   有了队列，响应先落进队列，取指可以继续往前跑 DEPTH 条；停顿一解除，
//   存好的指令连续送进 IF/ID，不必再等一次取指延迟。
//
// ---------------------------------------------------------------------------
// 边界纪律（本模块刻意只做缓冲）
// ---------------------------------------------------------------------------
//   * 不生成取指地址、不产生重定向、不看 BTB；
//   * in_discard（错误路径的那一条）**直接丢弃，不入队**；
//   * flush 一个周期清空全部条目。flush 当拍：
//       - in_ready 仍为 1，让上游把已在场的响应收干净
//         （pipeline_cpu 在 Redirect/Trap 当拍本来就把 i_rsp_ready 强制拉高来排空）；
//       - 该拍被接受的响应**同样丢弃**，不入队；
//       - out_valid 被强制屏蔽为 0，避免重定向当拍又把旧指令写进 IF/ID。
//
// ---------------------------------------------------------------------------
// 时序口径（测试必须逐条验证，见 tb/tb_fetch_fifo.v）
// ---------------------------------------------------------------------------
//   * 队列空 + 下游能收 -> 当拍直通，out_valid 当拍即为 1，**零附加延迟**；
//   * 队列空 + 下游不能收 -> 先寄存一条，下一拍起输出；
//   * 队列满 -> in_ready=0（背压），但同拍若有出队（pop），仍可接收新条目；
//   * 入队与出队可以同时发生，占用数保持不变。
module fetch_fifo #(
    // 队列条目数。必须是 >= 2 的 2 的幂（2/4/8），环形指针靠位宽自然回绕。
    // DEPTH=2 已可吸收"一次数据访存阻塞"；DEPTH=4 可吸收连续两三次。
    parameter DEPTH = 4
)(
    input  wire        clk,
    input  wire        reset,

    //--------------------------------------------------------------------
    // 上游：取指存储器响应（对应 pipeline_cpu 的 i_rsp_*）
    //--------------------------------------------------------------------
    input  wire        in_valid,        // = i_rsp_valid
    output wire        in_ready,        // = 上游可以进队（有空位）
    // in_fire：**上游本次握手真的成功**（= in_valid && 外部的 rsp_ready）。
    // 为什么必须单独给这一根，而不能由模块内部用 in_valid&&in_ready 自己算：
    //   pipeline_cpu 的 i_rsp_ready 还额外受 !mem_block / if_rsp 门控，
    //   这些门控在模块外面。若模块只看自己的 in_ready，就会在
    //   i_rsp_ready=0（流水线认为"没接收"）的周期把响应吃掉；
    //   等门控放开，流水线又把同一笔响应接收一次 —— 实测表现为
    //   "一条指令被提交两次"（M 扩展回归里 0x78 的 sw 重复提交）。
    input  wire        in_fire,
    input  wire [31:0] in_inst,         // = i_rsp_data
    input  wire [31:0] in_pc,           // 这条指令自己的 PC
    input  wire        in_error,        // = i_rsp_error
    input  wire        in_pred_hit,     // 取这条时 BTB 的命中位
    input  wire        in_pred_taken,   // 取这条时 BTB 的方向预测
    input  wire [31:0] in_pred_target,  // 取这条时 BTB 的目标
    input  wire        in_discard,      // 1 = 这条属于错误路径，丢弃不入队

    //--------------------------------------------------------------------
    // 下游：IF/ID
    //--------------------------------------------------------------------
    output wire        out_valid,
    output wire [31:0] out_inst,
    output wire [31:0] out_pc,
    output wire        out_error,
    output wire        out_pred_hit,
    output wire        out_pred_taken,
    output wire [31:0] out_pred_target,
    input  wire        out_ready,       // IF/ID 能收下一条（= ifid_available）

    //--------------------------------------------------------------------
    // 控制与观测
    //--------------------------------------------------------------------
    input  wire        flush,           // 重定向 / Trap：清空队列
    output wire [3:0]  level            // 当前占用条目数（观测 / ILA 用）
);

    // 指针位宽：DEPTH=2 -> AW=1，DEPTH=4 -> AW=2，DEPTH=8 -> AW=3
    // DEPTH=1 时不真的需要指针，但为了代码只有一份，仍然用 1 位指针 +
    // 索引掩码（IMASK=0）把它钉在 0 号条目上。
    localparam AW = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    // 计数位宽：能表示 0..DEPTH
    localparam CW = (DEPTH <= 2) ? 2 : ($clog2(DEPTH) + 1);
    localparam [CW-1:0] FULL  = DEPTH;
    // 索引掩码：DEPTH 必须是 2 的幂，因此 & (DEPTH-1) 等价于取模。
    // 这一句是 DEPTH=1 能正确工作的关键：指针可以加到 1，但索引恒为 0，
    // 不会越界访问 ent_*[1]（越界读出来是 X，会顺着 ifid_inst 污染整条流水线）。
    localparam [AW-1:0] IMASK = DEPTH - 1;

    reg [AW-1:0] wp;    // 写入指针
    reg [AW-1:0] rp;    // 读出指针
    reg [CW-1:0] cnt;   // 占用条目数

    reg          ent_valid [0:DEPTH-1];
    reg [31:0]   ent_inst  [0:DEPTH-1];
    reg [31:0]   ent_pc    [0:DEPTH-1];
    reg          ent_error [0:DEPTH-1];
    reg          ent_hit   [0:DEPTH-1];
    reg          ent_taken [0:DEPTH-1];
    reg [31:0]   ent_tgt   [0:DEPTH-1];

    //------------------------------------------------------------------
    // 握手判定（全部组合）
    //------------------------------------------------------------------
    wire empty = (cnt == {CW{1'b0}});
    wire full  = (cnt == FULL);

    // 出队：队列非空且下游能吃下。flush 当拍不出队（整条前端作废）。
    wire pop = (!empty) && out_ready && !flush;

    // 是否有位置收新条目：未满，或同拍有出队腾出的位置，或正在 flush（清空）。
    assign in_ready = flush || (!full) || pop;

    // 真正写进存储器的那一条：由外部握手 in_fire 驱动，并排除错误路径与 flush。
    wire accept = in_fire && !in_discard && !flush;

    // 直通：队列空的当拍，进来的这条直接送到输出端，不占条目、不加拍。
    // 只在"下游当拍就能收"时才直通——否则必须先寄存，防止上游换数据。
    wire bypass = accept && empty && out_ready;
    wire store  = accept && !bypass;

    //------------------------------------------------------------------
    // 输出选择
    //------------------------------------------------------------------
    // 实际索引一律经过掩码，保证 DEPTH=1 时恒为 0 号条目（不越界）。
    wire [AW-1:0] widx = wp & IMASK;
    wire [AW-1:0] ridx = rp & IMASK;

    assign out_valid       = ((!empty) || bypass) && !flush;
    assign out_inst        = (!empty) ? ent_inst [ridx] : in_inst;
    assign out_pc          = (!empty) ? ent_pc   [ridx] : in_pc;
    assign out_error       = (!empty) ? ent_error[ridx] : in_error;
    assign out_pred_hit    = (!empty) ? ent_hit  [ridx] : in_pred_hit;
    assign out_pred_taken  = (!empty) ? ent_taken[ridx] : in_pred_taken;
    assign out_pred_target = (!empty) ? ent_tgt  [ridx] : in_pred_target;
    assign level           = cnt;

    //------------------------------------------------------------------
    // 占用数推进
    //------------------------------------------------------------------
    reg [CW-1:0] cnt_next;
    always @(*) begin
        cnt_next = cnt;
        if (flush) begin
            // flush 清空一切，不区分同拍有没有 store/pop
            cnt_next = {CW{1'b0}};
        end
        else if (store && !pop) begin
            cnt_next = cnt + 1'b1;
        end
        else if (!store && pop) begin
            cnt_next = cnt - 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 顺序逻辑
    //------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            wp  <= {AW{1'b0}};
            rp  <= {AW{1'b0}};
            cnt <= {CW{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                ent_valid[i] <= 1'b0;
                ent_inst [i] <= 32'b0;
                ent_pc   [i] <= 32'b0;
                ent_error[i] <= 1'b0;
                ent_hit  [i] <= 1'b0;
                ent_taken[i] <= 1'b0;
                ent_tgt  [i] <= 32'b0;
            end
        end
        else begin
            cnt <= cnt_next;

            if (flush) begin
                // 一条不留：重定向之后队列里全是错误路径
                wp  <= {AW{1'b0}};
                rp  <= {AW{1'b0}};
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ent_valid[i] <= 1'b0;
                end
            end
            else begin
                if (store) begin
                    ent_valid[widx] <= 1'b1;
                    ent_inst [widx] <= in_inst;
                    ent_pc   [widx] <= in_pc;
                    ent_error[widx] <= in_error;
                    ent_hit  [widx] <= in_pred_hit;
                    ent_taken[widx] <= in_pred_taken;
                    ent_tgt  [widx] <= in_pred_target;
                    wp <= wp + 1'b1;
                end
                if (pop) begin
                    ent_valid[ridx] <= 1'b0;
                    rp <= rp + 1'b1;
                end
            end
        end
    end

endmodule
