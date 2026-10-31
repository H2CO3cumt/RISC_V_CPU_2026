`timescale 1ns/1ps
// M-24 / N1 板级验收：周期性定时器中断的**板级数据通路**端到端 Testbench。
//
// 被测对象是 fpga/timer_demo/rtl/mes50hp_timer_demo_top.v —— 真正要下载到 MES50HP 的顶层，
// 不是另抄一份简化模型。因此这里验过的连线就是板上的连线：
//   Core → soc_data_interconnect（TARGET_TIMER / TARGET_GPIO / TARGET_UART）
//        → timer_mmio（mtime/mtimecmp，电平 irq_timer）
//        → Core.irq_timer_i → WB 退休边界接受精确 Trap → mtvec → ISR → mret
//
// 时基为什么要参数化：
//   交付镜像的 delta = 12_500_000 拍（50 MHz 下 0.25 s）。按真实 delta 仿真，跑一次中断
//   要 1250 万拍，iverilog 跑不动。所以分成两条证据：
//     - 逻辑验收：用 -D TIMER_DEMO_TB_DELTA=<小值> 跑完整链路，验周期关系、ISR、LED、UART；
//     - 交付镜像：本 TB 自己从 fpga/timer_demo/rtl/timer_demo_program.mem 的
//       "自描述指针块"里解出 delta 与标签地址，并断言 delta 等于 -D 传入值。
//       真实值 12_500_000 由生成脚本写入，板上再用 mtime 自计时核对。
//
// 时基用**真实值**：CLK_HALF_NS=20 与 BAUD_CYCLES=434 就是 MES50HP 上的 50 MHz / 115200
// 分频比，只有 DELTA 被换成仿真小值。
//
// 为什么不用 -P 覆盖参数：实测本工程的 Icarus 12 会**静默忽略**命令行参数覆盖
// （编译过了、跑起来却还是 20/434），于是十几次中断要仿上亿拍。
// 需要覆盖时用下面的 ifdef 宏。
module tb_timer_demo_board_top;
`ifdef TIMER_DEMO_TB_CLK_HALF_NS
    parameter integer CLK_HALF_NS = `TIMER_DEMO_TB_CLK_HALF_NS;
`else
    parameter integer CLK_HALF_NS = 20;
`endif
`ifdef TIMER_DEMO_TB_BAUD_CYCLES
    parameter integer BAUD_CYCLES = `TIMER_DEMO_TB_BAUD_CYCLES;
`else
    parameter integer BAUD_CYCLES = 50_000_000 / 115200;
`endif
`ifdef TIMER_DEMO_TB_DELTA
    parameter integer DELTA = `TIMER_DEMO_TB_DELTA;
`else
    parameter integer DELTA = 200000;
