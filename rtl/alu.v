module alu(
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0] alu_ctrl,
    output reg [31:0] result
);
wire [31:0] arithmetic_shift_right;
wire signed_less_than;

// 算术右移先执行逻辑右移，再根据符号位补高位，避免依赖 signed 声明。
assign arithmetic_shift_right =
    (a >> b[4:0]) |
    (a[31] ? ~(32'hffff_ffff >> b[4:0]) : 32'b0);

// 符号不同时负数更小；符号相同时可直接按无符号数比较低 31 位。
assign signed_less_than =
    (a[31] != b[31]) ? a[31] : (a[30:0] < b[30:0]);

always @(*) begin
    case (alu_ctrl)
        4'b0000: result = a + b;
        4'b0001: result = a - b;
        4'b0010: result = a & b;
        4'b0011: result = a | b;
        4'b0100: result = a ^ b;
        4'b0101: result = a << b[4:0];
        4'b0110: result = a >> b[4:0];
        4'b0111: result = arithmetic_shift_right;
        4'b1000: result = signed_less_than ? 32'd1 : 32'd0;
        4'b1001: result = (a < b) ? 32'd1 : 32'd0;
        default: result = 32'b0;
    endcase
end
endmodule
