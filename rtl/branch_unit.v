module branch_unit (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  funct3,
    output reg          taken
);
wire equal;
wire signed_less;
wire unsigned_less;

assign equal=(a==b);
assign signed_less=(a[31] != b[31]) ? a[31] : (a < b);
assign unsigned_less = (a < b);
always@(*) begin
    taken = 1'b0;
    case(funct3)
        3'b000: taken = equal; // BEQ
        3'b001: taken = !equal; // BNE
        3'b100: taken = signed_less; // BLT
        3'b101: taken = !signed_less; // BGE
        3'b110: taken = unsigned_less; // BLTU
        3'b111: taken = !unsigned_less; // BGEU
        default: taken = 1'b0;
    endcase
end
endmodule
