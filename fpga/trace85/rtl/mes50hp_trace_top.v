// MES50HP trace 版 SoC 顶层：在交付的逻辑分析仪 SoC 之上，多挂一个
// "提交级 trace" 子窗口（0x1000_2200..0x1000_22FF）。
//
// 与 fpga/logic_analyzer_85m/rtl/mes50hp_logic_analyzer_top.v 的差异只有三处：
//   ① application_mmio_mux -> application_mmio_mux3（多一个 0x2 子窗口）；
//   ② pipeline_cpu 的 trace_* 观测输出由悬空改为接到 core_trace_mmio；
//   ③ 新增 core_trace_mmio 实例。
// 其余（PLL 外的时钟、UART、GPIO、定时器、性能计数器、逻辑分析仪、J8 回环、
// 上电复位、镜像 ch7）逐行保持不变。
//
// **Core 一行未改**：trace_* 是 pipeline_cpu 已经冻结的对外观测输出
// （docs/interfaces.md §6.1），本文件只是把它们接到了一个 Core 外部的观察者上。
module mes50hp_trace_top #(
 parameter UART_BAUD_CYCLES = 50_000_000 / 115200,
 // 记录深度：与固件 software/logic_analyzer/logic_analyzer.c 的 TR_DEPTH 必须一致。
 // 4096 条的取舍：一条 132 位 = 约 30 个 DRM18K（全片 134 个，交付版整机只用了 6 个），
 // 而 phase=0 的处理窗口只有一两百条，phase=1 的轮询窗口 4096 条已足够把
 // "窗口里绝大部分是空转"这件事说清楚。再往上加只增加导出时间，不增加信息。
 // 波特率保持 115200：那是这块板在 85 MHz 下已经实测跑通的唯一档位，换档要重打位流
 // 才能验证，而交付纪律不允许拿没验证过的档位做演示。
 parameter TRACE_DEPTH = 4096,
 parameter TRACE_AW    = 12
)(
 input wire clk_50m,input wire uart0_rx,output wire uart0_tx,output wire [7:0] led,
 input wire [7:0] capture_ch,output wire [7:0] loopback_tx
);
 reg [7:0] por_count=0; reg reset=1;
 always @(posedge clk_50m) if (reset) begin por_count<=por_count+1'b1;if(&por_count) reset<=0;end
 wire iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de;
 wire [31:0] ia,idata,da,dwd,drd; wire [3:0] dst;
 wire perf_retire,perf_stall,perf_load,perf_branch,perf_taken,perf_flush,perf_predict,perf_btb_hit,perf_mispredict,perf_clear;
 wire [63:0] perf_cycles,perf_instret,perf_stalls,perf_loads,perf_branches,perf_taken_count,perf_flushes,perf_predicts,perf_btb_hits,perf_mispredicts;
 wire ram_v,ram_r,uart_v,uart_r,gpio_v,gpio_r,app_v,app_r,timer_v,timer_r;
 wire [31:0] ta,twd,ram_rd,uart_rd,gpio_rd,app_rd,timer_rd; wire tw,ram_sv,uart_sv,gpio_sv,app_sv,ram_sr,uart_sr,gpio_sr,app_sr,timer_sv,timer_sr;
 wire [3:0] tws; wire ram_se,uart_se,gpio_se,app_se,timer_se; wire [31:0] gpio_out;
 wire irq_timer;
 wire p_req_v,p_req_r,p_rsp_v,p_rsp_r,p_err; wire [31:0] p_addr,p_wdata,p_rdata; wire p_write; wire [3:0] p_wstrb;
 wire a_req_v,a_req_r,a_rsp_v,a_rsp_r,a_err; wire [31:0] a_addr,a_wdata,a_rdata; wire a_write; wire [3:0] a_wstrb; wire [7:0] sample_outputs;
 // trace 子窗口
 wire t_req_v,t_req_r,t_rsp_v,t_rsp_r,t_err; wire [31:0] t_addr,t_wdata,t_rdata; wire t_write; wire [3:0] t_wstrb;
 // 提交级 trace（Core 的既有冻结输出）
 wire [31:0] tp_pc,tp_inst,tp_rd_data,tp_mem_addr,tp_mem_data;
 wire        tp_rd_we,tp_mem_we,tp_error;
 wire [4:0]  tp_rd_addr;
 wire [3:0]  tp_mem_wstrb;

 pipeline_cpu core(.clk(clk_50m),.reset(reset),
  .trace_valid(perf_retire),.trace_pc(tp_pc),.trace_instruction(tp_inst),
  .trace_rd_we(tp_rd_we),.trace_rd_addr(tp_rd_addr),.trace_rd_data(tp_rd_data),
  .trace_mem_we(tp_mem_we),.trace_mem_addr(tp_mem_addr),.trace_mem_data(tp_mem_data),
  .trace_mem_wstrb(tp_mem_wstrb),.trace_error(tp_error),
  .i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),
  .d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),
  .d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),
  .event_stall(perf_stall),.event_load_stall(perf_load),.event_branch(perf_branch),.event_branch_taken(perf_taken),
  .event_flush(perf_flush),.event_predict(perf_predict),.event_btb_hit(perf_btb_hit),.event_mispredict(perf_mispredict),
  .event_control_redirect(),.event_trap(),.event_trap_return(),.event_illegal(),.event_misaligned(),.event_bus_error(),
  .irq_software_i(1'b0),.irq_timer_i(irq_timer),.irq_external_i(1'b0));
 perf_monitor perf(.clk(clk_50m),.reset(reset),.clear(perf_clear),.enable(1'b1),.event_retire(perf_retire),.event_stall(perf_stall),.event_load_stall(perf_load),.event_branch(perf_branch),.event_branch_taken(perf_taken),.event_flush(perf_flush),.event_predict(perf_predict),.event_btb_hit(perf_btb_hit),.event_mispredict(perf_mispredict),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes),.predict_count(perf_predicts),.btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts));
 logic_analyzer_imem imem(.clk(clk_50m),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 soc_data_interconnect #(.RAM_LAST_ADDR(32'h0000_1fff)) xbar(.clk(clk_50m),.reset(reset),.cpu_req_valid(dv),.cpu_req_ready(dr),.cpu_req_addr(da),.cpu_req_write(dw),.cpu_req_wdata(dwd),.cpu_req_wstrb(dst),.cpu_rsp_valid(dsv),.cpu_rsp_ready(dsr),.cpu_rsp_rdata(drd),.cpu_rsp_error(de),.ram_req_valid(ram_v),.ram_req_ready(ram_r),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.app_req_valid(app_v),.app_req_ready(app_r),.target_req_addr(ta),.target_req_write(tw),.target_req_wdata(twd),.target_req_wstrb(tws),.ram_rsp_valid(ram_sv),.ram_rsp_ready(ram_sr),.ram_rsp_rdata(ram_rd),.ram_rsp_error(ram_se),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.app_rsp_valid(app_sv),.app_rsp_ready(app_sr),.app_rsp_rdata(app_rd),.app_rsp_error(app_se),.timer_req_valid(timer_v),.timer_req_ready(timer_r),.timer_rsp_valid(timer_sv),.timer_rsp_ready(timer_sr),.timer_rsp_rdata(timer_rd),.timer_rsp_error(timer_se));
 logic_analyzer_dmem dmem(.clk(clk_50m),.reset(reset),.req_valid(ram_v),.req_ready(ram_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(ram_sv),.rsp_ready(ram_sr),.rsp_rdata(ram_rd),.rsp_error(ram_se));
 uart_mmio #(.UART_MAX_1BAUD(UART_BAUD_CYCLES),.UART_RX_MAX_1BAUD(UART_BAUD_CYCLES)) uart(.clk(clk_50m),.reset(reset),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.uart_req_addr(ta),.uart_req_write(tw),.uart_req_wdata(twd),.uart_req_wstrb(tws),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.uart_rx(uart0_rx),.uart_tx(uart0_tx));
 timer_mmio timer(.clk(clk_50m),.reset(reset),.timer_req_valid(timer_v),.timer_req_ready(timer_r),.timer_req_addr(ta),.timer_req_write(tw),.timer_req_wdata(twd),.timer_req_wstrb(tws),.timer_rsp_valid(timer_sv),.timer_rsp_ready(timer_sr),.timer_rsp_rdata(timer_rd),.timer_rsp_error(timer_se),.irq_timer(irq_timer));
 gpio_mmio gpio(.clk(clk_50m),.reset(reset),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.gpio_req_addr(ta),.gpio_req_write(tw),.gpio_req_wdata(twd),.gpio_req_wstrb(tws),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.gpio_out(gpio_out));
 application_mmio_mux3 appmux(.clk(clk_50m),.reset(reset),
  .req_valid(app_v),.req_ready(app_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),
  .rsp_valid(app_sv),.rsp_ready(app_sr),.rsp_rdata(app_rd),.rsp_error(app_se),
  .perf_req_valid(p_req_v),.perf_req_ready(p_req_r),.perf_req_addr(p_addr),.perf_req_write(p_write),.perf_req_wdata(p_wdata),.perf_req_wstrb(p_wstrb),.perf_rsp_valid(p_rsp_v),.perf_rsp_ready(p_rsp_r),.perf_rsp_rdata(p_rdata),.perf_rsp_error(p_err),
  .la_req_valid(a_req_v),.la_req_ready(a_req_r),.la_req_addr(a_addr),.la_req_write(a_write),.la_req_wdata(a_wdata),.la_req_wstrb(a_wstrb),.la_rsp_valid(a_rsp_v),.la_rsp_ready(a_rsp_r),.la_rsp_rdata(a_rdata),.la_rsp_error(a_err),
  .tr_req_valid(t_req_v),.tr_req_ready(t_req_r),.tr_req_addr(t_addr),.tr_req_write(t_write),.tr_req_wdata(t_wdata),.tr_req_wstrb(t_wstrb),.tr_rsp_valid(t_rsp_v),.tr_rsp_ready(t_rsp_r),.tr_rsp_rdata(t_rdata),.tr_rsp_error(t_err));
 perf_mmio perf_mmio(.clk(clk_50m),.reset(reset),.req_valid(p_req_v),.req_ready(p_req_r),.req_addr(p_addr),.req_write(p_write),.req_wdata(p_wdata),.req_wstrb(p_wstrb),.rsp_valid(p_rsp_v),.rsp_ready(p_rsp_r),.rsp_rdata(p_rdata),.rsp_error(p_err),.clear(perf_clear),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes),.predict_count(perf_predicts),.btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts));
 // ---- 提交级 trace 子窗口 ----
 core_trace_mmio #(.DEPTH(TRACE_DEPTH),.MARKS(256),.AW(TRACE_AW),.MW(8)) trace(
  .clk(clk_50m),.reset(reset),
  .req_valid(t_req_v),.req_ready(t_req_r),.req_addr(t_addr),.req_write(t_write),.req_wdata(t_wdata),.req_wstrb(t_wstrb),
  .rsp_valid(t_rsp_v),.rsp_ready(t_rsp_r),.rsp_rdata(t_rdata),.rsp_error(t_err),
  .trace_valid(perf_retire),.trace_pc(tp_pc),.trace_instruction(tp_inst),
  .trace_rd_we(tp_rd_we),.trace_rd_addr(tp_rd_addr),.trace_rd_data(tp_rd_data),
  .trace_mem_we(tp_mem_we),.trace_mem_addr(tp_mem_addr),.trace_mem_data(tp_mem_data),
  .trace_mem_wstrb(tp_mem_wstrb),.trace_error(tp_error));
 // ---- 采集源"双源可选"：J8 外部 8 路 / Core 内部观测点（与交付版一致）----
 reg [7:0] core_probe_q;
 always @(posedge clk_50m) core_probe_q <= {perf_retire,perf_flush,perf_stall,dr,dv,rv,ir,iv};
 wire [7:0] core_probe = core_probe_q;
 logic_analyzer_mmio analyzer(.clk(clk_50m),.reset(reset),.req_valid(a_req_v),.req_ready(a_req_r),.req_addr(a_addr),.req_write(a_write),.req_wdata(a_wdata),.req_wstrb(a_wstrb),.rsp_valid(a_rsp_v),.rsp_ready(a_rsp_r),.rsp_rdata(a_rdata),.rsp_error(a_err),.channels(capture_ch),.probe_channels(core_probe),.sample_outputs(sample_outputs));
 assign led=gpio_out[7:0]; assign loopback_tx={uart0_rx,sample_outputs[6:0]};
endmodule