`endif
    parameter integer INTERRUPTS  = 12;
    // 中断从"mtime 到期"到"ISR 第一条指令被取出"之间的固定流水线开销上界（拍）。
    parameter integer ISR_OVERHEAD_MAX = 128;
    // 本 ISR 的长度上界（拍）。ISR 里要发 5 个 UART 字节（计数 + LED + mtime 三位），
    // 每个字节 10 位 × 434 拍 ≈ 4340 拍；实测约 4.0e4 拍（第 1 个字节通常不用等）。
    // 这里按 6 个字节时间留余量。
    // **这个上界是"周期可预测"的前提**：只有 ISR 在下一个 deadline 之前跑完，
    // mtimecmp 才会被"当时读到的 mtime + delta"重装，中断间隔才严格等于 delta。
    // 实测证据：delta=2000（旧 2 字节 ISR）→ 间隔退化成 ISR 长度；
    //           delta=40000（5 字节 ISR）→ 间隔 80012 ≈ 2×delta + 12。
    parameter integer ISR_LENGTH_MAX = 6 * (50_000_000 / 115200) * 10;
    parameter integer RECORD_BYTES = 5;   // ISR 每次往串口写 5 个字节

    reg clk = 1'b0;
    reg uart_rx = 1'b1;                 // 本演示不看串口输入，保持空闲高电平
    wire uart_tx;
    wire [7:0] led;

    mes50hp_timer_demo_top #(
        .UART_BAUD_CYCLES(BAUD_CYCLES),
        .RAM_LAST_ADDR(32'h0000_0fff)
    ) dut (
        .clk_50m(clk), .uart0_rx(uart_rx), .uart0_tx(uart_tx), .led(led)
    );

`ifdef TB_TIMER_DEMO_RANDOM
    // 第二遍：同顶层、同断言，只把 IMEM/DMEM 换成带随机背压的行为模型，
    // 用于验证"随机取指/数据延迟下中断依然不丢、不重复、周期仍可预测"（对齐 M-16 口径）。
    //
    // 这里**不是**覆盖 DUT 内部的例化，而是配合顶层的 ifndef TIMER_DEMO_RANDOM_MEM：
    // 顶层在定义 TIMER_DEMO_RANDOM_MEM 时**不例化**那两个 BRAM，
    // 由本 Testbench 通过 dut 的内部网线（dut.iv / dut.ir / …）从外部驱动同样的连线。
    // 所以"同一个顶层、同一套断言、只换存储模型"这句话是真的。
    pipeline_imem_adapter #(.DEPTH(1024), .RANDOM_DELAY(1), .FILL_WORD(32'h0000_006F),
                            .INIT_FILE("fpga/timer_demo/rtl/timer_demo_program.mem")) imem_rand (
        .clk(clk), .reset(dut.reset),
        .req_valid(dut.iv), .req_ready(dut.ir), .req_addr(dut.ia),
        .rsp_valid(dut.rv), .rsp_ready(dut.rr), .rsp_data(dut.idata), .rsp_error(dut.ie)
    );
    ram_adapter #(.DEPTH(1024), .RANDOM_DELAY(1),
                  .INIT_FILE("fpga/timer_demo/rtl/timer_demo_program.mem")) dmem_rand (
        .clk(clk), .reset(dut.reset),
        .req_valid(dut.ram_v), .req_ready(dut.ram_r), .req_addr(dut.ta),
        .req_write(dut.tw), .req_wdata(dut.twd), .req_wstrb(dut.tws),
        .rsp_valid(dut.ram_sv), .rsp_ready(dut.ram_sr), .rsp_rdata(dut.ram_rd),
        .rsp_error(dut.ram_se), .write_side_effect_count()
    );
