module regfile(
    input clk,
    input rd_we,
    input [4:0]rd_addr,
    input [31:0]rd_data,
    input [4:0]rs1_addr,
    input [4:0]rs2_addr,
    output [31:0]rs1_data,
    output [31:0]rs2_data
);
reg [31:0]regs[0:31];
always@(posedge clk)begin
    if(rd_we && rd_addr!=0)  
        regs[rd_addr]<=rd_data;
end
assign rs1_data=(rs1_addr==5'd0)?32'h0:regs[rs1_addr];
assign rs2_data=(rs2_addr==5'd0)?32'h0:regs[rs2_addr];
endmodule
