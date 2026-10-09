// EX 阶段 RAW 前递选择器。EX/MEM 的较新结果优先于 MEM/WB；Load 的值在
// EX/MEM 阶段尚未返回，所以不能从该路径前递，必须由 Load-Use Stall 处理。
module forward_unit(
    input wire [4:0] idex_rs1,
    input wire [4:0] idex_rs2,
    input wire exmem_valid,
    input wire exmem_regwrite,
    input wire exmem_memread,
    input wire [4:0] exmem_rd,
    input wire memwb_valid,
    input wire memwb_regwrite,
    input wire memwb_error,
    input wire [4:0] memwb_rd,
    output reg [1:0] forward_a,
    output reg [1:0] forward_b
);
    // 00=ID/EX 原值，01=MEM/WB，10=EX/MEM。x0 永不构成 RAW producer。
    always @(*) begin//假设刚开始我都不前递
        forward_a = 2'b00;
        forward_b = 2'b00;
        if (memwb_valid && memwb_regwrite && !memwb_error && memwb_rd != 5'd0) begin
            if (memwb_rd == idex_rs1) forward_a = 2'b01;
            if (memwb_rd == idex_rs2) forward_b = 2'b01;
        end
        // 该判断后置以保证连续写同一 rd 时选择更年轻的 EX/MEM 值。
        if (exmem_valid && exmem_regwrite && !exmem_memread && exmem_rd != 5'd0) begin
            if (exmem_rd == idex_rs1) forward_a = 2'b10;
            if (exmem_rd == idex_rs2) forward_b = 2'b10;
        end//这里的优先级是EXMEM>MEMWB,之前搞反了
    end
endmodule
