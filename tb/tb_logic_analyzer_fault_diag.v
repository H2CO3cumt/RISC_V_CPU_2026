`timescale 1ns/1ps
// A6 故障诊断演示：可控故障注入 + 采集 + 与真值自动比较。
//
// 被测对象是**现有的** Capture Engine（rtl/capture_engine.v），不是新造的简化模型：
//   * 通道源 = 8 位自由计数器，完全确定，因此"真值"可以在同一个 Testbench 里边采边记；
//   * 故障注入 = 在第 INJ_TICK 个采样点把 INJ_MASK 指定的通道位翻转**一拍**
//     （INJ_TICK<0 表示不注入，作为基线场景）；
//   * 触发条件 = 电平触发 channels==0x40，pre=8、post=8，
//     因此采样窗口是被触发点前后各 8 个样本固定住的、可复现的。
//
// 本 Testbench 只负责"产生日志"：把真值流（CLEAN）、引擎实际看到的流（SEEN）
// 和引擎读出的 Raw 流（CAP）落盘，判定交给 python/logic_analyzer_fault_diag.py。
// 这样"采集/定位/复现"三步都有自动判据，而不是靠肉眼看波形。
//
// 宏入口（脚本用 -D 传入，与项目其它 Testbench 一致；-P 的字符串参数在本机会被 shell 吞掉）：
//   TB_FD_TAG        场景名
//   TB_FD_INJ_TICK   注入发生在第几个采样点（-1 = 不注入）
//   TB_FD_INJ_MASK   注入翻转哪些通道位
module tb_logic_analyzer_fault_diag;

// 场景编号用**整数**而不是字符串：Verilog 的 %s 打印定宽向量会把填充的 NUL 一起写进
// 日志，解析方要额外处理；编号由判定器映射成名字，日志保持纯 ASCII 文本。
`ifdef TB_FD_SCEN
    localparam integer SCEN = `TB_FD_SCEN;
`else
    localparam integer SCEN = 3;
`endif
`ifdef TB_FD_INJ_TICK
    localparam integer INJ_TICK = `TB_FD_INJ_TICK;
`else
    localparam integer INJ_TICK = -1;
`endif
`ifdef TB_FD_INJ_MASK
    localparam [7:0] INJ_MASK = `TB_FD_INJ_MASK;
`else
    localparam [7:0] INJ_MASK = 8'h00;
`endif

    localparam integer MAXTICK = 512;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg  [7:0]  gen = 8'h00;      // 确定性通道源
    integer     tick = 0;         // 采样点序号
    reg  [7:0]  clean [0:MAXTICK-1];   // 真值：没有注入时引擎应该看到的
    reg  [7:0]  seen  [0:MAXTICK-1];   // 引擎实际看到的（含注入）

    // 注入只持续一拍：恰好是第 INJ_TICK 个采样点。
    wire [7:0] inj = (INJ_TICK >= 0 && tick == INJ_TICK) ? INJ_MASK : 8'h00;
    wire [7:0] channel_src = gen ^ inj;

    // ---- Capture Engine 控制 ----
    reg         arm = 1'b0, stop = 1'b0, clear = 1'b0;
    wire        armed, triggered, done, overflow;
    wire [15:0] trigger_index, capture_count;
    wire [7:0]  read_data;
    reg  [15:0] read_index = 16'd0;

    capture_engine #(.CHANNELS(8), .DEPTH(256)) ce(
        .clk(clk), .reset(reset), .channels(channel_src),
        .arm(arm), .stop(stop), .clear(clear),
        .sample_div(16'd0), .channel_mask(8'hFF),
        .trigger_mask(8'hFF), .trigger_value(8'h40),
        .trigger_rise(8'h00), .trigger_fall(8'h00),
        .pre_count(16'd8), .post_count(16'd8),
        .read_index(read_index), .read_data(read_data),
        .armed(armed), .triggered(triggered), .done(done), .overflow(overflow),
        .trigger_index(trigger_index), .capture_count(capture_count));

    always #5 clk = ~clk;

    integer logfd;
    // trig_tick = 触发样本所在的采样点序号；导出窗口的起点是 trig_tick - trigger_index。
    // 不能用"引擎第一次存样本的那拍"当窗口起点：引擎在触发之前就已经在存 pre 样本，
    // 触发之后才把 start_index 重新基准化到"最老的那个 pre 样本"。
    integer trig_tick = -1;
    integer window_first = -1;
    integer i;
    // 采样点记录：sample_div=0，因此每个时钟沿都是一个采样点。
    // 用阻塞赋值读 gen / channel_src，读到的正是本拍引擎看到的那一份值。
    always @(posedge clk) if (!reset && tick < MAXTICK) begin
        clean[tick] = gen;
        seen[tick]  = channel_src;
        // 触发条件与引擎一致（电平 channels==0x40）：记录它落在哪个采样点。
        if (trig_tick < 0 && channel_src == 8'h40)
            trig_tick = tick;
        tick = tick + 1;
        gen  = gen + 8'd1;
    end

    initial begin
        logfd = $fopen("tmp/logic_analyzer_fault_diag/capture.log", "w");
        if (logfd == 0) begin
            $display("FAULT DIAG LOG OPEN FAIL");
            $fatal(1);
        end
        $fwrite(logfd, "CFG %0d %0d %02h\n", SCEN, INJ_TICK, INJ_MASK);

        repeat (4) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);
        arm = 1'b1;
        @(negedge clk);
        arm = 1'b0;

        // 等到引擎采完（触发 + post 结束）或超时
        i = 0;
        while (!done && i < 200) begin @(negedge clk); i = i + 1; end
        if (!done) begin
            $display("FAULT DIAG TIMEOUT scen=%0d", SCEN);
            $fatal(1);
        end

        window_first = (trig_tick >= 0) ? (trig_tick - trigger_index) : 0;
        $fwrite(logfd, "INFO %0d %0d %0d %0d %0d\n",
                window_first, trigger_index, capture_count, overflow, tick);

        // 把引擎读出的 Raw 流整段倒出来；read_data 是组合读，逐拍扫 read_index 即可。
        for (i = 0; i < capture_count; i = i + 1) begin
            read_index = i[15:0];
            @(negedge clk);
            $fwrite(logfd, "CAP %0d %02h\n", i, read_data);
        end

        // 真值与"引擎看到的"两条流：窗口内的部分才参与比较。
        for (i = 0; i < capture_count; i = i + 1) begin
            if ((window_first + i) >= 0 && (window_first + i) < MAXTICK) begin
                $fwrite(logfd, "CLEAN %0d %02h\n", i, clean[window_first + i]);
                $fwrite(logfd, "SEEN %0d %02h\n", i, seen[window_first + i]);
            end
        end

        $fclose(logfd);
        $display("FAULT DIAG LOG DONE scen=%0d inj_tick=%0d cap=%0d trig=%0d",
                 SCEN, INJ_TICK, capture_count, trigger_index);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "FAULT DIAG HARD TIMEOUT scen=%0d", SCEN);
    end

endmodule
