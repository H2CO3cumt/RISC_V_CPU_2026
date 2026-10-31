`timescale 1ns/1ps
module tb_coremark_pipeline;
 parameter RANDOM_DELAY = 0;
 parameter MAX_CYCLES = 12000000;
 parameter ENABLE_BRANCH_PREDICTOR = 1;
parameter ENABLE_RAS = 0;
 // M 扩展乘法的 EX 占用拍数（见 rtl/mdu.v 的 MUL_LAT）：3=基线/2=并行部分积/1=全组合。
 // 只影响周期数与关键路径，不影响架构结果；Before/After 由 -PMDU_MUL_LAT=<n> 切换。
 parameter MDU_MUL_LAT = 2;
 // S3：取指路径上是否插入 2 路组相联 I-Cache（Off/On 的唯一变量）
 parameter ENABLE_ICACHE = 0;
 // S4：数据路径上是否插入 2 路组相联 D-Cache；CACHE_EN_D 控制其内部开关
 parameter ENABLE_DCACHE = 0;
 parameter CACHE_EN_D    = 1;
 // 调试追踪窗口（默认关闭，TRACE_LEN=0 时该 generate 块根本不生成，不影响任何测量）。
 // 用法：-Ptb_coremark_pipeline.TRACE_FROM=<n> -Ptb_coremark_pipeline.TRACE_LEN=<m>
 // 配合 -P...MAX_CYCLES=<n+m> 可以在几百拍内定位"第一个卡住的周期"。
 parameter TRACE_FROM = 0;
 parameter TRACE_LEN  = 0;
 // 数据事务流水账：打印**前 XACT_LOG 笔被 Core 接受的数据响应**（地址/wr/数据/err）。
 // 用途：Off/On 两种配置下逐笔比对"同一笔访问两边各拿到什么"，比看波形快得多。
 // 只依赖顶层端口网，不引用 generate 块内部，所以任何配置都能开。
 parameter XACT_LOG   = 0;
 // 影子比对默认**致命**（第一笔错读就停），保证"零错读"是硬结论。
 // 但在 `DATA_SLOW_LATENCY>0` 的探索性配置下，下游模型的写延迟会让影子
 // 与存储模型对不上（**纯直连配置也会报**，所以那不是 Cache 的问题），
 // 这时把它设成 0 只统计不中止，用来拿 cycles 数做同后端 Off/On 对比。
 parameter SHADOW_FATAL = 1;

 // 数据后端读延迟拍数：0 = 零等待（与 ram_adapter 等价）；>0 = 慢后端（DDR3 那类）
 parameter DATA_SLOW_LATENCY = 0;
 reg clk = 0;
 reg reset = 1;
 // 一次性打印本次 elaboration 实际用到的关键参数：用来判断 -P 覆盖是否真的生效。
 initial $display("TB-PARAMS enable_dcache=%0d cache_en_d=%0d enable_icache=%0d slow_lat=%0d",
                  ENABLE_DCACHE, CACHE_EN_D, ENABLE_ICACHE, DATA_SLOW_LATENCY);
 reg uart_rx = 1;
 wire uart_tx;
 wire [7:0] uart_byte;
 wire uart_byte_valid, uart_frame_error;
 integer cycles = 0;
`ifdef COREMARK_STALL_DEBUG
 // 卡死定位用的两个计数器（只在 -DCOREMARK_STALL_DEBUG 时存在）。
 integer stall_idle = 0;
 integer stall_last_retired = -1;
