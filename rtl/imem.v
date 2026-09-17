module imem #(
    parameter DEPTH = 256,
    parameter INIT_FILE = ""
) (
    input  wire [31:0] addr,
    output reg  [31:0] instruction
);

reg [31:0] mem [0:DEPTH-1];
integer i;

initial begin
    for (i = 0; i <= DEPTH-1; i = i + 1)
        mem[i] = 32'b0;
    if (INIT_FILE != "")
        $readmemh(INIT_FILE, mem);
end

wire [31:0] word_index = addr >> 2;

always @(*) begin
    if (addr[1:0] == 2'b00 && word_index < DEPTH)
        instruction = mem[word_index];
    else
        instruction = 32'b0;
end

endmodule
