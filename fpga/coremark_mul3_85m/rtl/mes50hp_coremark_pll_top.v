// 85 MHz CoreMark 顶层：PLL + CPU/SoC + UART/GPIO + CoreMark 程序存储器。
// 除时钟生成（PLL）与波特率分频常数外，与 50 MHz 版本的 mes50hp_coremark_top 完全一致。
// 与 80 MHz 版的唯一区别：CLK_HZ 80e6 -> 85e6，PLL 换成 pll_85m（VCO 800 -> 850 MHz）。
module mes50hp_coremark_pll_top #(
 parameter CLK_HZ = 85_000_000,
 parameter POR_CYCLES = 1024,
 // 乘法 EX 占用拍数（rtl/mdu.v 的 MUL_LAT）。本工程是 Before/After 实验工程：
 // 唯一变量就是这个参数，其余 RTL/约束/镜像与 fpga/coremark_im_85m 逐字节相同。
 parameter MUL_LAT = 3
)(input wire clk_50m,input wire uart0_rx,output wire uart0_tx,output wire [7:0] led);
 // 静态波特率分频：85e6/115200 = 737.85 -> 取 737，实际 115332 baud（+0.115%，在 UART 容差内）
 localparam UART_BAUD_CYCLES = CLK_HZ / 115200;

 wire clk_85m, pll_locked;
 pll_85m u_pll(.clk_50m_in(clk_50m),.clk_85m(clk_85m),.pll_locked(pll_locked));

 reg [15:0] por_count = 0;
 always @(posedge clk_85m) if(!pll_locked) por_count<=0; else if(!(&por_count)) por_count<=por_count+1'b1;
 wire por_reset = !(&por_count);
 wire memory_ready;
 wire reset = por_reset || !memory_ready || !pll_locked;

 wire iv,ir,rv,rr,ie,dv,dr,dw,dsv,dsr,de;wire [31:0] ia,idata,da,dwd,drd;wire [3:0] dst;
 wire perf_retire,perf_stall,perf_load,perf_branch,perf_taken,perf_flush,perf_predict,perf_btb_hit,perf_mispredict,perf_clear;
 wire [63:0] perf_cycles,perf_instret,perf_stalls,perf_loads,perf_branches,perf_taken_count,perf_flushes,perf_predicts,perf_btb_hits,perf_mispredicts;
 wire [31:0] trace_pc,trace_instruction,trace_rd_data,trace_mem_addr,trace_mem_data;
 wire trace_rd_we,trace_mem_we; wire [4:0] trace_rd_addr; wire [3:0] trace_mem_wstrb;
 wire ram_v,ram_r,uart_v,uart_r,gpio_v,gpio_r,app_v,app_r;wire [31:0] ta,twd,ram_rd,uart_rd,gpio_rd,app_rd;
 wire tw,ram_sv,uart_sv,gpio_sv,app_sv,ram_sr,uart_sr,gpio_sr,app_sr;wire [3:0] tws;
 wire ram_se,uart_se,gpio_se,app_se;wire [31:0] gpio_out;

 pipeline_cpu #(.MDU_MUL_LAT(MUL_LAT)) core(.clk(clk_85m),.reset(reset),.trace_valid(perf_retire),.trace_pc(trace_pc),.trace_instruction(trace_instruction),.trace_rd_we(trace_rd_we),.trace_rd_addr(trace_rd_addr),.trace_rd_data(trace_rd_data),.trace_mem_we(trace_mem_we),.trace_mem_addr(trace_mem_addr),.trace_mem_data(trace_mem_data),.trace_mem_wstrb(trace_mem_wstrb),.i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),.i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),.d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),.d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),.d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(perf_stall),.event_load_stall(perf_load),.event_branch(perf_branch),.event_branch_taken(perf_taken),.event_flush(perf_flush),.event_predict(perf_predict),.event_btb_hit(perf_btb_hit),.event_mispredict(perf_mispredict));
 perf_monitor perf(.clk(clk_85m),.reset(reset),.clear(perf_clear),.enable(1'b1),.event_retire(perf_retire),.event_stall(perf_stall),.event_load_stall(perf_load),.event_branch(perf_branch),.event_branch_taken(perf_taken),.event_flush(perf_flush),.event_predict(perf_predict),.event_btb_hit(perf_btb_hit),.event_mispredict(perf_mispredict),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes),.predict_count(perf_predicts),.btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts));
 coremark_imem imem(.clk(clk_85m),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),.rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 soc_data_interconnect #(.RAM_LAST_ADDR(32'h0000_ffff)) xbar(.clk(clk_85m),.reset(reset),.cpu_req_valid(dv),.cpu_req_ready(dr),.cpu_req_addr(da),.cpu_req_write(dw),.cpu_req_wdata(dwd),.cpu_req_wstrb(dst),.cpu_rsp_valid(dsv),.cpu_rsp_ready(dsr),.cpu_rsp_rdata(drd),.cpu_rsp_error(de),.ram_req_valid(ram_v),.ram_req_ready(ram_r),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.app_req_valid(app_v),.app_req_ready(app_r),.target_req_addr(ta),.target_req_write(tw),.target_req_wdata(twd),.target_req_wstrb(tws),.ram_rsp_valid(ram_sv),.ram_rsp_ready(ram_sr),.ram_rsp_rdata(ram_rd),.ram_rsp_error(ram_se),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.app_rsp_valid(app_sv),.app_rsp_ready(app_sr),.app_rsp_rdata(app_rd),.app_rsp_error(app_se));
 // 正式镜像在配置时初始化 DRM；memory_ready 保留为板级可见的启动约定。
 coremark_dmem dmem(.clk(clk_85m),.reset(por_reset),.init_done(memory_ready),.req_valid(ram_v),.req_ready(ram_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(ram_sv),.rsp_ready(ram_sr),.rsp_rdata(ram_rd),.rsp_error(ram_se));
 uart_mmio #(.UART_MAX_1BAUD(UART_BAUD_CYCLES),.UART_RX_MAX_1BAUD(UART_BAUD_CYCLES)) uart(.clk(clk_85m),.reset(reset),.uart_req_valid(uart_v),.uart_req_ready(uart_r),.uart_req_addr(ta),.uart_req_write(tw),.uart_req_wdata(twd),.uart_req_wstrb(tws),.uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),.uart_rsp_error(uart_se),.uart_rx(uart0_rx),.uart_tx(uart0_tx));
 gpio_mmio gpio(.clk(clk_85m),.reset(reset),.gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.gpio_req_addr(ta),.gpio_req_write(tw),.gpio_req_wdata(twd),.gpio_req_wstrb(tws),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),.gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.gpio_out(gpio_out));
 perf_mmio app(.clk(clk_85m),.reset(reset),.req_valid(app_v),.req_ready(app_r),.req_addr(ta),.req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(app_sv),.rsp_ready(app_sr),.rsp_rdata(app_rd),.rsp_error(app_se),.clear(perf_clear),.cycle_count(perf_cycles),.instret_count(perf_instret),.stall_count(perf_stalls),.load_stall_count(perf_loads),.branch_count(perf_branches),.branch_taken_count(perf_taken_count),.flush_count(perf_flushes),.predict_count(perf_predicts),.btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts));
 assign led = gpio_out[7:0];
endmodule
