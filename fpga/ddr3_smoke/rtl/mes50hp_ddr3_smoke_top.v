// MES50HP 板级 DDR3 冒烟测试顶层（S1）。
//
// 设计意图：
//   厂商的 `test_ddr`（HMIC_S 自带例程）是**板卡无关**的，它的 `ref_clk`/`free_clk`/
//   `uart_txd` 等端口需要由板级 wrapper 绑到本板真实管脚上。本文件就是那层 wrapper。
//
//   为什么另起一个顶层、而不改厂商的 `test_ddr.v`：
//     1. 厂商代码里 UART 波特率分频写的是 `CLK_DIV_P = 16'd72`，而它自己头部的
//        `TH_1S = 27'd50_000_000` 说明原设计就是按 50 MHz 写的；72 分频只能得到
//        约 694 kbaud，与注释 "115200bps for 50MHz clk" 自相矛盾。
//        本 wrapper 用 **434**（50_000_000 / 115200 = 434.03，误差 0.007%），
//        并且**不改厂商源文件**，只在例化时覆盖参数。
//     2. 管脚必须按 MES50HP 手册接线（厂商自带的 `50h_ddr3_fbg484_b3_x32.fdc`
//        有 65/69 个管脚与本板不符，**绝不能**用）。
//
// 安全边界：本工程独立于 `fpga/logic_analyzer`、`fpga/coremark`、`fpga/coremark_80m`、
// `fpga/timer_demo`，且 DDR3 只接 Bank 3（1.5 V），不与那些工程的 3.3 V 约束混用。
module mes50hp_ddr3_smoke_top (
    input  wire clk_50m,        // P20：板上 50 MHz（DDR3 的 ref_clk / free_clk 都用它）
    input  wire uart0_rx,       // R8：板载 CP2102 RX
    output wire uart0_tx,       // R9：板载 CP2102 TX
    output wire [7:0] led,      // B2..F8：用户 LED（高电平点亮）

    // ---- DDR3（Bank 3，1.5 V SSTL15）----
    output wire        mem_rst_n,
    output wire        mem_ck,
    output wire        mem_ck_n,
    output wire        mem_cke,
    output wire        mem_cs_n,
    output wire        mem_ras_n,
    output wire        mem_cas_n,
    output wire        mem_we_n,
    output wire        mem_odt,
    output wire [14:0] mem_a,
    output wire [2:0]  mem_ba,
    inout  wire [31:0] mem_dq,
    inout  wire [3:0]  mem_dqs,
    inout  wire [3:0]  mem_dqs_n,
    output wire [3:0]  mem_dm
);

    // ---------------------------------------------------------------- 复位
    // 内部上电复位（与项目其它工程一致：不用底板 REST，它只用于重新加载固件）。
    // 256 拍后释放，保证 DDR PHY 的 PLL 与时钟稳定后再开始初始化。
    reg [7:0] por_count = 8'd0;
    reg       por_rstn  = 1'b0;
    always @(posedge clk_50m) begin
        if (!por_rstn) begin
            por_count <= por_count + 1'b1;
            if (&por_count) por_rstn <= 1'b1;
        end
    end

    wire pll_lock;
    wire ddr_init_done;
    wire heart_beat_led;
    wire err_flag_led;

    // ------------------------------------------------- 厂商 DDR3 冒烟例程
    // 两处必须改厂商文件的地方（都由 scripts/ddr3_reapply_vendor_patches.py 幂等重打，
    // 因为 `ip_generate` 会整体重写 example_design/）：
    //   1) UART 分频 CLK_DIV_P: 16'd72 -> 16'd434（50 MHz 下才是 115200 baud）；
    //   2) `free_clk` 输入端口 -> 模块内 `assign free_clk = ref_clk;`
    //      （官方例程 07_ddr3_test 就是这么写的；留成两个端口会让时序分析
    //        多出一个时钟域，实测 232 个端点 hold 违例）。
    // 因此这里**不再**连 `.free_clk(...)`。
    test_ddr u_dut (
        .ref_clk        (clk_50m),       // P20 同时作 DDR3 参考时钟与例程逻辑时钟
        .rst_board      (por_rstn),
        .pll_lock       (pll_lock),
        .ddr_init_done  (ddr_init_done),
        .uart_rxd       (uart0_rx),
        .uart_txd       (uart0_tx),
        .mem_rst_n      (mem_rst_n),
        .mem_ck         (mem_ck),
        .mem_ck_n       (mem_ck_n),
        .mem_cke        (mem_cke),
        .mem_cs_n       (mem_cs_n),
        .mem_ras_n      (mem_ras_n),
        .mem_cas_n      (mem_cas_n),
        .mem_we_n       (mem_we_n),
        .mem_odt        (mem_odt),
        .mem_a          (mem_a),
        .mem_ba         (mem_ba),
        .mem_dq         (mem_dq),
        .mem_dqs        (mem_dqs),
        .mem_dqs_n      (mem_dqs_n),
        .mem_dm         (mem_dm),
        .heart_beat_led (heart_beat_led),
        .err_flag_led   (err_flag_led)
    );

    // ---------------------------------------------------------------- LED
    // 用板级状态做**不依赖串口**的可视证据（串口万一读不出来，看灯也能判断）：
    //   led[0] = PLL 锁定          常亮表示 DDR PHY 的 PLL 锁上
    //   led[1] = DDR 初始化完成    常亮表示 PHY 训练结束、进入正常工作
    //   led[2] = 例程心跳          闪烁
    //   led[3] = 例程错误标志      亮 = BIST 比对出错
    //   led[7:4] 保留为 0
    assign led = {4'b0000, err_flag_led, heart_beat_led, ddr_init_done, pll_lock};

endmodule
