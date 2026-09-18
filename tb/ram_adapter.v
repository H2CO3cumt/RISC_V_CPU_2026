// Task 15 behaviour-level RAM target.  This module is outside the CPU Core:
// it accepts one generic data transaction at a time and returns one response.
module ram_adapter #(
    parameter DEPTH = 256,
    parameter INIT_FILE = "",
    parameter RANDOM_DELAY = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire        req_write,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wstrb,
    output reg         rsp_valid,
    input  wire        rsp_ready,
    output reg  [31:0] rsp_rdata,
    output reg         rsp_error,
    output reg  [31:0] write_side_effect_count
);
    reg [31:0] mem [0:DEPTH-1];
    reg        pending;
    reg [1:0]  delay_count;
    reg [7:0]  lfsr;
    integer    i;

    wire addr_in_range;
    assign addr_in_range = (req_addr[31:2] < DEPTH);

    // Randomized ready creates backpressure.  A response in flight blocks a
    // new request, so every accepted request maps to exactly one response.
    assign req_ready = !pending && !rsp_valid && (RANDOM_DELAY ? lfsr[0] : 1'b1);

    always @(posedge clk) begin
        if (reset) begin
            pending                 <= 1'b0;
            delay_count             <= 2'b0;
            rsp_valid               <= 1'b0;
            rsp_rdata               <= 32'b0;
            rsp_error               <= 1'b0;
            lfsr                    <= 8'hB4;
            write_side_effect_count <= 32'b0;
        end
        else begin
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};

            // A write side effect occurs only on the request handshake.
            if (req_valid && req_ready) begin
                pending     <= 1'b1;
                delay_count <= RANDOM_DELAY ? lfsr[2:1] : 2'b0;
                rsp_error   <= !addr_in_range;
                if (req_write) begin
                    if (addr_in_range) begin
                        if (req_wstrb[0]) mem[req_addr[31:2]][7:0]   <= req_wdata[7:0];
                        if (req_wstrb[1]) mem[req_addr[31:2]][15:8]  <= req_wdata[15:8];
                        if (req_wstrb[2]) mem[req_addr[31:2]][23:16] <= req_wdata[23:16];
                        if (req_wstrb[3]) mem[req_addr[31:2]][31:24] <= req_wdata[31:24];
                        write_side_effect_count <= write_side_effect_count + 1'b1;
                    end
                    rsp_rdata <= 32'b0;
                end
                else if (addr_in_range) begin
                    rsp_rdata <= mem[req_addr[31:2]];
                end
                else begin
                    rsp_rdata <= 32'b0;
                end
            end

            // The target can delay completion after accepting the request.
            if (pending) begin
                if (delay_count == 2'b0) begin
                    pending   <= 1'b0;
                    rsp_valid <= 1'b1;
                end
                else begin
                    delay_count <= delay_count - 1'b1;
                end
            end

            // Response fields stay stable until the Core accepts them.
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;
        end
    end

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end
endmodule
