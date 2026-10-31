// M-24 / N1：MES50HP 板级"周期性定时器中断"最小演示工程。
//
// 存在的意义：把**已经做完**的高阶任务②（机器模式 CSR / 精确 Trap / 三根通用中断输入）
// 从"仿真通过"升级为"实板可复现"。验收现象有三条：
//   1. LED0 固定周期闪烁（周期 = mtimecmp 的 delta，缺省 0.25 s 翻转一次）；
//   2. UART 上每次中断打印两个字符（中断计数 0..9 + LED 值低 4 位），
//      说明 ISR 真的在跑；
//   3. 计数一直累加、LED 一直翻转，说明 mret 回到了被打断的位置。
//
// 边界纪律（docs/interfaces.md）：
//   - CPU Core 完全不知道定时器和 GPIO 的存在；中断只通过一根设备无关的 irq_timer_i 进入；
//   - 地址译码、定时器、UART、GPIO 全在 Core 外部；
//   - 本工程是**新的最小工程**，不改动交付用的 fpga/logic_analyzer 程序镜像与位流。
module mes50hp_timer_demo_top #(
    parameter UART_BAUD_CYCLES = 50_000_000 / 115200,
    // 数据 RAM 窗口上界。1024 字（4 KB）= 与 IMEM 镜像同深度，
    // 于是"取指端口"和"数据端口"指向同一份 BRAM 镜像，见 timer_demo_program_memory.v 的说明。
    parameter [31:0] RAM_LAST_ADDR = 32'h0000_0fff
) (
    input  wire       clk_50m,
    input  wire       uart0_rx,
    output wire       uart0_tx,
    output wire [7:0] led
);

    // 内部上电复位（docs/fpga_platform.md §3：USE_EXTERNAL_RESET=0）。
    // 8 位计数器计满 256 拍后释放复位，保证 BRAM（$readmemh 初始化）和 MMIO 都稳定。
    reg [7:0] por_count = 8'd0;
    reg       reset = 1'b1;
    always @(posedge clk_50m) begin
        if (reset) begin
            por_count <= por_count + 1'b1;
            if (&por_count) reset <= 1'b0;
        end
    end

    // ---- Core 的统一事务端口 ----
    wire        iv, ir, rv, rr, ie;
    wire        dv, dr, dw, dsv, dsr, de;
    wire [31:0] ia, idata, da, dwd, drd;
    wire [3:0]  dst;

    // ---- 性能计数器事件（本演示不需要读数，但端口必须接全） ----
    wire        perf_retire, perf_stall, perf_load, perf_branch, perf_taken, perf_flush;
    wire        perf_predict, perf_btb_hit, perf_mispredict;

    // ---- 互连到各目标的请求/响应 ----
    wire        ram_v, ram_r, uart_v, uart_r, gpio_v, gpio_r, timer_v, timer_r;
    wire        ram_sv, ram_sr, ram_se, uart_sv, uart_sr, uart_se;
    wire        gpio_sv, gpio_sr, gpio_se, timer_sv, timer_sr, timer_se;
    wire [31:0] ta, twd, ram_rd, uart_rd, gpio_rd, timer_rd;
    wire        tw;
    wire [3:0]  tws;

    wire [31:0] gpio_out;
    // SoC 侧聚合出来的定时器中断请求：只接 Core 的一根通用中断输入。
    wire        irq_timer;

    // APP 目标（0x1000_2000~0x1000_2FFF）本演示不使用。
    // docs/interfaces.md §3.2 的约定允许把不需要的目标留空：该窗口没有地址被译码过去时，
    // app_req_valid 恒为 0；互连的 app 请求/响应端口在下面显式接常量，不留悬空。

    pipeline_cpu core (
        .clk(clk_50m), .reset(reset),
        .trace_valid(perf_retire),
        .trace_pc(), .trace_instruction(),
        .trace_rd_we(), .trace_rd_addr(), .trace_rd_data(),
        .trace_mem_we(), .trace_mem_addr(), .trace_mem_data(), .trace_mem_wstrb(),
        .i_req_valid(iv), .i_req_ready(ir), .i_req_addr(ia),
        .i_rsp_valid(rv), .i_rsp_ready(rr), .i_rsp_data(idata), .i_rsp_error(ie),
        .d_req_valid(dv), .d_req_ready(dr), .d_req_addr(da), .d_req_write(dw),
        .d_req_wdata(dwd), .d_req_wstrb(dst),
        .d_rsp_valid(dsv), .d_rsp_ready(dsr), .d_rsp_rdata(drd), .d_rsp_error(de),
        // 只有定时器这一根被真正驱动；另外两根通用中断输入显式接 0（其余中断源做在 SoC 之外
        // 才允许接入，本演示只演示机器定时器中断）。
        .irq_software_i(1'b0), .irq_timer_i(irq_timer), .irq_external_i(1'b0),
        .event_stall(perf_stall), .event_load_stall(perf_load),
        .event_branch(perf_branch), .event_branch_taken(perf_taken),
        .event_flush(perf_flush), .event_predict(perf_predict),
        .event_btb_hit(perf_btb_hit), .event_mispredict(perf_mispredict)
`ifdef PDS_TIMER_DEMO_ILA
        // ---- M-24 / N2 诊断位流专用（`` `ifdef `` 之外一个字都不变）----
        // 这里接出来的全是 Core **既有**的输出端口（rtl/pipeline_cpu.v 第 55-59 行），
        // 因此**不需要改 Core 的端口表**，满足 Core 端口不变的硬约束。
        // 非诊断构建（即已交付的 N1 位流）端口连接与改动前完全一致。
        , .event_trap(ila_event_trap)
        , .event_trap_return(ila_event_trap_return)
        , .event_illegal(ila_event_illegal)
        , .event_misaligned(ila_event_misaligned)
        , .event_bus_error(ila_event_bus_error)
        , .event_control_redirect(ila_event_ctrl_redirect)
`endif
    );

    perf_monitor perf (
        .clk(clk_50m), .reset(reset), .clear(1'b0), .enable(1'b1),
        .event_retire(perf_retire), .event_stall(perf_stall),
        .event_load_stall(perf_load), .event_branch(perf_branch),
        .event_branch_taken(perf_taken), .event_flush(perf_flush),
        .event_predict(perf_predict), .event_btb_hit(perf_btb_hit),
        .event_mispredict(perf_mispredict),
        .cycle_count(), .instret_count(), .stall_count(), .load_stall_count(),
        .branch_count(), .branch_taken_count(), .flush_count(),
        .predict_count(), .btb_hit_count(), .mispredict_count()
    );

    // IMEM / DMEM。
    // `TIMER_DEMO_RANDOM_MEM` 只在 Testbench 的第二遍（随机背压）里定义：
    //   那时这两个 BRAM 不例化，改由 Testbench 用带随机延迟的行为模型，
    //   经下面的 imem_* / dmem_* 端口从**外部**驱动同一组网线。
    //   这样"同一个顶层、同一套断言、只换存储模型"成立，DUT 的连线一个字都不用改。
    // 综合（PDS）永远不定义这个宏，所以交付位流里就是这两个 BRAM。
`ifndef TIMER_DEMO_RANDOM_MEM
    timer_demo_imem imem (
        .clk(clk_50m), .reset(reset),
        .req_valid(iv), .req_ready(ir), .req_addr(ia),
        .rsp_valid(rv), .rsp_ready(rr), .rsp_data(idata), .rsp_error(ie)
    );
`endif

    soc_data_interconnect #(.RAM_LAST_ADDR(RAM_LAST_ADDR)) xbar (
        .clk(clk_50m), .reset(reset),
        .cpu_req_valid(dv), .cpu_req_ready(dr), .cpu_req_addr(da),
        .cpu_req_write(dw), .cpu_req_wdata(dwd), .cpu_req_wstrb(dst),
        .cpu_rsp_valid(dsv), .cpu_rsp_ready(dsr),
        .cpu_rsp_rdata(drd), .cpu_rsp_error(de),
        .ram_req_valid(ram_v), .ram_req_ready(ram_r),
        .uart_req_valid(uart_v), .uart_req_ready(uart_r),
        .gpio_req_valid(gpio_v), .gpio_req_ready(gpio_r),
        .app_req_valid(), .app_req_ready(1'b0),
        .timer_req_valid(timer_v), .timer_req_ready(timer_r),
        .target_req_addr(ta), .target_req_write(tw),
        .target_req_wdata(twd), .target_req_wstrb(tws),
        .ram_rsp_valid(ram_sv), .ram_rsp_ready(ram_sr),
        .ram_rsp_rdata(ram_rd), .ram_rsp_error(ram_se),
        .uart_rsp_valid(uart_sv), .uart_rsp_ready(uart_sr),
        .uart_rsp_rdata(uart_rd), .uart_rsp_error(uart_se),
        .gpio_rsp_valid(gpio_sv), .gpio_rsp_ready(gpio_sr),
        .gpio_rsp_rdata(gpio_rd), .gpio_rsp_error(gpio_se),
        // APP 目标不使用：rsp 端必须给"确定"的值。互连对未选择目标取的是 1'b1
        // （见 soc_data_interconnect 的 selected_rsp_error），这里显式接上以免悬空。
        .app_rsp_valid(1'b0), .app_rsp_rdata(32'b0), .app_rsp_error(1'b1),
        .timer_rsp_valid(timer_sv), .timer_rsp_ready(timer_sr),
        .timer_rsp_rdata(timer_rd), .timer_rsp_error(timer_se)
    );

`ifndef TIMER_DEMO_RANDOM_MEM
    timer_demo_dmem dmem (
        .clk(clk_50m), .reset(reset),
        .req_valid(ram_v), .req_ready(ram_r), .req_addr(ta),
        .req_write(tw), .req_wdata(twd), .req_wstrb(tws),
        .rsp_valid(ram_sv), .rsp_ready(ram_sr),
        .rsp_rdata(ram_rd), .rsp_error(ram_se)
    );
`endif

    uart_mmio #(
        .UART_MAX_1BAUD(UART_BAUD_CYCLES),
        .UART_RX_MAX_1BAUD(UART_BAUD_CYCLES)
    ) uart (
        .clk(clk_50m), .reset(reset),
        .uart_req_valid(uart_v), .uart_req_ready(uart_r),
        .uart_req_addr(ta), .uart_req_write(tw),
        .uart_req_wdata(twd), .uart_req_wstrb(tws),
        .uart_rsp_valid(uart_sv), .uart_rsp_ready(uart_sr),
        .uart_rsp_rdata(uart_rd), .uart_rsp_error(uart_se),
        .uart_rx(uart0_rx), .uart_tx(uart0_tx)
    );

    timer_mmio timer (
        .clk(clk_50m), .reset(reset),
        .timer_req_valid(timer_v), .timer_req_ready(timer_r),
        .timer_req_addr(ta), .timer_req_write(tw),
        .timer_req_wdata(twd), .timer_req_wstrb(tws),
        .timer_rsp_valid(timer_sv), .timer_rsp_ready(timer_sr),
        .timer_rsp_rdata(timer_rd), .timer_rsp_error(timer_se),
        .irq_timer(irq_timer)
    );

    gpio_mmio gpio (
        .clk(clk_50m), .reset(reset),
        .gpio_req_valid(gpio_v), .gpio_req_ready(gpio_r),
        .gpio_req_addr(ta), .gpio_req_write(tw),
        .gpio_req_wdata(twd), .gpio_req_wstrb(tws),
        .gpio_rsp_valid(gpio_sv), .gpio_rsp_ready(gpio_sr),
        .gpio_rsp_rdata(gpio_rd), .gpio_rsp_error(gpio_se),
        .gpio_out(gpio_out)
    );

    // MES50HP 用户 LED 高电平点亮（docs/fpga_platform.md §4）。
    // gpio_out[0] 就是 ISR 每 delta 拍翻转一次的 bit0 → LED0（管脚 B2）。
    assign led = gpio_out[7:0];

`ifdef PDS_TIMER_DEMO_ILA
    //=========================================================================
    // M-24 / N2：把 Trap 进入/返回挂到 DebugCore 的 192 位探针上（板级 ILA）
    //
    // 【为什么这样接才合规】
    //   Core 的端口与事务语义不得改变。所以：
    //     - 事件脉冲全部用 Core **既有**的输出端口（上面例化处已接出）；
    //     - `mepc/mcause/mtval/mtvec/mscratch/mstatus.MIE` 是 `csr_unit` 的内部寄存器，
    //       这里用**层级引用** `core.csr.*` 观察 —— 观察不改行为，Core 文件一字未动。
    //   DebugCore 与 JTAG Hub **完全位于 Core 之外**，只观察上面这些通用事件/状态，
    //   不引入任何设备专用端口，符合 §8 的 Core/SoC 边界。
    //
    // 显式声明（不写会得到 Verilog-2057 "declared implicitly" 警告）。
    wire ila_event_trap, ila_event_trap_return, ila_event_illegal;
    wire ila_event_misaligned, ila_event_bus_error, ila_event_ctrl_redirect;

    // 【探针布局】192 位，明细表见 fpga/timer_demo_ila/README.md
    //   [0] event_trap           Trap 进入脉冲        ← 触发点
    //   [1] event_trap_return    Trap 返回脉冲（mret）
    //   [2] event_illegal / [3] event_misaligned / [4] event_bus_error
    //   [5] event_control_redirect  [6] irq_timer  [7] perf_retire
    //   [39:8] ia 取指地址   [71:40] idata 取回指令
    //   [103:72] da 数据地址 [135:104] drd 数据读回
    //   [136..142] iv/ir/rv/rr/dv/dr/dw（各 1 位握手）
    //
    // 【为什么没有 mepc/mcause】——这是被工具链**硬性挡回来**的，记录在此免得重犯：
    //   最初想用层级引用 `core.csr.mepc_q` / `mcause_q` 观察 CSR，
    //   PDS(Logos) 直接报错拒绝：
    //       E: Verilog-4311: Reference to identifier 'mepc_q' of module instance 'csr' is not allowed.
    //   而把 mepc/mcause 引到 Core 端口又会**改变 pipeline_cpu.v 的端口表**，
    //   这是明确不允许的。
    //   因此诊断位流改为：用 Core **既有**的事件端口给出"Trap 进入/返回"本身，
    //   再用取指地址 `ia` 看"跳进陷入入口、返回后回到原 PC"作为佐证；
    //   mcause/mepc 的**数值**由固件自己的串口记录证明（N1 已有的 50 条中断记录）。
    wire [191:0] ila_probe = {
        49'b0,                      // [191:143] 保留
        dw,                         // [142] 数据写标志
        dr,                         // [141] 数据请求 ready
        dv,                         // [140] 数据请求 valid
        rr,                         // [139] 取指响应 ready
        rv,                         // [138] 取指响应 valid
        ir,                         // [137] 取指请求 ready
        iv,                         // [136] 取指请求 valid
        drd,                        // [135:104] 数据读回
        da,                         // [103:72]  数据地址
        idata,                      // [71:40]   取回指令
        ia,                         // [39:8]    取指地址（看得到跳进陷入入口）
        perf_retire,                // [7]       退休脉冲
        irq_timer,                  // [6]       定时器中断请求线
        ila_event_ctrl_redirect,    // [5]
        ila_event_bus_error,        // [4]
        ila_event_misaligned,       // [3]
        ila_event_illegal,          // [2]
        ila_event_trap_return,      // [1]       ← Trap 返回
        ila_event_trap              // [0]       ← Trap 进入（触发点）
    };

    // DebugCore + JTAG Hub：与 fpga/coremark_ila 复用**同一个 IP**
    // （单一 192 位探针 / 50 MHz 采样 / 512 采样深度），所以不需要重新生成 IP。
    wire        ila_drck, ila_tdi, ila_capt, ila_shift, ila_tdo;
    wire [14:0] ila_conf_sel, ila_hub_tdo;
    wire [4:0]  ila_id;
    assign ila_hub_tdo = {14'b0, ila_tdo};
    coremark_jtag_hub ila_hub(
        .resetn_i(!reset), .drck_o(ila_drck), .hub_tdi(ila_tdi),
        .capt_o(ila_capt), .shift_o(ila_shift), .conf_sel(ila_conf_sel),
        .id_o(ila_id), .hub_tdo(ila_hub_tdo));
    coremark_ila ila(
        .drck_in(ila_drck), .hub_tdi(ila_tdi), .id_i(ila_id),
        .capt_i(ila_capt), .shift_i(ila_shift), .conf_sel(ila_conf_sel[0]),
        .hub_tdo(ila_tdo), .clk(clk_50m), .trig0_i(ila_probe), .resetn_i(!reset));
`endif

endmodule
