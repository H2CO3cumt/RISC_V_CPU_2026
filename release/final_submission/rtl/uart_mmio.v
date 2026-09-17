module uart_mmio #(
    // 默认对应 50 MHz / 115200 baud；Testbench 可覆盖为较小值以加快仿真。
    parameter UART_MAX_1BAUD = 50_000_000 / 115200,
    parameter UART_RX_MAX_1BAUD = 50_000_000 / 115200
) (
    input  wire        clk,
    input  wire        reset,

    // 来自 SoC interconnect 的 UART MMIO 请求
    input  wire        uart_req_valid,
    output wire        uart_req_ready,
    input  wire [31:0] uart_req_addr,
    input  wire        uart_req_write,
    input  wire [31:0] uart_req_wdata,
    input  wire [3:0]  uart_req_wstrb,

    // 返回 SoC interconnect 的响应
    output wire        uart_rsp_valid,
    input  wire        uart_rsp_ready,
    output wire [31:0] uart_rsp_rdata,
    output wire        uart_rsp_error,

    // 连接 board wrapper 的 UART 引脚
    input  wire        uart_rx,
    output wire        uart_tx
);

localparam IDLE = 1'b0;
localparam RESP = 1'b1;

localparam [5:0] UART_TXDATA_OFFSET = 6'd0;  // 0x00
localparam [5:0] UART_STATUS_OFFSET = 6'd1;  // 0x04
localparam [5:0] UART_RXDATA_OFFSET = 6'd2;  // 0x08

reg        wrapper_state;
reg [31:0] rsp_rdata_reg;
reg        rsp_error_reg;
reg [7:0]  rx_data_reg;
reg        rx_valid_reg;
reg        rx_overflow_reg;
reg        rx_frame_error_reg;

wire       uart_tx_ready;
wire       uart_tx_data_vld;
wire [7:0] uart_rx_data;
wire       uart_rx_data_vld;
wire       uart_rx_frame_error;

wire addr_aligned;
wire addr_txdata;
wire addr_status;
wire addr_rxdata;
wire legal_txdata_write;
wire legal_rxdata_read;
wire legal_status_write;
wire request_accept;
wire rxdata_read_accept;
wire tx_request_blocked;
wire rx_request_blocked;
wire [31:0] status_word;

assign addr_aligned = (uart_req_addr[1:0] == 2'b00);
assign addr_txdata = addr_aligned &&
                     (uart_req_addr[7:2] == UART_TXDATA_OFFSET);
assign addr_status = addr_aligned &&
                    (uart_req_addr[7:2] == UART_STATUS_OFFSET);
assign addr_rxdata = addr_aligned &&
                     (uart_req_addr[7:2] == UART_RXDATA_OFFSET);

// TXDATA 只使用最低 byte。这样 SB base+0 与 SW base+0 都可发送字符。
assign legal_txdata_write = addr_txdata &&
                            uart_req_write &&
                            uart_req_wstrb[0];
assign legal_rxdata_read = addr_rxdata && !uart_req_write;

// STATUS 写仅允许 W1C 清除 sticky 错误位，使用最低 byte。
assign legal_status_write = addr_status && uart_req_write && uart_req_wstrb[0];

// STATUS 在握手周期采样，之后由 rsp_rdata_reg 保持稳定。
assign status_word = {27'd0, rx_frame_error_reg, rx_overflow_reg,
                      rx_valid_reg, !uart_tx_ready, uart_tx_ready};

/*
 * 只有合法 TXDATA 写需要等待 UART 空闲。
 * 其他请求（STATUS 读、非法访问等）立即接受并返回对应响应，
 * 避免非法软件访问在 UART busy 时永久阻塞。
 */
assign tx_request_blocked = legal_txdata_write && !uart_tx_ready;
assign rx_request_blocked = legal_rxdata_read && !rx_valid_reg;
assign uart_req_ready = (wrapper_state == IDLE) &&
                        (!uart_req_valid ||
                         (!tx_request_blocked && !rx_request_blocked));

assign request_accept = uart_req_valid && uart_req_ready;
assign rxdata_read_accept = request_accept && legal_rxdata_read;

/*
 * 此脉冲是唯一 UART 发送副作用来源：
 * 一个已接受的合法 TXDATA Store 只产生一个时钟周期的有效脉冲。
 * 响应阶段即使被背压，也不会再次触发发送。
 */
assign uart_tx_data_vld = request_accept && legal_txdata_write;

assign uart_rsp_valid = (wrapper_state == RESP);
assign uart_rsp_rdata = rsp_rdata_reg;
assign uart_rsp_error = rsp_error_reg;

UART_TX #(
    .MAX_1BAUD(UART_MAX_1BAUD)
) u_uart_tx (
    .clk_50m   (clk),
    .rst       (reset),
    .tx_data_vld(uart_tx_data_vld),
    .tx_data   (uart_req_wdata[7:0]),
    .ready     (uart_tx_ready),
    .tx        (uart_tx)
);

