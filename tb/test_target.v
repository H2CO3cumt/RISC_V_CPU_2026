// Small Core-external target used only to verify Task 15 address routing.
// It records every accepted request and produces one stable response.
module test_target #(
    parameter [31:0] READ_DATA = 32'b0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wstrb,
    output reg         rsp_valid,
    input  wire        rsp_ready,
    output reg  [31:0] rsp_rdata,
    output reg         rsp_error,
    output reg  [31:0] request_count,
    output reg  [31:0] write_count
);
    assign req_ready = !rsp_valid;

    always @(posedge clk) begin
        if (reset) begin
            rsp_valid     <= 1'b0;
            rsp_rdata     <= 32'b0;
            rsp_error     <= 1'b0;
            request_count <= 32'b0;
            write_count   <= 32'b0;
        end
        else begin
            // A side effect is counted precisely once: at request acceptance.
            if (req_valid && req_ready) begin
                rsp_valid     <= 1'b1;
                rsp_rdata     <= READ_DATA;
                rsp_error     <= 1'b0;
                request_count <= request_count + 1'b1;
                if (req_write && (req_wstrb != 4'b0))
                    write_count <= write_count + 1'b1;
            end

            // rdata/error remain unchanged while rsp_valid waits for ready.
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;
        end
    end
endmodule
