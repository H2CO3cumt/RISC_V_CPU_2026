// ============================================================================
// ModelSim / PDS 联合仿真专用 Testbench
// ----------------------------------------------------------------------------
// 用途：在 PDS 2024.2-SP2 里对工程执行「Behavior Simulation」时，PDS 会自动
//       调用 ModelSim 编译本文件与被测顶层 mes50hp_logic_analyzer_top，并把
//       ModelSim 的波形窗口直接打开（工程内的 wgt_simulation 已配置好 target
//       与 sim_exe_dir，不需要用户手工设置任何东西）。
//
// 与 tb/tb_logic_analyzer_board_top.v 的三点区别，都是为「在 PDS 里直接出波形」
// 服务的：
//   1) 时钟按真实板级 50 MHz（20 ns 周期）产生，UART 用真实 115200 分频，
//      波形时间轴与实体板一致，不需要换算；
//   2) PDS 会把仿真工作目录切到 <工程>/sim/behav，此时 RTL 里
//      $readmemh("rtl/program.mem") 的相对路径必然找不到文件。所以本文件不依赖
//      它，而是用候选路径列表自己把程序镜像搬进 IMEM/DMEM（见 load_image）；
//   3) 结束时用 $stop 而不是 $finish/$fatal。PDS 是通过 run_behav.bat 启动 modelsim.exe 的，
//      stdio 被重定向，此时 $finish 会让 ModelSim 直接退出、波形窗口看不到；$stop 则把仿真
//      停在断点并回到提示符，波形窗口保持打开，用户可以直接量时间、加信号。
//
// 命令序列与 tb_logic_analyzer_board_top.v 完全一致（J8 回环验收用的那一帧）：
//   A5, mode=static, data=1, dividers=0, level trigger bit0=1, pre/post=4, xor=A4
// ============================================================================
`timescale 1ns/1ps

module tb_msim_logic_analyzer_top;

    // 真实板级参数：P20 = 50 MHz；CP2102 串口 = 115200。
    localparam CLK_HALF_NS  = 10;                     // 半周期 10 ns -> 50 MHz
    localparam BAUD_CYCLES  = 50_000_000 / 115200;    // 一个 UART 位 = 434 个时钟
    localparam DEPTH        = 1024;                   // IMEM/DMEM 深度，与 program_memory.v 一致

    reg        clk_50m = 1'b0;
    reg        uart_rx = 1'b1;
    reg  [7:0] capture_ch = 8'h00;
    wire       uart_tx;
    wire [7:0] led;
    wire [7:0] loopback_tx;

    // 被观察的 UART 输出：直接复用 RTL 里的 UART_RX，参数与 DUT 内部一致。
    wire [7:0] rx_byte;
    wire       rx_vld;
    wire       rx_err;

    integer rx_bytes = 0;
    integer rx_errors = 0;
    integer cycles = 0;
    integer mirror_errors = 0;

    // 50 MHz 板级时钟。
    always #CLK_HALF_NS clk_50m = ~clk_50m;

    mes50hp_logic_analyzer_top dut (
        .clk_50m(clk_50m),
        .uart0_rx(uart_rx),
        .uart0_tx(uart_tx),
        .led(led),
        .capture_ch(capture_ch),
        .loopback_tx(loopback_tx)
    );

    UART_RX #(.MAX_1BAUD(BAUD_CYCLES)) mon (
        .clk_50m(clk_50m),
        .rst(dut.reset),
        .rx(uart_tx),
        .rx_data(rx_byte),
        .rx_data_vld(rx_vld),
        .rx_frame_error(rx_err)
    );

    // ------------------------------------------------------------------
    // 程序镜像加载
    // ------------------------------------------------------------------
    // 为什么不用 $readmemh：ModelSim 的 $readmemh 只按“进程当前目录”解析相对
    // 路径，而 PDS 生成 run_behav.bat 时会先 cd 到 <工程>/sim/behav。工程里
    // program_memory.v 的 "rtl/program.mem" 在那个目录下并不存在，只会打印一条
    // vsim-7 警告并让存储体保持 X。这里改用 $fopen + $fscanf 逐个试探候选路径，
    // 命中后直接写进 DUT 的 imem/dmem 存储体，因此无论 PDS 从哪个目录启动都能跑。
    reg [8*128-1:0] image_path;
    reg [31:0]      image_word;
    reg             image_loaded = 1'b0;
    integer         fd;
    integer         word_index;
    integer         total_words;

    task load_image;
        input [8*128-1:0] candidate;
        begin
            fd = $fopen(candidate, "r");
            if (fd != 0) begin
                word_index = 0;
                total_words = 0;
                while ($fscanf(fd, "%h", image_word) == 1) begin
                    if (word_index < DEPTH) begin
                        // imem/dmem 都是 1 KiB 镜像的同一份拷贝，与实体板加载方式一致。
                        dut.imem.mem[word_index] = image_word;
                        dut.dmem.mem[word_index] = image_word;
                    end
                    word_index = word_index + 1;
                    total_words = total_words + 1;
                end
                $fclose(fd);
                image_loaded = 1'b1;
                $display("[MSIM-TB] program image loaded from %0s (%0d words)", candidate, total_words);
            end
        end
    endtask

    initial begin
        // 候选顺序按“PDS 仿真目录”优先，其次才是从工程目录直接跑的情况。
        // 发布包用 rtl/program.mem，开发工程用 rtl/logic_analyzer_program.mem。
        load_image("../../rtl/program.mem");
        if (!image_loaded) load_image("../../rtl/logic_analyzer_program.mem");
        if (!image_loaded) load_image("rtl/program.mem");
        if (!image_loaded) load_image("rtl/logic_analyzer_program.mem");
        if (!image_loaded)
            $display("[MSIM-TB] WARNING: program image not found, CPU will not boot (cwd is not the project dir)");
    end

    // ------------------------------------------------------------------
    // 逻辑分析仪 8 通道激励
    // ------------------------------------------------------------------
    // 触发前把通道压平，触发后给出会跳变的计数，这样波形上能一眼看出触发点。
    reg [7:0] pattern = 8'h00;
    always @(posedge clk_50m) begin
        if (!dut.reset) begin
            pattern <= pattern + 8'h01;
            if (dut.analyzer.cap.armed && dut.analyzer.cap.capture_count < 3)
                capture_ch <= 8'h00;
            else
                capture_ch <= pattern;
        end else begin
            capture_ch <= 8'h00;
        end
    end

    // ------------------------------------------------------------------
    // 主机侧 UART 发送（一位 434 个时钟，与实体板相同）
    // ------------------------------------------------------------------
    task uart_send_byte;
        input [7:0] value;
        integer bit_index;
        begin
            @(negedge clk_50m); uart_rx = 1'b0; repeat (BAUD_CYCLES) @(posedge clk_50m);   // start
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                @(negedge clk_50m); uart_rx = value[bit_index]; repeat (BAUD_CYCLES) @(posedge clk_50m);
            end
            @(negedge clk_50m); uart_rx = 1'b1; repeat (BAUD_CYCLES) @(posedge clk_50m);   // stop
        end
    endtask

    always @(posedge clk_50m) begin
        if (!dut.reset) begin
            cycles = cycles + 1;
            if (rx_vld) rx_bytes = rx_bytes + 1;
            if (rx_err) rx_errors = rx_errors + 1;
            // ch7 必须每拍都镜像 uart0_rx（组合直连）：整包 13 字节传输期间持续检查，
            // 这样"上位机发什么、J8-31 就出什么"才是被证明的，而不是某一拍碰巧对上。
            if (loopback_tx[7] !== uart_rx) mirror_errors = mirror_errors + 1;
        end
    end

    initial begin
        // 固件上电后会先吐一帧状态，收到 10 个字节后再下发命令。
        wait (!dut.reset);
        wait (rx_bytes >= 10);
        repeat (20) @(posedge clk_50m);
        uart_send_byte(8'hA5); uart_send_byte(8'h00); uart_send_byte(8'h01);
        uart_send_byte(8'h00); uart_send_byte(8'h00); uart_send_byte(8'h00);
        uart_send_byte(8'h00); uart_send_byte(8'h00); uart_send_byte(8'h01);
        uart_send_byte(8'h01); uart_send_byte(8'h04); uart_send_byte(8'h04);
        uart_send_byte(8'hA4);
        $display("[MSIM-TB] 13-byte capture command sent at %0t", $time);
    end

    // ------------------------------------------------------------------
    // 自检：抓到 9 个样点、触发点在 index=4、LED=0x5A、回环输出=0x01
    // ------------------------------------------------------------------
    integer failures = 0;
    initial begin
        while ((rx_bytes < 13 || !dut.analyzer.cap.done) && cycles < 400000)
            @(posedge clk_50m);
        repeat (10) @(posedge clk_50m);

        if (cycles >= 400000) begin
            $display("[MSIM-TB] FAIL timeout cycles=%0d bytes=%0d", cycles, rx_bytes);
            failures = failures + 1;
        end
        if (led !== 8'h5A || loopback_tx[6:0] !== 7'h01 || loopback_tx[7] !== uart_rx) begin
            $display("[MSIM-TB] FAIL output led=%h loopback=%h uart_rx=%b", led, loopback_tx, uart_rx);
            failures = failures + 1;
        end else begin
            $display("[MSIM-TB] PASS mirror loopback=%h (ch7=uart_rx)", loopback_tx);
        end
        if (mirror_errors != 0) begin
            $display("[MSIM-TB] FAIL mirror mismatched cycles=%0d", mirror_errors);
            failures = failures + 1;
        end
        if (rx_errors != 0) begin
            $display("[MSIM-TB] FAIL uart frame errors=%0d", rx_errors);
            failures = failures + 1;
        end
        if (rx_bytes < 13) begin
            $display("[MSIM-TB] FAIL uart bytes=%0d", rx_bytes);
            failures = failures + 1;
        end else begin
            $display("[MSIM-TB] PASS uart bytes=%0d", rx_bytes);
        end
        if (dut.analyzer.cap.done && dut.analyzer.cap.triggered &&
            dut.analyzer.cap.capture_count == 9 && dut.analyzer.cap.trigger_index == 4)
            $display("[MSIM-TB] PASS capture count=%0d index=%0d", dut.analyzer.cap.capture_count, dut.analyzer.cap.trigger_index);
        else begin
            $display("[MSIM-TB] FAIL capture count=%0d index=%0d done=%b",
                     dut.analyzer.cap.capture_count, dut.analyzer.cap.trigger_index, dut.analyzer.cap.done);
            failures = failures + 1;
        end

        if (failures == 0) $display("ALL MSIM LOGIC ANALYZER TOP TEST PASS");
        else               $display("MSIM LOGIC ANALYZER TOP %0d FAIL", failures);

        // 用 $stop 而不是 $finish 收尾：ModelSim 会把仿真停在断点并回到提示符，
        // 波形窗口保持打开，用户可以直接在窗口里量时间、加信号；
        // 若用 $finish，PDS 这条启动链（bat + 重定向 stdio）会让 ModelSim 直接退出。
        $display("[MSIM-TB] simulation stopped at %0t (waveform window stays open)", $time);
        $stop;
    end

    // 兜底超时：默认分频下 13 字节命令约 1.2 ms，这里给到 8 ms。
    initial #8000000 begin
        $display("[MSIM-TB] FAIL hard timeout at %0t cycles=%0d bytes=%0d", $time, cycles, rx_bytes);
        $stop;
    end

endmodule
