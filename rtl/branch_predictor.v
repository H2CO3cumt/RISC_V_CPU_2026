// 16 项直接映射分支目标缓冲器，每项配一个 2-bit 饱和计数器。
// 预测只影响下一条取指地址；EX 阶段始终使用真实分支结果校验并恢复。
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
    input wire [31:0] update_target
);
    reg valid [0:15];
    reg [25:0] tag [0:15];
    reg [31:0] target [0:15];
    reg [1:0] counter [0:15];
    integer index;

    wire [3:0] query_index = query_pc[5:2];
    wire [3:0] update_index = update_pc[5:2];
    wire entry_match = valid[query_index] &&
                       (tag[query_index] == query_pc[31:6]);

    assign query_hit = enable && entry_match;
    assign predicted_taken = query_hit && counter[query_index][1];
    assign predicted_target = target[query_index];

    always @(posedge clk) begin
        if (reset) begin
            for (index = 0; index < 16; index = index + 1) begin
                valid[index] <= 1'b0;
                tag[index] <= 26'b0;
                target[index] <= 32'b0;
                counter[index] <= 2'b01;
            end
        end
        else if (enable && update_valid) begin
            // 地址冲突时直接替换该项；新分支按本次真实结果建立初始倾向。
            if (!valid[update_index] ||
                (tag[update_index] != update_pc[31:6])) begin
                valid[update_index] <= 1'b1;
                tag[update_index] <= update_pc[31:6];
                target[update_index] <= update_target;
                counter[update_index] <= update_taken ? 2'b10 : 2'b01;
            end
            else begin
                target[update_index] <= update_target;
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
