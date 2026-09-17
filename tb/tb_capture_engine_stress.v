`timescale 1ns/1ps
module tb_capture_engine_stress;
 reg clk=0,reset=1,arm=0,stop=0,clear=0;reg[7:0]channels=0;reg[15:0]read_index=0;wire[7:0]read_data;wire armed,triggered,done,overflow;wire[15:0]trigger_index,capture_count;integer run,failures=0,wait_cycles;
 capture_engine #(.CHANNELS(8),.DEPTH(16)) dut(.clk(clk),.reset(reset),.channels(channels),.arm(arm),.stop(stop),.clear(clear),.sample_div(16'd0),.channel_mask(8'hff),.trigger_mask(8'h01),.trigger_value(8'h01),.trigger_rise(8'h00),.trigger_fall(8'h00),.pre_count(16'd2),.post_count(16'd2),.read_index(read_index),.read_data(read_data),.armed(armed),.triggered(triggered),.done(done),.overflow(overflow),.trigger_index(trigger_index),.capture_count(capture_count));
 always #5 clk=~clk;
 task pulse;output reg signal;begin signal=1;@(posedge clk);#1;signal=0;end endtask
 initial begin
  repeat(2)@(posedge clk);#1;reset=0;
  for(run=0;run<20;run=run+1)begin
   clear=1;@(posedge clk);#1;clear=0;channels=0;arm=1;@(posedge clk);#1;arm=0;
   repeat(3)@(posedge clk);#1;channels=1;
   wait_cycles=0;while(!done&&wait_cycles<20)begin @(posedge clk);#1;wait_cycles=wait_cycles+1;end
   if(!done||!triggered||overflow||capture_count!=5||trigger_index!=2)begin $display("CAPTURE STRESS RUN %0d FAIL done=%b trig=%b overflow=%b count=%0d index=%0d",run,done,triggered,overflow,capture_count,trigger_index);failures=failures+1;end
   else $display("CAPTURE STRESS RUN %0d PASS count=%0d",run,capture_count);
   if((run%5)==4)begin reset=1;@(posedge clk);#1;reset=0;end
  end
  if(failures==0)$display("ALL 20 CAPTURE STRESS TEST PASS");else $fatal(1,"CAPTURE STRESS %0d FAIL",failures);$finish;
 end
endmodule
