module dmem #(
    parameter DEPTH = 256
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire        we,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata
);

    reg  [31:0] mem [0:DEPTH-1];
    wire [31:0] word_index;
    wire        addr_valid;

    assign word_index = addr >> 2;
    assign addr_valid = (word_index < DEPTH);

    always @(*) begin
        rdata = 32'b0;
        if (addr_valid) begin
            rdata = mem[word_index];
        end
    end

    always @(posedge clk) begin
        if (we && addr_valid) begin
            if (wstrb[0]) mem[word_index][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[word_index][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[word_index][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[word_index][31:24] <= wdata[31:24];
        end
    end

endmodule
