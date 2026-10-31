// MES50HP CoreMark delivery top.  Device and MMIO integration stay outside
// the reusable pipeline_cpu core.
module mes50hp_coremark_top #(
 parameter UART_BAUD_CYCLES = 50_000_000 / 115200
)(input wire clk_50m,input wire uart0_rx,output wire uart0_tx,output wire [7:0] led);
 reg [7:0] por_count=0;
 always @(posedge clk_50m) if(!(&por_count)) por_count<=por_count+1'b1;
 wire por_reset=!(&por_count);
 wire memory_ready;
 wire reset=por_reset||!memory_ready;
 wire iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de;wire [31:0] ia,idata,da,dwd,drd;wire [3:0] dst;
 wire perf_retire,perf_stall,perf_load,perf_branch,perf_taken,perf_flush,perf_predict,perf_btb_hit,perf_mispredict,perf_clear;wire [63:0] perf_cycles,perf_instret,perf_stalls,perf_loads,perf_branches,perf_taken_count,perf_flushes,perf_predicts,perf_btb_hits,perf_mispredicts;
 wire [31:0] trace_pc,trace_instruction,trace_rd_data,trace_mem_addr,trace_mem_data;
 wire trace_rd_we,trace_mem_we; wire [4:0] trace_rd_addr; wire [3:0] trace_mem_wstrb;
 wire ram_v,ram_r,uart_v,uart_r,gpio_v,gpio_r,app_v,app_r;wire [31:0] ta,twd,ram_rd,uart_rd,gpio_rd,app_rd;wire tw,ram_sv,uart_sv,gpio_sv,app_sv,ram_sr,uart_sr,gpio_sr,app_sr;wire [3:0] tws;wire ram_se,uart_se,gpio_se,app_se;wire [31:0] gpio_out;
 pipeline_cpu core(.clk(clk_50m),.reset(reset),.trace_valid(perf_retire),.trace_pc(trace_pc),.trace_instruction(trace_instruction),.trace_rd_we(trace_rd_we),.trace_rd_addr(trace_rd_addr),.trace_rd_data(trace_rd_data),.trace_mem_we(trace_mem_we),.trace_mem_addr(trace_mem_addr),.trace_mem_data(trace_mem_data),.trace_mem_wstrb(trace_mem_wstrb),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(perf_stall),.event_load_stall(perf_load),.event_branch(perf_branch),.event_branch_taken(perf_taken),.event_flush(perf_flush),.event_predict(perf_predict),.event_btb_hit(perf_btb_hit),.event_mispredict(perf_mispredict));
 perf_monitor perf(.clk(clk_50m),.reset(reset),.clear(perf_clear),.enable(1'b1),.event_retire(perf_retire),.event_stall(perf_stall),.event_load_stall(perf_load),.event_branch(perf_branch),.event_branch_taken(perf_taken),.event_flush(perf_flush),.event_predict(perf_predict),.event_btb_hit(perf_btb_hit),.event_mispredict(perf_mispredict),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes),.predict_count(perf_predicts),.btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts));
 coremark_imem imem(.clk(clk_50m),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 soc_data_interconnect #(.RAM_LAST_ADDR(32'h0000_ffff)) xbar(.clk(clk_50m),.reset(reset),.cpu_req_valid(dv),.cpu_req_ready(dr),.cpu_req_addr(da),.cpu_req_write(dw),.cpu_req_wdata(dwd),.cpu_req_wstrb(dst),.cpu_rsp_valid(dsv),.cpu_rsp_ready(dsr),.cpu_rsp_rdata(drd),.cpu_rsp_error(de),.ram_req_valid(ram_v),.ram_req_ready(ram_r),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.app_req_valid(app_v),.app_req_ready(app_r),.target_req_addr(ta),.target_req_write(tw),.target_req_wdata(twd),.target_req_wstrb(tws),.ram_rsp_valid(ram_sv),.ram_rsp_ready(ram_sr),.ram_rsp_rdata(ram_rd),.ram_rsp_error(ram_se),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.app_rsp_valid(app_sv),.app_rsp_ready(app_sr),.app_rsp_rdata(app_rd),.app_rsp_error(app_se));
 // 正式镜像在配置时初始化 DRM；memory_ready 保留为板级可见的启动约定。
 coremark_dmem dmem(.clk(clk_50m),.reset(por_reset),.init_done(memory_ready),.req_valid(ram_v),.req_ready(ram_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(ram_sv),.rsp_ready(ram_sr),.rsp_rdata(ram_rd),.rsp_error(ram_se));
 uart_mmio #(.UART_MAX_1BAUD(UART_BAUD_CYCLES),.UART_RX_MAX_1BAUD(UART_BAUD_CYCLES)) uart(.clk(clk_50m),.reset(reset),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.uart_req_addr(ta),.uart_req_write(tw),.uart_req_wdata(twd),.uart_req_wstrb(tws),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.uart_rx(uart0_rx),.uart_tx(uart0_tx));
 gpio_mmio gpio(.clk(clk_50m),.reset(reset),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.gpio_req_addr(ta),.gpio_req_write(tw),.gpio_req_wdata(twd),.gpio_req_wstrb(tws),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.gpio_out(gpio_out));
 perf_mmio app(.clk(clk_50m),.reset(reset),.req_valid(app_v),.req_ready(app_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(app_sv),.rsp_ready(app_sr),.rsp_rdata(app_rd),.rsp_error(app_se),.clear(perf_clear),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes),.predict_count(perf_predicts),.btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts));
`ifdef PDS_COREMARK_ILA
 // 诊断 bitstream 专用。DebugCore 只观察 Core 的通用提交/事件接口，不进入 CPU Core。
 // probe[176:0] 布局见 fpga/coremark_ila/README.md；其余位保留为 0。
 wire [191:0] ila_probe = {9'b0,memory_ready,ir,iv,dr,dv,reset,
                           perf_flush,perf_taken,perf_branch,perf_load,perf_stall,
                           trace_mem_wstrb,trace_mem_data,trace_mem_addr,trace_mem_we,
                           trace_rd_data,trace_rd_addr,trace_rd_we,
                           trace_instruction,trace_pc,perf_retire};
 wire ila_drck,ila_tdi,ila_capt,ila_shift,ila_tdo;
 wire [14:0] ila_conf_sel,ila_hub_tdo;
 wire [4:0] ila_id;
 assign ila_hub_tdo = {14'b0,ila_tdo};
 coremark_jtag_hub ila_hub(.resetn_i(!reset),.drck_o(ila_drck),.hub_tdi(ila_tdi),
   .capt_o(ila_capt),.shift_o(ila_shift),.conf_sel(ila_conf_sel),.id_o(ila_id),
   .hub_tdo(ila_hub_tdo));
 coremark_ila ila(.drck_in(ila_drck),.hub_tdi(ila_tdi),.id_i(ila_id),
   .capt_i(ila_capt),.shift_i(ila_shift),.conf_sel(ila_conf_sel[0]),.hub_tdo(ila_tdo),
   .clk(clk_50m),.trig0_i(ila_probe),.resetn_i(!reset));
`endif
 assign led=gpio_out[7:0];
endmodule
