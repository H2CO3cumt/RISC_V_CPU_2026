// 乘除法单元（M 扩展：mul/mulh/mulhsu/mulhu + div/divu/rem/remu）
//
// 两条通路的周期数完全不同，所以用同一个"忙"信号把 ID/EX 冻住：
//   乘法组（op[2]=0）：拍数由参数 MUL_LAT 决定（见下），用"忙"挡住 ID/EX；
//   除法组（op[2]=1）：32 拍恢复余数法迭代。
//
// MUL_LAT 是"同一条算法、三种存储方式"的开关，只影响延迟与关键路径，不影响结果：
//   3 = 基线：锁操作数 1 拍 + 两级**串联** 16x32 部分积 1 拍 + 组合出结果 1 拍（挡 2 拍）
//   2 = 并行部分积：锁操作数与 4 个 16x16 部分积压在同一拍（挡 1 拍）
//   1 = 全组合：乘法不进状态机，操作数出现的那一拍结果就有效（挡 0 拍）
// 为什么 3 曾经是必要的：第一版做成"一拍组合 32x32 直接吃前递后的操作数"时，
// PDS 把 32x32 摊成 **4 级串联 APM**，85 MHz 下最差路径
//   `mdu_unit/N25_m1/gopapm/CLK -> APM1/PO -> APM2 -> APM3 -> APM4 -> exmem_alu`
//   slack −3.268 ns；只把操作数寄存（2 拍版）也不够，因为串联链本身约 8.4 ns。
// MUL_LAT=2/1 之所以还敢试：换成 4 个 16x16 **并联**之后，乘法链只有 1 层 APM，
// 后面是 2 层加法树，而不是 4 层串联 APM —— 深度结构变了，不是单纯少寄存。
// **MUL_LAT=1/2 的时序必须由 PDS 实测确认后才可默认启用**，仿真只能证明功能与周期数。
//
// 协议（两条通路共用）：
//   run  = 当前 ID/EX 上有一条 M 指令（两组都算）；
//   ack  = 这条指令**已经被消费**（流水线把它连同结果锁进了 EX/MEM）。
//         背靠背的两条同类指令之间 run 一直是 1，只有 ack 能区分"还是同一条"
//          和"换了新的一条"——少了它，第二条会沿用第一条的结果（实测 rem 返回了商）。
//         注意：MUL_LAT=1 时乘法不占状态机、没有副作用，ack 对乘法无意义。
//   busy = 结果还没好，流水线必须把 ID/EX 冻住。
//
// 操作数编码（就是 funct3）：
//   000 mul      001 mulh      010 mulhsu    011 mulhu
//   100 div      101 divu      110 rem       111 remu
module mdu #(
    // 乘法占用 ID/EX 的拍数：3=旧基线（两级串联部分积）/2=并行部分积（当前默认）/1=全组合。
    parameter MUL_LAT = 2
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        run,
    input  wire [2:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        ack,

    output wire        busy,
    output wire [31:0] result
);

    //=========================================================================
    // 乘法组：部分积分解（算法核心）
    //
    // 一个 32x32 乘法，无论怎么实现，最后都是把 4 个 16x16 部分积按权重加起来：
    //     a = a_hi*2^16 + a_lo         b = b_hi*2^16 + b_lo
    //     a*b = pp00 + (pp01 + pp10)*2^16 + pp11*2^32
    // 老实现是"两级**串联**的 16x32"：先算 a_lo*b，再算 a_hi*b，两级 APM 串在
    // 一条链上，所以必须多花一拍把它们分别寄存下来才能满足时序。
    // 新实现把四个 16x16 做成**并联**：每一路只有 1 层 APM，后面是 2 层加法树。
    // 同样的 APM 数量（4 个 16x16 = 4 个 APM，与原来两个 16x32 相同），
    // 但关键路径从"2 层 APM 串联"变成"1 层 APM + 2 层加法"，于是可以少寄存一拍。
    //=========================================================================
    wire [15:0] mla_lo = a[15:0];
    wire [15:0] mla_hi = a[31:16];
    wire [15:0] mlb_lo = b[15:0];
    wire [15:0] mlb_hi = b[31:16];

    wire [31:0] pp00 = mla_lo * mlb_lo;   // 低 x 低
    wire [31:0] pp01 = mla_lo * mlb_hi;   // 低 x 高（交叉项 1）
    wire [31:0] pp10 = mla_hi * mlb_lo;   // 高 x 低（交叉项 2）
    wire [31:0] pp11 = mla_hi * mlb_hi;   // 高 x 高

    // 四个部分积 -> 64 位**无符号**全积（低位/高位分块，2 级加法深度）。
    // 为什么不能直接写成"三项相加"：第一版写成 64 位三元相加后，PDS 把它实现成
    // **两条 64 位行波进位链串联**，实测 85 MHz 下 WNS −2.947 ns（估算 67.97 MHz，
    // 关键路径 `core/rf/regs -> mdu_unit/pp00 -> CLMA../COUT ×N -> exmem_alu`）。
    // 正确性：P = q00 + cross*2^16 + q11*2^32，其中 cross = q01 + q10：
    //   低 16 位只由 q00 决定，因此低半只需一个 17 位加法
    //       mid = q00[31:16] + cross[15:0]（mid[16] 是向高位的进位）
    //   高半 = q11 + cross[32:16] + mid[16]
    // 进位只有 1 位，所以高半先算"进位=0"的 high_a，再算 +1 的 high_b，
    // 用 mid[16] 二选一——这样最高位加法与最低位加法处在**同一级**。
    //   prod_par : 直接用当前（前递后的）操作数，供 MUL_LAT=1
    //   prod_reg : 用 MUL_LAT=2 寄存下来的四个部分积
    wire [32:0] cross_p = {1'b0, pp01} + {1'b0, pp10};
    wire [16:0] mid_p   = {1'b0, pp00[31:16]} + {1'b0, cross_p[15:0]};
    wire [32:0] hid0_p  = {1'b0, pp11} + {16'b0, cross_p[32:16]};
    wire [32:0] hid1_p  = hid0_p + 33'd1;
    wire [63:0] prod_par = {(mid_p[16] ? hid1_p[31:0] : hid0_p[31:0]), mid_p[15:0], pp00[15:0]};

    localparam [1:0] M_IDLE = 2'd0;   // 还没锁操作数
    localparam [1:0] M_OPER = 2'd1;   // 基线专用：正在算串联部分积
    localparam [1:0] M_READY = 2'd2;  // 部分积已锁，全积可由组合逻辑给出

    reg        mul_busy;   // 兼容旧名（现在等价于"不在 M_IDLE"）
    reg [1:0]  mul_state;
    reg [31:0] ma;
    reg [31:0] mb;
    reg [2:0]  mop;
    reg [47:0] pp_lo_q;    // 基线：a_lo  * b （下标 32 位零扩展后相乘）
    reg [47:0] pp_hi_q;    // 基线：a_hi  * b
    reg [31:0] pp00_q;     // 并行版：四个已寄存的 16x16 部分积
    reg [31:0] pp01_q;
    reg [31:0] pp10_q;
    reg [31:0] pp11_q;

    // MUL_LAT=1 时乘法不进状态机（纯组合，一拍不挡）；1/2 才需要"忙"信号。
    wire mul_use_sm = (MUL_LAT != 1);
    wire mul_active = run && !op[2] && mul_use_sm;
    // 结果没准备好之前都要挡住流水线：M_IDLE 与 M_OPER 两拍（MUL_LAT=2 只有 M_IDLE）。
    wire mul_block  = mul_active && (mul_state != M_READY);

    always @(posedge clk) begin
        if (reset) begin
            mul_state <= M_IDLE;
            mul_busy  <= 1'b0;
            ma        <= 32'b0;
            mb        <= 32'b0;
            mop       <= 3'b000;
            pp_lo_q   <= 48'b0;
            pp_hi_q   <= 48'b0;
            pp00_q    <= 32'b0;
            pp01_q    <= 32'b0;
            pp10_q    <= 32'b0;
            pp11_q    <= 32'b0;
        end else if (ack || !mul_active) begin
            // 指令被消费（ack）或已经不在 EX：回到起点，等下一条乘法。
            mul_state <= M_IDLE;
            mul_busy  <= 1'b0;
        end else begin
            case (mul_state)
                M_IDLE: begin
                    ma        <= a;
                    mb        <= b;
                    mop       <= op;
                    mul_busy  <= 1'b1;
                    // MUL_LAT=2：锁操作数和算四个并联部分积压在同一拍。
                    // 这一拍的入口只有"前递 MUX -> 1 层 APM"，所以寄存得住。
                    if (MUL_LAT == 2) begin
                        pp00_q    <= pp00;
                        pp01_q    <= pp01;
                        pp10_q    <= pp10;
                        pp11_q    <= pp11;
                        mul_state <= M_READY;   // 下一拍直接出结果，省掉 M_OPER
                    end else begin
                        mul_state <= M_OPER;
                    end
                end
                M_OPER: begin
                    // 只有基线（MUL_LAT=3）会走到这里：两级串联 16x32 部分积。
                    // 输入是寄存器 ma/mb，输出也是寄存器，这一段里没有寄存器堆、
                    // 没有前递 MUX，串联深度只有 2 级 APM。
                    if (MUL_LAT == 3) begin
                        pp_lo_q   <= {32'b0, ma[15:0]} * mb;
                        pp_hi_q   <= {16'b0, ma[31:16]} * mb;
                    end
                    mul_state <= M_READY;
                end
                default: begin
                    // M_READY：结果由下面的组合逻辑给出，保持到被消费。
                end
            endcase
        end
    end

    // 结果来源：MUL_LAT=1 用当前操作数，2/3 用寄存后的操作数/部分积。
    wire [31:0] mul_a  = (MUL_LAT == 1) ? a  : ma;
    wire [31:0] mul_b  = (MUL_LAT == 1) ? b  : mb;
    wire [2:0]  mul_op = (MUL_LAT == 1) ? op : mop;

    // 寄存版（MUL_LAT=2）：结构与 prod_par 完全相同，只是输入换成一拍前锁下的四个部分积。
    wire [32:0] cross_q = {1'b0, pp01_q} + {1'b0, pp10_q};
    wire [16:0] mid_q   = {1'b0, pp00_q[31:16]} + {1'b0, cross_q[15:0]};
    wire [32:0] hid0_q  = {1'b0, pp11_q} + {16'b0, cross_q[32:16]};
    wire [32:0] hid1_q  = hid0_q + 33'd1;
    wire [63:0] prod_reg = {(mid_q[16] ? hid1_q[31:0] : hid0_q[31:0]), mid_q[15:0], pp00_q[15:0]};
    // 基线：全积 = 高半部分积 << 16 + 低半部分积。
    wire [63:0] prod_ser = ({16'b0, pp_hi_q} << 16) + {16'b0, pp_lo_q};

    wire [63:0] prod_uu = (MUL_LAT == 1) ? prod_par :
                          (MUL_LAT == 2) ? prod_reg : prod_ser;

    // 一个无符号 32x32->64 全积 + 两次减法，覆盖四种 MUL 语义。
    // 为什么不做四个乘法器：无符号积的高 32 位与有符号积的高 32 位之间
    // 只差"两个操作数符号位各自贡献的一份被乘数/乘数"：
    //     signed_hi = unsigned_hi - (a 为负 ? b : 0) - (b 为负 ? a : 0)
    // mulhsu 只减 a 那一项。低 32 位在有符号/无符号下完全相同，直接用 mul。
    wire        mul_sa  = mul_a[31];
    wire        mul_sb  = mul_b[31];

    wire [31:0] prod_hi_ss = prod_uu[63:32] - (mul_sa ? mul_b : 32'b0)
                                            - (mul_sb ? mul_a : 32'b0);
    wire [31:0] prod_hi_su = prod_uu[63:32] - (mul_sa ? mul_b : 32'b0);

    wire [31:0] mul_result = (mul_op == 3'b000) ? prod_uu[31:0]   : // mul
                             (mul_op == 3'b001) ? prod_hi_ss       : // mulh
                             (mul_op == 3'b010) ? prod_hi_su       : // mulhsu
                             (mul_op == 3'b011) ? prod_uu[63:32]   : // mulhu
                                                prod_uu[31:0];

    //=========================================================================
    // 除法组：32 步恢复余数法（shift-subtract）
    //
    // 每一步把被除数寄存器的最高位移进余数，试减一次除数：
    //   余数够减 -> 商左移并补 1，余数更新为差值
    //   余数不够 -> 商左移并补 0，余数保持
    // 32 步之后，商就在 dd 里、余数在 dr 里。迭代版本的组合深度只有
    // "32 位比较 + 32 位减法"，不进关键路径；代价是每笔除法 32 拍。
    //=========================================================================
    localparam [1:0] S_IDLE = 2'd0;   // 空闲，等一条除法指令进来
    localparam [1:0] S_RUN  = 2'd1;   // 正在迭代
    localparam [1:0] S_DONE = 2'd2;   // 结果已经算好，保持到该指令被消费

    reg [1:0]  state;
    reg [31:0] dd;      // 先放被除数，边移位边攒商
    reg [31:0] dr;      // 余数
    reg [31:0] dv;      // 除数（绝对值）
    reg [31:0] a_q;     // 原始被除数：除零时 rem 要直接返回它
    reg [31:0] b_q;     // 原始除数：除零判定也要用原始值
    reg [1:0]  rem_uns; // {is_rem, is_unsigned}
    reg        sign_q;  // 商的符号（被除数符号 ^ 除数符号）
    reg        sign_r;  // 余数的符号 = 被除数符号
    reg [5:0]  cnt;

    wire        run_div = run && op[2];

    // 有符号除法按"绝对值相除、最后补符号"实现，避免在迭代里同时处理符号。
    wire        start_uns = op[0];
    wire [31:0] a_abs = (start_uns || !a[31]) ? a : (~a + 32'd1);
    wire [31:0] b_abs = (start_uns || !b[31]) ? b : (~b + 32'd1);

    // 一步迭代的组合部分：先把被除数的下一位移进余数，再试减。
    wire [31:0] rem_shift = {dr[30:0], dd[31]};
    wire        ge        = (rem_shift >= dv);
    wire [31:0] rem_next  = ge ? (rem_shift - dv) : rem_shift;
    wire [31:0] quo_next  = {dd[30:0], ge};

    wire        is_rem = rem_uns[1];
    wire        is_uns = rem_uns[0];

    // 结果的组合读出：S_DONE 那一拍组合给出结果，流水线正好在这一拍把它
    // 连同 ex_result 一起锁进 EX/MEM，因此不需要额外的"结果寄存器"时序约定。
    wire [31:0] quo_mag = dd;
    wire [31:0] rem_mag = dr;
    wire [31:0] quo_fin = is_uns ? quo_mag : (sign_q ? (~quo_mag + 32'd1) : quo_mag);
    wire [31:0] rem_fin = is_uns ? rem_mag : (sign_r ? (~rem_mag + 32'd1) : rem_mag);

    // RISC-V 规定：除零时商为全 1、余数为被除数本身；
    // 溢出（-2^31 / -1）走绝对值通路自然得到 -2^31 与余数 0，无需特判。
    wire [31:0] div_result = is_rem ? ((b_q == 32'b0) ? a_q : rem_fin)
                                    : ((b_q == 32'b0) ? 32'hFFFF_FFFF : quo_fin);

    always @(posedge clk) begin
        if (reset) begin
            state   <= S_IDLE;
            dd      <= 32'b0;
            dr      <= 32'b0;
            dv      <= 32'b0;
            a_q     <= 32'b0;
            b_q     <= 32'b0;
            rem_uns <= 2'b00;
            sign_q  <= 1'b0;
            sign_r  <= 1'b0;
            cnt     <= 6'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (run_div) begin
                        // 起拍：锁操作数、锁符号、初始化余数与商。
                        dd      <= a_abs;
                        dr      <= 32'b0;
                        dv      <= b_abs;
                        a_q     <= a;
                        b_q     <= b;
                        rem_uns <= {op[1], op[0]};
                        sign_q  <= a[31] ^ b[31];
                        sign_r  <= a[31];
                        cnt     <= 6'd0;
                        state   <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (!run_div) begin
                        // 指令被取消（Trap/Redirect）或已经不在 EX：直接放弃本次除法，
                        // 不留任何副作用。
                        state <= S_IDLE;
                    end else begin
                        dr <= rem_next;
                        dd <= quo_next;
                        if (cnt == 6'd31) begin
                            state <= S_DONE;
                        end else begin
                            cnt <= cnt + 6'd1;
                        end
                    end
                end
                S_DONE: begin
                    // 结果保持到该指令真的被消费：正常路径靠 ack（流水线把它
                    // 锁进了 EX/MEM），取消路径靠 run_div 落下。两者缺一不可：
                    // 只看 ack 会在 Trap 取消时卡住，只看 run_div 会让背靠背的两条
                    // 除法共用同一次迭代结果（实测 rem 返回了上一条的商）。
                    if (ack || !run_div) begin
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // 统一对外：busy 覆盖两条通路，result 按当前指令的操作码选路。
    // MUL_LAT=1 时 mul_block 恒 0，乘法对流水线完全不可见。
    assign busy   = mul_block || (run_div && (state != S_DONE));
    assign result = op[2] ? div_result : mul_result;

endmodule
