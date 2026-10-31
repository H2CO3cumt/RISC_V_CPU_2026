`timescale 1ns/1ps
// M-14 验收：SoC 定时器 → irq_timer_i → 精确 Trap → ISR 重新装载 → 周期可预测。
//
// 这是"中断源在 SoC、Core 只接一根通用线"这条边界（docs/trap_contract.md §4.2）
// 的端到端验收：被测链路是
//   Core 的数据事务 → soc_data_interconnect（TARGET_TIMER）→ timer_mmio（mtime/mtimecmp）
//   → irq_timer → Core 的 irq_timer_i → WB 退休边界接受 Trap → mtvec → ISR → mret
//
// 程序（tb/data/timer_irq.mem，24 字，0x00～0x5C）：
//   0x00 addi x6, x0, 0       中断计数清零。**必须显式清零**：寄存器初值未定义，
//                             用 x6+1 计数会一直保持 X，比较结果也是 X，
//                             于是 bne 取“不跳”分支，程序会在第 1 次中断就收工。
//   0x04 addi x1, x0, 0x3C    建立 mtvec = ISR 入口
//   0x08 csrrw x0, mtvec, x1
//   0x0C lui  x2, 0x10003     x2 = 定时器基地址 0x1000_3000
//   0x10 addi x3, x0, 20      delta = 20 拍
//   0x14 addi x4, x0, 1
//   0x18 slli x4, x4, 7       x4 = 128 = mie.MTIE
//   0x1C csrrs x0, mie, x4    打开定时器中断使能
//   0x20 sw   x0, 12(x2)      **mtimecmp_hi 必须清零**：复位值是全 1（保证复位后无中断），
//                             只写低 32 位的话 mtime < mtimecmp 恒成立，中断永远不来。
//   0x24 lw   x5, 0(x2)       读 mtime
//   0x28 add  x5, x5, x3      + delta
//   0x2C sw   x5, 8(x2)       写 mtimecmp_lo（第一次装载）
//   0x30 csrrsi x0, mstatus, 8  打开 mstatus.MIE
//   0x34/0x38 jal x0,0       自跳转占位：无论 mret 回到哪一条都停在原地
//   0x3C addi x6, x6, 1       ISR：中断计数
//   0x40 lw   x5, 0(x2)       读当前 mtime
//   0x44 add  x5, x5, x3
//   0x48 sw   x5, 8(x2)       **重新装载**——不做这一步只会中断一次
//   0x4C addi x8, x0, 3
//   0x50 bne  x6, x8, 12      未到 3 次 → 直接 mret
//   0x54 addi x7, x0, 0x555   第 3 次：写完成标记
//   0x58 csrrc x0, mie, x4    关掉 MTIE，停止后续中断
//   0x5C mret
//// 断言（全部自动判定）：
//   1. 恰好 3 次 Trap，且每次 mcause 都是 0x80000007（机器定时器中断）；
//   2. 第 2、3 次中断的间隔**完全相等**（周期可预测），且落在 [delta, delta+16] 内；
//   3. ISR 真的执行了 3 次（x6==3）并写出完成标记（x7==0x555）；
//   4. 关掉 MTIE 之后再等 200 拍不会出现第 4 次 Trap（不重复响应）；
//   5. irq_timer 是电平信号：ISR 重新装载之后必须自动落下（不需要“清中断”寄存器）。
module tb_timer_irq;

    reg clk = 1'b0;
    reg reset = 1'b1;

    wire        iv, ir, rv, rr, ie, dv, dr, dw, dsv, dsr, de;
    wire [31:0] ia, idata, da, dwd, drd;
    wire [3:0]  dst;

    wire        timer_v, timer_r, timer_sv, timer_sr, timer_se;
    wire [31:0] timer_rd;
    wire [31:0] ta, twd, ram_rd;
    wire        tw, ram_v, ram_r, ram_sv, ram_sr, ram_se;
    wire [3:0]  tws;
    wire        irq_timer;

    integer failures = 0, test_no = 0, cycles = 0;
    integer n_trap = 0, n_trap_at_marker = 0, wait_guard = 0;
    integer trap_cycle0 = 0, trap_cycle1 = 0, trap_cycle2 = 0;
    reg [31:0] cause0 = 0, cause1 = 0, cause2 = 0;
    integer irq_high_cycles = 0;
    reg        marker_seen = 1'b0;

    pipeline_cpu core(
        .clk(clk), .reset(reset),
        .trace_valid(), .trace_pc(), .trace_instruction(),
        .trace_rd_we(), .trace_rd_addr(), .trace_rd_data(),
        .trace_mem_we(), .trace_mem_addr(), .trace_mem_data(),
        .trace_mem_wstrb(), .trace_error(),
        .i_req_valid(iv), .i_req_ready(ir), .i_req_addr(ia),
        .i_rsp_valid(rv), .i_rsp_ready(rr), .i_rsp_data(idata), .i_rsp_error(ie),
        .d_req_valid(dv), .d_req_ready(dr), .d_req_addr(da), .d_req_write(dw),
        .d_req_wdata(dwd), .d_req_wstrb(dst),
        .d_rsp_valid(dsv), .d_rsp_ready(dsr), .d_rsp_rdata(drd), .d_rsp_error(de),
        // 只有定时器这一根中断线被真正驱动；另外两根显式接 0。
        .irq_software_i(1'b0), .irq_timer_i(irq_timer), .irq_external_i(1'b0),
        .event_stall(), .event_load_stall(), .event_branch(), .event_branch_taken(),
        .event_flush(), .event_predict(), .event_btb_hit(), .event_mispredict(),
        .event_control_redirect(), .event_trap(), .event_trap_return(),
        .event_illegal(), .event_misaligned(), .event_bus_error());

    // 程序区之外填自跳转：程序停住之后不会取到未初始化字而误陷入。
    pipeline_imem_adapter #(.DEPTH(24), .INIT_FILE("tb/data/timer_irq.mem"),
                            .RANDOM_DELAY(0), .FILL_WORD(32'h0000_006f)) im(
        .clk(clk), .reset(reset), .req_valid(iv), .req_ready(ir), .req_addr(ia),
        .rsp_valid(rv), .rsp_ready(rr), .rsp_data(idata), .rsp_error(ie));

    soc_data_interconnect #(.RAM_LAST_ADDR(32'h0000_00FF)) xbar(
        .clk(clk), .reset(reset),
        .cpu_req_valid(dv), .cpu_req_ready(dr), .cpu_req_addr(da), .cpu_req_write(dw),
        .cpu_req_wdata(dwd), .cpu_req_wstrb(dst),
        .cpu_rsp_valid(dsv), .cpu_rsp_ready(dsr), .cpu_rsp_rdata(drd), .cpu_rsp_error(de),
        .ram_req_valid(ram_v), .ram_req_ready(ram_r),
        .uart_req_valid(), .uart_req_ready(1'b0),
        .gpio_req_valid(), .gpio_req_ready(1'b0),
        .app_req_valid(), .app_req_ready(1'b0),
        .timer_req_valid(timer_v), .timer_req_ready(timer_r),
        .target_req_addr(ta), .target_req_write(tw), .target_req_wdata(twd), .target_req_wstrb(tws),
        .ram_rsp_valid(ram_sv), .ram_rsp_ready(ram_sr), .ram_rsp_rdata(ram_rd), .ram_rsp_error(ram_se),
        .uart_rsp_valid(1'b0), .uart_rsp_ready(), .uart_rsp_rdata(32'b0), .uart_rsp_error(1'b0),
        .gpio_rsp_valid(1'b0), .gpio_rsp_ready(), .gpio_rsp_rdata(32'b0), .gpio_rsp_error(1'b0),
        .app_rsp_valid(1'b0), .app_rsp_ready(), .app_rsp_rdata(32'b0), .app_rsp_error(1'b0),
        .timer_rsp_valid(timer_sv), .timer_rsp_ready(timer_sr),
        .timer_rsp_rdata(timer_rd), .timer_rsp_error(timer_se));

    timer_mmio timer(
        .clk(clk), .reset(reset),
        .timer_req_valid(timer_v), .timer_req_ready(timer_r), .timer_req_addr(ta),
        .timer_req_write(tw), .timer_req_wdata(twd), .timer_req_wstrb(tws),
        .timer_rsp_valid(timer_sv), .timer_rsp_ready(timer_sr),
        .timer_rsp_rdata(timer_rd), .timer_rsp_error(timer_se),
        .irq_timer(irq_timer));

    ram_adapter #(.DEPTH(64), .RANDOM_DELAY(0)) ram(
        .clk(clk), .reset(reset), .req_valid(ram_v), .req_ready(ram_r), .req_addr(ta),
        .req_write(tw), .req_wdata(twd), .req_wstrb(tws),
        .rsp_valid(ram_sv), .rsp_ready(ram_sr), .rsp_rdata(ram_rd), .rsp_error(ram_se),
        .write_side_effect_count());

    // ram 端口由互连驱动（本程序不访问 RAM，但端口必须接全，避免悬空）。


    always #5 clk = ~clk;

    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (irq_timer) irq_high_cycles = irq_high_cycles + 1;
        if (core.trap_take) begin
            n_trap = n_trap + 1;
            if (n_trap == 1) begin trap_cycle0 = cycles; cause0 = core.trap_cause_value; end
            if (n_trap == 2) begin trap_cycle1 = cycles; cause1 = core.trap_cause_value; end
            if (n_trap == 3) begin trap_cycle2 = cycles; cause2 = core.trap_cause_value; end
        end
        if (core.rf.regs[7] == 32'h0000_0555) begin
            if (!marker_seen) begin marker_seen = 1'b1; n_trap_at_marker = n_trap; end
        end
    end

    task expect_int;
        input integer actual;
        input integer expected;
        input [8*52-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected) $display("TEST %0d PASS %0s (%0d)", test_no, name, actual);
            else begin
                $display("TEST %0d FAIL %0s expected=%0d actual=%0d", test_no, name, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*52-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected) $display("TEST %0d PASS %0s", test_no, name);
            else begin
                $display("TEST %0d FAIL %0s expected=%08h actual=%08h", test_no, name, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    integer gap1, gap2;

    initial begin
        $display("=== M-14 SoC 定时器中断端到端验收 ===");
        repeat (2) @(negedge clk);
        reset = 1'b0;

        // 等 ISR 写出完成标记（3 次中断都处理完），带周期守卫。
        wait_guard = 0;
        while (!marker_seen && wait_guard < 4000) begin
            @(negedge clk);
            wait_guard = wait_guard + 1;
        end
        // 再多等一段：确认关掉 MTIE 之后不会有第 4 次中断。
        repeat (200) @(negedge clk);

        expect_int(n_trap, 3, "M-14: exactly three timer interrupts");
        expect_word(cause0, 32'h8000_0007, "M-14: 1st mcause = machine timer interrupt");
        expect_word(cause1, 32'h8000_0007, "M-14: 2nd mcause = machine timer interrupt");
        expect_word(cause2, 32'h8000_0007, "M-14: 3rd mcause = machine timer interrupt");
        expect_word(core.rf.regs[6], 32'd3, "M-14: ISR ran exactly three times");
        expect_word(core.rf.regs[7], 32'h0000_0555, "M-14: ISR completion marker written");
        expect_int(n_trap_at_marker, 3, "M-14: no interrupt pending when the marker was written");

        gap1 = trap_cycle1 - trap_cycle0;
        gap2 = trap_cycle2 - trap_cycle1;
        expect_int(gap2, gap1, "M-14: interrupt period is exactly reproducible");
        test_no = test_no + 1;
        if (gap1 >= 20 && gap1 <= 36) $display("TEST %0d PASS M-14: period is delta + fixed overhead (%0d)", test_no, gap1);
        else begin
            $display("TEST %0d FAIL M-14: period out of range got=%0d", test_no, gap1);
            failures = failures + 1;
        end

        test_no = test_no + 1;
        if (irq_high_cycles > 0 && irq_high_cycles < cycles)
            $display("TEST %0d PASS M-14: irq_timer is a level that clears when ISR re-arms", test_no);
        else begin
            $display("TEST %0d FAIL M-14: irq_timer level behaviour wrong high=%0d cycles=%0d",
                     test_no, irq_high_cycles, cycles);
            failures = failures + 1;
        end

        test_no = test_no + 1;
        if (timer.mtimecmp_lo_q > 32'd20 && timer.mtime_lo_q > timer.mtimecmp_lo_q - 32'd40)
            $display("TEST %0d PASS M-14: mtime/mtimecmp advanced (mtime=%0d cmp=%0d)",
                     test_no, timer.mtime_lo_q, timer.mtimecmp_lo_q);
        else begin
            $display("TEST %0d FAIL M-14: timer registers did not advance mtime=%0d cmp=%0d",
                     test_no, timer.mtime_lo_q, timer.mtimecmp_lo_q);
            failures = failures + 1;
        end

        if (failures == 0) $display("ALL TIMER INTERRUPT TEST PASS");
        else $fatal(1, "TIMER INTERRUPT %0d TESTS FAIL", failures);
        $finish;
    end

    initial begin
        #4000000;
        $fatal(1, "TIMER INTERRUPT TIMEOUT at cycle %0d n_trap=%0d marker=%b", cycles, n_trap, marker_seen);
    end

endmodule
