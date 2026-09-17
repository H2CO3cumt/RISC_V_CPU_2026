module decoder(
    input      [31:0] instruction,
    output reg        reg_write,
    output reg        alu_src_a,
    output reg        alu_src_b,
    output reg [3:0]  alu_ctrl,
    output reg        mem_read,
    output reg        mem_write,
    output reg [1:0]  result_src,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg        illegal
);

wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;

assign opcode = instruction[6:0];
assign funct3 = instruction[14:12];
assign funct7 = instruction[31:25];

always @(*) begin
    reg_write  = 1'b0;
    alu_src_a  = 1'b0;
    alu_src_b  = 1'b0;
    alu_ctrl   = 4'b0000;
    mem_read   = 1'b0;
    mem_write  = 1'b0;
    result_src = 2'b00;
    branch     = 1'b0;
    jump       = 1'b0;
    jalr       = 1'b0;
    illegal    = 1'b1;

    case (opcode)
        7'b0110011: begin
            case ({funct7, funct3})
                10'b0000000_000: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0000; // add
                    illegal   = 1'b0;
                end
                10'b0100000_000: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0001; // sub
                    illegal   = 1'b0;
                end
                10'b0000000_111: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0010; // and
                    illegal   = 1'b0;
                end
                10'b0000000_110: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0011; // or
                    illegal   = 1'b0;
                end
                10'b0000000_100: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0100; // xor
                    illegal   = 1'b0;
                end
                10'b0000000_001: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0101; // sll
                    illegal   = 1'b0;
                end
                10'b0000000_101: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0110; // srl
                    illegal   = 1'b0;
                end
                10'b0100000_101: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b0111; // sra
                    illegal   = 1'b0;
                end
                10'b0000000_010: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b1000; // slt
                    illegal   = 1'b0;
                end
                10'b0000000_011: begin
                    reg_write = 1'b1;
                    alu_ctrl  = 4'b1001; // sltu
                    illegal   = 1'b0;
                end
                default: begin
                    // Keep safe defaults for illegal R-Type encodings.
                end
            endcase
        end

        7'b0010011: begin
            case (funct3)
                3'b000: begin
                    reg_write = 1'b1;
                    alu_src_a = 1'b0;
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b0000; // addi
                    illegal   = 1'b0;
                end
                3'b010: begin
                    reg_write = 1'b1;
                    alu_src_a = 1'b0;
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b1000; // slti
                    illegal   = 1'b0;
                end
                3'b011: begin
                    reg_write = 1'b1;
                    alu_src_a = 1'b0;
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b1001; // sltiu
                    illegal   = 1'b0;
                end
                3'b100: begin
                    reg_write = 1'b1;
                    alu_src_a = 1'b0;
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b0100; // xori
                    illegal   = 1'b0;
                end
                3'b111: begin
                    reg_write = 1'b1;
                    alu_src_a = 1'b0;
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b0010; // andi
                    illegal   = 1'b0;
                end
                3'b110: begin
                    reg_write = 1'b1;
                    alu_src_a = 1'b0;
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b0011; // ori
                    illegal   = 1'b0;
                end
                3'b001: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write = 1'b1;
                        alu_src_a = 1'b0;
                        alu_src_b = 1'b1;
                        alu_ctrl  = 4'b0101; // slli
                        illegal   = 1'b0;
                    end
                end
                3'b101: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write = 1'b1;
                        alu_src_a = 1'b0;
                        alu_src_b = 1'b1;
                        alu_ctrl  = 4'b0110; // srli
                        illegal   = 1'b0;
                    end
                    else if (funct7 == 7'b0100000) begin
                        reg_write = 1'b1;
                        alu_src_a = 1'b0;
                        alu_src_b = 1'b1;
                        alu_ctrl  = 4'b0111; // srai
                        illegal   = 1'b0;
                    end
                end
                default: begin
                    // Keep safe defaults for illegal OP-IMM encodings.
                end
            endcase
        end

        7'b0000011: begin
            case (funct3)
                3'b000,
                3'b001,
                3'b010,
                3'b100,
                3'b101: begin
                    reg_write  = 1'b1;
                    alu_src_b  = 1'b1;
                    alu_ctrl   = 4'b0000;
                    mem_read   = 1'b1;
                    result_src = 2'b01;
                    illegal    = 1'b0;
                end
                default: begin
                    // Keep safe defaults for illegal Load encodings.
                end
            endcase
        end

        7'b0100011: begin
            case (funct3)
                3'b000,
                3'b001,
                3'b010: begin
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b0000;
                    mem_write = 1'b1;
                    illegal   = 1'b0;
                end
                default: begin
                    // Keep safe defaults for illegal Store encodings.
                end
            endcase
        end

        7'b1100011: begin
            case (funct3)
                3'b000,
                3'b001,
                3'b100,
                3'b101,
                3'b110,
                3'b111: begin
                    alu_src_a = 1'b1;
                    alu_src_b = 1'b1;
                    alu_ctrl  = 4'b0000;
                    branch    = 1'b1;
                    illegal   = 1'b0;
                end
                default: begin
                    // Keep safe defaults for illegal Branch encodings.
                end
            endcase
        end

        7'b1101111: begin
            reg_write  = 1'b1;
            alu_src_a  = 1'b1;
            alu_src_b  = 1'b1;
            alu_ctrl   = 4'b0000;
            result_src = 2'b10;
            jump       = 1'b1;
            illegal    = 1'b0;
        end

        7'b1100111: begin
            if (funct3 == 3'b000) begin
                reg_write  = 1'b1;
                alu_src_a  = 1'b0;
                alu_src_b  = 1'b1;
                alu_ctrl   = 4'b0000;
                result_src = 2'b10;
                jump       = 1'b1;
                jalr       = 1'b1;
                illegal    = 1'b0;
            end
        end

        7'b0110111: begin
            reg_write  = 1'b1;
            result_src = 2'b11;
            illegal    = 1'b0;
        end

        7'b0010111: begin
            reg_write = 1'b1;
            alu_src_a = 1'b1;
            alu_src_b = 1'b1;
            alu_ctrl  = 4'b0000;
            illegal   = 1'b0;
        end
        7'b0001111:if(funct3==3'b000)
                illegal=1'b0;
        default: begin
            // Keep safe defaults for unsupported opcodes.
        end
    endcase
end

endmodule
