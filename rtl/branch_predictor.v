// 16 项直接映射分支目标缓冲器，每项配一个 2-bit 饱和计数器和一个“这条是跳转”标志。
// 预测只影响下一条取指地址；EX 阶段始终用真实结果校验，只有校验失败才重定向。
//
// 为什么要区分“分支”和“跳转”（`is_jump`）：
//  - 条件分支的方向本身是未知的，必须靠 2-bit 计数器去学；
//  - JAL/JALR 是“永远跳”的指令，方向根本不需要学。若仍让它们共用计数器，
//    一旦被别的分支污染成 not-taken，跳转就会被预测成“不跳”，
//    每次都要等 EX 算出目标再重定向，白扔掉整条流水线的前端。
// 因此对 `is_jump` 的项直接输出 taken，让 IF 就用 BTB 目标去取指；
// 目标对不对由 EX 的 `control_mispredict` 负责兜底。这样 JAL 这类
// “目标只由 PC 和立即数决定”的跳转可以做到 100% 预测正确。
module branch_predictor (
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [31:0] query_pc,
    output wire query_hit,
    output wire predicted_taken,
    output wire [31:0] predicted_target,

    input wire update_valid,
    input wire [31:0] update_pc,
    input wire update_taken,
    input wire update_is_jump,
    input wire [31:0] update_target
);
    reg valid [0:15];
    reg [25:0] tag [0:15];
    reg [31:0] target [0:15];
    reg [1:0] counter [0:15];
    // is_jump：该 PC 上最后执行的是一条跳转指令（JAL/JALR），方向恒为 taken。
    reg is_jump [0:15];
    integer index;

    wire [3:0] query_index = query_pc[5:2];
    wire [3:0] update_index = update_pc[5:2];
    wire entry_match = valid[query_index] &&
                       (tag[query_index] == query_pc[31:6]);

    assign query_hit = enable && entry_match;
    // 跳转项不看饱和计数器：方向恒 taken，只信目标地址。
    assign predicted_taken = query_hit && (is_jump[query_index] ||
                                           counter[query_index][1]);
    assign predicted_target = target[query_index];

    always @(posedge clk) begin
        if (reset) begin
            for (index = 0; index < 16; index = index + 1) begin
                valid[index] <= 1'b0;
                tag[index] <= 26'b0;
                target[index] <= 32'b0;
                counter[index] <= 2'b01;
                is_jump[index] <= 1'b0;
            end
        end
        else if (enable && update_valid) begin
            // 地址冲突时直接替换该项；新分支按本次真实结果建立初始倾向。
            // 跳转项按 taken 建立，避免第一次执行就落在“不跳”一侧。
            if (!valid[update_index] ||
                (tag[update_index] != update_pc[31:6])) begin
                valid[update_index] <= 1'b1;
                tag[update_index] <= update_pc[31:6];
                target[update_index] <= update_target;
                is_jump[update_index] <= update_is_jump;
                counter[update_index] <= (update_taken || update_is_jump)
                                         ? 2'b10 : 2'b01;
            end
            else begin
                target[update_index] <= update_target;
                is_jump[update_index] <= update_is_jump;
                if (update_taken && counter[update_index] != 2'b11) begin
                    counter[update_index] <= counter[update_index] + 1'b1;
                end
                else if (!update_taken && counter[update_index] != 2'b00) begin
                    counter[update_index] <= counter[update_index] - 1'b1;
                end
            end
        end
    end
endmodule
