`timescale 1ns/1ps
module tb_capture_engine;
 localparam DEPTH=8; reg clk=0,reset=1; reg [7:0] channels=0; reg arm=0,stop=0,clear=0; reg [15:0] sample_div=0,pre_count=0,post_count=0,read_index=0; reg [7:0] channel_mask=8'hff,trigger_mask=0,trigger_value=0,trigger_rise=0,trigger_fall=0; wire [7:0] read_data; wire armed,triggered,done,overflow; wire [15:0] trigger_index,capture_count; integer failures=0,i;
 capture_engine #(.CHANNELS(8),.DEPTH(DEPTH)) dut(.clk(clk),.reset(reset),.channels(channels),.arm(arm),.stop(stop),.clear(clear),.sample_div(sample_div),.channel_mask(channel_mask),.trigger_mask(trigger_mask),.trigger_value(trigger_value),.trigger_rise(trigger_rise),.trigger_fall(trigger_fall),.pre_count(pre_count),.post_count(post_count),.read_index(read_index),.read_data(read_data),.armed(armed),.triggered(triggered),.done(done),.overflow(overflow),.trigger_index(trigger_index),.capture_count(capture_count));
 always #5 clk=~clk;
 task pulse_arm; begin @(negedge clk);arm=1;@(posedge clk);#1 arm=0;end endtask
 task pulse_stop; begin @(negedge clk);stop=1;@(posedge clk);#1 stop=0;end endtask
 task sample; input [7:0]v; begin @(negedge clk);channels=v;@(posedge clk);end endtask
 task check; input cond; input [8*40-1:0]name; begin if(cond)$display("TEST %0s PASS",name);else begin $display("TEST %0s FAIL",name);failures=failures+1;end end endtask
 initial begin
  repeat(2)@(posedge clk);reset=0;
  // Stop without trigger must finish cleanly and must not report overflow.
  trigger_mask=0;pre_count=0;post_count=0;pulse_arm;repeat(4)sample(8'h00);check(!done,"no-trigger waiting");pulse_stop;@(posedge clk);check(done&& !armed,"stop completes");check(!overflow,"stop no overflow");
  // Level trigger with pre/post capture and channel mask.
  reset=1;@(posedge clk);reset=0;trigger_mask=1;trigger_value=1;trigger_rise=0;trigger_fall=0;channel_mask=8'h01;pre_count=2;post_count=2;pulse_arm;sample(8'h00);sample(8'h00);sample(8'h01);sample(8'h01);sample(8'h01);wait(done);check(triggered,"level triggered");check(capture_count==5,"exact pre trigger post count");check(trigger_index==2,"logical trigger index");read_index=0;#1;check(read_data==0,"pre sample 0");read_index=2;#1;check(read_data==1,"trigger sample");read_index=3;#1;check(read_data==1,"channel mask store");
  // Rising-edge trigger and explicit clear.
  reset=1;@(posedge clk);#1 reset=0;trigger_mask=1;trigger_value=0;trigger_rise=1;trigger_fall=0;pre_count=4;post_count=0;pulse_arm;sample(0);sample(0);sample(1);wait(done);check(triggered,"rise triggered");check(capture_count==3&&trigger_index==2,"early trigger logical window");clear=1;@(posedge clk);#1 clear=0;check(!done&&!triggered&&!armed,"clear reset");
  // Falling edge trigger and channel mask are independent of level trigger.
  trigger_mask=1;trigger_value=0;trigger_rise=0;trigger_fall=1;pre_count=0;post_count=0;pulse_arm;sample(8'h01);sample(8'h01);sample(8'h00);wait(done);check(triggered,"fall triggered");
  // A nonzero divider creates a clock-enable interval rather than a new clock.
  clear=1;@(posedge clk);#1 clear=0;sample_div=2;trigger_mask=0;pulse_arm;sample(0);sample(0);#1 check(capture_count==0,"sample divider hold");sample(0);#1 check(capture_count==1,"sample divider tick");pulse_stop;
  // An edge occurring between divided sample ticks must remain visible at the
  // next effective sample; comparing against the previous system clock loses it.
  clear=1;@(posedge clk);#1 clear=0;sample_div=2;channels=1;trigger_mask=1;trigger_rise=0;trigger_fall=1;pre_count=0;post_count=0;pulse_arm;sample(0);sample(0);sample(0);wait(done);check(triggered&&capture_count==1,"divided edge retained");
  // Small ring buffer saturates and flags overflow after capacity is exceeded.
  clear=1;@(posedge clk);#1 clear=0;sample_div=0;trigger_mask=0;pre_count=0;post_count=0;pulse_arm;for(i=0;i<DEPTH+3;i=i+1)sample(i[7:0]);pulse_stop;@(posedge clk);#1;check(capture_count==DEPTH,"count saturates");check(overflow,"overflow flag");
  reset=1;@(posedge clk);#1 reset=0;trigger_mask=1;trigger_value=1;trigger_rise=0;trigger_fall=0;channel_mask=1;pre_count=3;post_count=2;pulse_arm;for(i=0;i<10;i=i+1)sample(0);sample(1);sample(0);sample(0);wait(done);check(capture_count==6&&trigger_index==3,"wrapped logical window");read_index=3;#1;check(read_data==1,"wrapped trigger sample");check(overflow,"pretrigger wrap reported");
  reset=1;@(posedge clk);#1 check(capture_count==0&&!done&&!overflow,"reset clears");
  if(failures==0)$display("ALL CAPTURE ENGINE TEST PASS");else $fatal(1,"CAPTURE ENGINE %0d FAIL",failures);$finish;
 end
 initial #1000000 $fatal(1,"CAPTURE ENGINE TIMEOUT");
endmodule