`endif integer retired = 0;
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
 wire trace_valid,event_stall,event_load,event_branch,event_taken,event_flush,event_predict,event_btb_hit,event_mispredict,event_control_redirect;
 wire [31:0] trace_pc,trace_instruction;
 wire trace_rd_we,trace_mem_we;
 wire [4:0] trace_rd_addr;
 wire [31:0] trace_rd_data,trace_mem_addr,trace_mem_data;
 wire [3:0] trace_mem_wstrb;
 wire [63:0] perf_cycles,perf_instret,perf_stalls,perf_loads;
 wire [63:0] perf_branches,perf_taken_count,perf_flushes,perf_predicts,perf_btb_hits,perf_mispredicts,perf_ctrl_redirects;
 wire perf_clear;
 wire ram_v,ram_r,uart_v,uart_r,gpio_v,gpio_r,app_v,app_r;
 wire [31:0] ta,twd,ram_rd,uart_rd,gpio_rd,app_rd,gpio_out;
 wire tw,ram_sv,uart_sv,gpio_sv,app_sv,ram_sr,uart_sr,gpio_sr,app_sr;
 wire [3:0] tws;
 wire ram_se,uart_se,gpio_se,app_se;
 wire [31:0] writes;

 // ---- D-Cache 串联专用的一对网（S4 集成接线，踩过大坑，务必别改回去）----
 // 互连 `soc_data_interconnect` 的 CPU 侧**不再直接挂 Core**，而是挂在这组 `x_*` 上：
 //   g_dcache   : Core -> D-Cache -> 互连   （Cache 的 ram 侧接 x_*）
 //   g_no_dcache: Core -> 互连             （x_* 与 Core 端口直连）
 // 【为什么必须这样】第一版把互连和 D-Cache **并联**接在同一组 Core 端口网上，
 // `dr/dsv/drd/de` 于是各有**两个驱动源**，仿真里全变成 x——
 // 表现为 Core 永远停在 D_RSP、`mem_done` 恒为 x/0、CoreMark 卡死在第一条 sw。
 // 这正是 S4 集成"卡死"的真根因：不是 Cache 的握手，也不是"拒收=丢请求"，是接线。
 wire        x_dv, x_dr, x_dw, x_dsv, x_dsr, x_de;
 wire [31:0] x_da, x_dwd, x_drd;
 wire [3:0]  x_dst;

 pipeline_cpu #(.ENABLE_BRANCH_PREDICTOR(ENABLE_BRANCH_PREDICTOR),.ENABLE_RAS(ENABLE_RAS),.MDU_MUL_LAT(MDU_MUL_LAT)) core(
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
  .event_predict(event_predict),.event_btb_hit(event_btb_hit),.event_mispredict(event_mispredict),
  .event_control_redirect(event_control_redirect));
 perf_monitor perf(.clk(clk),.reset(reset),.clear(perf_clear),.enable(1'b1),
  .event_retire(trace_valid),.event_stall(event_stall),
  .event_load_stall(event_load),.event_branch(event_branch),
  .event_branch_taken(event_taken),.event_flush(event_flush),
  .event_predict(event_predict),.event_btb_hit(event_btb_hit),.event_mispredict(event_mispredict),
  .event_control_redirect(event_control_redirect),
  .cycle_count(perf_cycles),.instret_count(perf_instret),
  .stall_count(perf_stalls),.load_stall_count(perf_loads),
  .branch_count(perf_branches),.branch_taken_count(perf_taken_count),
  .flush_count(perf_flushes),.predict_count(perf_predicts),
  .btb_hit_count(perf_btb_hits),.mispredict_count(perf_mispredicts),
  .control_redirect_count(perf_ctrl_redirects));
 // ---- S3：取指路径上可选插入 2 路组相联 I-Cache（全部位于 Core 外部）----
 // `ENABLE_ICACHE=0` 时**编译期**把 I-Cache 整体旁路掉，取指直连 imem——
 // 于是 Off/On 是同一份 TB、同一份 Core、同一份程序，唯一变量就是这条 Cache 路径。
 // 这样做而不是运行时开关，是为了让"Off"真的等价于加入 Cache 之前的基线，
 // 不引入任何额外组合/时序开销。
 wire        ic_m_req_valid, ic_m_req_ready, ic_m_beat_valid, ic_m_beat_ready;
 wire        ic_m_beat_last, ic_m_beat_error;
 wire [31:0] ic_m_req_addr, ic_m_beat_data;
 wire [7:0]  ic_m_req_len;
 wire [31:0] ic_hits, ic_misses, ic_bus_cycles, ic_beats;

 generate
 if (ENABLE_ICACHE) begin : g_icache
   // I-Cache 的"行填充"下游：一个**组合读**的指令内存。
   // 为什么不用 pipeline_imem_adapter：那个模型的响应要等下一拍，
   // 与"整行 8 拍连发"的行填充语义不合；这里的模型每拍给一个字，
   // 正好对应真实 BRAM 的 1 拍读延迟，也让 Cache 的收益/代价看得清楚。
   reg [31:0] imem_img [0:8191];
   integer ii;
   initial begin
     for (ii = 0; ii < 8192; ii = ii + 1) imem_img[ii] = 32'h0000_0013;  // nop 兜底
     $readmemh("software/coremark/build/coremark_imem.mem", imem_img);
   end
   reg        fill_active;
   reg [7:0]  fill_idx_g;
   reg [31:0] fill_base;
   reg        fill_err;

   // 行请求握手：接受后进入连发；每拍给一个字，第 8 拍置 last
   always @(posedge clk) begin
     if (reset) begin
       fill_active <= 1'b0;
       fill_idx_g  <= 8'd0;
       fill_err    <= 1'b0;
     end
     else if (ic_m_req_valid && ic_m_req_ready) begin
       fill_base   <= ic_m_req_addr;
       fill_idx_g  <= 8'd0;
       fill_err    <= ((ic_m_req_addr[31:2] + ic_m_req_len) >= 8192);
       fill_active <= 1'b1;
     end
     else if (fill_active && ic_m_beat_valid && ic_m_beat_ready) begin
       if (ic_m_beat_last) fill_active <= 1'b0;
       else                fill_idx_g  <= fill_idx_g + 8'd1;
     end
   end

   assign ic_m_req_ready  = !fill_active;
   assign ic_m_beat_valid = fill_active;
   assign ic_m_beat_data  = imem_img[fill_base[31:2] + fill_idx_g];
   assign ic_m_beat_last  = fill_active && (fill_idx_g == ic_m_req_len);
   assign ic_m_beat_error = fill_active && fill_err;

   soc_icache_2way #(.SETS(32), .WAYS(2), .LINE_BYTES(32), .CACHE_EN(1)) icache(
     .clk(clk), .reset(reset),
     .req_valid(iv), .req_ready(ir), .req_addr(ia),
     .rsp_valid(rv), .rsp_ready(rr), .rsp_data(idata), .rsp_error(ie),
     .m_req_valid(ic_m_req_valid), .m_req_ready(ic_m_req_ready),
     .m_req_addr(ic_m_req_addr), .m_req_len(ic_m_req_len),
     .m_beat_valid(ic_m_beat_valid), .m_beat_ready(ic_m_beat_ready),
     .m_beat_data(ic_m_beat_data), .m_beat_last(ic_m_beat_last),
     .m_beat_error(ic_m_beat_error),
     .stat_hits(ic_hits), .stat_misses(ic_misses),
     .stat_bus_cycles(ic_bus_cycles), .stat_beats(ic_beats),
     .stat_core_wait()
   );
 end
 else begin : g_no_icache
   // 基线：取指直连原有的 imem 适配器（与加入 Cache 之前完全一致）
   pipeline_imem_adapter #(.DEPTH(8192),
     .INIT_FILE("software/coremark/build/coremark_imem.mem"),
     .RANDOM_DELAY(RANDOM_DELAY)) imem(
     .clk(clk),.reset(reset),.req_valid(iv),.req_ready(ir),.req_addr(ia),
     .rsp_valid(rv),.rsp_ready(rr),.rsp_data(idata),.rsp_error(ie));
 end
 endgenerate

 soc_data_interconnect #(.RAM_LAST_ADDR(32'h0000ffff)) xbar(
  .clk(clk),.reset(reset),.cpu_req_valid(x_dv),.cpu_req_ready(x_dr),
  .cpu_req_addr(x_da),.cpu_req_write(x_dw),.cpu_req_wdata(x_dwd),
  .cpu_req_wstrb(x_dst),.cpu_rsp_valid(x_dsv),.cpu_rsp_ready(x_dsr),
  .cpu_rsp_rdata(x_drd),.cpu_rsp_error(x_de),.ram_req_valid(ram_v),
  .ram_req_ready(ram_r),.uart_req_valid(uart_v),.uart_req_ready(uart_r),
  .gpio_req_valid(gpio_v),.gpio_req_ready(gpio_r),.app_req_valid(app_v),
  .app_req_ready(app_r),.target_req_addr(ta),.target_req_write(tw),
  .target_req_wdata(twd),.target_req_wstrb(tws),.ram_rsp_valid(ram_sv),
  .ram_rsp_ready(ram_sr),.ram_rsp_rdata(ram_rd),.ram_rsp_error(ram_se),
  .uart_rsp_valid(uart_sv),.uart_rsp_ready(uart_sr),.uart_rsp_rdata(uart_rd),
  .uart_rsp_error(uart_se),.gpio_rsp_valid(gpio_sv),.gpio_rsp_ready(gpio_sr),
  .gpio_rsp_rdata(gpio_rd),.gpio_rsp_error(gpio_se),.app_rsp_valid(app_sv),
  .app_rsp_ready(app_sr),.app_rsp_rdata(app_rd),.app_rsp_error(app_se));
 // ---- S4：数据路径上可选插入 2 路组相联 D-Cache（全部位于 Core 外部）----
 // `ENABLE_DCACHE=0` 时编译期整体旁路，走原来的 `ram_adapter` —— 与加入 Cache 之前完全一致。
 // `DATA_SLOW_LATENCY` 表示 RAM 后端有多慢：0 = 零等待（与 ram_adapter 等价），
 //   >0 = 每次读多等若干拍（DDR3 那类）。评价 Cache 必须连同这个前提一起报告。
 generate
 if (ENABLE_DCACHE) begin : g_dcache
   initial $display("TB-BUILT g_dcache");
   wire [31:0] dc_hits, dc_misses, dc_bypass, dc_forward;
   dcache_coremark_adapter #(
     .CACHE_EN(CACHE_EN_D),
     .SLOW_RD_LATENCY(DATA_SLOW_LATENCY),
     .SETS(32)
   ) dcache_wrap (
     .clk(clk), .reset(reset),
     .cpu_req_valid(dv), .cpu_req_ready(dr), .cpu_req_addr(da),
     .cpu_req_write(dw), .cpu_req_wdata(dwd), .cpu_req_wstrb(dst),
     .cpu_rsp_valid(dsv), .cpu_rsp_ready(dsr), .cpu_rsp_rdata(drd), .cpu_rsp_error(de),
     .ram_req_valid(x_dv), .ram_req_ready(x_dr), .ram_req_addr(x_da),
     .ram_req_write(x_dw), .ram_req_wdata(x_dwd), .ram_req_wstrb(x_dst),
     .ram_rsp_valid(x_dsv), .ram_rsp_ready(x_dsr), .ram_rsp_rdata(x_drd),
     .ram_rsp_error(x_de),
     .stat_hits(dc_hits), .stat_misses(dc_misses), .stat_bypass(dc_bypass),
     .stat_forward(dc_forward)
   );
   slow_ram_adapter #(
     .DEPTH(16384),
     .INIT_FILE("software/coremark/build/coremark_dmem.mem"),
     .SLOW_RD_LATENCY(DATA_SLOW_LATENCY)
   ) ram (
     .clk(clk), .reset(reset), .req_valid(ram_v), .req_ready(ram_r), .req_addr(ta),
     .req_write(tw), .req_wdata(twd), .req_wstrb(tws), .rsp_valid(ram_sv),
     .rsp_ready(ram_sr), .rsp_rdata(ram_rd), .rsp_error(ram_se),
     .write_side_effect_count(writes));
 end
 else begin : g_no_dcache
   initial $display("TB-BUILT g_no_dcache");
   // 无 D-Cache：互连的 CPU 侧与 Core 数据端口直连（与加入 Cache 之前完全一致）
   assign x_dv = dv; assign x_da = da; assign x_dw = dw;
   assign x_dwd = dwd; assign x_dst = dst; assign x_dsr = dsr;
   assign dr = x_dr; assign dsv = x_dsv; assign drd = x_drd; assign de = x_de;
   ram_adapter #(.DEPTH(16384),
     .INIT_FILE("software/coremark/build/coremark_dmem.mem"),
     .RANDOM_DELAY(RANDOM_DELAY)) ram(
     .clk(clk),.reset(reset),.req_valid(ram_v),.req_ready(ram_r),.req_addr(ta),
     .req_write(tw),.req_wdata(twd),.req_wstrb(tws),.rsp_valid(ram_sv),
     .rsp_ready(ram_sr),.rsp_rdata(ram_rd),.rsp_error(ram_se),
     .write_side_effect_count(writes));
 end
 endgenerate

 // ---- 调试追踪：逐拍打印取指/访存/D-Cache/适配器内部状态（默认关闭）----
 generate
 if (TRACE_LEN > 0 && ENABLE_DCACHE != 0) begin : g_trace
   initial $display("TRACE-ON from=%0d len=%0d enable_dcache=%0d", TRACE_FROM, TRACE_LEN, ENABLE_DCACHE);
   // 只在"签名"变化时打印：否则一次卡死会刷出几百行完全相同的状态。
   reg [95:0] tr_sig = 96'd0;
   wire [95:0] tr_now = {iv,ir,rv,rr,dv,dsv,dsr,da[15:0],dw,
                         g_dcache.dcache_wrap.u_cache.state,
                         g_dcache.dcache_wrap.u_cache.pend_valid,
                         g_dcache.dcache_wrap.u_cache.wb_valid,
                         g_dcache.dcache_wrap.u_cache.m_rd_valid,
                         g_dcache.dcache_wrap.u_cache.m_rd_ready,
                         g_dcache.dcache_wrap.lf_state,
                         g_dcache.dcache_wrap.u_cache.addr_q[15:0],
                         g_dcache.dcache_wrap.u_cache.stat_rsp_accepted[7:0]};
   always @(negedge clk) begin
     if (cycles >= TRACE_FROM && cycles < (TRACE_FROM + TRACE_LEN)) begin
       if (tr_now !== tr_sig) begin
         $display("TR c=%0d pc=%08h |IF v=%b r=%b sv=%b sr=%b |DP v=%b sv=%b sr=%b a=%04h wr=%b |CORE dstate=%0d exv=%b exacc=%b mdone=%b mblk=%b idxv=%b |CACHE st=%0d pend=%b wb=%b mrdv=%b mrrdy=%b acc=%0d |ADAP lf=%0d |RAM v=%b r=%b sv=%b",
           cycles, trace_pc, iv, ir, rv, rr,
           dv, dsv, dsr, da[15:0], dw,
           core.dstate, core.exmem_valid, core.exmem_access, core.mem_done, core.mem_block, core.idex_valid,
           g_dcache.dcache_wrap.u_cache.state,
           g_dcache.dcache_wrap.u_cache.pend_valid,
           g_dcache.dcache_wrap.u_cache.wb_valid,
           g_dcache.dcache_wrap.u_cache.m_rd_valid,
           g_dcache.dcache_wrap.u_cache.m_rd_ready,
           g_dcache.dcache_wrap.u_cache.stat_rsp_accepted[7:0],
           g_dcache.dcache_wrap.lf_state,
           ram_v, ram_r, ram_sv);
         tr_sig <= tr_now;
       end
     end
   end
 end
 endgenerate

 // ---- 数据事务流水账（XACT_LOG>0 时打印前 N 笔**非 RAM** 的数据响应）----
 // 只记 MMIO（addr[31:16] != 0）：RAM 访问有几千笔会淹掉输出，
 // 而 S4 出问题的正是"MMIO 必须原样透传"这条，所以只看它。
 // 只依赖顶层端口网，不引用 generate 块内部，任何配置都能开。
 generate
 if (XACT_LOG > 0) begin : g_xact
   integer xn = 0;
   always @(negedge clk) begin
     if (dsv && dsr && (da[31:16] != 16'h0000) && xn < XACT_LOG) begin
       $display("XACT %0d addr=%08h wr=%b wdata=%08h rdata=%08h err=%b",
                xn, da, dw, dwd, drd, de);
       xn = xn + 1;
     end
   end
 end
 endgenerate

 // ---- 影子内存：逐笔比对数据读，报出**第一笔读错**（这是找 S4 错数据最快的办法）----
 // 为什么需要：模块级 TB 的存储模型只有 2048 字（0x0~0x1FFF），
 // 而 CoreMark 的数据在 0x8000~0xFFFF —— **模块级 TB 根本寻址不到出问题的区间**，
 // 所以它 19 项全过但集成烂。这里直接用同一份 dmem 镜像做影子，逐笔对。
 // 判据：addr <= 0xFFFF 的读响应被 Core 接受时，数据必须等于影子值。
 //   （MMIO 地址 > 0xFFFF 不比对：那些是寄存器，本来就没有影子。）
 // 只在 ENABLE_DCACHE!=0 时生成：报错信息要引用 D-Cache 内部信号。
 generate
 if (ENABLE_DCACHE != 0) begin : g_shadow
   reg [31:0] shadow [0:16383];
   integer    sh_i;
   integer    sh_bad = 0;
   initial begin
     for (sh_i = 0; sh_i < 16384; sh_i = sh_i + 1) shadow[sh_i] = 32'd0;
     $readmemh("software/coremark/build/coremark_dmem.mem", shadow);
   end
   always @(negedge clk) begin
     // 写：按 wstrb 更新影子（写穿，与下游 RAM 同一份数据）
     if (dv && dr && dw && (da <= 32'h0000_FFFF)) begin
       if (dst[0]) shadow[da[15:2]][7:0]   = dwd[7:0];
       if (dst[1]) shadow[da[15:2]][15:8]  = dwd[15:8];
       if (dst[2]) shadow[da[15:2]][23:16] = dwd[23:16];
       if (dst[3]) shadow[da[15:2]][31:24] = dwd[31:24];
     end
     // 读：响应被接受的那一拍比对
     if (dsv && dsr && !dw && (da <= 32'h0000_FFFF)) begin
       if (drd !== shadow[da[15:2]]) begin
         sh_bad = sh_bad + 1;
         if (sh_bad <= 4)
           $display("!!! WRONG DATA READ #%0d cycles=%0d addr=%08h expected=%08h got=%08h\n    CACHE st=%0d cacheable=%b aq=%08h set=%0d word=%0d tag=%08h hit=%b hit0=%b hit1=%b\n    CACHE mrdv=%b mrrdy=%b mrdaddr=%08h mrdlen=%0d beatv=%b beatrdy=%b last=%b\n    ADAP  lf=%0d base=%08h idx=%0d feed=%0d words=%0d\n    CORE  dstate=%0d exv=%b exacc=%b mdone=%b mblk=%b",
                    sh_bad, cycles, da, shadow[da[15:2]], drd,
                    g_dcache.dcache_wrap.u_cache.state,
                    g_dcache.dcache_wrap.u_cache.cacheable_q,
                    g_dcache.dcache_wrap.u_cache.addr_q,
                    g_dcache.dcache_wrap.u_cache.set_q,
                    g_dcache.dcache_wrap.u_cache.word_q,
                    g_dcache.dcache_wrap.u_cache.tag_q,
                    g_dcache.dcache_wrap.u_cache.hit,
                    g_dcache.dcache_wrap.u_cache.hit0,
                    g_dcache.dcache_wrap.u_cache.hit1,
                    g_dcache.dcache_wrap.u_cache.m_rd_valid,
                    g_dcache.dcache_wrap.u_cache.m_rd_ready,
                    g_dcache.dcache_wrap.u_cache.m_rd_addr,
                    g_dcache.dcache_wrap.u_cache.m_rd_len,
                    g_dcache.dcache_wrap.u_cache.m_beat_valid,
                    g_dcache.dcache_wrap.u_cache.m_beat_ready,
                    g_dcache.dcache_wrap.u_cache.m_beat_last,
                    g_dcache.dcache_wrap.lf_state,
                    g_dcache.dcache_wrap.lf_base,
                    g_dcache.dcache_wrap.lf_idx,
                    g_dcache.dcache_wrap.lf_feed,
                    g_dcache.dcache_wrap.lf_words,
                    core.dstate, core.exmem_valid, core.exmem_access,
                    core.mem_done, core.mem_block);
         if (SHADOW_FATAL != 0 && sh_bad == 3) $fatal(1, "S4 WRONG DATA READS (see above)");
       end
     end
   end
 end
 endgenerate

 // ---- UART 诊断：TX 寄存器写次数 ----
 // 与 TB 统计的 `bytes`（实际发出的字节数）对比，就能区分两种"丢字符"：
 //   写次数 == bytes  -> 程序没少写，是 UART 没发出去（例如写太早、TX 还忙）
 //   写次数 <  bytes  -> 不可能
 //   写次数 >  bytes  -> 程序写了但 UART 丢了一部分
 // 定期打印，避免依赖程序是否跑完。
 integer uart_tx_writes = 0;
 always @(negedge clk)
   if (uart_v && uart_r && tw && (ta[7:0] == 8'h00)) uart_tx_writes = uart_tx_writes + 1;
 initial begin
   forever begin
     #2000000;
     $display("UART-DIAG tx_reg_writes=%0d bytes=%0d cycles=%0d", uart_tx_writes, bytes, cycles);
   end
 end

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
`ifdef COREMARK_TRACE_COMMITS
    // 逐条提交记录：两个版本（改前/改后）跑同一镜像时逐行 diff，第一处不同就是
    // 第一个被算错的指令。默认不编译，只在本轮定位 M 扩展问题时打开。
    if (retired <= 400000)
     $display("RETIRE %0d pc=%08h inst=%08h rw=%b rd=%0d data=%08h mw=%b ma=%08h md=%08h",
              retired,trace_pc,trace_instruction,trace_rd_we,trace_rd_addr,trace_rd_data,
              trace_mem_we,trace_mem_addr,trace_mem_data);