`endif

    // 监视 DUT 实际发出的串口字节（与板载 CP2102 看到的是同一根 tx 线）。
    wire [7:0] mon_data;
    wire       mon_valid, mon_frame_error;
    UART_RX #(.MAX_1BAUD(BAUD_CYCLES)) mon (
        .clk_50m(clk), .rst(dut.reset), .rx(uart_tx),
        .rx_data(mon_data), .rx_data_vld(mon_valid), .rx_frame_error(mon_frame_error)
    );

    integer cycles = 0;
    integer failures = 0;
    integer test_no = 0;

    // ---- 观测点 ----
    integer isr_entries = 0;
    integer last_isr_cycle = -1;
    integer led_edges   = 0;
    integer uart_bytes  = 0;
    integer uart_errors = 0;
    integer prev_led0   = -1;

    reg [7:0]  cap_bytes [0:255];
    integer    cap_words [0:63];        // 每个 LED 翻转沿时的 LED 低 8 位
    integer    cap_led_idx = 0;

    // mtimecmp 样本：第 i 次中断**重装完成之后**的 mtimecmp 值。
    // 取"重装之后"而不是"重装之前"：重装前采到的是上一轮的旧值，
    // 相邻差会混进"从 deadline 到期到 ISR 取到重装指令"这段 CPU/定时器流水线延迟。
    integer    cmp_samples [0:63];
    integer    cmp_idx = 0;
    reg        cmp_sampling = 1'b0;     // 一次采样在途时不再触发第二次
    reg [6:0]  cmp_wait = 7'd0;
    // mtime 样本：第 i 次中断 ISR 入口被取出时的 mtime。
    // 相邻之差 = 实际中断间隔，必须**恒定**且 ∈ [delta, delta + 固定开销上界]。
    integer    mt_samples [0:63];
    integer    mt_idx = 0;

    // ---- 从**交付镜像**里解出 delta 与各标签地址，而不是写死在 Testbench 里 ----
    // 镜像自带一个"自描述指针块"（software/timer_demo/start.S 的 image_pointers）：
    //   [k+0] = MTIMECMP_DELTA     [k+1] = isr_entry
    //   [k+2] = sleep_loop(主循环)  [k+3] = 0x4E315444 标志字
    //   注意这三个地址是**字节地址**，索引镜像数组时要 >>2。
    //
    // 除了读这个块，还做一次**交叉核对**：boot 里装载 mtvec 的是
    //   "auipc ra, 0" + "addi ra, ra, <页内偏移>"
    // （isr_entry 与它同页，所以 auipc 立即数必须是 0）。核对内容是
    //   auipc 所在字节地址 + 其 imm12 == 指针块给出的 isr_entry
    // 这把"指针块说的地址"和"程序真正装进 mtvec 的地址"钉在一起：
    // 两者不一致就直接失败，不会出现"指针块写错、测试却照样过"的情况。
    localparam [31:0] IMAGE_FLAG = 32'h4E31_5444;
    reg [31:0] img [0:1023];
    integer    img_delta;
    integer    img_isr_entry;
    integer    img_main_loop;
    integer    k, j;
    reg        ptr_found;
    reg [31:0] apc_word, aadd_word;

    initial begin
        $readmemh("fpga/timer_demo/rtl/timer_demo_program.mem", img);
        img_delta = -1; img_isr_entry = -1; img_main_loop = -1; ptr_found = 1'b0;
        for (k = 0; k < 1024 - 4; k = k + 1) begin
            if (img[k+3] == IMAGE_FLAG) begin
                ptr_found     = 1'b1;
                img_delta     = img[k];
                img_isr_entry = img[k+1];
                img_main_loop = img[k+2];

                if (img_isr_entry % 4 !== 0 || img_main_loop % 4 !== 0 ||
                    img_isr_entry < 0 || img_isr_entry >= 4096) begin
                    $display("TEST FAIL N1: pointer block has an out-of-range/unaligned address isr=0x%08h main=0x%08h",
                             img_isr_entry, img_main_loop);
                    $fatal(1);
                end
                // 主循环那一条必须是自跳转（jal x0,0 = 0x0000006f），否则"mret 回到被打断的
                // 位置"这条断言就失去意义。
                if (img[img_main_loop/4] !== 32'h0000_006f) begin
                    $display("TEST FAIL N1: image says main loop=0x%08h but that word is %08h (not a self-jump)",
                             img_main_loop, img[img_main_loop/4]);
                    $fatal(1);
                end
                // 交叉核对 auipc/addi 装载对：找 "auipc ra, 0" + "addi ra, ra, imm12"，
                // 要求 auipc 所在字节地址 + imm12 == isr_entry
                // （auipc 加的是**自己那条指令的地址**，不是下一条；同页所以 imm20 必须是 0）。
                begin : cross_check
                    integer found;
                    found = 0;
                    for (j = 0; j < 1023; j = j + 1) begin
                        apc_word  = img[j];
                        aadd_word = img[j+1];
                        if (apc_word[6:0] === 7'b0010111 && apc_word[11:7] === 5'd1 && apc_word[31:12] === 20'd0 &&
                            aadd_word[6:0] === 7'b0010011 && aadd_word[11:7] === 5'd1 && aadd_word[14:12] === 3'b000) begin
                            if (j*4 + aadd_word[31:20] === img_isr_entry) found = found + 1;
                            else $display("       candidate at 0x%03h: auipc=%08h addi=%08h -> target 0x%03h, want 0x%03h",
                                          j*4, apc_word, aadd_word, j*4 + aadd_word[31:20], img_isr_entry);
                        end
                    end
                    if (found !== 1) begin
                        $display("TEST FAIL N1: expected exactly one auipc/addi pair resolving to isr_entry=0x%03h, found %0d",
                                 img_isr_entry, found);
                        $fatal(1);
                    end
                end
            end
        end
        if (!ptr_found) begin
            $display("TEST FAIL N1: image is missing the self-describing pointer block (flag %08h)", IMAGE_FLAG);
            $fatal(1);
        end
        if (img_delta !== DELTA) begin
            $display("TEST FAIL N1: image delta=%0d but Testbench DELTA=%0d (regenerate the image with matching -Delta)",
                     img_delta, DELTA);
            $fatal(1);
        end
        $display("N1 image self-description: delta=%0d isr_entry=0x%03h main_loop=0x%03h (mtvec cross-check PASS)",
                 img_delta, img_isr_entry, img_main_loop);
    end

    always #(CLK_HALF_NS) clk = ~clk;

    always @(posedge clk) if (!dut.reset) begin
        cycles = cycles + 1;

        // ISR 入口：用取指 PC 直接观测"ISR 真的被执行了"。入口地址来自镜像自描述块。
        //
        // 为什么要 last_isr_cycle 去抖：取指 PC 可能在同一次进入里**连续多个周期**
        // 都停在入口地址（前端被 Redirect 冲刷后重新登记，或取指响应被背压），
        // 实测同一次中断会记到 2 次。一次中断不可能在 ISR 长度内再来一次，
        // 所以用"距上次记录是否超过 ISR 长度"作为去抖条件。
        if (dut.core.fetch_pc === img_isr_entry[31:0] &&
            (last_isr_cycle < 0 || (cycles - last_isr_cycle) > ISR_LENGTH_MAX)) begin
            last_isr_cycle = cycles;
            isr_entries = isr_entries + 1;
            if (!cmp_sampling) begin
                cmp_sampling = 1'b1;
                cmp_wait = 7'd64;       // 等重装那条 store 走完再采
            end
            if (mt_idx < 64) begin
                mt_samples[mt_idx] = dut.timer.mtime_lo_q;
                mt_idx = mt_idx + 1;
            end
        end
        if (cmp_sampling) begin
            if (cmp_wait == 7'd0) begin
                if (cmp_idx < 64) begin
                    cmp_samples[cmp_idx] = dut.timer.mtimecmp_lo_q;
                    cmp_idx = cmp_idx + 1;
                end
                cmp_sampling = 1'b0;
            end
            else cmp_wait = cmp_wait - 7'd1;
        end

        // LED bit0 翻转沿 = "周期性"的直接板级现象。
        if (prev_led0 >= 0 && led[0] !== prev_led0[0]) begin
            led_edges = led_edges + 1;
            cap_words[cap_led_idx] = led;
            if (cap_led_idx < 63) cap_led_idx = cap_led_idx + 1;
        end
        prev_led0 = led[0];
    end

    // UART 字节落表。**数据与计数必须在同一个 always 块、同一次赋值里更新**：
    // 先前的写法把 cap_bytes[i] 和 uart_bytes++ 拆在两句、并且用 uart_bytes 当索引，
    // 于是"计数器已经指到下一位、而数据还没写进去"的那一拍会读到未初始化的 x。
    always @(posedge clk) if (mon_valid) begin
        cap_bytes[uart_bytes] = mon_data;
        uart_bytes = uart_bytes + 1;
    end
    always @(posedge clk) if (mon_frame_error) uart_errors = uart_errors + 1;

    // ---------------------------------------------------------------- 断言工具
    task expect_int;
        input integer actual;
        input integer expected;
        input [8*60-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected) $display("TEST %0d PASS %0s (%0d)", test_no, name, actual);
            else begin
                $display("TEST %0d FAIL %0s expected=%0d actual=%0d", test_no, name, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task expect_byte;
        input [7:0] actual;
        input [7:0] expected;
        input [8*60-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected) $display("TEST %0d PASS %0s ('%c')", test_no, name, actual);
            else begin
                $display("TEST %0d FAIL %0s expected=%02h('%c') actual=%02h", test_no, name,
                         expected, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task expect_true;
        input integer condition;
        input [8*60-1:0] name;
        begin
            test_no = test_no + 1;
            if (condition) $display("TEST %0d PASS %0s", test_no, name);
            else begin
                $display("TEST %0d FAIL %0s", test_no, name);
                failures = failures + 1;
            end
        end
    endtask

    integer i, gap, min_cmp_gap, max_cmp_gap, min_mt_gap, max_mt_gap;
    integer expect_val, led_expect, led_bad, uart_bad;
    integer guard;

    initial begin
        $display("=== N1 板级周期性定时器中断验收（CLK_HALF_NS=%0d, DELTA=%0d, BAUD_CYCLES=%0d）===",
                 CLK_HALF_NS, DELTA, BAUD_CYCLES);
        // 上限只是"防呆"：真正的 delta（12_500_000）按这个时钟要仿一亿多拍。
        if (DELTA > 400000) begin
            $display("TEST FAIL N1: DELTA=%0d is too large to simulate; use the small test-delta image", DELTA);
            $fatal(1);
        end

        wait (!dut.reset);

        guard = 0;
        while (isr_entries < INTERRUPTS && guard < (DELTA + ISR_LENGTH_MAX) * (INTERRUPTS + 8)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        // 收尾：最后一次中断的 5 个 UART 字节还要走完（每字节 4340 拍），
        // 并且要等 CPU 从 ISR 里 mret 回到主循环。
        // 判断条件必须按**整条记录**算；早先只等固定拍数，结果串口少收字节、
        // "mret 回到主循环"也判定失败——那是**测试收尾太早**，不是 DUT 的问题。
        guard = 0;
        while ((uart_bytes < 1 + RECORD_BYTES * isr_entries ||
                dut.core.fetch_pc !== img_main_loop[31:0]) &&
               guard < 4 * ISR_LENGTH_MAX) begin
            @(posedge clk);
            guard = guard + 1;
        end
        repeat (50) @(posedge clk);

        // ---- A. 中断周期性发生 ----
        expect_true(isr_entries >= INTERRUPTS, "N1: ISR was entered at least INTERRUPTS times");
        expect_int(led_edges, isr_entries, "N1: LED0 toggled exactly once per ISR entry");

        // 先算 mtime 间隔（下面几条断言都要用，顺序不能反）。
        min_mt_gap = 1 << 30; max_mt_gap = 0;
        for (i = 1; i < mt_idx; i = i + 1) begin
            gap = mt_samples[i] - mt_samples[i-1];
            if (gap < min_mt_gap) min_mt_gap = gap;
            if (gap > max_mt_gap) max_mt_gap = gap;
        end
        // "间隔精确可复现"只在**确定性存储**下有物理意义：
        // 零延迟时 ISR 重装 deadline 的那一拍完全固定，间隔就是 delta + 固定拍数。
        // 打开随机背压后，重装前的两次访存被随机拖后若干拍，间隔会在这个范围内抖动——
        // 那是**刻意注入的背压**，不是周期失效。所以随机那一遍只断言"抖动有界"。
`ifdef TB_TIMER_DEMO_RANDOM
        expect_true(max_mt_gap - min_mt_gap <= 8,
                    "N1: random-backpressure interval jitter stays within 8 cycles");
