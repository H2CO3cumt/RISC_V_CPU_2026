// ENABLE_SYSTEM 控制 SYSTEM（opcode 1110011）编码的语义：
//   0（默认，单周期参考模型使用）：ECALL/EBREAK/MRET 与全部 CSR 指令
//     保持 `illegal=1`，沿用"未实现编码只抑制副作用、PC 顺序 +4"的既定行为，
//     单周期 CPU 的行为与既有约束测试因此逐位不变。
//   1（流水线 Core 使用）：按 docs/trap_contract.md 译码出 CSR 读改写与
//     ECALL/EBREAK/MRET。
//
// 当前状态：A3（精确 Trap/中断）集成尚未完成，流水线暂停使用这一参数，
// 因此这里临时改回 0，保持 A0/A1 的已验证行为。A3 的 CSR 单元
// （rtl/csr_unit.v，32/32 PASS）与 docs/trap_contract.md 的约定保留不动。
// 完成 A3 集成时把流水线改回 #(.ENABLE_SYSTEM(1)) 即可。
//
// M 扩展（mul/mulh/mulhsu/mulhu/div/divu/rem/remu）**不受 ENABLE_SYSTEM 影响**，
// 两个 CPU（五级流水与单周期 Reference Model）都按 RV32IM 译码这八条编码：
// 单周期 Reference 与流水线必须对同一程序给出相同架构状态，若只给一边加 M，
// RTL 等价性比较会在任何用到乘除法的程序上直接失效。
module decoder #(
    parameter ENABLE_SYSTEM = 0
)(
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
    output reg        illegal,
    // ---- Zicsr / SYSTEM（异常约定见 docs/trap_contract.md）----
    // csr_en：本指令是 CSR 读改写指令；
    // csr_wen：本次访问真的会产生"写"副作用（CSRRS/CSRRC 用 x0 时是纯读，不算写）；
    // csr_imm：源操作数取 5-bit 无符号立即数（CSRRWI/CSRRSI/CSRRCI）；
    // csr_funct：00=写(RW) 01=置位(RS) 10=清位(RC)；
    // trap_ecall/trap_ebreak/trap_mret：ECALL / EBREAK / MRET。
    // 这些指令都不写通用寄存器、不访存、不参与分支预测，唯一的架构效果是 CSR 访问或陷入。
    output reg        csr_en,
    output reg        csr_wen,
    output reg        csr_imm,
    output reg [1:0]  csr_funct,
    output reg        trap_ecall,
    output reg        trap_ebreak,
    output reg        trap_mret,
    // ---- M 扩展（RV32IM 的 mul/mulh/mulhsu/mulhu/div/divu/rem/remu）----
    // mdu_en：本条指令由乘除法单元执行（结果写 rd，不走 ALU/访存/CSR）；
    // mdu_op：直接就是 funct3，编码见 rtl/mdu.v 顶部（op[2]=1 表示需要迭代除法）。
    output reg        mdu_en,
    output reg [2:0]  mdu_op
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
    csr_en     = 1'b0;
    csr_wen    = 1'b0;
    csr_imm    = 1'b0;
    csr_funct  = 2'b00;
    trap_ecall  = 1'b0;
    trap_ebreak = 1'b0;
    trap_mret   = 1'b0;
    mdu_en      = 1'b0;
    mdu_op      = 3'b000;

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
                // M 扩展：funct7=0000001 的整组 R-Type 全部合法，funct3 直接
                // 作为 mdu_op 传给乘除法单元（000..111 恰好对应八条指令）。
                // 这八条不写内存、不碰 CSR，写回值由 mdu 给出，因此
                // result_src 保持 00（走"ALU 结果"那条写回通路）。
                10'b0000001_000,
                10'b0000001_001,
                10'b0000001_010,
                10'b0000001_011,
                10'b0000001_100,
                10'b0000001_101,
                10'b0000001_110,
                10'b0000001_111: begin
                    reg_write  = 1'b1;
                    result_src = 2'b00;
                    alu_ctrl   = 4'b0000;
                    mdu_en     = 1'b1;
                    mdu_op     = funct3;
                    illegal    = 1'b0;
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

        // ------------------------------------------------------------------
        // SYSTEM（opcode 1110011）：Zicsr 六条 + ECALL/EBREAK/MRET
        //
        // 区分规则（写死在这里，避免"看起来像就放行"）：
        //  - funct3 != 000：Zicsr 读改写，rs1 就是 CSR 号，rs1=x0 限定为纯读写法；
        //  - funct3 == 000 且 rs2==0 且 rd==0：由 12-bit 立即数唯一确定特权指令，
        //    其余立即数编码（包括 WFI 0x105、SFENCE 等）保持非法指令。
        // ECALL/EBREAK/MRET 不写通用寄存器、不访存，所以这里 reg_write 保持 0。
        // ------------------------------------------------------------------
        7'b1110011: begin
            if (ENABLE_SYSTEM == 0) begin
                // 单周期 Reference Model：整类 SYSTEM 编码按未实现处理。
            end
            else if (funct3 != 3'b000) begin
                csr_en    = 1'b1;
                // Zicsr 一定会写 rd：写回值 = CSR 旧值。注意具体值不在这里产生，
                // 而是由流水线在 EX 级把 ALU 结果换成 CSR 读值（见 pipeline_cpu 的
                // ex_result 定义）。单周期 Reference Model 用 ENABLE_SYSTEM=0，
                // 这三行对默认行为没有任何影响。
                reg_write  = 1'b1;
                result_src = 2'b00;
                csr_funct = (funct3[1:0] == 2'b01) ? 2'b00 :  // CSRRW/CSRRWI：直接写
                            (funct3[1:0] == 2'b10) ? 2'b01 :  // CSRRS/CSRRSI：置位
                                                     2'b10;   // CSRRC/CSRRCI：清位
                csr_imm   = funct3[2];
                // CSRRS/CSRRC 系列且源为 x0（或 uimm=0）时是纯读，不产生写副作用。
                // 这条很关键：否则"读一个只读 CSR"会被误判成非法指令。
                // 注意判据是 funct3[1:0]==01（CSRRW/CSRRWI），不是 00：
                // Zicsr 合法的 funct3 只会是 001/010/011/101/110/111，
                // funct3[1:0] 永远不为 00，写成 00 会让"CSRRW 一定写"这条规则失效。
                if (funct3[1:0] == 2'b01) begin
                    csr_wen = 1'b1;
                end
                else begin
                    csr_wen = (instruction[19:15] != 5'b0);
                end
                illegal = 1'b0;
            end
            else if ((instruction[19:15] == 5'b0) && (instruction[11:7] == 5'b0)) begin
                case (instruction[31:20])
                    12'h000: begin
                        trap_ecall  = 1'b1;
                        illegal     = 1'b0;
                    end
                    12'h001: begin
                        trap_ebreak = 1'b1;
                        illegal     = 1'b0;
                    end
                    12'h302: begin
                        trap_mret   = 1'b1;
                        illegal     = 1'b0;
                    end
                    default: begin
                        // WFI、SFENCE.VMA 及其他 SYSTEM 编码保持非法指令。
                    end
                endcase
            end
        end

        default: begin
            // Keep safe defaults for unsupported opcodes.
        end
    endcase
end

endmodule
