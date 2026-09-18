`timescale 1ns/1ps
// Pipeline + real SoC interconnect + application mux integration.  The
// analyzer inputs are driven as a deterministic in-simulation source.
module tb_logic_analyzer_soc;
 reg clk=0,reset=1,uart_rx=1; reg [7:0] capture_ch=0; wire uart_tx; wire [31:0] gpio_out;
 wire [7:0] mon_data; wire mon_vld,mon_err; integer cycles=0,bytes=0,errors=0,failures=0; reg [7:0] got[0:255];
 wire iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de; wire [31:0] ia,idata,da,dwd,drd; wire [3:0] dst;
 wire ram_v,ram_r,uart_v,uart_r,gpio_v,gpio_r,app_v,app_r; wire [31:0] ta,twd,ram_rd,uart_rd,gpio_rd,app_rd; wire tw,ram_sv,uart_sv,gpio_sv,app_sv,ram_sr,uart_sr,gpio_sr,app_sr; wire [3:0] tws; wire ram_se,uart_se,gpio_se,app_se;
 wire p_req_v,p_req_r,p_rsp_v,p_rsp_r,p_err; wire [31:0] p_addr,p_wdata,p_rdata; wire p_write; wire [3:0] p_wstrb;
 wire a_req_v,a_req_r,a_rsp_v,a_rsp_r,a_err; wire [31:0] a_addr,a_wdata,a_rdata; wire a_write; wire [3:0] a_wstrb; wire [7:0] sample_outputs;
 wire tv,ev_stall,ev_load,ev_branch,ev_taken,ev_flush; wire [63:0] perf_cycles,perf_instret,perf_stalls,perf_loads,perf_branches,perf_taken_count,perf_flushes;
 pipeline_cpu core(.clk(clk),.reset(reset),.trace_valid(tv),.trace_pc(),.trace_instruction(),.trace_rd_we(),.trace_rd_addr(),.trace_rd_data(),.trace_mem_we(),.trace_mem_addr(),.trace_mem_data(),.trace_mem_wstrb(),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(ev_stall),.event_load_stall(ev_load),.event_branch(ev_branch),.event_branch_taken(ev_taken),.event_flush(ev_flush));
 pipeline_imem_adapter #(.DEPTH(1024),.INIT_FILE("software/logic_analyzer/build/logic_analyzer.mem"),.RANDOM_DELAY(1)) imem(.clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 ram_adapter #(.DEPTH(1024),.INIT_FILE("software/logic_analyzer/build/logic_analyzer.mem"),.RANDOM_DELAY(1)) ram(.clk(clk),.reset(reset),.req_valid(ram_v),.req_ready(ram_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(ram_sv),.rsp_ready(ram_sr),.rsp_rdata(ram_rd),.rsp_error(ram_se),.write_side_effect_count());
 soc_data_interconnect #(.RAM_LAST_ADDR(32'h0000_0fff)) xbar(.clk(clk),.reset(reset),.cpu_req_valid(dv),.cpu_req_ready(dr),.cpu_req_addr(da),.cpu_req_write(dw),.cpu_req_wdata(dwd),.cpu_req_wstrb(dst),.cpu_rsp_valid(dsv),.cpu_rsp_ready(dsr),.cpu_rsp_rdata(drd),.cpu_rsp_error(de),.ram_req_valid(ram_v),.ram_req_ready(ram_r),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.app_req_valid(app_v),.app_req_ready(app_r),.target_req_addr(ta),.target_req_write(tw),.target_req_wdata(twd),.target_req_wstrb(tws),.ram_rsp_valid(ram_sv),.ram_rsp_ready(ram_sr),.ram_rsp_rdata(ram_rd),.ram_rsp_error(ram_se),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.app_rsp_valid(app_sv),.app_rsp_ready(app_sr),.app_rsp_rdata(app_rd),.app_rsp_error(app_se));
 uart_mmio #(.UART_MAX_1BAUD(16),.UART_RX_MAX_1BAUD(16)) uart(.clk(clk),.reset(reset),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.uart_req_addr(ta),.uart_req_write(tw),.uart_req_wdata(twd),.uart_req_wstrb(tws),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.uart_rx(uart_rx),.uart_tx(uart_tx));
 gpio_mmio gpio(.clk(clk),.reset(reset),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.gpio_req_addr(ta),.gpio_req_write(tw),.gpio_req_wdata(twd),.gpio_req_wstrb(tws),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.gpio_out(gpio_out));
 perf_monitor perf(.clk(clk),.reset(reset),.clear(1'b0),.enable(1'b1),.event_retire(tv),.event_stall(ev_stall),.event_load_stall(ev_load),.event_branch(ev_branch),.event_branch_taken(ev_taken),.event_flush(ev_flush),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes));
 perf_mmio perf_mmio(.clk(clk),.reset(reset),.req_valid(p_req_v),.req_ready(p_req_r),.req_addr(p_addr),.req_write(p_write),.req_wdata(p_wdata),.req_wstrb(p_wstrb),.rsp_valid(p_rsp_v),.rsp_ready(p_rsp_r),.rsp_rdata(p_rdata),.rsp_error(p_err),.clear(),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes));
 logic_analyzer_mmio analyzer(.clk(clk),.reset(reset),.req_valid(a_req_v),.req_ready(a_req_r),.req_addr(a_addr),.req_write(a_write),.req_wdata(a_wdata),.req_wstrb(a_wstrb),.rsp_valid(a_rsp_v),.rsp_ready(a_rsp_r),.rsp_rdata(a_rdata),.rsp_error(a_err),.channels(capture_ch),.sample_outputs(sample_outputs));
 application_mmio_mux appmux(.clk(clk),.reset(reset),.req_valid(app_v),.req_ready(app_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(app_sv),.rsp_ready(app_sr),.rsp_rdata(app_rd),.rsp_error(app_se),.perf_req_valid(p_req_v),.perf_req_ready(p_req_r),.perf_req_addr(p_addr),.perf_req_write(p_write),.perf_req_wdata(p_wdata),.perf_req_wstrb(p_wstrb),.perf_rsp_valid(p_rsp_v),.perf_rsp_ready(p_rsp_r),.perf_rsp_rdata(p_rdata),.perf_rsp_error(p_err),.la_req_valid(a_req_v),.la_req_ready(a_req_r),.la_req_addr(a_addr),.la_req_write(a_write),.la_req_wdata(a_wdata),.la_req_wstrb(a_wstrb),.la_rsp_valid(a_rsp_v),.la_rsp_ready(a_rsp_r),.la_rsp_rdata(a_rdata),.la_rsp_error(a_err));
 UART_RX #(.MAX_1BAUD(16)) monitor(.clk_50m(clk),.rst(reset),.rx(uart_tx),.rx_data(mon_data),.rx_data_vld(mon_vld),.rx_frame_error(mon_err));
 always #5 clk=~clk;
 always @(posedge clk) begin
  if(!reset) begin
   cycles=cycles+1;
   if(mon_vld&&bytes<256) begin got[bytes]=mon_data;bytes=bytes+1;end
   if(mon_err) errors=errors+1;
   if(analyzer.cap.armed) begin if(analyzer.cap.capture_count<16'd3) capture_ch<=8'h00; else capture_ch<=8'h01; end else capture_ch<=8'h00;
  end
 end
 initial begin
  repeat(2) @(negedge clk); reset=1'b0;
  while((bytes<13 || !analyzer.cap.done) && cycles<200000) @(posedge clk);
  @(negedge clk);
  if(cycles>=200000) begin $display("LOGIC ANALYZER SOC FAIL TIMEOUT"); failures=failures+1; end
  if(gpio_out!==32'h5a) begin $display("LOGIC ANALYZER SOC FAIL GPIO %h",gpio_out); failures=failures+1; end
  if(errors!=0) begin $display("LOGIC ANALYZER SOC FAIL UART errors=%0d",errors); failures=failures+1; end
  if(bytes<13) begin $display("LOGIC ANALYZER SOC FAIL UART bytes=%0d",bytes); failures=failures+1; end
  else if(got[0]!="L"||got[1]!="A"||got[2]!=" "||got[3]!="R"||got[4]!="A"||got[5]!="W"||got[6]!=" ") begin $display("LOGIC ANALYZER SOC FAIL UART prefix"); failures=failures+1; end else $display("LOGIC ANALYZER SOC UART PREFIX PASS");
  if(analyzer.cap.capture_count==0 || analyzer.cap.triggered!==1'b1) begin $display("LOGIC ANALYZER SOC FAIL capture count=%0d trig=%b",analyzer.cap.capture_count,analyzer.cap.triggered); failures=failures+1; end else $display("LOGIC ANALYZER SOC CAPTURE PASS count=%0d trigger_index=%0d post_cfg=%0d post_remaining=%0d",analyzer.cap.capture_count,analyzer.cap.trigger_index,analyzer.post_count,analyzer.cap.post_remaining);
  if(failures==0) $display("ALL LOGIC ANALYZER SOC TEST PASS"); else $fatal(1,"LOGIC ANALYZER SOC %0d FAIL",failures);
  $finish;
 end
 initial #2200000 $fatal(1,"LOGIC ANALYZER SOC TIMEOUT");
endmodule
