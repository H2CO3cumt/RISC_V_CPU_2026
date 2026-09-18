`timescale 1ns/1ps
module tb_coremark_pipeline;
 parameter RANDOM_DELAY = 0;
 parameter MAX_CYCLES = 12000000;
 parameter ENABLE_BRANCH_PREDICTOR = 1;
 reg clk = 0;
 reg reset = 1;
 reg uart_rx = 1;
 wire uart_tx;
 wire [7:0] uart_byte;
 wire uart_byte_valid, uart_frame_error;
 integer cycles = 0;
 integer retired = 0;
 integer bytes = 0;
 integer errors = 0;
 integer log_file;
 reg [31:0] last_trace_pc = 0;
 reg [31:0] last_trace_instruction = 0;
 reg [31:0] trace_pc_history [0:15];
 reg [31:0] trace_instruction_history [0:15];
 integer trace_history_index = 0;
 integer history_dump_index;

 wire iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de;
 wire [31:0] ia,idata,da,dwd,drd;
 wire [3:0] dst;
 wire trace_valid,event_stall,event_load,event_branch,event_taken,event_flush,event_predict,event_btb_hit,event_mispredict;
 wire [31:0] trace_pc,trace_instruction;
 wire trace_rd_we,trace_mem_we;
 wire [4:0] trace_rd_addr;
 wire [31:0] trace_rd_data,trace_mem_addr,trace_mem_data;
 wire [3:0] trace_mem_wstrb;
 wire [63:0] perf_cycles,perf_instret,perf_stalls,perf_loads;
 wire [63:0] perf_branches,perf_taken_count,perf_flushes,perf_predicts,perf_btb_hits,perf_mispredicts;
 wire perf_clear;
 wire ram_v,ram_r,uart_v,uart_r,gpio_v,gpio_r,app_v,app_r;
 wire [31:0] ta,twd,ram_rd,uart_rd,gpio_rd,app_rd,gpio_out;
 wire tw,ram_sv,uart_sv,gpio_sv,app_sv,ram_sr,uart_sr,gpio_sr,app_sr;
 wire [3:0] tws;
 wire ram_se,uart_se,gpio_se,app_se;
 wire [31:0] writes;

 pipeline_cpu #(.ENABLE_BRANCH_PREDICTOR(ENABLE_BRANCH_PREDICTOR)) core(
  .clk(clk),.reset(reset),.trace_valid(trace_valid),.trace_pc(trace_pc),.trace_instruction(trace_instruction),
  .trace_rd_we(trace_rd_we),.trace_rd_addr(trace_rd_addr),.trace_rd_data(trace_rd_data),
  .trace_mem_we(trace_mem_we),.trace_mem_addr(trace_mem_addr),
  .trace_mem_data(trace_mem_data),.trace_mem_wstrb(trace_mem_wstrb),
  .i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),
  .i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),
  .d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),
  .d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),
  .d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(event_stall),
  .event_load_stall(event_load),.event_branch(event_branch),
  .event_branch_taken(event_taken),.event_flush(event_flush),
  .event_predict(event_predict),.event_btb_hit(event_btb_hit),.event_mispredict(event_mispredict));
 perf_monitor perf(.clk(clk),.reset(reset),.clear(perf_clear),.enable(1'b1),
  .event_retire(trace_valid),.event_stall(event_stall),
  .event_load_stall(event_load),.event_branch(event_branch),
  .event_branch_taken(event_taken),.event_flush(event_flush),
  .event_predict(event_predict),.event_btb_hit(event_btb_hit),.event_mispredict(event_mispredict),
  .cycle_count(perf_cycles),.instret_count(perf_instret),
  .stall_count(perf_stalls),.load_stall_count(perf_loads),
  .branch_count(perf_branches),.branch_taken_count(perf_taken_count),
  .flush_count(perf_flushes),.predict_count(perf_predicts),
  .btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts));
 pipeline_imem_adapter #(.DEPTH(8192),
  .INIT_FILE("software/coremark/build/coremark_imem.mem"),
  .RANDOM_DELAY(RANDOM_DELAY)) imem(
  .clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),
  .rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 soc_data_interconnect #(.RAM_LAST_ADDR(32'h0000ffff)) xbar(
  .clk(clk),.reset(reset),.cpu_req_valid(dv),.cpu_req_ready(dr),
  .cpu_req_addr(da),.cpu_req_write(dw),.cpu_req_wdata(dwd),
  .cpu_req_wstrb(dst),.cpu_rsp_valid(dsv),.cpu_rsp_ready(dsr),
  .cpu_rsp_rdata(drd),.cpu_rsp_error(de),.ram_req_valid(ram_v),
  .ram_req_ready(ram_r),.uart_req_valid(uart_v),.uart_req_ready(uart_r),
  .gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.app_req_valid(app_v),
  .app_req_ready(app_r),.target_req_addr(ta),.target_req_write(tw),
  .target_req_wdata(twd),.target_req_wstrb(tws),.ram_rsp_valid(ram_sv),
  .ram_rsp_ready(ram_sr),.ram_rsp_rdata(ram_rd),.ram_rsp_error(ram_se),
  .uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),
  .uart_rsp_error(uart_se),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),
  .gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.app_rsp_valid(app_sv),
  .app_rsp_ready(app_sr),.app_rsp_rdata(app_rd),.app_rsp_error(app_se));
 ram_adapter #(.DEPTH(16384),
  .INIT_FILE("software/coremark/build/coremark_dmem.mem"),
  .RANDOM_DELAY(RANDOM_DELAY)) ram(
  .clk(clk),.reset(reset),.req_valid(ram_v),.req_ready(ram_r),.req_addr(ta),
  .req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(ram_sv),
  .rsp_ready(ram_sr),.rsp_rdata(ram_rd),.rsp_error(ram_se),
  .write_side_effect_count(writes));
 uart_mmio #(.UART_MAX_1BAUD(8),.UART_RX_MAX_1BAUD(8)) uart(
  .clk(clk),.reset(reset),.uart_req_valid(uart_v),.uart_req_ready(uart_r),
  .uart_req_addr(ta),.uart_req_write(tw),.uart_req_wdata(twd),
  .uart_req_wstrb(tws),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),
  .uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.uart_rx(uart_rx),
  .uart_tx(uart_tx));
 gpio_mmio gpio(.clk(clk),.reset(reset),.gpio_req_valid(gpio_v),
  .gpio_req_ready(gpio_r),.gpio_req_addr(ta),.gpio_req_write(tw),
  .gpio_req_wdata(twd),.gpio_req_wstrb(tws),.gpio_rsp_valid(gpio_sv),
  .gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),
  .gpio_out(gpio_out));
 perf_mmio app(.clk(clk),.reset(reset),.req_valid(app_v),.req_ready(app_r),
  .req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),
  .rsp_valid(app_sv),.rsp_ready(app_sr),.rsp_rdata(app_rd),
  .rsp_error(app_se),.clear(perf_clear),.cycle_count(perf_cycles),
  .instret_count(perf_instret),.stall_count(perf_stalls),
  .load_stall_count(perf_loads),.branch_count(perf_branches),
  .branch_taken_count(perf_taken_count),.flush_count(perf_flushes),
  .predict_count(perf_predicts),.btb_hit_count(perf_btb_hits),
  .mispredict_count(perf_mispredicts));
 UART_RX #(.MAX_1BAUD(8)) monitor(.clk_50m(clk),.rst(reset),.rx(uart_tx),
  .rx_data(uart_byte),.rx_data_vld(uart_byte_valid),
  .rx_frame_error(uart_frame_error));

 always #5 clk = ~clk;
 always @(posedge clk) begin
  if (!reset) begin
   cycles = cycles + 1;
   if (trace_valid) begin
    if (trace_pc[1:0] != 2'b00 || trace_pc >= 32'h0000_8000) begin
     $display("COREMARK FIRST BAD COMMIT pc=%08h inst=%08h retired=%0d cycles=%0d",
              trace_pc,trace_instruction,retired,cycles);
     for (history_dump_index=0;history_dump_index<16;history_dump_index=history_dump_index+1)
      $display("COREMARK HISTORY %0d pc=%08h inst=%08h",
               history_dump_index,
               trace_pc_history[(trace_history_index+history_dump_index)&15],
               trace_instruction_history[(trace_history_index+history_dump_index)&15]);
     $display("COREMARK BAD STATE x1=%08h sp=%08h a0=%08h a1=%08h",
              core.rf.regs[1],core.rf.regs[2],core.rf.regs[10],core.rf.regs[11]);
     $fatal(1,"COREMARK CONTROL FLOW LEFT IMEM");
    end
    retired = retired + 1;
    last_trace_pc = trace_pc;
    last_trace_instruction = trace_instruction;
    trace_pc_history[trace_history_index] = trace_pc;
    trace_instruction_history[trace_history_index] = trace_instruction;
    trace_history_index = (trace_history_index + 1) & 15;
   end
   if ((cycles % 1000000) == 0)
    $display("COREMARK PROGRESS cycles=%0d retired=%0d pc=%08h inst=%08h gpio=%02h",
             cycles,retired,last_trace_pc,last_trace_instruction,gpio_out[7:0]);
   if (uart_byte_valid) begin
    bytes = bytes + 1;
    $fwrite(log_file,"%c",uart_byte);
   end
   if (uart_frame_error) errors = errors + 1;
  end
 end

 initial begin
  for (history_dump_index=0;history_dump_index<16;history_dump_index=history_dump_index+1) begin
   trace_pc_history[history_dump_index] = 0;
   trace_instruction_history[history_dump_index] = 0;
  end
  log_file = $fopen("tmp/coremark/uart.log","w");
  repeat (4) @(negedge clk);
  reset = 0;
  while (gpio_out[7:0] != 8'hc3 && cycles < MAX_CYCLES) @(posedge clk);
  repeat (200) @(posedge clk);
  $fclose(log_file);
  if (cycles >= MAX_CYCLES) begin
   $display("COREMARK TIMEOUT STATE pc=%08h inst=%08h x1=%08h sp=%08h a0=%08h a1=%08h",
             last_trace_pc,last_trace_instruction,core.rf.regs[1],core.rf.regs[2],
            core.rf.regs[10],core.rf.regs[11]);
   $fatal(1,"COREMARK PIPELINE TIMEOUT");
  end
  if (errors != 0) $fatal(1,"COREMARK UART FRAME ERRORS %0d",errors);
  if (bytes < 200) $fatal(1,"COREMARK UART OUTPUT TOO SHORT %0d",bytes);
  $display("COREMARK PIPELINE EXECUTION PASS cycles=%0d retired=%0d bytes=%0d",cycles,retired,bytes);
  $display("COREMARK PERF stall=%0d load=%0d branch=%0d taken=%0d flush=%0d writes=%0d",
           perf_stalls,perf_loads,perf_branches,perf_taken_count,perf_flushes,writes);
  $display("COREMARK PREDICTOR enabled=%0d predict=%0d btb_hit=%0d mispredict=%0d",
           ENABLE_BRANCH_PREDICTOR,perf_predicts,perf_btb_hits,perf_mispredicts);
  $finish;
 end
endmodule