`endif
    last_trace_pc = trace_pc;
    last_trace_instruction = trace_instruction;
    trace_pc_history[trace_history_index] = trace_pc;
    trace_instruction_history[trace_history_index] = trace_instruction;
    trace_history_index = (trace_history_index + 1) & 15;
   end
   if ((cycles % 1000000) == 0)
    $display("COREMARK PROGRESS cycles=%0d retired=%0d pc=%08h inst=%08h gpio=%02h",
             cycles,retired,last_trace_pc,last_trace_instruction,gpio_out[7:0]);
`ifdef COREMARK_STALL_DEBUG
   // 卡死定位：连续 512 拍没有新的提交记录时，把流水线各级状态打一次。
   // 只在显式 -DCOREMARK_STALL_DEBUG 时编译进来，默认完全不参与测量与判据。
   if (retired == stall_last_retired) begin
    stall_idle = stall_idle + 1;
    if (stall_idle == 512) begin
     $display("STALL DUMP cycles=%0d retired=%0d lastpc=%08h lastinst=%08h",
              cycles,retired,last_trace_pc,last_trace_instruction);
     $display("  IF if_req=%b if_arm=%b if_rsp=%b i_req_valid=%b i_req_ready=%b i_rsp_ready=%b fetch_pc=%08h",
              core.if_req,core.if_arm,core.if_rsp,core.i_req_valid,core.i_req_ready,core.i_rsp_ready,core.fetch_pc);
     $display("  IFID valid=%b pc=%08h inst=%08h",core.ifid_valid,core.ifid_pc,core.ifid_inst);
     $display("  IDEX valid=%b pc=%08h inst=%08h mdu_en=%b mdu_op=%b illegal=%b",
              core.idex_valid,core.idex_pc,core.idex_inst,core.idex_mdu_en,core.idex_mdu_op,core.idex_illegal);
     $display("  MDU busy=%b block=%b mul_busy=%b state=%0d run=%b ack=%b",
              core.mdu_busy,core.mdu_block,core.mdu_unit.mul_busy,core.mdu_unit.state,core.mdu_run,core.mdu_ack);
     $display("  EXMEM valid=%b retired=%b access=%b mem_done=%b mem_block=%b alu=%08h dstate=%0d",
              core.exmem_valid,core.exmem_retired,core.exmem_access,core.mem_done,core.mem_block,core.exmem_alu,core.dstate);
     $display("  MEMWB valid=%b pc=%08h inst=%08h",core.memwb_valid,core.memwb_pc,core.memwb_inst);
     $display("  TRAP take=%b ready=%b wb_exc=%0d",core.trap_take,core.trap_ready,core.wb_exc_cause);
    end
   end else begin
    stall_last_retired = retired; stall_idle = 0;
   end
