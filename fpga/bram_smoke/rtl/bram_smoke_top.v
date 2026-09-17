// Task 10 FPGA smoke test.
// The board wrapper owns board-specific pins and polarity; the CPU will not.
module bram_smoke_top (
    input  wire clk,
    output wire status_led_n
);

    // The remote DUT's external reset may remain asserted.  Use a short
    // configuration-time power-on reset instead of exposing rst_n here.
    reg [7:0] por_count = 8'd0;
    reg       reset_done = 1'b0;

    always @(posedge clk) begin
        if (!reset_done) begin
            por_count <= por_count + 1'b1;
            if (&por_count)
                reset_done <= 1'b1;
        end
    end

    localparam ST_WAIT       = 3'd0;
    localparam ST_WRITE      = 3'd1;
    localparam ST_READ_INIT  = 3'd2;
    localparam ST_READ_ISSUE = 3'd3;
    localparam ST_READ_CHECK = 3'd4;
    localparam ST_PASS       = 3'd5;
    localparam ST_FAIL       = 3'd6;
    localparam [31:0] LFSR_SEED = 32'h1ACE_B00C;

    reg [2:0]  state = ST_WAIT;
    reg [9:0]  mem_addr = 10'd0;
    wire [9:0] ram_addr = mem_addr;
    reg [31:0] ram_wdata;
    reg        ram_we;
    reg [31:0] ram_rdata;
    // 1024 x 32 = 32 Kbit.  Dynamic addresses and data deliberately prevent
    // PDS from collapsing this test into a few LUT RAM bits.
    reg [31:0] ram [0:1023];
    reg [31:0] write_lfsr = LFSR_SEED;
    reg [31:0] expected_lfsr = LFSR_SEED;
    reg [23:0] blink_count = 24'd0;

    function [31:0] lfsr_next;
        input [31:0] value;
        begin
            lfsr_next = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
        end
    endfunction

    // This is intentionally a synchronous-read RAM template: an address is
    // sampled on one rising edge and its corresponding rdata is checked on
    // the following state/edge.
    always @(posedge clk) begin
        if (ram_we)
            ram[ram_addr] <= ram_wdata;
        ram_rdata <= ram[ram_addr];
    end

    always @(*) begin
        ram_wdata = 32'd0;
        ram_we    = 1'b0;
        case (state)
            ST_WRITE: begin
                ram_wdata = write_lfsr;
                ram_we    = 1'b1;
            end
            default: ;
        endcase
    end

    always @(posedge clk) begin
        if (!reset_done) begin
            state       <= ST_WAIT;
            blink_count <= 24'd0;
            mem_addr    <= 10'd0;
            write_lfsr  <= LFSR_SEED;
            expected_lfsr <= LFSR_SEED;
        end else begin
            case (state)
                ST_WAIT: state <= ST_WRITE;
                ST_WRITE: begin
                    if (mem_addr == 10'd1023) begin
                        state <= ST_READ_INIT;
                    end else begin
                        mem_addr   <= mem_addr + 1'b1;
                        write_lfsr <= lfsr_next(write_lfsr);
                    end
                end
                ST_READ_INIT: begin
                    mem_addr      <= 10'd0;
                    expected_lfsr <= LFSR_SEED;
                    state         <= ST_READ_ISSUE;
                end
                ST_READ_ISSUE: state <= ST_READ_CHECK;
                ST_READ_CHECK: begin
                    if (ram_rdata != expected_lfsr) begin
                        state <= ST_FAIL;
                    end else if (mem_addr == 10'd1023) begin
                        state <= ST_PASS;
                    end else begin
                        mem_addr      <= mem_addr + 1'b1;
                        expected_lfsr <= lfsr_next(expected_lfsr);
                        state         <= ST_READ_ISSUE;
                    end
                end
                ST_FAIL: blink_count <= blink_count + 1'b1;
                default: ;
            endcase
        end
    end

    // S3 LED[0] is active low: solid on means BRAM test PASS; blinking means
    // FAIL; off while the self-test is still running.
    assign status_led_n = (state == ST_PASS) ? 1'b0 :
                          (state == ST_FAIL) ? blink_count[23] : 1'b1;

endmodule
