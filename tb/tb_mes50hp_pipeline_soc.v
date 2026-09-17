`timescale 1ns/1ps
module tb_mes50hp_pipeline_soc;
 reg clk=0,rx=1;wire tx;wire [7:0]led;wire [7:0]rxdata;wire rxv,rxerr;integer bytes=0,errors=0,cycles=0,i;reg [7:0]got[0:29];
 mes50hp_pipeline_soc_top #(.UART_BAUD_CYCLES(16)) dut(.clk_50m(clk),.uart0_rx(rx),.uart0_tx(tx),.led(led));
 UART_RX #(.MAX_1BAUD(16)) mon(.clk_50m(clk),.rst(dut.reset),.rx(tx),.rx_data(rxdata),.rx_data_vld(rxv),.rx_frame_error(rxerr));
 always #5 clk=~clk;always @(posedge clk)if(!dut.reset)begin cycles=cycles+1;if(rxv&&bytes<30)begin got[bytes]=rxdata;bytes=bytes+1;end if(rxerr)errors=errors+1;end
 initial begin while(bytes<30&&cycles<25000)@(posedge clk);@(negedge clk);if(led!==8'haa||bytes!==30||errors!==0||got[0]!=="H"||got[14]!==8'h0a||got[15]!=="H"||got[29]!==8'h0a)$fatal(1,"PIPELINE SOC FAIL led=%h bytes=%0d errors=%0d",led,bytes,errors);for(i=0;i<15;i=i+1)if(got[i]!==got[i+15])$fatal(1,"PIPELINE UART REPEAT FAIL byte=%0d",i);$display("ALL MES50HP PIPELINE SOC TEST PASS");$finish;end
 initial #300000 $fatal(1,"PIPELINE SOC TIMEOUT");
endmodule
