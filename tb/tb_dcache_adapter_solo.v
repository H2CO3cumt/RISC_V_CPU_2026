`timescale 1ns/1ps
// S4 集成适配器（`tb/dcache_coremark_adapter.v`）的**独立 trace Testbench**。
//
// ## 为什么要单独写这个 TB
//
// 上一轮把 D-Cache 接进 CoreMark 时卡死在开机第一条分支（`pc=00000018 retired=7`）。
// 在 CoreMark 上调这个适配器，一次试跑就是几百万拍，代价过高。
// 所以这里用**小规模、逐拍可看**的方式先把握手对清楚：
//   - 后端用 `slow_ram_adapter`（读延迟可参数化，默认 2 拍，能覆盖"背压"情形）；
//   - 用固定序列驱动：行读 8 拍 → 同行命中 → 中途插一笔写 → 再读同字 → MMIO 直连；
//   - 出错时打印逐拍状态，第一个错拍一目了然。
//
// ## 测的目标（就是 CoreMark 里会用到的全部路径）
//
//   1. 可缓存读未命中 -> 适配器逐字取满 8 拍 -> Cache 返回正确数据；
//   2. 同行后续读 -> 命中，不再走适配器；
//   3. **写与读的交替**（这是上一轮最可疑的地方）：写在下行被接受的那一拍，
//      读请求**不能**同时被接受（否则互连只有一个端口，两边都以为自己发出了请求）；
//   4. 写后立刻读同一字 -> Store->Load 转发拿到新值，且写确实落到了后端；
//   5. MMIO（超出可缓存上界）直连读，不进 Cache。
module tb_dcache_adapter_solo;

    localparam CACHE_EN   = 1;
    localparam RD_LATENCY = 2;      // 后端读延迟，制造背压
    localparam AD_DEPTH   = 4096;

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

    // 期望值**直接从下游模型的内存里读**，而不是在 TB 里另造一个镜像。
    // 【为什么这样写】第一版自造镜像写 mem[i] = 0xC0000000|i，但 `slow_ram_adapter`
    // 自己的 initial 会把整块内存清零，两个 initial 的先后顺序决定了谁生效
    // （实测镜像被清掉了），于是"冷行填充"读到 0、断言失败。
    // 直接问模型要值就没有这个耦合——测试的是**通路**，不是内存里的具体内容。
    function [31:0] exp_word;
        input [31:0] a;
        begin
            exp_word = model.mem[a[31:2]];
        end
    endfunction

    // ---------------- DUT：适配器 + Cache ----------------
    reg         cpu_valid = 1'b0;
    reg  [31:0] cpu_addr  = 32'd0;
    reg         cpu_write = 1'b0;
    reg  [31:0] cpu_wdata = 32'd0;
    reg  [3:0]  cpu_wstrb = 4'b0;
    reg         cpu_ready = 1'b1;
    wire        cpu_req_ready, cpu_rsp_valid, cpu_rsp_error;
    wire [31:0] cpu_rsp_rdata, hits, misses, bypass, forward;

    wire        ram_req_valid, ram_req_ready, ram_req_write;
    wire [31:0] ram_req_addr, ram_req_wdata;
    wire [3:0]  ram_req_wstrb;
    wire        ram_rsp_valid, ram_rsp_ready, ram_rsp_error;
    wire [31:0] ram_rsp_rdata;
    wire [31:0] wr_side_effects;

    dcache_coremark_adapter #(
        .CACHE_EN(CACHE_EN), .SLOW_RD_LATENCY(RD_LATENCY), .SETS(32)
    ) dut (
        .clk(clk), .reset(reset),
        .cpu_req_valid(cpu_valid), .cpu_req_ready(cpu_req_ready), .cpu_req_addr(cpu_addr),
        .cpu_req_write(cpu_write), .cpu_req_wdata(cpu_wdata), .cpu_req_wstrb(cpu_wstrb),
        .cpu_rsp_valid(cpu_rsp_valid), .cpu_rsp_ready(cpu_ready), .cpu_rsp_rdata(cpu_rsp_rdata),
        .cpu_rsp_error(cpu_rsp_error),
        .ram_req_valid(ram_req_valid), .ram_req_ready(ram_req_ready), .ram_req_addr(ram_req_addr),
        .ram_req_write(ram_req_write), .ram_req_wdata(ram_req_wdata), .ram_req_wstrb(ram_req_wstrb),
        .ram_rsp_valid(ram_rsp_valid), .ram_rsp_ready(ram_rsp_ready), .ram_rsp_rdata(ram_rsp_rdata),
        .ram_rsp_error(ram_rsp_error),
        .stat_hits(hits), .stat_misses(misses), .stat_bypass(bypass), .stat_forward(forward)
    );

    slow_ram_adapter #(
        .DEPTH(AD_DEPTH), .INIT_FILE(""), .SLOW_RD_LATENCY(RD_LATENCY)
    ) model (
        .clk(clk), .reset(reset),
        .req_valid(ram_req_valid), .req_ready(ram_req_ready), .req_addr(ram_req_addr),
        .req_write(ram_req_write), .req_wdata(ram_req_wdata), .req_wstrb(ram_req_wstrb),
        .rsp_valid(ram_rsp_valid), .rsp_ready(ram_rsp_ready), .rsp_rdata(ram_rsp_rdata),
        .rsp_error(ram_rsp_error), .write_side_effect_count(wr_side_effects)
    );

    // 模型内存由 `slow_ram_adapter` 自己的 initial 清零；TB 不再另行初始化
    // （避免两个 initial 竞争导致期望值与实际不符）。

    // ---------------- 逐拍 trace（出错时用）----------------
    // 默认打开：本 TB 很小，直接把从头到尾的时序打出来更省事。
    // （上级 CoreMark 那边千万不能这么干——一次几百万拍。）
    reg trace_on = 1'b1;
    integer trace_cnt = 0;
    always @(posedge clk) begin
        if (trace_on && trace_cnt < 120) begin
            $display("      [%0t] st=%0d rsp_v=%b ram_v=%b wr=%b ram_a=%h ram_rsp=%b lf=%0d idx=%0d feed=%0d | cache req a=%h rd_v=%b rd_rdy=%b",
                     $time, dut.u_cache.state, cpu_rsp_valid,
                     ram_req_valid, ram_req_write, ram_req_addr, ram_rsp_valid,
                     dut.lf_state, dut.lf_idx, dut.lf_feed,
                     dut.u_cache.addr_q, dut.c_rd_valid, dut.c_rd_ready);
            trace_cnt = trace_cnt + 1;
        end
    end

    // ---------------- 事务任务 ----------------
    integer    wait_cycles;
    reg [31:0] got;
    reg        got_err;

    task xact;
        input [31:0] a;
        input        wr;
        input [31:0] wd;
        input [3:0]  ws;
        begin
            @(negedge clk);
            cpu_addr = a; cpu_write = wr; cpu_wdata = wd; cpu_wstrb = ws;
            cpu_valid = 1'b1;
            wait_cycles = 0;
            while (!cpu_req_ready) begin
                @(posedge clk); #1; wait_cycles = wait_cycles + 1;
                if (wait_cycles > 500) begin
                    $display("!!! 超时：等 cpu_req_ready 超过 500 拍, addr=%h wr=%b", a, wr);
                    trace_on = 1'b1; @(posedge clk); trace_on = 1'b0;
                    $fatal(1, "ADAPTER SOLO TIMEOUT (req_ready)");
                end
            end
            @(posedge clk); #1;
            cpu_valid = 1'b0;
            while (!cpu_rsp_valid) begin
                @(posedge clk); #1; wait_cycles = wait_cycles + 1;
                if (wait_cycles > 500) begin
                    $display("!!! 超时：等 cpu_rsp_valid 超过 500 拍, addr=%h wr=%b", a, wr);
                    trace_on = 1'b1; @(posedge clk); trace_on = 1'b0;
                    $fatal(1, "ADAPTER SOLO TIMEOUT (rsp_valid)");
                end
            end
            // 采样时机：rsp_valid 有效的那一拍（与 D-Cache TB 同样的踩坑）
            got     = cpu_rsp_rdata;
            got_err = cpu_rsp_error;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        // ---- 1) 可缓存读未命中：整行 8 拍取回 ----
        xact(32'h0000_0008, 1'b0, 32'd0, 4'd0);
        expect_true(got === exp_word(32'h0000_0008), "solo_miss_right_data");
        expect_true(got_err === 1'b0, "solo_miss_no_error");
        expect_true(misses == 32'd1, "solo_miss_counted");

        // ---- 2) 同行后续读：命中 ----
        xact(32'h0000_001C, 1'b0, 32'd0, 4'd0);
        expect_true(got === exp_word(32'h0000_001C), "solo_same_line_hit");
        expect_true(hits == 32'd1, "solo_hit_counted");

        // ---- 3) 写：必须完成，并且确实落到后端 ----
        xact(32'h0000_0020, 1'b1, 32'h1111_2222, 4'hF);
        expect_true(got_err === 1'b0, "solo_write_completes");
        repeat (6) @(posedge clk);            // 等写缓冲下推
        expect_true(wr_side_effects == 32'd1, "solo_write_reached_backend");
        expect_true(model.mem[32'h20 >> 2] === 32'h1111_2222, "solo_write_value_in_mem");

        // ---- 4) 写后读同一字（同行、命中路径）----
        xact(32'h0000_0020, 1'b0, 32'd0, 4'd0);
        expect_true(got === 32'h1111_2222, "solo_write_then_read_same_word");

        // ---- 5) **写与读交替**（上一轮最可疑处）：连续写-读-写-读 ----
        xact(32'h0000_0024, 1'b1, 32'h3333_4444, 4'hF);
        xact(32'h0000_0024, 1'b0, 32'd0, 4'd0);
        expect_true(got === 32'h3333_4444, "solo_wr_rd_alt_1");
        xact(32'h0000_0028, 1'b1, 32'h5555_6666, 4'hF);
        xact(32'h0000_0028, 1'b0, 32'd0, 4'd0);
        expect_true(got === 32'h5555_6666, "solo_wr_rd_alt_2");

        // ---- 6) 写未命中（新行）后立刻读该行 ----
        // 【本轮定位重点】0x400 与前面用过的 0x000/0x020/0x024/0x028 都落在 **set 0**
        //   （set = addr[11:5]，则 0x400>>5 = 32 = 0 mod 32），但 tag 不同（0x400 的 tag = 0x1）。
        //   所以这一笔既考"写未命中不分配"，也考"第二次行填充的地址跟踪"。
        xact(32'h0000_0400, 1'b1, 32'h7777_8888, 4'hF);
        repeat (4) @(posedge clk);      // 排空写缓冲
        $display("    [dbg] 写 0x400 之后: hits=%0d misses=%0d bypass=%0d wr_backend=%0d mem[0x100]=%h",
                 hits, misses, bypass, wr_side_effects, model.mem[32'h0400 >> 2]);
        $display("    [dbg]   set0: val0=%b tag0=%h val1=%b tag1=%h",
                 dut.u_cache.val0[0], dut.u_cache.tag0[0], dut.u_cache.val1[0], dut.u_cache.tag1[0]);
        $display("    [dbg]   lf: base=%h ptr=%h state=%0d buf0=%h",
                 dut.lf_base, dut.lf_ptr, dut.lf_state, dut.lf_buf[0]);

        trace_cnt = 0; trace_on = 1'b1;      // 只追踪这一笔
        xact(32'h0000_0400, 1'b0, 32'd0, 4'd0);
        trace_on = 1'b0;
        $display("    [dbg]  读回 got=%h (期望 %h)", got, 32'h7777_8888);
        $display("    [dbg]  读后 set0: val0=%b tag0=%h val1=%b tag1=%h; lf base=%h buf0=%h",
                 dut.u_cache.val0[0], dut.u_cache.tag0[0], dut.u_cache.val1[0], dut.u_cache.tag1[0],
                 dut.lf_base, dut.lf_buf[0]);
        expect_true(got === 32'h7777_8888, "solo_write_miss_line_then_read");

        // ---- 7) MMIO（超出可缓存上界）直连读 ----
        xact(32'h1000_0000, 1'b0, 32'd0, 4'd0);
        expect_true(got_err === 1'b1, "solo_mmio_out_of_range_error");
        expect_true(bypass >= 32'd1, "solo_mmio_bypassed");

        // ---- 8) 背压：响应端慢一拍接收 ----
        cpu_ready = 1'b0;
        fork
            xact(32'h0000_0000, 1'b0, 32'd0, 4'd0);
            begin
                repeat (3) @(posedge clk);
                cpu_ready = 1'b1;
            end
        join
        $display("    [dbg] backpressure: got=%h expect=%h", got, exp_word(32'h0000_0000));
        expect_true(got === exp_word(32'h0000_0000), "solo_backpressure_read");
        cpu_ready = 1'b1;

        $display("");
        $display("S4 ADAPTER SOLO: hits=%0d misses=%0d bypass=%0d forwards=%0d writes_to_backend=%0d",
                 hits, misses, bypass, forward, wr_side_effects);
        $display("");

        if (failures == 0) $display("ALL S4 ADAPTER SOLO TEST PASS");
        else               $fatal(1, "S4 ADAPTER SOLO %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "S4 ADAPTER SOLO TIMEOUT (global)");
    end

endmodule
