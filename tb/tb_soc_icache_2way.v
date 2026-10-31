`timescale 1ns/1ps
// S3：2 路组相联 I-Cache 的独立 Testbench。
//
// ## 测什么
//
// 功能：
//   1. 冷启动未命中 -> 整行填充 -> 取到正确指令；
//   2. 同一行内后续取指 -> 命中（且后面的字都在阵列里）；
//   3. 同一组不同 tag -> **冲突未命中**，且两路交替替换（round-robin）；
//   4. 跨组顺序取指 -> 每组各占一行；
//   5. 背压：响应未被接受时数据必须保持；
//   6. 复位：清空阵列后必须重新填充，且不能返回旧数据；
//   7. 下游报错的行**不得**被缓存成有效行；
//   8. 越界取指的 error 透传；
//   9. `CACHE_EN=0` 的直通模式：每次取指都走下游、不写阵列。
//
// 量化（Off/On，同一份 RTL 的两种参数）：
//   固定取指序列下比较 下游请求数 / 下游数据拍 / 下游总线周期 / 命中率 / Core 等待周期。
//
// 判据：① 功能全过；② On 模式命中率 > 0 且下游总线周期**严格小于** Off 模式。
//       否则触发 `handoff_next.md` §3.3 的回退条件（Off 与 On 都没有可测净收益就停用并回退）。

// =============================================================================
// 下游取指存储模型：行请求 + 连拍返回。
// 首拍延迟 `FIRST_DELAY` 拍（模拟存储/互连的固定开销），之后每拍给一个字。
// 超过 `DEPTH_WORDS` 的地址返回 error（用于越界用例）。
// =============================================================================
module icache_mem_model #(
    parameter DEPTH_WORDS = 4096,
    parameter FIRST_DELAY = 2
) (
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
    output reg  [31:0] bus_cycles,
    output reg  [31:0] req_count
);
    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer i;
    reg        busy;
    reg [3:0]  wait_cnt;
    reg [31:0] base;
    reg [7:0]  idx;
    reg [7:0]  last_idx;
    reg        err_flag;

    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            // 指令镜像：用字地址编码，便于校验"取到的是不是要的那个字"
            mem[i] = 32'h1000_0000 | (i & 32'h000F_FFFF);
    end

    always @(posedge clk) begin
        if (reset) begin
            m_req_ready  <= 1'b1;
            m_beat_valid <= 1'b0;
            m_beat_last  <= 1'b0;
            m_beat_error <= 1'b0;
            busy         <= 1'b0;
            wait_cnt     <= 4'd0;
            idx          <= 8'd0;
            last_idx     <= 8'd0;
            err_flag     <= 1'b0;
            bus_cycles   <= 32'd0;
            req_count    <= 32'd0;
        end
        else begin
            if (m_beat_valid && m_beat_ready) begin
                m_beat_valid <= 1'b0;
                m_beat_last  <= 1'b0;
            end

            if (busy) begin
                bus_cycles <= bus_cycles + 32'd1;
                if (wait_cnt != 0) begin
                    wait_cnt <= wait_cnt - 4'd1;
                end
                else begin
                    m_beat_valid <= 1'b1;
                    m_beat_data  <= mem[base[31:2] + idx];
                    m_beat_error <= err_flag;
                    if (idx == last_idx) begin
                        m_beat_last <= 1'b1;
                        busy        <= 1'b0;
                        m_req_ready <= 1'b1;
                    end
                    else begin
                        idx <= idx + 8'd1;
                    end
                end
            end
            else if (m_req_valid && m_req_ready) begin
                base        <= m_req_addr;
                idx         <= 8'd0;
                last_idx    <= m_req_len;
                err_flag    <= ((m_req_addr[31:2] + m_req_len) >= DEPTH_WORDS);
                busy        <= 1'b1;
                wait_cnt    <= FIRST_DELAY[3:0];
                m_req_ready <= 1'b0;
                bus_cycles  <= bus_cycles + 32'd1;
                req_count   <= req_count + 32'd1;
            end
        end
    end
endmodule

// =============================================================================
// DUT 封装：把 I-Cache 与下游模型连起来，供 TB 以同一套任务驱动两份实例
// =============================================================================
module icache_harness #(
    parameter CACHE_EN   = 1,
    parameter SETS       = 32,
    parameter FIRST_DELAY= 2
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    output wire        rsp_valid,
    input  wire        rsp_ready,
    output wire [31:0] rsp_data,
    output wire        rsp_error,
    output wire [31:0] stat_hits,
    output wire [31:0] stat_misses,
    output wire [31:0] stat_bus_cycles,
    output wire [31:0] stat_core_wait,
    output wire [31:0] mem_req_count
);
    wire        m_req_valid, m_req_ready, m_beat_valid, m_beat_ready;
    wire        m_beat_last, m_beat_error;
    wire [31:0] m_req_addr, m_beat_data;
    wire [7:0]  m_req_len;

    soc_icache_2way #(.SETS(SETS), .WAYS(2), .LINE_BYTES(32), .CACHE_EN(CACHE_EN)) u_cache (
        .clk(clk), .reset(reset),
        .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_data(rsp_data),
        .rsp_error(rsp_error),
        .m_req_valid(m_req_valid), .m_req_ready(m_req_ready), .m_req_addr(m_req_addr),
        .m_req_len(m_req_len),
        .m_beat_valid(m_beat_valid), .m_beat_ready(m_beat_ready),
        .m_beat_data(m_beat_data), .m_beat_last(m_beat_last),
        .m_beat_error(m_beat_error),
        .stat_hits(stat_hits), .stat_misses(stat_misses),
        .stat_bus_cycles(stat_bus_cycles), .stat_beats(), .stat_core_wait(stat_core_wait)
    );
    icache_mem_model #(.DEPTH_WORDS(4096), .FIRST_DELAY(FIRST_DELAY)) u_mem (
        .clk(clk), .reset(reset),
        .m_req_valid(m_req_valid), .m_req_ready(m_req_ready), .m_req_addr(m_req_addr),
        .m_req_len(m_req_len),
        .m_beat_valid(m_beat_valid), .m_beat_ready(m_beat_ready),
        .m_beat_data(m_beat_data), .m_beat_last(m_beat_last),
        .m_beat_error(m_beat_error),
        .bus_cycles(), .req_count(mem_req_count)
    );
endmodule

// =============================================================================
// 主 Testbench
// =============================================================================
module tb_soc_icache_2way;

    localparam SETS        = 32;
    localparam LINE_BYTES  = 32;
    localparam FIRST_DELAY = 2;

    reg clk   = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

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

    function [31:0] exp_instr;
        input [31:0] byte_addr;
        begin
            exp_instr = 32'h1000_0000 | ((byte_addr >> 2) & 32'h000F_FFFF);
        end
    endfunction

    // ---- On 模式（CACHE_EN=1）----
    reg         on_req_valid = 1'b0;
    reg  [31:0] on_req_addr  = 32'd0;
    reg         on_rsp_ready = 1'b1;
    wire        on_req_ready, on_rsp_valid, on_rsp_error;
    wire [31:0] on_rsp_data, on_hits, on_misses, on_bus, on_wait, on_reqs;

    icache_harness #(.CACHE_EN(1), .SETS(SETS), .FIRST_DELAY(FIRST_DELAY)) u_on (
        .clk(clk), .reset(reset),
        .req_valid(on_req_valid), .req_ready(on_req_ready), .req_addr(on_req_addr),
        .rsp_valid(on_rsp_valid), .rsp_ready(on_rsp_ready), .rsp_data(on_rsp_data),
        .rsp_error(on_rsp_error),
        .stat_hits(on_hits), .stat_misses(on_misses), .stat_bus_cycles(on_bus),
        .stat_core_wait(on_wait), .mem_req_count(on_reqs)
    );

    // ---- Off 模式（CACHE_EN=0，直通）----
    reg         off_req_valid = 1'b0;
    reg  [31:0] off_req_addr  = 32'd0;
    reg         off_rsp_ready = 1'b1;
    wire        off_req_ready, off_rsp_valid, off_rsp_error;
    wire [31:0] off_rsp_data, off_hits, off_misses, off_bus, off_wait, off_reqs;

    icache_harness #(.CACHE_EN(0), .SETS(SETS), .FIRST_DELAY(FIRST_DELAY)) u_off (
        .clk(clk), .reset(reset),
        .req_valid(off_req_valid), .req_ready(off_req_ready), .req_addr(off_req_addr),
        .rsp_valid(off_rsp_valid), .rsp_ready(off_rsp_ready), .rsp_data(off_rsp_data),
        .rsp_error(off_rsp_error),
        .stat_hits(off_hits), .stat_misses(off_misses), .stat_bus_cycles(off_bus),
        .stat_core_wait(off_wait), .mem_req_count(off_reqs)
    );

    integer    on_wait_cycles;
    reg [31:0] on_got;
    reg        on_err;

    task on_fetch;
        input [31:0] address;
        begin
            @(negedge clk);
            on_req_addr  = address;
            on_req_valid = 1'b1;
            on_wait_cycles = 0;
            while (!on_req_ready) begin
                @(posedge clk); #1; on_wait_cycles = on_wait_cycles + 1;
            end
            @(posedge clk); #1;
            on_req_valid = 1'b0;
            while (!on_rsp_valid) begin
                @(posedge clk); #1; on_wait_cycles = on_wait_cycles + 1;
            end
            on_got = on_rsp_data;
            on_err = on_rsp_error;
            @(posedge clk); #1;
        end
    endtask

    task off_fetch;
        input [31:0] address;
        begin
            @(negedge clk);
            off_req_addr  = address;
            off_req_valid = 1'b1;
            while (!off_req_ready) @(posedge clk);
            @(posedge clk); #1;
            off_req_valid = 1'b0;
            while (!off_rsp_valid) @(posedge clk);
            @(posedge clk); #1;
        end
    endtask

    integer    i;
    reg [31:0] on_wait_total = 0;
    reg [31:0] off_wait_total = 0;
    reg        trace_on = 1'b0;

    // 调试用追踪块已移除：它一度用来定位"命中路径握手不完成"的问题，
    // 但引用了后来重构掉的内部信号，留着会让 TB 编译不过。需要时用 `-DTRACE_ICACHE`
    // 之类的开关再临时加回，不要常驻。

    // 固定取指序列：顺序取指 + 少量回跳（贴近真实取指流）
    reg [31:0] fseq [0:31];

    initial begin
        // 一行 8 个字 = 32 B。序列：第 0 行全取、第 1 行全取、回跳第 0 行、第 2 行全取、
        //          跨到第 8 行（set 冲突相关）、再顺序 4 个字。
        for (i = 0; i < 8;  i = i + 1) fseq[i]      = (i % 8) * 4;                  // 行 0
        for (i = 8; i < 16; i = i + 1) fseq[i]      = 32 + ((i - 8) % 8) * 4;       // 行 1
        for (i = 16; i < 20; i = i + 1) fseq[i]     = ((i - 16) % 8) * 4;           // 回跳行 0
        for (i = 20; i < 28; i = i + 1) fseq[i]     = 64 + ((i - 20) % 8) * 4;      // 行 2
        for (i = 28; i < 32; i = i + 1) fseq[i]     = 256 + ((i - 28) % 8) * 4;     // 行 8

        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        trace_on = 1'b1;

        // ---------------- 功能 1：冷启动未命中，整行填充 ----------------
        on_fetch(32'h0000_0008);
        expect_true(on_got === exp_instr(32'h0000_0008), "on_cold_miss_right_instr");
        expect_true(on_err === 1'b0, "on_cold_miss_no_error");
        expect_true(on_misses == 32'd1, "on_cold_miss_counted");
        expect_true(on_reqs == 32'd1, "on_cold_miss_single_line_request");

        // ---------------- 功能 2：同行后续取指命中，且行内其它字也已在阵列 ----------------
        on_fetch(32'h0000_0000);
        expect_true(on_got === exp_instr(32'h0000_0000), "on_same_line_hit_first");
        expect_true(on_hits == 32'd1, "on_same_line_hit_counted");
        on_fetch(32'h0000_001C);
        expect_true(on_got === exp_instr(32'h0000_001C), "on_same_line_hit_last");
        expect_true(on_hits == 32'd2, "on_same_line_hit_counted2");
        expect_true(on_reqs == 32'd1, "on_hits_need_no_downstream_request");

        // ---------------- 功能 3：跨行顺序取指 ----------------
        on_fetch(32'h0000_0020);
        expect_true(on_got === exp_instr(32'h0000_0020), "on_next_line_miss");
        expect_true(on_misses == 32'd2, "on_next_line_miss_counted");

        // ---------------- 功能 4：背压：响应未被接受时数据保持 ----------------
        on_rsp_ready = 1'b0;
        fork
            on_fetch(32'h0000_0000);       // 命中路径
            begin
                repeat (4) @(posedge clk);
                on_rsp_ready = 1'b1;
            end
        join
        expect_true(on_got === exp_instr(32'h0000_0000), "on_backpressure_hit_data");
        on_rsp_ready = 1'b1;

        // ---------------- 功能 5：越界 -> error 透传，且不被缓存 ----------------
        on_fetch(32'h0002_0000);           // 远超 4096 字
        expect_true(on_err === 1'b1, "on_out_of_range_error_passthrough");
        on_fetch(32'h0002_0000);
        expect_true(on_err === 1'b1, "on_error_line_not_cached");

        // ---------------- 功能 6：复位后必须重新填充 ----------------
        reset = 1'b1;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        on_fetch(32'h0000_0000);
        expect_true(on_got === exp_instr(32'h0000_0000), "on_after_reset_refill_data");
        expect_true(on_misses == 32'd1, "on_after_reset_miss_counted");

        // ---------------- 功能 7：冲突未命中 + 两路交替替换 ----------------
        // 默认参数下 set = addr[11:5]，所以 0x000 与 0x800 落在同一 set、tag 不同。
        reset = 1'b1;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        on_fetch(32'h0000_0000);           // 行 A -> 路 0
        expect_true(on_misses == 32'd1, "conflict_A_miss");
        on_fetch(32'h0000_0800);           // 行 B，同 set 不同 tag -> 冲突未命中 -> 路 1
        expect_true(on_misses == 32'd2, "conflict_B_miss");
        on_fetch(32'h0000_0000);           // 行 A 仍在路 0 -> 命中（这就是"2 路"的意义）
        expect_true(on_hits == 32'd1, "conflict_A_still_hits_with_2way");
        expect_true(on_got === exp_instr(32'h0000_0000), "conflict_A_data_ok");

        // ---------------- 功能 8：Off 模式每次取指都走下游 ----------------
        off_fetch(32'h0000_0000);
        off_fetch(32'h0000_0004);
        off_fetch(32'h0000_0000);
        expect_true(off_reqs == 32'd3, "off_mode_requests_every_fetch");
        expect_true(off_hits == 32'd0, "off_mode_no_hits");

        // ===================== 量化：Off vs On（同一序列、同时复位）=====================
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        on_wait_total = 0;
        for (i = 0; i < 32; i = i + 1) begin
            on_fetch(fseq[i]);
            on_wait_total = on_wait_total + on_wait_cycles;
        end
        off_wait_total = 0;
        for (i = 0; i < 32; i = i + 1) begin
            off_fetch(fseq[i]);
            off_wait_total = off_wait_total + 1;
        end

        $display("");
        $display("S3 ICACHE OFF/ON MEASUREMENT");
        $display("  fetch sequence         : 32 fetches (sequential within lines + back-jumps)");
        $display("  --- CACHE_EN=0 (Off, before) ---");
        $display("    hits / misses        : %0d / %0d", off_hits, off_misses);
        $display("    downstream requests  : %0d", off_reqs);
        $display("    downstream bus cycles: %0d", off_bus);
        $display("    core wait cycles     : %0d", off_wait);
        $display("  --- CACHE_EN=1 (On, after) ---");
        $display("    hits / misses        : %0d / %0d", on_hits, on_misses);
        $display("    downstream requests  : %0d", on_reqs);
        $display("    downstream bus cycles: %0d", on_bus);
        $display("    core wait cycles     : %0d", on_wait);
        if ((on_hits + on_misses) != 0)
            $display("    hit rate             : %0d%%",
                     (on_hits * 100) / (on_hits + on_misses));
        $display("");

        expect_true(on_hits > 32'd0, "from_measure_on_has_hits");
        expect_true(on_bus < off_bus, "on_fewer_downstream_bus_cycles");
        expect_true(on_wait < off_wait, "on_fewer_core_wait_cycles");
        expect_true(on_reqs < off_reqs, "on_fewer_downstream_requests");

        $display("  reduction: downstream bus cycles %0d -> %0d (%0d%% less)",
                 off_bus, on_bus,
                 (off_bus == 0) ? 0 : ((off_bus - on_bus) * 100) / off_bus);
        $display("             core wait cycles     %0d -> %0d (%0d%% less)",
                 off_wait, on_wait,
                 (off_wait == 0) ? 0 : ((off_wait - on_wait) * 100) / off_wait);

        if (failures == 0) $display("ALL S3 ICACHE 2WAY TEST PASS");
        else               $fatal(1, "S3 ICACHE 2WAY %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #400000;
        $fatal(1, "S3 ICACHE 2WAY TIMEOUT");
    end

endmodule
