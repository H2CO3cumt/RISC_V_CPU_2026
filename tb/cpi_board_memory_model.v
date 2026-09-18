// T1 只读观测专用：与实体板 CoreMark 镜像 fpga/coremark/rtl/coremark_program_memory.v
// 中 coremark_imem / coremark_dmem 的语义与时序**逐拍一致**的存储器行为模型。
//
// 为什么必须逐拍一致：历史上 RTL 仿真用的是 tb/ram_adapter.v / tb/pipeline_imem_adapter.v，
// 两者的 req_ready 策略与响应延迟和板上不同（数据侧多一拍延迟、取指侧允许交接当拍接收），
// 因此仿真 CPI 与板上 CPI 不同源，不能用来给板级 CPI 归因。
//
// ALLOW_HANDOFF：0 = 实体板现状（req_ready = !rsp_valid）；
//               1 = 允许“响应被接收的同一拍再收一笔新请求”，用于 T1 量化这一策略的影响。
module cpi_board_imem #(
    parameter DEPTH = 8192,
    parameter INIT_FILE = "",
    parameter ALLOW_HANDOFF = 0
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
    integer i;
    wire address_ok = (req_addr[1:0] == 2'b00) && (req_addr[31:2] < DEPTH);
    assign req_ready = ALLOW_HANDOFF ? (!rsp_valid || rsp_ready) : !rsp_valid;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'b0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end
    always @(posedge clk) begin
        if (reset) begin rsp_valid <= 1'b0; rsp_data <= 32'd0; rsp_error <= 1'b0; end
        else if (req_valid && req_ready) begin
            rsp_valid <= 1'b1;
            rsp_error <= !address_ok;
            rsp_data  <= address_ok ? mem[req_addr[31:2]] : 32'd0;
        end
        else if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;
    end
endmodule

// 数据侧：与 coremark_dmem 一致（单存储体，地址在请求被接收当拍锁存、响应次拍有效）。
module cpi_board_dmem #(
    parameter DEPTH = 16384,
    parameter INIT_FILE = "",
    parameter ALLOW_HANDOFF = 0
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
    output reg         rsp_error
);
    reg [31:0] mem [0:DEPTH-1];
    integer i;
    wire address_ok = (req_addr[31:2] < DEPTH);
    assign req_ready = ALLOW_HANDOFF ? (!rsp_valid || rsp_ready) : !rsp_valid;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'b0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end
    always @(posedge clk) begin
        if (reset) begin rsp_valid <= 1'b0; rsp_rdata <= 32'd0; rsp_error <= 1'b0; end
        else if (req_valid && req_ready) begin
            rsp_valid <= 1'b1;
            rsp_error <= !address_ok;
            if (req_write) begin
                rsp_rdata <= 32'd0;
                if (address_ok) begin
                    if (req_wstrb[0]) mem[req_addr[31:2]][7:0]   <= req_wdata[7:0];
                    if (req_wstrb[1]) mem[req_addr[31:2]][15:8]  <= req_wdata[15:8];
                    if (req_wstrb[2]) mem[req_addr[31:2]][23:16] <= req_wdata[23:16];
                    if (req_wstrb[3]) mem[req_addr[31:2]][31:24] <= req_wdata[31:24];
                end
            end
            else rsp_rdata <= address_ok ? mem[req_addr[31:2]] : 32'd0;
        end
        else if (rsp_valid && rsp_ready) rsp_valid <= 1'b0;
    end
endmodule