`else
        expect_int(max_mt_gap, min_mt_gap, "N1: interrupt interval is exactly reproducible");
`endif
        // 完整性条件：ISR 必须在下一个 deadline 之前跑完，否则 mtimecmp 会迟到、
        // 周期就不再等于 delta + 固定开销。
        expect_true(max_mt_gap <= DELTA + ISR_OVERHEAD_MAX && min_mt_gap >= DELTA,
                    "N1: interrupt interval is delta + bounded fixed overhead");

        // mtimecmp 每次重装前进的量 = 本次中断间隔（deadline 是"读 mtime 那一刻 + delta"，
        // 而两次读之间正好隔着一个中断间隔）。**不要期待它严格等于 delta**：
        // 从 deadline 到期到 CPU 真正取到 ISR 第一条指令，还有固定的流水线延迟
        // （实测 delta=200000 → 间隔 200006）。
        // 这个延迟是固定的，所以"周期可预测"照样成立；把它写成"等于 delta"是**测试写错**。
        //
        // 两条采样序列（mtime 在 ISR 入口采、mtimecmp 在入口后 64 拍采）相差一个偏移，
        // 因此只能比较"**相邻差**是否落在同一个带里"，不能逐对相减：
        // 打开随机背压时那个偏移本身会变，逐对相减会假报错（实测 200014 vs 200018）。
        min_cmp_gap = 1 << 30; max_cmp_gap = 0;
        for (i = 1; i < cmp_idx; i = i + 1) begin
            gap = cmp_samples[i] - cmp_samples[i-1];
            if (gap < min_cmp_gap) min_cmp_gap = gap;
            if (gap > max_cmp_gap) max_cmp_gap = gap;
        end
        expect_true(max_cmp_gap <= DELTA + ISR_OVERHEAD_MAX && min_cmp_gap >= DELTA,
                    "N1: mtimecmp reload step is delta + bounded fixed overhead");
