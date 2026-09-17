`timescale 1ns/1ps
module tb_mes50hp_coremark;
 reg clk=0,rx=1;wire tx;wire [7:0] led;wire [7:0] byte_data;wire byte_valid,frame_error;integer cycles=0,bytes=0,errors=0,log_file;
 mes50hp_coremark_top #(.UART_BAUD_CYCLES(8)) dut(.clk_50m(clk),.uart0_rx(rx),.uart0_tx(tx),.led(led));
 UART_RX #(.MAX_1BAUD(8)) monitor(.clk_50m(clk),.rst(dut.reset),.rx(tx),.rx_data(byte_data),.rx_data_vld(byte_valid),.rx_frame_error(frame_error));
 always #5 clk=~clk;
 always @(posedge clk) begin cycles=cycles+1;if(byte_valid)begin bytes=bytes+1;$fwrite(log_file,"%c",byte_data);end;if(frame_error)errors=errors+1;end
 initial begin log_file=$fopen("tmp/coremark_fpga/uart.log","w");while(led!==8'hc3&&cycles<5000000)@(posedge clk);repeat(200)@(posedge clk);$fclose(log_file);if(cycles>=5000000)$fatal(1,"COREMARK FPGA TOP TIMEOUT pc=%08h",dut.core.fetch_pc);if(errors)$fatal(1,"COREMARK FPGA UART ERRORS %0d",errors);if(!dut.memory_ready)$fatal(1,"COREMARK FPGA MEMORY NOT READY");$display("COREMARK FPGA TOP PASS cycles=%0d bytes=%0d",cycles,bytes);$finish;end
endmodule
