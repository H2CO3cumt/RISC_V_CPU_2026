// Core-external single-outstanding data interconnect.
// Address decoding and every device-specific signal stay outside the CPU Core.
module soc_data_interconnect #(
    // 基础教学 SoC 保持 1 KiB 默认窗口；CoreMark 等大镜像只在 Core 外
    // 通过参数扩展 RAM aperture，不改变 CPU 事务接口或外设地址。
    parameter [31:0] RAM_LAST_ADDR = 32'h0000_03FF
) (
    input  wire        clk,
    input  wire        reset,

    input  wire        cpu_req_valid,
    output wire        cpu_req_ready,
    input  wire [31:0] cpu_req_addr,
    input  wire        cpu_req_write,
    input  wire [31:0] cpu_req_wdata,
    input  wire [3:0]  cpu_req_wstrb,
    output wire        cpu_rsp_valid,
    input  wire        cpu_rsp_ready,
    output wire [31:0] cpu_rsp_rdata,
    output wire        cpu_rsp_error,

    output wire        ram_req_valid,
    input  wire        ram_req_ready,
    output wire        uart_req_valid,
    input  wire        uart_req_ready,
    output wire        gpio_req_valid,
    input  wire        gpio_req_ready,
    output wire        app_req_valid,
    input  wire        app_req_ready,

    output wire [31:0] target_req_addr,
    output wire        target_req_write,
    output wire [31:0] target_req_wdata,
    output wire [3:0]  target_req_wstrb,

    input  wire        ram_rsp_valid,
    output wire        ram_rsp_ready,
    input  wire [31:0] ram_rsp_rdata,
    input  wire        ram_rsp_error,
    input  wire        uart_rsp_valid,
    output wire        uart_rsp_ready,
    input  wire [31:0] uart_rsp_rdata,
    input  wire        uart_rsp_error,
    input  wire        gpio_rsp_valid,
    output wire        gpio_rsp_ready,
    input  wire [31:0] gpio_rsp_rdata,
    input  wire        gpio_rsp_error,
    input  wire        app_rsp_valid,
    output wire        app_rsp_ready,
    input  wire [31:0] app_rsp_rdata,
    input  wire        app_rsp_error
);
    localparam TARGET_RAM  = 3'd0;
    localparam TARGET_UART = 3'd1;
    localparam TARGET_GPIO = 3'd2;
    localparam TARGET_APP  = 3'd3;
    localparam TARGET_NONE = 3'd4;

    reg        pending;
    reg [2:0]  pending_target;
    reg        unmapped_rsp_valid;

    wire ram_selected;
    wire uart_selected;
    wire gpio_selected;
    wire app_selected;
    wire [2:0] decoded_target;
    wire selected_target_ready;
    wire selected_rsp_valid;
    wire [31:0] selected_rsp_rdata;
    wire selected_rsp_error;
    wire request_busy;

    // The ranges are disjoint.  Each address therefore decodes to exactly one
    // target, or TARGET_NONE for a deterministic unmapped-address response.
    assign ram_selected  = (cpu_req_addr >= 32'h0000_0000) && (cpu_req_addr <= RAM_LAST_ADDR);
    assign uart_selected = (cpu_req_addr >= 32'h1000_0000) && (cpu_req_addr <= 32'h1000_00FF);
    assign gpio_selected = (cpu_req_addr >= 32'h1000_1000) && (cpu_req_addr <= 32'h1000_10FF);
    assign app_selected  = (cpu_req_addr >= 32'h1000_2000) && (cpu_req_addr <= 32'h1000_2FFF);
    assign decoded_target = ram_selected  ? TARGET_RAM  :
                            uart_selected ? TARGET_UART :
                            gpio_selected ? TARGET_GPIO :
                            app_selected  ? TARGET_APP  : TARGET_NONE;

    assign request_busy = pending || unmapped_rsp_valid;
    assign selected_target_ready = (decoded_target == TARGET_RAM)  ? ram_req_ready  :
                                   (decoded_target == TARGET_UART) ? uart_req_ready :
                                   (decoded_target == TARGET_GPIO) ? gpio_req_ready :
                                   (decoded_target == TARGET_APP)  ? app_req_ready  : 1'b1;

    // No second request is accepted until the unique response is consumed.
    assign cpu_req_ready = !request_busy && selected_target_ready;
    assign ram_req_valid  = cpu_req_valid && !request_busy && (decoded_target == TARGET_RAM);
    assign uart_req_valid = cpu_req_valid && !request_busy && (decoded_target == TARGET_UART);
    assign gpio_req_valid = cpu_req_valid && !request_busy && (decoded_target == TARGET_GPIO);
    assign app_req_valid  = cpu_req_valid && !request_busy && (decoded_target == TARGET_APP);

    assign target_req_addr  = cpu_req_addr;
    assign target_req_write = cpu_req_write;
    assign target_req_wdata = cpu_req_wdata;
    assign target_req_wstrb = cpu_req_wstrb;

    assign selected_rsp_valid = (pending_target == TARGET_RAM)  ? ram_rsp_valid  :
                                (pending_target == TARGET_UART) ? uart_rsp_valid :
                                (pending_target == TARGET_GPIO) ? gpio_rsp_valid :
                                (pending_target == TARGET_APP)  ? app_rsp_valid  : 1'b0;
    assign selected_rsp_rdata = (pending_target == TARGET_RAM)  ? ram_rsp_rdata  :
                                (pending_target == TARGET_UART) ? uart_rsp_rdata :
                                (pending_target == TARGET_GPIO) ? gpio_rsp_rdata :
                                (pending_target == TARGET_APP)  ? app_rsp_rdata  : 32'b0;
    assign selected_rsp_error = (pending_target == TARGET_RAM)  ? ram_rsp_error  :
                                (pending_target == TARGET_UART) ? uart_rsp_error :
                                (pending_target == TARGET_GPIO) ? gpio_rsp_error :
                                (pending_target == TARGET_APP)  ? app_rsp_error  : 1'b1;

    assign cpu_rsp_valid = unmapped_rsp_valid || (pending && selected_rsp_valid);
    assign cpu_rsp_rdata = unmapped_rsp_valid ? 32'b0 : selected_rsp_rdata;
    assign cpu_rsp_error = unmapped_rsp_valid ? 1'b1  : selected_rsp_error;

    // Ready is returned only to the endpoint whose response is being routed.
    assign ram_rsp_ready  = pending && (pending_target == TARGET_RAM)  && cpu_rsp_ready;
    assign uart_rsp_ready = pending && (pending_target == TARGET_UART) && cpu_rsp_ready;
    assign gpio_rsp_ready = pending && (pending_target == TARGET_GPIO) && cpu_rsp_ready;
    assign app_rsp_ready  = pending && (pending_target == TARGET_APP)  && cpu_rsp_ready;

    always @(posedge clk) begin
        if (reset) begin
            pending            <= 1'b0;
            pending_target     <= TARGET_NONE;
            unmapped_rsp_valid <= 1'b0;
        end
        else begin
            // Lock the selected target at request acceptance so a later CPU
            // address change cannot route the response to a different device.
            if (cpu_req_valid && cpu_req_ready) begin
                if (decoded_target == TARGET_NONE) begin
                    unmapped_rsp_valid <= 1'b1;
                end
                else begin
                    pending        <= 1'b1;
                    pending_target <= decoded_target;
                end
            end

            if (pending && selected_rsp_valid && cpu_rsp_ready) begin
                pending        <= 1'b0;
                pending_target <= TARGET_NONE;
            end

            if (unmapped_rsp_valid && cpu_rsp_ready)
                unmapped_rsp_valid <= 1'b0;
        end
    end
endmodule
