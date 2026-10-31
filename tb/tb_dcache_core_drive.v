`timescale 1ns/1ps
// 复刻 `pipeline_cpu.v` 数据端口的**精确驱动时序**，验证 D-Cache 能否配合。
//
// ## 为什么要写这个 TB
//
// 已有的 `tb_soc_dcache_2way.v` / `tb_dcache_adapter_solo.v` 是这样驱动的：
//     拉高 `req_valid`，**保持到 req_ready**，然后保持到 rsp_valid，再收响应。
// 本 TB 用 `rtl/pipeline_cpu.v` 第 720 / 876-883 / 918-920 行的真实寄存器语义驱动，
// 覆盖两个别的 TB 都没覆盖的点：
//   (1) **请求在被拒收期间会一直举着**（Core 不撤回），下游随时可以慢；
//   (2) **两笔访存之间没有空拍**：响应被接受的那一拍，Core 同时把下一笔推进
//       EX/MEM 并直接回 D_REQ（L881 与 L919 同沿、**L919 在后所以生效**），
//       于是下一笔请求紧接着下一拍就出现。
//
// ## 这份 TB 推翻过的错误结论（务必保留记录）
// 第 6 轮我写的旧版 TB 在"请求被拒"时**无条件**把 dstate 掰到 D_RSP，于是
// "下游拒收"在 TB 里表现成"请求凭空消失"，我据此把根因写成"拒收=丢请求"，
// 并给 RTL 加了一个 skid buffer。**那个根因是 TB 造出来的假象**：
// 按 L876-879，`dstate` 只在 `d_req_ready` 为高时才离开 D_REQ，Core 本身就会
// 一直举着请求。本 TB 已改为忠实模型；skid buffer 保留（它让"请求收下后
// 处理可以延后"，本身是合理的解耦，只是**不是**当初以为的那个根因）。

module tb_dcache_core_drive;

    localparam RD_LATENCY = 0;      // 先测零等待后端（CoreMark 工程当前的配置）

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

    // ---------------- DUT ----------------
    reg         req_valid = 1'b0;
    reg  [31:0] req_addr  = 32'd0;
    reg         req_write = 1'b0;
    reg  [31:0] req_wdata = 32'd0;
    reg  [3:0]  req_wstrb = 4'b0;
    // 【关键】ready 由"Core 自己的状态"决定，这里用 `dstate` 复刻
    reg         rsp_ready = 1'b0;
    wire        req_ready, rsp_valid, rsp_error;
    wire [31:0] rsp_rdata, hits, misses, bypass, forward, acc_cnt;

    wire        ram_req_valid, ram_req_ready, ram_req_write;
    wire [31:0] ram_req_addr, ram_req_wdata;
    wire [3:0]  ram_req_wstrb;
    wire        ram_rsp_valid, ram_rsp_ready, ram_rsp_error;
    wire [31:0] ram_rsp_rdata;
    wire [31:0] wr_side;

    dcache_coremark_adapter #(.CACHE_EN(1), .SETS(32)) dut (
        .clk(clk), .reset(reset),
        .cpu_req_valid(req_valid), .cpu_req_ready(req_ready), .cpu_req_addr(req_addr),
        .cpu_req_write(req_write), .cpu_req_wdata(req_wdata), .cpu_req_wstrb(req_wstrb),
        .cpu_rsp_valid(rsp_valid), .cpu_rsp_ready(rsp_ready), .cpu_rsp_rdata(rsp_rdata),
        .cpu_rsp_error(rsp_error),
        .ram_req_valid(ram_req_valid), .ram_req_ready(ram_req_ready), .ram_req_addr(ram_req_addr),
        .ram_req_write(ram_req_write), .ram_req_wdata(ram_req_wdata), .ram_req_wstrb(ram_req_wstrb),
        .ram_rsp_valid(ram_rsp_valid), .ram_rsp_ready(ram_rsp_ready), .ram_rsp_rdata(ram_rsp_rdata),
        .ram_rsp_error(ram_rsp_error),
        .stat_hits(hits), .stat_misses(misses), .stat_bypass(bypass), .stat_forward(forward)
    );

    slow_ram_adapter #(.DEPTH(4096), .INIT_FILE(""), .SLOW_RD_LATENCY(RD_LATENCY)) model (
        .clk(clk), .reset(reset),
        .req_valid(ram_req_valid), .req_ready(ram_req_ready), .req_addr(ram_req_addr),
        .req_write(ram_req_write), .req_wdata(ram_req_wdata), .req_wstrb(ram_req_wstrb),
        .rsp_valid(ram_rsp_valid), .rsp_ready(ram_rsp_ready), .rsp_rdata(ram_rsp_rdata),
        .rsp_error(ram_rsp_error), .write_side_effect_count(wr_side)
    );

    // ---------------- 复刻 Core 的 dstate 行为 ----------------
    // D_IDLE=0, D_REQ=1, D_RSP=2
    reg [1:0] dstate;
    reg [31:0] got;
    reg        got_err;
    integer    wc;

    // 一次"Core 式"数据事务（**按 `pipeline_cpu.v` 的寄存器语义精确复刻**）
    //
    //   阶段 1（D_REQ）：请求摆在总线上，**保持到 `d_req_ready` 为高**才离开 D_REQ。
    //     依据 L720 + L876-879：`d_req_valid = ... && (dstate == D_REQ)`，
    //     而 `dstate` **只有** `d_req_ready` 为高时才从 D_REQ 跳到 D_RSP。
    //     —— 结论：**Core 不会因为下游没 ready 就撤回请求**，它会一直举着。
    //     【第 6 轮的教训】旧版 TB 在这里无条件把 dstate 掰到 D_RSP，于是"请求被拒"
    //     变成"请求消失"，我据此得出"拒收=丢请求"的根因——**那是我自己造的假象**，
    //     不是 Core 的行为。本版改成忠实模型后该结论作废。
    //   阶段 2（D_RSP）：请求落下，等 `rsp_valid`；此期间 `d_rsp_ready` 恒为高。
    //   阶段 3（交接）：响应被接受的那一拍，Core 同时把下一笔访存推进 EX/MEM 并
    //     直接回 D_REQ（L881 与 L919 同沿、L919 在后生效），所以**下一笔请求紧接着
    //     下一拍就出现，中间没有空拍**。本 task 返回后调用方立刻 `@(negedge clk)`，
    //     正好复刻这一点。
    task core_xact;
        input [31:0] a;
        input        wr;
        input [31:0] wd;
        input [3:0]  ws;
        integer guard;
        reg     accepted;
        begin
            // ---- 阶段 1：请求保持到被接受 ----
            guard = 0; accepted = 1'b0;
            @(negedge clk);
            req_addr = a; req_write = wr; req_wdata = wd; req_wstrb = ws;
            dstate   = 2'd1;           // D_REQ：请求在场
            req_valid = 1'b1;
            while (!accepted) begin
                @(posedge clk);        // 此刻 req_ready 仍是**边沿前**的组合值 = 本沿的接受判据
                if (req_ready) accepted = 1'b1;
                #1;
                if (accepted) begin    // 接受后本拍起转 D_RSP，请求随之落下
                    dstate    = 2'd2;
                    req_valid = 1'b0;
                end
                guard = guard + 1;
                if (guard > 200) begin
                    $display("!!! TIMEOUT waiting req_ready: addr=%h wr=%b req_rdy=%b st=%0d",
                             a, wr, req_ready, dut.u_cache.state);
                    $fatal(1, "CORE-DRIVE TIMEOUT (req_ready)");
                end
            end

            // ---- 阶段 2：等响应，并在被接受的那一拍锁存数据 ----
            guard = 0; accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                if (rsp_valid && rsp_ready) begin
                    got     = rsp_rdata;   // 边沿前的值 = Core 在 MEM 级锁存的值
                    got_err = rsp_error;
                    accepted = 1'b1;
                end
                #1;
                guard = guard + 1;
                if (guard > 200) begin
                    $display("!!! TIMEOUT waiting rsp: addr=%h wr=%b req_rdy=%b rsp_v=%b st=%0d",
                             a, wr, req_ready, rsp_valid, dut.u_cache.state);
                    $fatal(1, "CORE-DRIVE TIMEOUT (rsp_valid)");
                end
            end
            dstate = 2'd0;             // 回 D_IDLE
        end
    endtask


    always @(*) rsp_ready = (dstate == 2'd2);

    // 调试追踪：出错时看逐拍
    reg trace_on = 1'b0;
    integer tcnt = 0;
    always @(posedge clk) begin
        if (trace_on && tcnt < 40) begin
            $display("      [%0t] dstate=%0d req_v=%b req_rdy=%b rsp_v=%b rsp_rdy=%b | st=%0d acc=%0d",
                     $time, dstate, req_valid, req_ready, rsp_valid, rsp_ready,
                     dut.u_cache.state, dut.u_cache.stat_rsp_accepted);
            tcnt = tcnt + 1;
        end
    end

    // 【量化覆盖】统计"请求在场但下游没 ready"的拍数。这个窗口必须真的被测到，
    // 否则本 TB 就没有覆盖它存在的理由（只报告，不当作 PASS/FAIL 判据）。
    integer refused_cycles = 0;
    always @(posedge clk) if (req_valid && !req_ready) refused_cycles = refused_cycles + 1;

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        // ---- 读未命中（请求只举一拍）----
        core_xact(32'h0000_0008, 1'b0, 32'd0, 4'd0);
        expect_true(got_err === 1'b0, "cd_read_no_error");
        expect_true(misses >= 32'd1, "cd_read_counted_miss");

        // ---- 同行命中 ----
        core_xact(32'h0000_0000, 1'b0, 32'd0, 4'd0);
        expect_true(got_err === 1'b0, "cd_hit_no_error");

        // ---- 写（请求只举一拍）----
        core_xact(32'h0000_0040, 1'b1, 32'hA5A5_1234, 4'hF);
        expect_true(got_err === 1'b0, "cd_write_no_error");
        repeat (4) @(posedge clk);
        expect_true(wr_side >= 32'd1, "cd_write_reached_backend");

        // ---- 写后读同字 ----
        core_xact(32'h0000_0040, 1'b0, 32'd0, 4'd0);
        expect_true(got === 32'hA5A5_1234, "cd_write_then_read");

        // ---- 连续多笔（模拟 CoreMark 的紧密序列）----
        core_xact(32'h0000_0008, 1'b0, 32'd0, 4'd0);
        trace_on = 1'b1; tcnt = 0;
        core_xact(32'h0000_0008, 1'b1, 32'h1111_2222, 4'hF);
        trace_on = 1'b0;
        trace_on = 1'b1; tcnt = 0;
        core_xact(32'h0000_0008, 1'b0, 32'd0, 4'd0);
        trace_on = 1'b0;
        core_xact(32'h0000_0008, 1'b1, 32'h1111_2222, 4'hF);
        core_xact(32'h0000_0008, 1'b0, 32'd0, 4'd0);
        expect_true(got === 32'h1111_2222, "cd_back_to_back_1");

        core_xact(32'h0000_0080, 1'b1, 32'h3333_4444, 4'hF);
        core_xact(32'h0000_0080, 1'b0, 32'd0, 4'd0);
        expect_true(got === 32'h3333_4444, "cd_back_to_back_2");

        $display("");
        $display("MEASUREMENT S4 CORE-DRIVE: hits=%0d misses=%0d bypass=%0d forward=%0d refused_cycles=%0d",
                 hits, misses, bypass, forward, refused_cycles);
        $display("");
        if (failures == 0) $display("ALL S4 CORE-DRIVE TEST PASS");
        else               $fatal(1, "S4 CORE-DRIVE %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "S4 CORE-DRIVE TIMEOUT (global)");
    end

endmodule
