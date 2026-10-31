`timescale 1ns/1ps
// T1：把「剩余 48.4% cycles」精确定位到指令 / 流水级 / 状态。
//
// 本 Testbench 是**只读观测**：不改 pipeline_cpu 的接口，不驱动任何额外控制信号，
// 只是把 Core 内部已有信号逐拍采样并分类统计。存储器模型用 cpi_board_memory_model.v，
// 与实体板 coremark_imem / coremark_dmem 逐拍一致，因此统计结论可直接用于板级归因。
//
// 统计窗口与板上一致：从 core_portme.c 的 start_time() 写 PERF_CONTROL 产生的 perf_clear
// 脉冲开始（PERF_WINDOW_ALIGN=1）。
module tb_cpi_attribution;
  parameter MAX_CYCLES = 4000000;
  parameter ENABLE_BRANCH_PREDICTOR = 1;
  parameter ALLOW_HANDOFF = 0;

  reg clk = 0;
  reg reset = 1;
  reg uart_rx = 1;
  wire uart_tx;
  wire [7:0] uart_byte;
  wire uart_byte_valid, uart_frame_error;

  integer cycles = 0;
  integer retired = 0;
  integer bytes = 0;
  integer frame_errors = 0;

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

  pipeline_cpu #(.ENABLE_BRANCH_PREDICTOR(ENABLE_BRANCH_PREDICTOR)) core(
   .clk(clk),.reset(reset),.trace_valid(trace_valid),.trace_pc(trace_pc),.trace_instruction(trace_instruction),
   .trace_rd_we(trace_rd_we),.trace_rd_addr(trace_rd_addr),.trace_rd_data(trace_rd_data),
   .trace_mem_we(trace_mem_we),.trace_mem_addr(trace_mem_addr),
   .trace_mem_data(trace_mem_data),.trace_mem_wstrb(trace_mem_wstrb),.trace_error(),
   .i_req_valid(iv),.i_req_ready(ir),.i_req_addr(ia),.i_rsp_valid(rv),
   .i_rsp_ready(rr),.i_rsp_data(idata),.i_rsp_error(ie),
   .d_req_valid(dv),.d_req_ready(dr),.d_req_addr(da),.d_req_write(dw),
   .d_req_wdata(dwd),.d_req_wstrb(dst),.d_rsp_valid(dsv),.d_rsp_ready(dsr),
   .d_rsp_rdata(drd),.d_rsp_error(de),.event_stall(event_stall),
   .event_load_stall(event_load),.event_branch(event_branch),
   .event_branch_taken(event_taken),.event_flush(event_flush),
   .event_predict(event_predict),.event_btb_hit(event_btb_hit),.event_mispredict(event_mispredict),
   .event_illegal(),.event_misaligned(),.event_bus_error());
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

  // 与板上完全一致的取指/数据存储器时序
  cpi_board_imem #(.DEPTH(8192),
   .INIT_FILE("software/coremark/build/coremark_imem.mem"),
   .ALLOW_HANDOFF(ALLOW_HANDOFF)) imem(
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
  cpi_board_dmem #(.DEPTH(16384),
   .INIT_FILE("software/coremark/build/coremark_dmem.mem"),
   .ALLOW_HANDOFF(ALLOW_HANDOFF)) ram(
   .clk(clk),.reset(reset),.req_valid(ram_v),.req_ready(ram_r),.req_addr(ta),
   .req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(ram_sv),
   .rsp_ready(ram_sr),.rsp_rdata(ram_rd),.rsp_error(ram_se));
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

  // ---------------- 逐拍分类统计（全部只读） ----------------
  integer w_active = 0;
  integer w_cycles = 0, w_retired = 0;
  integer w_iv_high = 0, w_iv_low = 0;               // i_req_valid 高低拍数
  integer w_iv_low_memblk = 0;                       // 数据阻塞期间取指请求也不在场
  integer w_ifrq_acc = 0, w_ifrsp_acc = 0, w_ifid_write = 0, w_ifrsp_drop = 0;
  integer w_memblk = 0, w_memblk_req = 0, w_memblk_rsp = 0, w_memblk_front = 0;
  integer w_memblk_hold_rsp = 0;                     // 阻塞期间响应被扣住（IF 停住）的拍数
  integer w_load_acc = 0, w_store_acc = 0, w_drsp_acc = 0;
  integer w_ldstall = 0, w_redir = 0, w_idstall = 0;
  integer w_exmem_busy = 0;                          // EX/MEM 持有且未完成
  integer w_gap [1:64];
  integer w_last_write = 0;
  integer w_fetch_discard = 0;
  // 逐 PC 直方图（只读统计）：阻塞拍 / load / store
  integer pc_block [0:16383];
  integer pc_load  [0:16383];
  integer pc_store [0:16383];
  integer k;
  integer trace_file, csv_file;
  integer trace_dumped = 0;

  function integer pc_index; input [31:0] p; begin pc_index = p[15:2]; end endfunction

  always @(posedge clk) begin
    if (!reset) begin
      cycles = cycles + 1;
      if (trace_valid) retired = retired + 1;

      // perf_clear 脉冲（start_time 写 CONTROL）标记统计窗口开始
      if (perf_clear) begin
        w_active = 1; w_cycles = 0; w_retired = 0;
        w_iv_high = 0; w_iv_low = 0; w_iv_low_memblk = 0;
        w_ifrq_acc = 0; w_ifrsp_acc = 0; w_ifid_write = 0; w_ifrsp_drop = 0;
        w_memblk = 0; w_memblk_req = 0; w_memblk_rsp = 0; w_memblk_front = 0;
        w_memblk_hold_rsp = 0;
        w_load_acc = 0; w_store_acc = 0; w_drsp_acc = 0;
        w_ldstall = 0; w_redir = 0; w_idstall = 0; w_exmem_busy = 0;
        w_fetch_discard = 0; w_last_write = 0; trace_dumped = 0;
        for (k = 1; k < 64; k = k + 1) w_gap[k] = 0;
        for (k = 0; k < 16384; k = k + 1) begin
          pc_block[k] = 0; pc_load[k] = 0; pc_store[k] = 0;
        end
      end

      if (w_active) begin
        w_cycles = w_cycles + 1;
        if (trace_valid) w_retired = w_retired + 1;

        if (iv) w_iv_high = w_iv_high + 1; else begin
          w_iv_low = w_iv_low + 1;
          if (core.mem_block) w_iv_low_memblk = w_iv_low_memblk + 1;
        end
        if (iv && ir) w_ifrq_acc = w_ifrq_acc + 1;
        if (rv && rr) begin
          w_ifrsp_acc = w_ifrsp_acc + 1;
          if (core.if_discard || core.ex_redirect) w_fetch_discard = w_fetch_discard + 1;
          if (!core.if_discard && !core.ex_redirect) begin
            w_ifid_write = w_ifid_write + 1;
            if (w_cycles - w_last_write >= 63) w_gap[63] = w_gap[63] + 1;
            else w_gap[w_cycles - w_last_write] = w_gap[w_cycles - w_last_write] + 1;
            w_last_write = w_cycles;
          end
        end
        if (rv && !rr) w_ifrsp_drop = w_ifrsp_drop + 1;

        if (core.mem_block) begin
          w_memblk = w_memblk + 1;
          if (core.dstate == 2'd1) w_memblk_req = w_memblk_req + 1;
          else if (core.dstate == 2'd2) w_memblk_rsp = w_memblk_rsp + 1;
          else w_memblk_front = w_memblk_front + 1;
          if (rv && !rr) w_memblk_hold_rsp = w_memblk_hold_rsp + 1;
          if (core.exmem_valid) pc_block[pc_index(core.exmem_pc)] = pc_block[pc_index(core.exmem_pc)] + 1;
        end
        if (core.exmem_valid && !core.mem_done) w_exmem_busy = w_exmem_busy + 1;
        if (dv && dr) begin
          if (dw) begin
            w_store_acc = w_store_acc + 1;
            pc_store[pc_index(da)] = pc_store[pc_index(da)] + 1;
          end else begin
            w_load_acc = w_load_acc + 1;
            pc_load[pc_index(da)] = pc_load[pc_index(da)] + 1;
          end
        end
        if (dsv && dsr) w_drsp_acc = w_drsp_acc + 1;
        if (core.load_use) w_ldstall = w_ldstall + 1;
        if (core.ex_redirect) w_redir = w_redir + 1;
        if (!core.id_advance) w_idstall = w_idstall + 1;

        // 前 120 个窗口周期的逐拍证据
        if (w_cycles <= 120 && trace_dumped < 120) begin
          trace_dumped = trace_dumped + 1;
          $fwrite(trace_file, "TRACE cyc=%0d iv=%b ir=%b rv=%b rr=%b ia=%08h if_req=%b if_rsp=%b if_rq_addr=%08h if_disc=%b dstate=%0d memblk=%b memdone=%b dv=%b dr=%b exmem_v=%b exmem_rw=%b trace=%b pc=%08h\n",
            w_cycles, iv, ir, rv, rr, ia, core.if_req, core.if_rsp, core.if_req_addr_reg, core.if_discard,
            core.dstate, core.mem_block, core.mem_done, dv, dr, core.exmem_valid,
            {core.exmem_memread,core.exmem_memwrite}, trace_valid, trace_pc);
        end
      end
    end
  end

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (!reset) begin
      if (uart_byte_valid) bytes = bytes + 1;
      if (uart_frame_error) frame_errors = frame_errors + 1;
    end
  end

  integer bucket_redir, bucket_block, bucket_ldstall, bucket_serial, bucket_other;
  integer gap_sum, gap_n, g;
  integer i2;

  initial begin
    trace_file = $fopen("tmp/cpi/cycle_trace.log","w");
    for (i2 = 0; i2 < 16384; i2 = i2 + 1) begin
      pc_block[i2] = 0; pc_load[i2] = 0; pc_store[i2] = 0;
    end
    for (i2 = 1; i2 < 64; i2 = i2 + 1) w_gap[i2] = 0;
    repeat (4) @(negedge clk);
    reset = 0;
    while (gpio_out[7:0] != 8'hc3 && cycles < MAX_CYCLES) @(posedge clk);
    if (cycles >= MAX_CYCLES) begin
      $display("CPI ATTRIBUTION TIMEOUT cycles=%0d pc=%08h inst=%08h", cycles, trace_pc, trace_instruction);
      $fatal(1,"CPI ATTRIBUTION TIMEOUT");
    end
    repeat (4) @(posedge clk);
    $fclose(trace_file);

    // ---- 归因报告 ----
    bucket_redir = w_redir;
    bucket_block = w_memblk;
    bucket_ldstall = w_ldstall;
    bucket_serial = w_iv_low - w_iv_low_memblk;
    if (bucket_serial < 0) bucket_serial = 0;
    bucket_other = w_cycles - w_retired - bucket_redir - bucket_block - bucket_ldstall - bucket_serial;
    gap_sum = 0; gap_n = 0;
    for (g = 1; g < 64; g = g + 1) begin
      gap_sum = gap_sum + g * w_gap[g];
      gap_n = gap_n + w_gap[g];
    end

    $display("CPI ATTR CONFIG predictor=%0d allow_handoff=%0d", ENABLE_BRANCH_PREDICTOR, ALLOW_HANDOFF);
    $display("CPI ATTR WINDOW cycles=%0d retired=%0d cpi_x1000=%0d", w_cycles, w_retired,
             (w_retired != 0) ? (w_cycles * 1000 / w_retired) : 0);
    $display("CPI ATTR FETCH ifrq_acc=%0d ifrsp_acc=%0d ifid_write=%0d discard=%0d ifrsp_drop=%0d",
             w_ifrq_acc, w_ifrsp_acc, w_ifid_write, w_fetch_discard, w_ifrsp_drop);
    $display("CPI ATTR FRONT iv_high=%0d iv_low=%0d iv_low_memblk=%0d gap_sum=%0d gap_n=%0d",
             w_iv_high, w_iv_low, w_iv_low_memblk, gap_sum, gap_n);
    $display("CPI ATTR FRONT gap_hist 1..16 += %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
             w_gap[1],w_gap[2],w_gap[3],w_gap[4],w_gap[5],w_gap[6],w_gap[7],w_gap[8],
             w_gap[9],w_gap[10],w_gap[11],w_gap[12],w_gap[13],w_gap[14],w_gap[15],w_gap[16],w_gap[63]);
    $display("CPI ATTR DATA memblk=%0d req_phase=%0d rsp_phase=%0d front_phase=%0d hold_rsp=%0d exmem_busy=%0d",
             w_memblk, w_memblk_req, w_memblk_rsp, w_memblk_front, w_memblk_hold_rsp, w_exmem_busy);
    $display("CPI ATTR DATA load_acc=%0d store_acc=%0d drsp_acc=%0d lsu_x1000=%0d",
             w_load_acc, w_store_acc, w_drsp_acc,
             (w_retired != 0) ? ((w_load_acc + w_store_acc) * 1000 / w_retired) : 0);
    $display("CPI ATTR STALL load_use=%0d redirect=%0d id_stall=%0d", w_ldstall, w_redir, w_idstall);
    $display("CPI ATTR BUCKET redirect=%0d data_block=%0d load_use=%0d if_serialize=%0d other=%0d sum=%0d",
             bucket_redir, bucket_block, bucket_ldstall, bucket_serial, bucket_other,
             w_retired + bucket_redir + bucket_block + bucket_ldstall + bucket_serial + bucket_other);
    $display("CPI ATTR PERF cycle=%0d instret=%0d stall=%0d load=%0d branch=%0d taken=%0d flush=%0d predict=%0d btb=%0d mispredict=%0d",
             perf_cycles, perf_instret, perf_stalls, perf_loads, perf_branches,
             perf_taken_count, perf_flushes, perf_predicts, perf_btb_hits, perf_mispredicts);
    $display("CPI ATTR UART bytes=%0d frame_errors=%0d", bytes, frame_errors);

    // PC 直方图导出（给 Python 排序取前 10）
    csv_file = $fopen("tmp/cpi/pc_hist.csv","w");
    $fwrite(csv_file, "pc,block_cycles,loads,stores\n");
    for (i2 = 0; i2 < 16384; i2 = i2 + 1)
      if (pc_block[i2] != 0 || pc_load[i2] != 0 || pc_store[i2] != 0)
        $fwrite(csv_file, "%08x,%0d,%0d,%0d\n", {i2,2'b00}, pc_block[i2], pc_load[i2], pc_store[i2]);
    $fclose(csv_file);
    $finish;
  end
endmodule