`endif
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
`ifdef COREMARK_STALL_DEBUG
   // 超时时把最近 16 条提交记录按**时间顺序**打出来：直接看出程序卡在哪个循环里。
   for (history_dump_index=0;history_dump_index<16;history_dump_index=history_dump_index+1)
    $display("TIMEOUT HISTORY %0d pc=%08h inst=%08h",
             history_dump_index,
             trace_pc_history[(trace_history_index+history_dump_index)&15],
             trace_instruction_history[(trace_history_index+history_dump_index)&15]);
`endif
   $fatal(1,"COREMARK PIPELINE TIMEOUT");
  end
  if (errors != 0) $fatal(1,"COREMARK UART FRAME ERRORS %0d",errors);
  if (bytes < 200) $fatal(1,"COREMARK UART OUTPUT TOO SHORT %0d",bytes);
  $display("COREMARK PIPELINE EXECUTION PASS cycles=%0d retired=%0d bytes=%0d",cycles,retired,bytes);
      $display("ATTR cycles=%0d retired=%0d mem_block=%0d mdu_block=%0d data_xact=%0d store=%0d load_use=%0d stall=%0d",
               cycles, retired, c_memblk, c_mdublk, c_dxact, c_store, c_loaduse, c_stall);
  // 字段名必须与 python/release_evidence.py 的解析正则一致：
  // 该脚本按 `stall=... load_stall=... branch=... taken=... flush=...` 提取，
  // 历史上这里曾写成 `load=...`，导致 Task 29 证据提取必然失败（已修正）。
  $display("COREMARK PERF stall=%0d load_stall=%0d branch=%0d taken=%0d flush=%0d writes=%0d ctrl_redir=%0d",
           perf_stalls,perf_loads,perf_branches,perf_taken_count,perf_flushes,writes,perf_ctrl_redirects);
  $display("COREMARK PREDICTOR enabled=%0d predict=%0d btb_hit=%0d mispredict=%0d",
           ENABLE_BRANCH_PREDICTOR,perf_predicts,perf_btb_hits,perf_mispredicts);
  $finish;
 end

// ===========================================================================
// Attribution counters (read-only, 2026-10-18)
// Sample Core-internal signals through hierarchical references only, so
// pipeline_cpu keeps its frozen port list (docs/interfaces.md 6.1).
// Purpose: split event_stall into mem_block (data transaction frozen) and
// mdu_block (MDU frozen). Both are independent of the memory model, so they
// can be reconciled against the board performance counters.
// Note: mem_block costs 1 cycle per access on the board (coremark_dmem has
// req_ready=!rsp_valid) but about 2 in simulation (tb/ram_adapter.v has
// RANDOM_DELAY=1), so use data_xact for board projections, not c_memblk.
// ===========================================================================
integer c_memblk = 0;
integer c_mdublk = 0;
integer c_dxact  = 0;
integer c_store  = 0;
integer c_loaduse= 0;
integer c_stall  = 0;

always @(posedge clk) begin
    if (!reset) begin
        if (core.mem_block)                                     c_memblk <= c_memblk + 1;
        if (core.mdu_block)                                     c_mdublk <= c_mdublk + 1;
        if (core.d_req_valid && core.d_req_ready)                c_dxact  <= c_dxact  + 1;
        if (core.d_req_valid && core.d_req_ready && core.d_req_write) c_store <= c_store + 1;
        if (core.load_use)                                      c_loaduse<= c_loaduse+ 1;
        if (core.front_hold)                                    c_stall  <= c_stall  + 1;
    end
end
endmodule
