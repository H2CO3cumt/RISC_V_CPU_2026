// Core-external instruction ROM adapter for Task 15.  It models independent
// request and response backpressure without exposing storage inside the Core.
module task15_imem_adapter #(
    parameter DEPTH = 256,
    parameter INIT_FILE = "",
    parameter RANDOM_DELAY = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    output reg         rsp_valid,
    input  wire        rsp_ready,
    output reg  [31:0] rsp_data,
    output reg         rsp_error
);
    reg [31:0] mem [0:DEPTH-1];
    reg        pending;
    reg [1:0]  delay_count;
    reg [7:0]  lfsr;
    integer    i;

    wire address_ok;
    assign address_ok = (req_addr[1:0] == 2'b00) && (req_addr[31:2] < DEPTH);

    // A pseudo-random ready pattern forces IF_REQ to retain the same PC.
    assign req_ready = !pending && !rsp_valid && (RANDOM_DELAY ? lfsr[0] : 1'b1);

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (reset) begin
            pending     <= 1'b0;
            delay_count <= 2'b0;
            rsp_valid   <= 1'b0;
            rsp_data    <= 32'b0;
            rsp_error   <= 1'b0;
            lfsr        <= 8'h5A;
        end
        else begin
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};

            if (req_valid && req_ready) begin
                pending     <= 1'b1;
                delay_count <= RANDOM_DELAY ? lfsr[2:1] : 2'b0;
                rsp_error   <= !address_ok;
                rsp_data    <= address_ok ? mem[req_addr[31:2]] : 32'b0;
            end

            if (pending) begin
                if (delay_count == 2'b0) begin
                    pending   <= 1'b0;
                    rsp_valid <= 1'b1;
                end
                else begin
                    delay_count <= delay_count - 1'b1;
                end
            end

            // Keep instruction/error stable until the Core accepts response.
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;
        end
    end
endmodule
