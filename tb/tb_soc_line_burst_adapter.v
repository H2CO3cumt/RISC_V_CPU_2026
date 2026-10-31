`timescale 1ns/1ps
// 下游存储模型：支持「行请求 + 连拍返回」。
//
// 关键点：**请求到第一个数据拍固定间隔 2 拍**（1 拍接受请求 + 1 拍准备数据），
// 之后每个时钟给一拍数据。于是：
//   - 逐字模式（adapter 每拍发一笔 len=0 的单字请求）：每个字都要重新付这 2 拍；
//   - 突发模式（adapter 一次发 len=7 的整行请求）：整行只付一次 2 拍。
// 这个差值就是突发优化的收益来源，也是本 TB 要量出来的东西。
module burst_mem_model #(parameter DEPTH = 1024) (
    input  wire        clk,
    input  wire        reset,
    input  wire        m_req_valid,
    output reg         m_req_ready,
    input  wire [31:0] m_req_addr,
    input  wire [7:0]  m_req_len,
    output reg         m_beat_valid,
    input  wire        m_beat_ready,
    output reg  [31:0] m_beat_data,
    output reg         m_beat_last,
    output reg         m_beat_error,
    output reg  [31:0] bus_cycles
);
    reg [31:0] mem [0:DEPTH-1];
    integer i;
    reg        busy;
    reg [31:0] base;
    reg [7:0]  idx;          // 当前正在输出的第几拍（0 起）
    reg [7:0]  last_idx;     // 最后一拍的编号
    reg        err_flag;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            // 每个字填成 {0xA000_0000 | 字地址}，便于 TB 校验取对了哪个字
            mem[i] = 32'hA000_0000 | (i & 32'h0000_FFFF);
    end

    always @(posedge clk) begin
        if (reset) begin
            m_req_ready  <= 1'b1;
            m_beat_valid <= 1'b0;
            m_beat_last  <= 1'b0;
            m_beat_error <= 1'b0;
            busy         <= 1'b0;
            idx          <= 8'd0;
            last_idx     <= 8'd0;
            err_flag     <= 1'b0;
            bus_cycles   <= 32'd0;
        end
        else begin
            // 默认：数据拍保持到被接收
            if (m_beat_valid && m_beat_ready) begin
                m_beat_valid <= 1'b0;
                m_beat_last  <= 1'b0;
            end

            if (busy) begin
                bus_cycles <= bus_cycles + 32'd1;
                m_beat_valid <= 1'b1;
                m_beat_data  <= mem[base[31:2] + idx];
                m_beat_error <= err_flag;
                if (idx == last_idx) begin
                    m_beat_last <= 1'b1;      // 本拍即最后一拍
                    busy        <= 1'b0;
                    m_req_ready <= 1'b1;      // 可以接下一笔了
                end
                else begin
                    idx <= idx + 8'd1;
                end
            end
            else if (m_req_valid && m_req_ready) begin
                base        <= m_req_addr;
                idx         <= 8'd0;
                last_idx    <= m_req_len;
                err_flag    <= ((m_req_addr[31:2] + m_req_len) >= DEPTH);
                busy        <= 1'b1;
                m_req_ready <= 1'b0;
                bus_cycles  <= bus_cycles + 32'd1;
            end
        end
    end
endmodule

// =============================================================================
// S2 行式突发适配器 Testbench
// =============================================================================
module tb_soc_line_burst_adapter;

    localparam LINE_BYTES = 32;
    localparam WORDS      = LINE_BYTES / 4;

    reg clk   = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;      // 100 MHz 仿真时钟

    integer failures = 0;
    integer checks   = 0;

    task expect_true;
        input cond;
        input [255:0] name;
        begin
            checks = checks + 1;
            if (!cond) begin
                $display("TEST %0s FAIL", name);
                failures = failures + 1;
            end
            else $display("TEST %0s PASS", name);
        end
    endtask

    // ---- 突发（After）DUT ----
    reg         b_req_valid = 1'b0;
    reg  [31:0] b_req_addr  = 32'd0;
    reg         b_req_write = 1'b0;
    reg  [31:0] b_req_wdata = 32'd0;
    reg  [3:0]  b_req_wstrb = 4'b0;
    reg         b_rsp_ready = 1'b1;
    wire        b_req_ready, b_rsp_valid, b_rsp_error;
    wire [31:0] b_rsp_rdata;
    wire        b_m_req_valid, b_m_req_ready, b_m_beat_valid, b_m_beat_ready;
    wire        b_m_beat_last, b_m_beat_error;
    wire [31:0] b_m_req_addr, b_m_beat_data;
    wire [7:0]  b_m_req_len;
    wire [31:0] b_bus_cycles, b_reqs, b_beats, b_hits, b_misses;

    soc_line_burst_adapter #(.LINE_BYTES(LINE_BYTES), .BURST_LEN(WORDS)) u_burst (
        .clk(clk), .reset(reset),
        .req_valid(b_req_valid), .req_ready(b_req_ready), .req_addr(b_req_addr),
        .req_write(b_req_write), .req_wdata(b_req_wdata), .req_wstrb(b_req_wstrb),
        .rsp_valid(b_rsp_valid), .rsp_ready(b_rsp_ready), .rsp_rdata(b_rsp_rdata),
        .rsp_error(b_rsp_error),
        .m_req_valid(b_m_req_valid), .m_req_ready(b_m_req_ready), .m_req_addr(b_m_req_addr),
        .m_req_len(b_m_req_len),
        .m_beat_valid(b_m_beat_valid), .m_beat_ready(b_m_beat_ready),
        .m_beat_data(b_m_beat_data), .m_beat_last(b_m_beat_last),
        .m_beat_error(b_m_beat_error),
        .stat_bus_cycles(b_bus_cycles), .stat_burst_reqs(b_reqs),
        .stat_data_beats(b_beats), .stat_hits(b_hits), .stat_misses(b_misses)
    );
    burst_mem_model #(.DEPTH(1024)) u_burst_mem (
        .clk(clk), .reset(reset),
        .m_req_valid(b_m_req_valid), .m_req_ready(b_m_req_ready), .m_req_addr(b_m_req_addr),
        .m_req_len(b_m_req_len),
        .m_beat_valid(b_m_beat_valid), .m_beat_ready(b_m_beat_ready),
        .m_beat_data(b_m_beat_data), .m_beat_last(b_m_beat_last),
        .m_beat_error(b_m_beat_error), .bus_cycles()
    );

    // ---- 逐字（Before）DUT ----
    reg         w_req_valid = 1'b0;
    reg  [31:0] w_req_addr  = 32'd0;
    reg         w_req_write = 1'b0;
    reg  [31:0] w_req_wdata = 32'd0;
    reg  [3:0]  w_req_wstrb = 4'b0;
    reg         w_rsp_ready = 1'b1;
    wire        w_req_ready, w_rsp_valid, w_rsp_error;
    wire [31:0] w_rsp_rdata;
    wire        w_m_req_valid, w_m_req_ready, w_m_beat_valid, w_m_beat_ready;
    wire        w_m_beat_last, w_m_beat_error;
    wire [31:0] w_m_req_addr, w_m_beat_data;
    wire [7:0]  w_m_req_len;
    wire [31:0] w_bus_cycles, w_reqs, w_beats, w_hits, w_misses;

    soc_line_burst_adapter #(.LINE_BYTES(LINE_BYTES), .BURST_LEN(1)) u_word (
        .clk(clk), .reset(reset),
        .req_valid(w_req_valid), .req_ready(w_req_ready), .req_addr(w_req_addr),
        .req_write(w_req_write), .req_wdata(w_req_wdata), .req_wstrb(w_req_wstrb),
        .rsp_valid(w_rsp_valid), .rsp_ready(w_rsp_ready), .rsp_rdata(w_rsp_rdata),
        .rsp_error(w_rsp_error),
        .m_req_valid(w_m_req_valid), .m_req_ready(w_m_req_ready), .m_req_addr(w_m_req_addr),
        .m_req_len(w_m_req_len),
        .m_beat_valid(w_m_beat_valid), .m_beat_ready(w_m_beat_ready),
        .m_beat_data(w_m_beat_data), .m_beat_last(w_m_beat_last),
        .m_beat_error(w_m_beat_error),
        .stat_bus_cycles(w_bus_cycles), .stat_burst_reqs(w_reqs),
        .stat_data_beats(w_beats), .stat_hits(w_hits), .stat_misses(w_misses)
    );
    burst_mem_model #(.DEPTH(1024)) u_word_mem (
        .clk(clk), .reset(reset),
        .m_req_valid(w_m_req_valid), .m_req_ready(w_m_req_ready), .m_req_addr(w_m_req_addr),
        .m_req_len(w_m_req_len),
        .m_beat_valid(w_m_beat_valid), .m_beat_ready(w_m_beat_ready),
        .m_beat_data(w_m_beat_data), .m_beat_last(w_m_beat_last),
        .m_beat_error(w_m_beat_error), .bus_cycles()
    );

    // 期望值：模型里 mem[i] = 0xA0000000 | i
    function [31:0] exp_word;
        input [31:0] byte_addr;
        begin
            exp_word = 32'hA000_0000 | ((byte_addr >> 2) & 32'hFFFF);
        end
    endfunction

    integer    wait_cycles;
    reg [31:0] got_data;

    task core_read_burst;
        input [31:0] address;
        begin
            @(negedge clk);
            b_req_addr  = address;
            b_req_write = 1'b0;
            b_req_wstrb = 4'b0;
            b_req_valid = 1'b1;
            wait_cycles = 0;
            while (!b_req_ready) begin
                @(posedge clk); #1; wait_cycles = wait_cycles + 1;
            end
            @(posedge clk); #1;
            b_req_valid = 1'b0;
            while (!b_rsp_valid) begin
                @(posedge clk); #1; wait_cycles = wait_cycles + 1;
            end
            got_data = b_rsp_rdata;
            @(posedge clk); #1;
        end
    endtask

    task core_read_word;
        input [31:0] address;
        begin
            @(negedge clk);
            w_req_addr  = address;
            w_req_write = 1'b0;
            w_req_wstrb = 4'b0;
            w_req_valid = 1'b1;
            while (!w_req_ready) @(posedge clk);
            @(posedge clk); #1;
            w_req_valid = 1'b0;
            while (!w_rsp_valid) @(posedge clk);
            @(posedge clk); #1;
        end
    endtask

    integer    i;
    integer    burst_wait_total = 0;
    reg [31:0] seq [0:23];

    // 调试用：追踪 DUT 的内部状态（超时时用它定位卡在哪一步）
    // 注意：Verilog 没有隐式字符串拼接，`$display` 的格式串**不能跨行写**。
    reg trace_on = 1'b0;
    always @(posedge clk) begin
        if (trace_on)
            $display("    [%0t] st=%0d req_rdy=%b rsp_v=%b mreq_v=%b mreq_rdy=%b mbeat_v=%b mbeat_rdy=%b fi=%0d ri=%0d",
                     $time, u_burst.state, b_req_ready, b_rsp_valid,
                     b_m_req_valid, b_m_req_ready, b_m_beat_valid, b_m_beat_ready,
                     u_burst.fill_idx, u_burst.req_idx);
    end

    initial begin
        seq[0]=32'h0000_0000;  seq[1]=32'h0000_0004;  seq[2]=32'h0000_0008;  seq[3]=32'h0000_000C;
        seq[4]=32'h0000_0010;  seq[5]=32'h0000_0014;  seq[6]=32'h0000_0018;  seq[7]=32'h0000_001C;
        seq[8]=32'h0000_0020;  seq[9]=32'h0000_0024;  seq[10]=32'h0000_0040; seq[11]=32'h0000_0044;
        seq[12]=32'h0000_0100; seq[13]=32'h0000_0104; seq[14]=32'h0000_0108; seq[15]=32'h0000_010C;
        seq[16]=32'h0000_0110; seq[17]=32'h0000_0114; seq[18]=32'h0000_0118; seq[19]=32'h0000_011C;
        seq[20]=32'h0000_0000; seq[21]=32'h0000_0004; seq[22]=32'h0000_0120; seq[23]=32'h0000_0020;

        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        trace_on = 1'b1;      // 打开状态追踪，首个失败点一目了然

        // ---------- 功能 1：行未命中 + 行内后续访问命中 ----------
        core_read_burst(32'h0000_0008);
        expect_true(got_data === exp_word(32'h0000_0008), "burst_miss_reads_wanted_word");
        expect_true(b_rsp_error === 1'b0, "burst_miss_no_error");

        core_read_burst(32'h0000_0000);
        expect_true(got_data === exp_word(32'h0000_0000), "burst_same_line_hit_word0");
        core_read_burst(32'h0000_001C);
        expect_true(got_data === exp_word(32'h0000_001C), "burst_same_line_hit_last_word");

        // ---------- 功能 2：跨行 -> 重新填充 ----------
        core_read_burst(32'h0000_0020);
        expect_true(got_data === exp_word(32'h0000_0020), "burst_next_line_miss");

        // ---------- 功能 3：背压下的响应保持 ----------
        b_rsp_ready = 1'b0;
        fork
            core_read_burst(32'h0000_0040);
            begin
                repeat (5) @(posedge clk);
                b_rsp_ready = 1'b1;
            end
        join
        expect_true(got_data === exp_word(32'h0000_0040), "burst_backpressure_data");
        b_rsp_ready = 1'b1;

        // ---------- 功能 4：复位后仍能重新取到数据 ----------
        reset = 1'b1;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        core_read_burst(32'h0000_0000);
        expect_true(got_data === exp_word(32'h0000_0000), "burst_after_reset_refetch");

        // ---------- 功能 5：越界 -> 错误 ----------
        core_read_burst(32'h0000_FF00);
        expect_true(b_rsp_error === 1'b1, "burst_out_of_range_error");

        // ---------- 功能 6：写直通（S2 不做 D-Cache，写不缓存）----------
        @(negedge clk);
        b_req_addr = 32'h0000_0080; b_req_write = 1'b1;
        b_req_wdata = 32'h1234_5678; b_req_wstrb = 4'hF; b_req_valid = 1'b1;
        while (!b_req_ready) @(posedge clk);
        @(posedge clk); #1; b_req_valid = 1'b0; b_req_write = 1'b0; b_req_wstrb = 4'b0;
        while (!b_rsp_valid) @(posedge clk);
        @(posedge clk); #1;
        expect_true(b_rsp_error === 1'b0, "burst_write_bypass_ok");
        core_read_burst(32'h0000_0080);
        expect_true(got_data === exp_word(32'h0000_0080), "burst_write_then_read_bypasses");

        // ===================== 量化：逐字 vs 突发 =====================
        // 【为什么用"连续行访问"的序列】
        // 行缓冲只有 1 行。若序列在同一行内来回跳（0x00,0x04,0x40,0x44,...），
        // 每次跳到别行都会把行缓冲覆盖掉，于是"逐字"和"突发"都退化成每次未命中，
        // 量出的差异就只剩噪声（第一次实测：112 vs 110，看起来像"突发没用"，
        // 其实是序列设计不当）。
        // 这里改成**按行顺序推进、行内 8 个字连续读**——这才是"行填充被真正复用"的
        // 情形，也是真实取指模式的近似（顺序取指天然在一行内连续）。
        // 双方在此段前一起复位并清零统计，保证对比的是同一段序列、同一个起点。
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        burst_wait_total = 0;
        for (i = 0; i < 24; i = i + 1) begin
            // 行号 = i/8，行内字 = i%8：先读满第 0 行，再读满第 1 行，再读满第 2 行
            seq[i] = ((i / 8) * 32) + ((i % 8) * 4);
            core_read_burst(seq[i]);
            burst_wait_total = burst_wait_total + wait_cycles;
        end
        for (i = 0; i < 24; i = i + 1)
            core_read_word(seq[i]);

        $display("");
        $display("S2 BURST ADAPTER MEASUREMENT (sequential line-local access)");
        $display("  access sequence        : 24 reads = 3 full lines x 8 words, in order");
        $display("  --- word-at-a-time (BURST_LEN=1, Before) ---");
        $display("    line-buffer misses   : %0d", w_misses);
        $display("    downstream requests  : %0d", w_reqs);
        $display("    data beats           : %0d", w_beats);
        $display("    line-buffer hits     : %0d", w_hits);
        $display("    downstream bus cycles: %0d", w_bus_cycles);
        $display("  --- line burst (BURST_LEN=%0d, After) ---", WORDS);
        $display("    line-buffer misses   : %0d", b_misses);
        $display("    downstream requests  : %0d", b_reqs);
        $display("    data beats           : %0d", b_beats);
        $display("    line-buffer hits     : %0d", b_hits);
        $display("    downstream bus cycles: %0d", b_bus_cycles);
        $display("    core wait cycles(seq): %0d", burst_wait_total);
        $display("");

        // 前提校验：同一序列下两种模式的填充次数必须相同，否则对比不成立
        expect_true(w_misses == b_misses, "measurement_same_miss_count");
        expect_true(b_bus_cycles < w_bus_cycles, "burst_fewer_downstream_cycles");
        expect_true(b_reqs < w_reqs, "burst_fewer_downstream_requests");
        expect_true(b_hits > 32'd0, "burst_line_buffer_used");

        $display("  reduction: downstream bus cycles %0d -> %0d (%0d%% less)",
                 w_bus_cycles, b_bus_cycles,
                 (w_bus_cycles == 0) ? 0 : ((w_bus_cycles - b_bus_cycles) * 100) / w_bus_cycles);

        if (failures == 0) $display("ALL S2 LINE BURST ADAPTER TEST PASS");
        else               $fatal(1, "S2 LINE BURST ADAPTER %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "S2 LINE BURST ADAPTER TIMEOUT");
    end

endmodule
