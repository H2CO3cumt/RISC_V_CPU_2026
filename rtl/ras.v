// 返回地址栈（Return Address Stack, RAS）
//
// ---------------------------------------------------------------------------
// 为什么需要它
// ---------------------------------------------------------------------------
// BTB 对 `ret` 天生不准：BTB 每个 PC 只存**一个** target，而同一个 `ret`
// 会被多个调用点共享（CoreMark 静态统计：ret 49 处 / call 158 处），
// 于是目标在"最近一次调用者"和"其它调用者"之间反复错。
// RAS 记的是整个返回路径的栈，不是"上次去了哪儿"，所以对 ret 可以接近全对。
//
// ---------------------------------------------------------------------------
// RISC-V 没有专门的 call / ret 指令，只能用寄存器约定判定（本模块只管栈，
// 判定在 pipeline_cpu 里做，这里把规则写清楚，便于对照）：
//   jal  ra, imm          (rd = x1)                    -> push  pc+4
//   jalr ra, rs1, imm     (rd = x1)                    -> push  pc+4
//   jalr x0, 0(ra)        (rd = x0 且 rs1 = x1)        -> pop
//   jal  x0, imm          (rd = x0)                    -> 不压不弹（普通跳转/尾调用）
//   jalr 其它组合                                      -> 不压不弹（跳转表等）
// 判错的后果：栈指针与真实调用深度失配，ret 会一路错下去。所以
//   * 空栈时 pop 不得回绕（cnt 饱和在 0）；
//   * pop 优先于同拍 push（单发射下一次只有一条指令，二者本不该同拍；
//     这条规则只是给异常情况一个确定行为）。
//
// ---------------------------------------------------------------------------
// 溢出行为（必须知道的限制）
// ---------------------------------------------------------------------------
// 深度用尽后继续 push：**覆盖最老的一项**，cnt 饱和在 DEPTH。
// 于是最近 DEPTH 层调用仍然正确，更深的返回会错 —— 递归深度超过 DEPTH 的
// 程序（如深递归的快速排序）会退化，这一点与真实处理器一致。
module ras #(
    // 栈深度。建议 4 / 8。必须是 >= 2 的 2 的幂（环形指针靠位宽回绕）。
    parameter DEPTH = 8
)(
    input  wire        clk,
    input  wire        reset,
    // 0 = 旁路：状态保持不变、valid 恒 0，预测端不会用到栈顶
    input  wire        enable,

    input  wire        push,        // 调用：压栈
    input  wire [31:0] ret_addr,    // 返回地址（= 调用指令 pc + 4）
    input  wire        pop,         // 返回：弹栈

    output wire [31:0] top,         // 栈顶 = 预测的返回地址
    output wire        valid,       // 栈非空（且 enable）
    output wire [3:0]  level        // 当前深度（观测 / ILA 用）
);

    localparam AW = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam CW = (DEPTH <= 2) ? 2 : ($clog2(DEPTH) + 1);
    // 索引掩码：DEPTH 必须是 2 的幂，& (DEPTH-1) 等价于取模。
    // DEPTH=1 时掩码为 0，指针加到 1 也不会越界读 mem[1]（越界读出来是 X）。
    localparam [AW-1:0] IMASK = DEPTH - 1;
    localparam [CW-1:0] FULL  = DEPTH;

    reg [31:0]   mem [0:DEPTH-1];
    reg [AW-1:0] wp;    // 写指针（环形）
    reg [CW-1:0] cnt;   // 当前深度（0..DEPTH，饱和）

    // pop 优先：同拍二者都有效时不压栈
    wire do_pop  = enable && pop;
    wire do_push = enable && push && !pop;

    // 栈顶 = 写指针往回一格（cnt 为 0 时由 valid 屏蔽，读到的是陈旧值）
    // 读写索引一律经过掩码：DEPTH=1 时掩码为 0，恒指 0 号条目。
    // 不加掩码时 wp 会加到 1，mem[1] 越界（数组只有 [0:0]），读出 X ——
    // fetch_fifo 当初就是栽在同一个坑上（x5 变成 xxxxxxxx）。
    wire [AW-1:0] widx = wp & IMASK;
    wire [AW-1:0] tidx = (wp - 1'b1) & IMASK;
    assign top   = mem[tidx];
    assign valid = enable && (cnt != {CW{1'b0}});
    assign level = cnt;

    reg [CW-1:0] cnt_next;
    always @(*) begin
        cnt_next = cnt;
        if (do_push) begin
            cnt_next = (cnt == FULL) ? FULL : (cnt + 1'b1);
        end
        else if (do_pop) begin
            cnt_next = (cnt == {CW{1'b0}}) ? {CW{1'b0}} : (cnt - 1'b1);
        end
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            wp  <= {AW{1'b0}};
            cnt <= {CW{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= 32'b0;
            end
        end
        else begin
            cnt <= cnt_next;
            if (do_push) begin
                mem[widx] <= ret_addr;
                wp        <= wp + 1'b1;
            end
            else if (do_pop) begin
                // 空栈时不得回绕：只有 cnt 真的减了才动写指针
                if (cnt != {CW{1'b0}}) begin
                    wp <= wp - 1'b1;
                end
            end
        end
    end

endmodule
