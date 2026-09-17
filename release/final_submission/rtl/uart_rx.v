module UART_RX #(
    // 50 MHz / 115200 baud；Testbench 可覆盖为较小数值以缩短仿真。
    parameter MAX_1BAUD = 50_000_000 / 115200
) (
    input  wire       clk_50m,
    input  wire       rst,
    input  wire       rx,
    output wire [7:0] rx_data,
    output reg        rx_data_vld,
    output reg        rx_frame_error
);

localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam DATA  = 2'b10;
localparam STOP  = 2'b11;
localparam HALF_1BAUD = MAX_1BAUD / 2;

reg [1:0]  cstate;
reg [1:0]  nstate;
reg [15:0] cnt_baud;
reg [2:0]  cnt_bit;
reg [7:0]  rx_temp;

// 两级同步后再延迟一拍；边沿检测不使用可能亚稳的第一级寄存器。
reg rx_r1;
reg rx_r2;
reg rx_r2_d;

wire rx_nege;
wire add_baud;
wire end_baud;
wire sample_middle;

assign rx_nege = rx_r2_d && !rx_r2;
assign add_baud = (cstate != IDLE);
assign end_baud = add_baud && (cnt_baud == MAX_1BAUD - 1);
assign sample_middle = add_baud && (cnt_baud == HALF_1BAUD);
assign rx_data = rx_temp;

always @(posedge clk_50m or posedge rst) begin
    if (rst) begin
        rx_r1   <= 1'b1;
        rx_r2   <= 1'b1;
        rx_r2_d <= 1'b1;
    end
    else begin
        rx_r1   <= rx;
        rx_r2   <= rx_r1;
        rx_r2_d <= rx_r2;
    end
end

always @(posedge clk_50m or posedge rst) begin
    if (rst)
        cnt_baud <= 16'd0;
    else if (add_baud) begin
        if (end_baud)
            cnt_baud <= 16'd0;
        else
            cnt_baud <= cnt_baud + 1'b1;
    end
    else
        cnt_baud <= 16'd0;
end

always @(posedge clk_50m or posedge rst) begin
    if (rst)
        cnt_bit <= 3'd0;
    else if (cstate == IDLE)
        cnt_bit <= 3'd0;
    else if ((cstate == DATA) && end_baud) begin
        if (cnt_bit == 3'd7)
            cnt_bit <= 3'd0;
        else
            cnt_bit <= cnt_bit + 1'b1;
    end
end

always @(posedge clk_50m or posedge rst) begin
    if (rst)
        cstate <= IDLE;
    else
        cstate <= nstate;
end

always @(*) begin
    nstate = cstate;
    case (cstate)
        IDLE: begin
            if (rx_nege)
                nstate = START;
        end

        START: begin
            // 起始位中点已回到高电平，说明只是毛刺，丢弃本次检测。
            if (sample_middle && rx_r2)
                nstate = IDLE;
            else if (end_baud)
                nstate = DATA;
        end

        DATA: begin
            if (end_baud && (cnt_bit == 3'd7))
                nstate = STOP;
        end

        STOP: begin
            /*
             * 停止位中点确认后即可结束本帧。同步器会让内部状态略晚于
             * 线上边界；此处不再额外等待半个停止位，才能接住无间隔帧
             * 紧随而来的下一起始位。
             */
            if (sample_middle)
                nstate = IDLE;
        end

        default: nstate = IDLE;
    endcase
end

always @(posedge clk_50m or posedge rst) begin
    if (rst) begin
        rx_temp        <= 8'd0;
        rx_data_vld    <= 1'b0;
        rx_frame_error <= 1'b0;
    end
    else begin
        // 两个输出均为单周期事件，wrapper 再决定是否缓存或报告 overflow。
        rx_data_vld    <= 1'b0;
        rx_frame_error <= 1'b0;

        // UART 规定数据位低位先到达。
        if ((cstate == DATA) && sample_middle)
            rx_temp[cnt_bit] <= rx_r2;

        /*
         * 只有停止位中心为高才提交本帧数据；这避免把 break 或坏帧
         * 当成有效字节。停止位为低时只报告 frame_error，不更新有效标志。
         */
        if ((cstate == STOP) && sample_middle) begin
            if (rx_r2)
                rx_data_vld <= 1'b1;
            else
                rx_frame_error <= 1'b1;
        end
    end
end

endmodule