`ifndef TB_TIMER_DEMO_RANDOM
        expect_int(max_cmp_gap, min_cmp_gap, "N1: mtimecmp reload step is constant");
`endif

        // ---- B. 计数与比较寄存器都在动，高位被清过 ----
        expect_int(dut.timer.mtimecmp_hi_q, 0, "N1: mtimecmp_hi was cleared by software");
        expect_true(dut.timer.mtime_lo_q > 0, "N1: mtime advanced");

        // ---- C. LED：ISR 每次只翻转 bit0，其余位必须保持 0 ----
        led_bad = 0;
        led_expect = 1;
        for (i = 0; i < cap_led_idx; i = i + 1) begin
            if (cap_words[i][0] !== led_expect[0]) begin
                $display("       LED edge %0d bit0=%0d expected=%0d", i, cap_words[i][0], led_expect[0]);
                led_bad = led_bad + 1;
            end
            if (cap_words[i][7:1] !== 7'b0) begin
                $display("       LED edge %0d upper bits=%b expected=0", i, cap_words[i][7:1]);
                led_bad = led_bad + 1;
            end
            led_expect = ~led_expect;
        end
        expect_int(led_bad, 0, "N1: LED0 alternates 0/1 each interrupt, other LED bits stay 0");

        // ---- D. UART 输出：启动自检 '=' 之后每次中断 5 个字符 ----
        // 记录格式（见 software/timer_demo/start.S）：
        //   <计数低4位> <LED值低4位> <mtime[27:24]> <mtime[23:20]> <mtime[19:16]>
        expect_byte(cap_bytes[0], 8'h3D, "N1: boot self-check '=' sent over UART");
        expect_int(uart_bytes, 1 + RECORD_BYTES * isr_entries,
                  "N1: UART byte count = 1 + 5 per interrupt");
        uart_bad = 0;
        for (i = 0; i < isr_entries; i = i + 1) begin
            // 计数位：第 i+1 次中断 → 低 4 位十六进制字符（'1'..'9' 之后是 ':'..'?'）
            expect_val = 8'h30 + ((i + 1) & 15);
            if (cap_bytes[1 + RECORD_BYTES*i] !== expect_val[7:0]) begin
                $display("       UART count #%0d expected=%02h('%c') actual=%02h",
                         i, expect_val, expect_val, cap_bytes[1 + RECORD_BYTES*i]);
                uart_bad = uart_bad + 1;
            end
            // LED 位：第 i+1 次中断写出的 LED 值低 4 位 = bit0 = (i+1)&1，
            // 所以串口上第一个 LED 字符是 '1'（x13 从 0 翻成 1），之后 0/1 交替。
            led_expect = 8'h30 + ((i + 1) & 1);
            if (cap_bytes[2 + RECORD_BYTES*i] !== led_expect[7:0]) begin
                $display("       UART LED #%0d expected=%02h('%c') actual=%02h",
                         i, led_expect, led_expect, cap_bytes[2 + RECORD_BYTES*i]);
                uart_bad = uart_bad + 1;
            end
            // mtime 三位：必须都是十六进制字符（字符表 "0123456789=" 里的 0..9 与 a..f）。
            for (j = 0; j < 3; j = j + 1) begin
                expect_val = cap_bytes[3 + RECORD_BYTES*i + j];
                if (!((expect_val >= 8'h30 && expect_val <= 8'h39) ||
                      (expect_val >= 8'h61 && expect_val <= 8'h66) ||
                      (expect_val >= 8'h41 && expect_val <= 8'h46))) begin
                    $display("       UART mtime digit #%0d/%0d not hex: %02h (record starts at byte %0d)",
                             i, j, expect_val, 1 + RECORD_BYTES*i);
                    uart_bad = uart_bad + 1;
                end
            end
        end
        expect_int(uart_bad, 0, "N1: UART stream is '=' then (count, LED, mtime[27:16]) records");

        // ---- E. mret 真的回到了被打断的位置 ----
        expect_true(dut.core.fetch_pc === img_main_loop[31:0],
                    "N1: after the last mret the core is back in the main loop");
        expect_int(uart_errors, 0, "N1: no UART framing errors");

        if (failures == 0) $display("ALL TIMER DEMO BOARD TOP TEST PASS (interrupts=%0d, uart_bytes=%0d)",
                                    isr_entries, uart_bytes);
        else $fatal(1, "TIMER DEMO BOARD TOP %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #((DELTA + ISR_LENGTH_MAX) * (INTERRUPTS + 20) * CLK_HALF_NS * 2 + 200000);
        $fatal(1, "TIMER DEMO BOARD TOP TIMEOUT cycles=%0d isr=%0d edges=%0d bytes=%0d",
               cycles, isr_entries, led_edges, uart_bytes);
    end

`ifdef TIMER_DEMO_ILA_PROBE_SIM
    //=========================================================================
    // N2 金标准：板上 ILA **应该**抓到什么样的波形（先在这里固化下来）
    //
    // 【为什么加这一段】
    //   板级 ILA 抓到数据之后，必须能**机械地**判断"这次抓取合不合格"，
    //   而不是靠肉眼看波形。这里把判据固化成仿真输出：只要板上导出的波形
    //   在同样的观测量上呈现同样的模式，就算通过。
    //
    // 【读的是哪批信号】
    //   与 `fpga/timer_demo_ila` 那 192 位探针里接的**完全同一批**信号
    //   （`event_trap` / `event_trap_return` / `irq_timer` / 取指地址 ia / 提交 PC）。
    //   这里用**层级引用**读取（Icarus 支持；PDS/Logos 不支持层级引用，
    //   见 docs/debug_log.md 2026-09-30 条），所以本段**只用于仿真、不参与综合**。
    //
    // 【判据】
    //   C1 出现 `event_trap` 脉冲                     -> 打印 GOLD-TRAP
    //   C2 每次进入都跟一次 `event_trap_return`       -> 打印 GOLD-RET，末了计数配平
    //   C3 进入时 `irq_timer` 为高（原因 = 定时器中断）
    //   C4 进入后若干拍取指地址跳过陷入入口、返回后回到主程序区（打印窗口里可见）
    //   C5 相邻两次进入的间隔相等（周期性）
    //
    // 这一段默认**不生成**（未定义 TIMER_DEMO_ILA_PROBE_SIM 时完全不可见），
    // 所以既有的 N1 回归行为一字不变。
    integer gl_traps   = 0;
    integer gl_rets    = 0;
    integer gl_dump    = 0;
    integer gl_prev_t  = 0;
    integer gl_prev_gap= 0;
    integer gl_gap_ok  = 1;

    always @(posedge clk) begin
        if(dut.core.event_trap) begin
            gl_traps = gl_traps + 1;
            if(gl_traps > 2) begin
                if(($time - gl_prev_t) !== gl_prev_gap) gl_gap_ok = 0;
            end
            if(gl_traps > 1) gl_prev_gap = $time - gl_prev_t;
            $display("GOLD-TRAP #%0d t=%0t gap=%0d irq=%b fetch_pc=%08h ia=%08h",
                     gl_traps, $time, (gl_traps > 1) ? ($time - gl_prev_t) : 0,
                     dut.irq_timer, dut.core.fetch_pc, dut.ia);
            gl_prev_t = $time;
            if(gl_traps == 2) gl_dump = 24;      // 第 2 次进入开一个 24 拍窗口
        end
        if(dut.core.event_trap_return) begin
            gl_rets = gl_rets + 1;
            $display("GOLD-RET  #%0d t=%0t fetch_pc=%08h ia=%08h",
                     gl_rets, $time, dut.core.fetch_pc, dut.ia);
        end
        if(gl_dump > 0) begin
            $display("GOLD      t=%0t trap=%b ret=%b irq=%b ia=%08h fetch_pc=%08h",
                     $time, dut.core.event_trap, dut.core.event_trap_return,
                     dut.irq_timer, dut.ia, dut.core.fetch_pc);
            gl_dump = gl_dump - 1;
        end
        // 每次中断都打印一行计数，便于与板上抓到的条数对照
        if(dut.core.event_trap_return && gl_rets <= 3)
            $display("GOLD-COUNT traps=%0d rets=%0d gap_stable=%0d",
                     gl_traps, gl_rets, gl_gap_ok);
    end
`endif

endmodule
