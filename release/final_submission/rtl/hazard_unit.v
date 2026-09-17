// Load-Use 检测只比较当前指令真正读取的源寄存器，避免 I/U/J 型指令的
// immediate 位段碰巧等于 rd 时产生不必要的停顿。
module hazard_unit(
    input wire idex_valid,
    input wire idex_memread,
    input wire [4:0] idex_rd,
    input wire ifid_valid,
    input wire [31:0] ifid_instruction,
    output wire load_use_stall
);
    wire [6:0] opcode = ifid_instruction[6:0];
    wire [4:0] rs1 = ifid_instruction[19:15];
    wire [4:0] rs2 = ifid_instruction[24:20];
    reg uses_rs1;
    reg uses_rs2;

    always @(*) begin
        uses_rs1 = 1'b0;
        uses_rs2 = 1'b0;
        case (opcode)
            7'b0110011: begin uses_rs1 = 1'b1; uses_rs2 = 1'b1; end // R-Type
            7'b0010011,
            7'b0000011,
            7'b1100111: uses_rs1 = 1'b1;                         // ALU-I/Load/JALR
            7'b0100011,
            7'b1100011: begin uses_rs1 = 1'b1; uses_rs2 = 1'b1; end // Store/Branch
            default: begin uses_rs1 = 1'b0; uses_rs2 = 1'b0; end
        endcase
    end

    assign load_use_stall = idex_valid && idex_memread && (idex_rd != 5'd0) &&
                            ifid_valid &&
                            ((uses_rs1 && rs1 == idex_rd) ||
                             (uses_rs2 && rs2 == idex_rd));
endmodule