UART_RX #(
    .MAX_1BAUD(UART_RX_MAX_1BAUD)
) u_uart_rx (
    .clk_50m       (clk),
    .rst           (reset),
    .rx            (uart_rx),
    .rx_data       (uart_rx_data),
    .rx_data_vld   (uart_rx_data_vld),
    .rx_frame_error(uart_rx_frame_error)
);

always @(posedge clk) begin
    if (reset) begin
        wrapper_state <= IDLE;
        rsp_rdata_reg <= 32'd0;
        rsp_error_reg <= 1'b0;
        rx_data_reg <= 8'd0;
        rx_valid_reg <= 1'b0;
        rx_overflow_reg <= 1'b0;
        rx_frame_error_reg <= 1'b0;
    end
    else begin
        /*
         * RXDATA 是一格邮箱：未读数据保留，新到的第二个字节不覆盖它，
         * 而是置 overflow。读请求与新字节同拍时，读走旧字节并保存新字节。
         */
        if (uart_rx_data_vld) begin
            if (rx_valid_reg && !rxdata_read_accept)
                rx_overflow_reg <= 1'b1;
            else begin
                rx_data_reg <= uart_rx_data;
                rx_valid_reg <= 1'b1;
            end
        end

        if (rxdata_read_accept && !uart_rx_data_vld)
            rx_valid_reg <= 1'b0;

        // 帧错误也是 sticky 状态；由 STATUS W1C 后才清除。
        if (uart_rx_frame_error)
            rx_frame_error_reg <= 1'b1;

        if (request_accept && legal_status_write) begin
            if (uart_req_wdata[3])
                rx_overflow_reg <= 1'b0;
            if (uart_req_wdata[4])
                rx_frame_error_reg <= 1'b0;
        end

        case (wrapper_state)
            IDLE: begin
                if (request_accept) begin
                    /*
                     * 请求在本周期被唯一接受；下一周期进入 RESP。
                     * 合法 TXDATA 写已在同一握手周期交给 UART_TX。
                     */
                    wrapper_state <= RESP;
                    rsp_rdata_reg <= 32'd0;
                    rsp_error_reg <= 1'b0;

                    if (addr_status && !uart_req_write) begin
                        rsp_rdata_reg <= status_word;
                    end
                    else if (legal_status_write) begin
                        rsp_rdata_reg <= 32'd0;
                    end
                    else if (legal_txdata_write) begin
                        rsp_rdata_reg <= 32'd0;
                    end
                    else if (legal_rxdata_read) begin
                        rsp_rdata_reg <= {24'd0, rx_data_reg};
                    end
                    else begin
                        // TXDATA 读、RXDATA 写、未定义 offset、未对齐、错误 strobe。
                        rsp_rdata_reg <= 32'd0;
                        rsp_error_reg <= 1'b1;
                    end
                end
            end

            RESP: begin
                /*
                 * 响应未被上游取走前，rdata/error 均保持不变，
                 * 并且 req_ready=0，防止第二个请求或重复副作用。
                 */
                if (uart_rsp_valid && uart_rsp_ready) begin
                    wrapper_state <= IDLE;
                end
            end

            default: begin
                wrapper_state <= IDLE;
            end
        endcase
    end
end

endmodule
