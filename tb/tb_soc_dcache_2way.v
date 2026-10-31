`timescale 1ns/1ps
// 数据侧的下游存储模型：支持「行读 + 连拍返回」与「单笔写」。
//
// 参数 `RD_LATENCY` 是**读首拍延迟**，它代表后端有多慢：
//   - `RD_LATENCY = 0`：零等待（片上 BRAM 那类，本工程当前配置）
//   - `RD_LATENCY = 3..8`：慢后端（DDR3 那类，每次访问都有激活/命令开销）
// 这个参数就是 S4 量化里最重要的自变量：**Cache 的收益取决于后端有多慢**。
module dcache_mem_model #(
    parameter DEPTH_WORDS = 2048,
    parameter RD_LATENCY  = 0
) (
    input  wire        clk,
    input  wire        reset,
    // 读
    input  wire        m_rd_valid,
    output reg         m_rd_ready,
    input  wire [31:0] m_rd_addr,
    input  wire [7:0]  m_rd_len,
    output reg         m_beat_valid,
    input  wire        m_beat_ready,
    output reg  [31:0] m_beat_data,
    output reg         m_beat_last,
    output reg         m_beat_error,
    // 写
    input  wire        m_wr_valid,
    output reg         m_wr_ready,
    input  wire [31:0] m_wr_addr,
    input  wire [31:0] m_wr_data,
    input  wire [3:0]  m_wr_strb,
    // 统计与观测
    output reg  [31:0] bus_cycles,
    output reg  [31:0] rd_count,
    output reg  [31:0] wr_count
);
    reg [31:0] mem [0:DEPTH_WORDS-1];
    // MMIO 寄存器窗口：地址 > CACHEABLE_LAST 时当作外设寄存器，
    // 写进去读回来（用于验证"MMIO 强制绕行、副作用不被缓存"）。
    // 【为什么需要它】第一版只有 RAM 数组，MMIO 地址被判成越界 -> 返回 error + x，
    // 于是"写后读"用例失败；但那是**模型不真实**，不是 Cache 的错。
    localparam MMIO_WORDS = 64;
    reg [31:0] mmio [0:MMIO_WORDS-1];
    wire       is_mmio = (m_rd_addr > 32'h0000_FFFF) || (m_wr_addr > 32'h0000_FFFF);
    integer i;
    reg        busy;
    reg [3:0]  wait_cnt;
    reg [31:0] base;
    reg [7:0]  idx;
    reg [7:0]  last_idx;
    reg        err_flag;

    // 便于 TB 观察某一字当前的真实内容（RAM 或 MMIO 窗口）
    function [31:0] peek;
        input [31:0] byte_addr;
        begin
            peek = (byte_addr > 32'h0000_FFFF) ? mmio[byte_addr[7:2]]
                                               : mem[byte_addr[31:2]];
        end
    endfunction

    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = 32'hD000_0000 | (i & 32'h000F_FFFF);
        for (i = 0; i < MMIO_WORDS; i = i + 1)
            mmio[i] = 32'hE000_0000 | i;
    end

    always @(posedge clk) begin
        if (reset) begin
            m_rd_ready   <= 1'b1;
            m_beat_valid <= 1'b0;
            m_beat_last  <= 1'b0;
            m_beat_error <= 1'b0;
            m_wr_ready   <= 1'b1;
            busy         <= 1'b0;
            wait_cnt     <= 4'd0;
            idx          <= 8'd0;
            last_idx     <= 8'd0;
            err_flag     <= 1'b0;
            bus_cycles   <= 32'd0;
            rd_count     <= 32'd0;
            wr_count     <= 32'd0;
        end
        else begin
            if (m_beat_valid && m_beat_ready) begin
                m_beat_valid <= 1'b0;
                m_beat_last  <= 1'b0;
            end

            // ---- 写：单笔，1 拍接受（byte 级合并）----
            if (m_wr_valid && m_wr_ready) begin
                wr_count <= wr_count + 32'd1;
                bus_cycles <= bus_cycles + 32'd1;
                if (m_wr_addr > 32'h0000_FFFF) begin
                    // MMIO 寄存器窗口：整字写入
                    mmio[m_wr_addr[7:2]] <= m_wr_data;
                end
                else begin
                    if (m_wr_strb[0]) mem[m_wr_addr[31:2]][7:0]   <= m_wr_data[7:0];
                    if (m_wr_strb[1]) mem[m_wr_addr[31:2]][15:8]  <= m_wr_data[15:8];
                    if (m_wr_strb[2]) mem[m_wr_addr[31:2]][23:16] <= m_wr_data[23:16];
                    if (m_wr_strb[3]) mem[m_wr_addr[31:2]][31:24] <= m_wr_data[31:24];
                end
            end

            // ---- 读：行请求 + 连拍 ----
            if (busy) begin
                if (bus_cycles < 32'hFFFF_FFFF) bus_cycles <= bus_cycles + 32'd1;
                if (wait_cnt != 0) begin
                    wait_cnt <= wait_cnt - 4'd1;
                end
                else begin
                    m_beat_valid <= 1'b1;
                    // MMIO 窗口读寄存器；RAM 窗口读数组
                    if (base > 32'h0000_FFFF)
                        m_beat_data <= mmio[base[7:2]];
                    else
                        m_beat_data <= mem[base[31:2] + idx];
                    m_beat_error <= err_flag;
                    if (idx == last_idx) begin
                        m_beat_last <= 1'b1;
                        busy        <= 1'b0;
                        m_rd_ready  <= 1'b1;
                    end
                    else begin
                        idx <= idx + 8'd1;
                    end
                end
            end
            else if (m_rd_valid && m_rd_ready) begin
                base        <= m_rd_addr;
                idx         <= 8'd0;
                last_idx    <= m_rd_len;
                // 越界判定只对 RAM 窗口有意义：RAM 之外的地址是 MMIO，不是错误
                err_flag    <= (m_rd_addr <= 32'h0000_FFFF) &&
                               ((m_rd_addr[31:2] + m_rd_len) >= DEPTH_WORDS);
                busy        <= 1'b1;
                wait_cnt    <= RD_LATENCY[3:0];
                m_rd_ready  <= 1'b0;
                rd_count    <= rd_count + 32'd1;
                bus_cycles  <= bus_cycles + 32'd1;
            end
        end
    end
endmodule

// =============================================================================
// DUT 封装：D-Cache + 下游模型
// =============================================================================
module dcache_harness #(
    parameter CACHE_EN   = 0,
    parameter SETS       = 32,
    parameter RD_LATENCY = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire        req_write,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wstrb,
    output wire        rsp_valid,
    input  wire        rsp_ready,
    output wire [31:0] rsp_rdata,
    output wire        rsp_error,
    output wire [31:0] stat_hits,
    output wire [31:0] stat_misses,
    output wire [31:0] stat_bypass,
    output wire [31:0] stat_forward,
    output wire [31:0] stat_writes,
    output wire [31:0] stat_bus_cycles,
    output wire [31:0] mem_rd_count,
    output wire [31:0] mem_wr_count,
    output wire [31:0] mem_bus_cycles
);
    wire        m_rd_valid, m_rd_ready, m_beat_valid, m_beat_ready;
    wire        m_beat_last, m_beat_error;
    wire [31:0] m_rd_addr, m_beat_data;
    wire [7:0]  m_rd_len;
    wire        m_wr_valid, m_wr_ready;
    wire [31:0] m_wr_addr, m_wr_data;
    wire [3:0]  m_wr_strb;

    soc_dcache_2way #(.SETS(SETS), .WAYS(2), .LINE_BYTES(32), .CACHE_EN(CACHE_EN)) u_cache (
        .clk(clk), .reset(reset),
        .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
        .req_write(req_write), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata),
        .rsp_error(rsp_error),
        .m_rd_valid(m_rd_valid), .m_rd_ready(m_rd_ready), .m_rd_addr(m_rd_addr),
        .m_rd_len(m_rd_len),
        .m_beat_valid(m_beat_valid), .m_beat_ready(m_beat_ready),
        .m_beat_data(m_beat_data), .m_beat_last(m_beat_last),
        .m_beat_error(m_beat_error),
        .m_wr_valid(m_wr_valid), .m_wr_ready(m_wr_ready), .m_wr_addr(m_wr_addr),
        .m_wr_data(m_wr_data), .m_wr_strb(m_wr_strb),
        .stat_hits(stat_hits), .stat_misses(stat_misses), .stat_bypass(stat_bypass),
        .stat_writes(stat_writes), .stat_forward(stat_forward),
        .stat_bus_cycles(stat_bus_cycles), .stat_core_wait()
    );
    dcache_mem_model #(.DEPTH_WORDS(2048), .RD_LATENCY(RD_LATENCY)) u_mem (
        .clk(clk), .reset(reset),
        .m_rd_valid(m_rd_valid), .m_rd_ready(m_rd_ready), .m_rd_addr(m_rd_addr),
        .m_rd_len(m_rd_len),
        .m_beat_valid(m_beat_valid), .m_beat_ready(m_beat_ready),
        .m_beat_data(m_beat_data), .m_beat_last(m_beat_last),
        .m_beat_error(m_beat_error),
        .m_wr_valid(m_wr_valid), .m_wr_ready(m_wr_ready), .m_wr_addr(m_wr_addr),
        .m_wr_data(m_wr_data), .m_wr_strb(m_wr_strb),
        .bus_cycles(mem_bus_cycles), .rd_count(mem_rd_count), .wr_count(mem_wr_count)
    );
endmodule

// =============================================================================
// 主 Testbench
// =============================================================================
module tb_soc_dcache_2way;

    localparam SETS = 32;

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

    // 期望值：模型里 mem[i] = 0xD0000000 | i
    function [31:0] exp_word;
        input [31:0] byte_addr;
        begin
            exp_word = 32'hD000_0000 | ((byte_addr >> 2) & 32'h000F_FFFF);
        end
    endfunction

    // ---- On 模式（慢后端：读首拍延迟 4 拍）----
    reg         on_valid = 1'b0;
    reg  [31:0] on_addr  = 32'd0;
    reg         on_write = 1'b0;
    reg  [31:0] on_wdata = 32'd0;
    reg  [3:0]  on_wstrb = 4'b0;
    reg         on_ready = 1'b1;
    wire        on_req_ready, on_rsp_valid, on_rsp_error;
    wire [31:0] on_rsp_rdata, on_hits, on_misses, on_bypass, on_fwd, on_writes, on_bus;
    wire [31:0] on_mem_rd, on_mem_wr, on_mem_bus;

    dcache_harness #(.CACHE_EN(1), .SETS(SETS), .RD_LATENCY(4)) u_on (
        .clk(clk), .reset(reset),
        .req_valid(on_valid), .req_ready(on_req_ready), .req_addr(on_addr),
        .req_write(on_write), .req_wdata(on_wdata), .req_wstrb(on_wstrb),
        .rsp_valid(on_rsp_valid), .rsp_ready(on_ready), .rsp_rdata(on_rsp_rdata),
        .rsp_error(on_rsp_error),
        .stat_hits(on_hits), .stat_misses(on_misses), .stat_bypass(on_bypass),
        .stat_forward(on_fwd), .stat_writes(on_writes), .stat_bus_cycles(on_bus),
        .mem_rd_count(on_mem_rd), .mem_wr_count(on_mem_wr), .mem_bus_cycles(on_mem_bus)
    );

    // ---- Off 模式（同一份慢后端）----
    reg         off_valid = 1'b0;
    reg  [31:0] off_addr  = 32'd0;
    reg         off_write = 1'b0;
    reg  [31:0] off_wdata = 32'd0;
    reg  [3:0]  off_wstrb = 4'b0;
    reg         off_ready = 1'b1;
    wire        off_req_ready, off_rsp_valid, off_rsp_error;
    wire [31:0] off_rsp_rdata, off_hits, off_misses, off_bypass, off_fwd, off_writes, off_bus;
    wire [31:0] off_mem_rd, off_mem_wr, off_mem_bus;

    dcache_harness #(.CACHE_EN(0), .SETS(SETS), .RD_LATENCY(4)) u_off (
        .clk(clk), .reset(reset),
        .req_valid(off_valid), .req_ready(off_req_ready), .req_addr(off_addr),
        .req_write(off_write), .req_wdata(off_wdata), .req_wstrb(off_wstrb),
        .rsp_valid(off_rsp_valid), .rsp_ready(off_ready), .rsp_rdata(off_rsp_rdata),
        .rsp_error(off_rsp_error),
        .stat_hits(off_hits), .stat_misses(off_misses), .stat_bypass(off_bypass),
        .stat_forward(off_fwd), .stat_writes(off_writes), .stat_bus_cycles(off_bus),
        .mem_rd_count(off_mem_rd), .mem_wr_count(off_mem_wr), .mem_bus_cycles(off_mem_bus)
    );

    // ---- 第三份 DUT：零等待后端（RD_LATENCY=0），用来如实展示"后端越快 Cache 越没用" ----
    // 这是 S3 的教训在 S4 上的对照：结论必须注明前提（后端多久）。
    reg         z_valid = 1'b0;
    reg  [31:0] z_addr  = 32'd0;
    reg         z_write = 1'b0;
    reg  [31:0] z_wdata = 32'd0;
    reg  [3:0]  z_wstrb = 4'b0;
    reg         z_ready = 1'b1;
    wire        z_req_ready, z_rsp_valid, z_rsp_error;
    wire [31:0] z_rsp_rdata, z_hits, z_misses, z_bypass, z_fwd, z_writes, z_bus;
    wire [31:0] z_mem_rd, z_mem_wr, z_mem_bus;

    dcache_harness #(.CACHE_EN(0), .SETS(SETS), .RD_LATENCY(0)) u_zero (
        .clk(clk), .reset(reset),
        .req_valid(z_valid), .req_ready(z_req_ready), .req_addr(z_addr),
        .req_write(z_write), .req_wdata(z_wdata), .req_wstrb(z_wstrb),
        .rsp_valid(z_rsp_valid), .rsp_ready(z_ready), .rsp_rdata(z_rsp_rdata),
        .rsp_error(z_rsp_error),
        .stat_hits(z_hits), .stat_misses(z_misses), .stat_bypass(z_bypass),
        .stat_forward(z_fwd), .stat_writes(z_writes), .stat_bus_cycles(z_bus),
        .mem_rd_count(z_mem_rd), .mem_wr_count(z_mem_wr), .mem_bus_cycles(z_mem_bus)
    );

    task zero_xact;
        input [31:0] address;
        begin
            @(negedge clk);
            z_addr = address; z_write = 1'b0; z_wstrb = 4'b0;
            z_valid = 1'b1;
            while (!z_req_ready) @(posedge clk);
            @(posedge clk); #1;
            z_valid = 1'b0;
            while (!z_rsp_valid) @(posedge clk);
            @(posedge clk); #1;
        end
    endtask

    integer    on_wait;
    reg [31:0] on_got;
    reg        on_err;

    task on_xact;
        input [31:0] address;
        input        wr;
        input [31:0] wdat;
        input [3:0]  wstb;
        begin
            @(negedge clk);
            on_addr = address; on_write = wr; on_wdata = wdat; on_wstrb = wstb;
            on_valid = 1'b1;
            on_wait = 0;
            while (!on_req_ready) begin
                @(posedge clk); #1; on_wait = on_wait + 1;
            end
            @(posedge clk); #1;
            on_valid = 1'b0;
            while (!on_rsp_valid) begin
                @(posedge clk); #1; on_wait = on_wait + 1;
            end
            // 【采样时机】必须在 `rsp_valid` **有效的那一拍**读数据：
            // DUT 的 `rsp_rdata` 与 `rsp_valid` 同拍有效，握手完成后的下一拍就已经作废。
            // 第一版写成"看到 valid 后再等一拍才读"，读回来的是 `xxxxxxxx`
            // （实测追踪里 `rsv=1` 明明拉起来了，只是 TB 采错了时候）。
            on_got = on_rsp_rdata;
            on_err = on_rsp_error;
            @(posedge clk); #1;
        end
    endtask

    task off_xact;
        input [31:0] address;
        input        wr;
        input [31:0] wdat;
        input [3:0]  wstb;
        begin
            @(negedge clk);
            off_addr = address; off_write = wr; off_wdata = wdat; off_wstrb = wstb;
            off_valid = 1'b1;
            while (!off_req_ready) @(posedge clk);
            @(posedge clk); #1;
            off_valid = 1'b0;
            while (!off_rsp_valid) @(posedge clk);
            @(posedge clk); #1;
        end
    endtask

    integer    i;
    reg [31:0] seq [0:31];
    // 测量段的存档（见下方注释：第二次 reset 会清掉 DUT 统计，必须先存）
    reg [31:0] m_on_hits, m_on_miss, m_on_rd, m_on_bus, m_on_bypass, m_on_fwd;
    reg [31:0] m_off_hits, m_off_miss, m_off_rd, m_off_bus, m_off_byp;
    reg [31:0] m_z_rd, m_z_bus;

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        // ============ 功能 1：读未命中 -> 行填充 -> 正确数据 ============
        on_xact(32'h0000_0008, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === exp_word(32'h0000_0008), "miss_reads_right_word");
        expect_true(on_err === 1'b0, "miss_no_error");
        expect_true(on_misses == 32'd1, "miss_counted");

        // ============ 功能 2：同行命中 ============
        on_xact(32'h0000_0000, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === exp_word(32'h0000_0000), "same_line_hit_first");
        expect_true(on_hits == 32'd1, "same_line_hit_counted");
        on_xact(32'h0000_001C, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === exp_word(32'h0000_001C), "same_line_hit_last");

        // ============ 功能 3：写命中（写穿）后同字再读必须读到新值 ============
        on_xact(32'h0000_0000, 1'b1, 32'h1234_5678, 4'hF);
        expect_true(on_err === 1'b0, "write_completes");
        on_xact(32'h0000_0000, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === 32'h1234_5678, "write_through_read_back");

        // ============ 功能 4：**Store -> Load 转发**（写还在写缓冲里就读同一字）============
        // 先写一个可缓存地址（会更新行），紧接着立刻读同一字：
        // 该字要么来自已更新的行、要么来自写缓冲转发，无论哪条都必须得到新值。
        on_xact(32'h0000_0040, 1'b1, 32'hDEAD_BEEF, 4'hF);
        on_xact(32'h0000_0040, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === 32'hDEAD_BEEF, "store_to_load_forwarding");

        // ============ 功能 5：字节写（只改选中字节，其余保持）============
        // 0x0000_0080 先读进来建行，再只写第二个字节
        on_xact(32'h0000_0080, 1'b0, 32'd0, 4'd0);
        on_xact(32'h0000_0080, 1'b1, 32'h0000_AA00, 4'b0010);
        on_xact(32'h0000_0080, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === ((exp_word(32'h0000_0080) & 32'hFFFF_00FF) | 32'h0000_AA00),
                    "byte_write_merges");

        // ============ 功能 6：MMIO 强制绕行 ============
        // 0x1000_0000 超出 CACHEABLE_LAST_ADDR：不得进 Cache，且必须每次直连
        // 注：hit 计数到此为止应为 4（测试2 两次 + 测试3 一次 + 测试5 一次），
        //     第一版这里写成 3 是**我 TB 期望值算错了**，不是 DUT 的问题。
        on_xact(32'h1000_0000, 1'b0, 32'd0, 4'd0);
        on_xact(32'h1000_0000, 1'b0, 32'd0, 4'd0);
        expect_true(on_bypass >= 32'd2, "mmio_bypassed_twice");
        expect_true(on_hits == 32'd4, "mmio_does_not_hit_cache");

        // ============ 功能 7：MMIO 写的副作用不得被缓存 ============
        on_xact(32'h1000_1000, 1'b1, 32'h5555_AAAA, 4'hF);
        on_xact(32'h1000_1000, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === 32'h5555_AAAA, "mmio_write_then_read");

        // ============ 功能 8：越界 -> error ============
        on_xact(32'h0000_9000, 1'b0, 32'd0, 4'd0);
        expect_true(on_err === 1'b1, "out_of_range_error");

        // ============ 功能 9：复位后重新填充 ============
        reset = 1'b1;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        on_xact(32'h0000_0000, 1'b0, 32'd0, 4'd0);
        expect_true(on_got === 32'h1234_5678, "after_reset_refill_from_mem");

        // ============ 功能 10：2 路的意义（同组不同 tag 两行可同时驻留）============
        on_xact(32'h0000_0100, 1'b0, 32'd0, 4'd0);         // 行 A -> 路 0
        on_xact(32'h0000_0900, 1'b0, 32'd0, 4'd0);         // 同 set 不同 tag -> 路 1
        on_xact(32'h0000_0100, 1'b0, 32'd0, 4'd0);         // 行 A 仍应命中
        expect_true(on_got === exp_word(32'h0000_0100), "conflict_A_still_hits_2way");

        // ===================== 量化：Off vs On（慢后端，读首拍 4 拍）=====================
        // 访问序列：一个"有局部性"的混合序列（顺序 + 回访 + 少量 MMIO）
        for (i = 0; i < 12; i = i + 1) seq[i]      = (i % 12) * 4;              // 行 0 内顺序
        for (i = 12; i < 20; i = i + 1) seq[i]     = 32 + ((i - 12) % 8) * 4;   // 行 1
        for (i = 20; i < 28; i = i + 1) seq[i]     = ((i - 20) % 8) * 4;        // 回访行 0
        for (i = 28; i < 32; i = i + 1) seq[i]     = 64 + ((i - 28) % 4) * 4;   // 行 2

        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        for (i = 0; i < 32; i = i + 1) on_xact (seq[i], 1'b0, 32'd0, 4'd0);
        for (i = 0; i < 32; i = i + 1) off_xact(seq[i], 1'b0, 32'd0, 4'd0);

        // 【必须先存档】下面的零等待对照序列要再发一次 reset，
        // 而 reset 是共用的，会把 u_on / u_off 的统计一起清零。
        // 第一版就是直接在最后打印，结果读到的是清零后的 0（排查了好一阵）。
        m_on_hits   = on_hits;     m_on_miss  = on_misses;
        m_on_rd     = on_mem_rd;   m_on_bus   = on_mem_bus;
        m_on_bypass = on_bypass;   m_on_fwd   = on_fwd;
        m_off_hits  = off_hits;    m_off_miss = off_misses;
        m_off_rd    = off_mem_rd;  m_off_bus  = off_mem_bus;
        m_off_byp   = off_bypass;

        // ---- 零等待后端对照（用独立 reset 段，不影响上面的存档）----
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        for (i = 0; i < 32; i = i + 1) zero_xact(seq[i]);
        m_z_rd  = z_mem_rd;
        m_z_bus = z_mem_bus;

        // ---- 同一序列再跑一遍"零等待后端 + Cache Off"，作为对照（说明结论的前提）----
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        for (i = 0; i < 32; i = i + 1) zero_xact(seq[i]);

        $display("");
        $display("S4 DCACHE OFF/ON MEASUREMENT (slow backend, read latency 4 cycles)");
        $display("  access sequence        : 32 reads with locality (sequential + revisit)");
        $display("  --- CACHE_EN=0 (Off, before) ---");
        $display("    hits / misses        : %0d / %0d", m_off_hits, m_off_miss);
        $display("    cache bypass (MMIO)  : %0d", m_off_byp);
        $display("    downstream read reqs : %0d", m_off_rd);
        $display("    downstream bus cycles: %0d", m_off_bus);
        $display("  --- CACHE_EN=1 (On, after) ---");
        $display("    hits / misses        : %0d / %0d", m_on_hits, m_on_miss);
        $display("    cache bypass (MMIO)  : %0d", m_on_bypass);
        $display("    store->load forwards : %0d", m_on_fwd);
        $display("    downstream read reqs : %0d", m_on_rd);
        $display("    downstream bus cycles: %0d", m_on_bus);
        if ((m_on_hits + m_on_miss) != 0)
            $display("    hit rate             : %0d%%",
                     (m_on_hits * 100) / (m_on_hits + m_on_miss));
        $display("  --- 对照：零等待后端 (RD_LATENCY=0) + Cache Off ---");
        $display("    downstream read reqs : %0d", m_z_rd);
        $display("    downstream bus cycles: %0d", m_z_bus);
        $display("    （后端越快，同样的命中省下的拍数越少 -> Cache 的相对收益越小）");
        $display("");

        expect_true(m_on_hits > 32'd0, "measure_on_has_hits");
        expect_true(m_on_rd < m_off_rd, "on_fewer_downstream_reads");
        expect_true(m_on_bus < m_off_bus, "on_fewer_downstream_bus_cycles");

        $display("  reduction: downstream read reqs  %0d -> %0d (%0d%% less)",
                 m_off_rd, m_on_rd,
                 (m_off_rd == 0) ? 0 : ((m_off_rd - m_on_rd) * 100) / m_off_rd);
        $display("             downstream bus cycles %0d -> %0d (%0d%% less)",
                 m_off_bus, m_on_bus,
                 (m_off_bus == 0) ? 0 : ((m_off_bus - m_on_bus) * 100) / m_off_bus);

        if (failures == 0) $display("ALL S4 DCACHE 2WAY TEST PASS");
        else               $fatal(1, "S4 DCACHE 2WAY %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #400000;
        $fatal(1, "S4 DCACHE 2WAY TIMEOUT");
    end

endmodule
