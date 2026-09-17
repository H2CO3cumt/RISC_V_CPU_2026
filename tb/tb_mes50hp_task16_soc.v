`timescale 1ns/1ps
module tb_mes50hp_task16_soc;
    localparam EXPECTED_LINE_BYTES = 15;
    localparam EXPECTED_TOTAL_BYTES = EXPECTED_LINE_BYTES * 2;
    reg clk = 1'b0, uart_rx = 1'b1;
    wire uart_tx; wire [7:0] led; wire [7:0] rx_data; wire rx_vld, rx_err;
    integer bytes = 0, errors = 0, cycles = 0;
    integer index;
    reg [7:0] got [0:EXPECTED_TOTAL_BYTES-1];
    mes50hp_task16_soc_top #(.MEM_INIT_FILE("fpga/task16_soc/mem/task16_mmio_demo.mem"), .UART_BAUD_CYCLES(16)) dut (.clk_50m(clk), .uart0_rx(uart_rx), .uart0_tx(uart_tx), .led(led));
    UART_RX #(.MAX_1BAUD(16)) monitor (.clk_50m(clk), .rst(dut.reset), .rx(uart_tx), .rx_data(rx_data), .rx_data_vld(rx_vld), .rx_frame_error(rx_err));
    always #5 clk = ~clk;
    always @(posedge clk) if (!dut.reset) begin if (rx_vld && bytes < EXPECTED_TOTAL_BYTES) begin got[bytes] = rx_data; bytes = bytes + 1; end if (rx_err) errors = errors + 1; end
    initial begin
        while (bytes < EXPECTED_TOTAL_BYTES && cycles < 12000) begin @(posedge clk); cycles = cycles + 1; end
        @(negedge clk);
        if (led !== 8'hAA) begin $display("TEST mes50hp_task16_soc FAIL: LED=%h", led); $fatal; end
        if (bytes !== EXPECTED_TOTAL_BYTES || errors !== 0 || got[0] !== "H" || got[14] !== 8'h0A || got[15] !== "H" || got[29] !== 8'h0A) begin $display("TEST mes50hp_task16_soc FAIL: bytes=%0d errors=%0d first=%h line1_last=%h line2_first=%h line2_last=%h", bytes, errors, got[0], got[14], got[15], got[29]); $fatal; end
        for (index = 0; index < EXPECTED_LINE_BYTES; index = index + 1) begin
            if (got[index] !== got[index + EXPECTED_LINE_BYTES]) begin $display("TEST mes50hp_task16_soc FAIL: repeated line byte %0d differs", index); $fatal; end
        end
        $display("ALL MES50HP TASK16 SOC CONTINUOUS UART TEST PASS"); $finish;
    end
endmodule
