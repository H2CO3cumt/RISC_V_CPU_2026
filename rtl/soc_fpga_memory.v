// Synthesizable, single-outstanding instruction and data RAM adapters for
// the Task 16 FPGA SoC.  They implement the frozen generic transaction ports;
// address decoding and all peripherals remain outside the CPU Core.
module soc_fpga_imem #(
    parameter DEPTH = 256,
    parameter INIT_FILE = ""
) (
    input wire clk, input wire reset,
    input wire req_valid, output wire req_ready, input wire [31:0] req_addr,
    output reg rsp_valid, input wire rsp_ready,
    output reg [31:0] rsp_data, output reg rsp_error
);
    wire address_ok = (req_addr[1:0] == 2'b00) && (req_addr[31:2] < DEPTH);
    assign req_ready = !rsp_valid;
    // The PDS synthesis flow does not consume $readmemh initial blocks.
    // Keep the small Task 16 image as elaboration-time constants instead.
    function [31:0] image_word;
        input [31:0] index;
        begin
            case (index)
                32'd0: image_word = 32'h40000113; 32'd1: image_word = 32'h008000EF;
                32'd2: image_word = 32'h0000006F; 32'd3: image_word = 32'h100017B7;
                32'd4: image_word = 32'h0AA00713; 32'd5: image_word = 32'h00E7A023;
                32'd6: image_word = 32'h04800813; 32'd7: image_word = 32'h10000737;
                32'd8: image_word = 32'h00470713; 32'd9: image_word = 32'h10000537;
                32'd10: image_word = 32'h06300593; 32'd11: image_word = 32'h05400693;
                32'd12: image_word = 32'h00080613; 32'd13: image_word = 32'h00072783;
                32'd14: image_word = 32'h0017F793; 32'd15: image_word = 32'hFE078CE3;
                32'd16: image_word = 32'h00C52023; 32'd17: image_word = 32'h00168693;
                32'd18: image_word = 32'h0006C603; 32'd19: image_word = 32'hFEB694E3;
                32'd20: image_word = 32'hFDDFF06F; 32'd21: image_word = 32'h6C6C6548;
                32'd22: image_word = 32'h4952206F; 32'd23: image_word = 32'h562D4353;
                32'd24: image_word = 32'h000A0D21;
                default: image_word = 32'd0;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if (reset) begin rsp_valid <= 1'b0; rsp_data <= 32'd0; rsp_error <= 1'b0; end
        else begin
            if (req_valid && req_ready) begin
                rsp_valid <= 1'b1;
                rsp_error <= !address_ok;
                rsp_data <= address_ok ? image_word(req_addr[31:2]) : 32'd0;
            end else if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;
        end
    end
endmodule

module soc_fpga_dmem #(
    parameter DEPTH = 256,
    parameter INIT_FILE = ""
) (
    input wire clk, input wire reset,
    input wire req_valid, output wire req_ready,
    input wire [31:0] req_addr, input wire req_write,
    input wire [31:0] req_wdata, input wire [3:0] req_wstrb,
    output reg rsp_valid, input wire rsp_ready,
    output reg [31:0] rsp_rdata, output reg rsp_error
);
    reg [31:0] mem [0:DEPTH-1];
    reg [DEPTH-1:0] word_written;
    integer i;
    wire address_ok = (req_addr[31:2] < DEPTH);
    wire [31:0] current_word = word_written[req_addr[31:2]] ?
                               mem[req_addr[31:2]] :
                               image_word(req_addr[31:2]);
    assign req_ready = !rsp_valid;
    function [31:0] image_word;
        input [31:0] index;
        begin
            case (index)
                32'd21: image_word = 32'h6C6C6548;
                32'd22: image_word = 32'h4952206F;
                32'd23: image_word = 32'h562D4353;
                32'd24: image_word = 32'h000A0D21;
                default: image_word = 32'd0;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if (reset) begin
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'd0;
            rsp_error <= 1'b0;
            word_written <= {DEPTH{1'b0}};
        end
        else begin
            if (req_valid && req_ready) begin
                rsp_valid <= 1'b1;
                rsp_error <= !address_ok;
                if (req_write) begin
                    rsp_rdata <= 32'd0;
                    if (address_ok) begin
                        // 第一次部分写入时，未选中的字节必须保留初始化镜像内容。
                        mem[req_addr[31:2]][7:0] <= req_wstrb[0] ?
                            req_wdata[7:0] : current_word[7:0];
                        mem[req_addr[31:2]][15:8] <= req_wstrb[1] ?
                            req_wdata[15:8] : current_word[15:8];
                        mem[req_addr[31:2]][23:16] <= req_wstrb[2] ?
                            req_wdata[23:16] : current_word[23:16];
                        mem[req_addr[31:2]][31:24] <= req_wstrb[3] ?
                            req_wdata[31:24] : current_word[31:24];
                        word_written[req_addr[31:2]] <= 1'b1;
                    end
                end
                else begin
                    // 运行时写入后从同一 mem 存储体读回；未写地址仍返回初始化镜像。
                    rsp_rdata <= address_ok ? current_word : 32'd0;
                end
            end
            else if (rsp_valid && rsp_ready) begin
                rsp_valid <= 1'b0;
            end
        end
    end
endmodule

// Reserved Application-MMIO range receives deterministic error responses
// until Task 30 replaces it with the capture-engine wrapper.
module soc_fpga_app_dummy (
    input wire clk, input wire reset, input wire req_valid, output wire req_ready,
    output reg rsp_valid, input wire rsp_ready, output wire [31:0] rsp_rdata,
    output wire rsp_error
);
    assign req_ready = !rsp_valid;
    assign rsp_rdata = 32'd0;
    assign rsp_error = 1'b1;
    always @(posedge clk) begin
        if (reset) rsp_valid <= 1'b0;
        else if (req_valid && req_ready) rsp_valid <= 1'b1;
        else if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;
    end
endmodule
