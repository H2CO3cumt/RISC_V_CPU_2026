`timescale 1ns/1ps
// csr_unit 独立 Testbench —— 对应 docs/trap_contract.md §6 的 M-01/M-02/M-03/M-20。
// 只测 CSR 单元本身：复位初值、位域掩码、只读/未实现地址的非法判定、
// Trap 进入与 MRET 返回的 mstatus 语义、minstret 计数。
// 上层流水线的精确性（精确提交、取消年轻指令）由流水线级 TB 覆盖，不在这里重复。
module tb_csr_unit;
    reg clk = 1'b0;
    reg reset = 1'b1;

    reg  [11:0] csr_addr = 12'b0;
    wire [31:0] csr_rdata;
    reg         csr_we = 1'b0;
    reg  [11:0] csr_waddr = 12'b0;
    reg  [31:0] csr_wdata = 32'b0;

    reg         csr_check_en = 1'b0;
    reg  [11:0] csr_check_addr = 12'b0;
    reg         csr_check_write = 1'b0;
    wire        csr_illegal;

    reg         trap_enter = 1'b0;
    reg  [31:0] trap_cause = 32'b0;
    reg  [31:0] trap_value = 32'b0;
    reg  [31:0] epc_next = 32'b0;
    reg         trap_return = 1'b0;

    reg         irq_sw_pending = 1'b0;
    reg         irq_timer_pending = 1'b0;
    reg         irq_ext_pending = 1'b0;

    reg         retire = 1'b0;

    wire        mstatus_mie;
    wire        mie_mtie;
    wire        mie_meie;
    wire        mie_msie;
    wire [31:0] mtvec_base;
    wire [31:0] epc_out;

    integer failures = 0;
    integer test_no = 0;
    reg [63:0] retires_before;

    csr_unit dut(
        .clk(clk), .reset(reset),
        .csr_addr(csr_addr), .csr_rdata(csr_rdata),
        .csr_we(csr_we), .csr_waddr(csr_waddr), .csr_wdata(csr_wdata),
        .csr_check_en(csr_check_en), .csr_check_addr(csr_check_addr),
        .csr_check_write(csr_check_write), .csr_illegal(csr_illegal),
        .trap_enter(trap_enter), .trap_cause(trap_cause), .trap_value(trap_value),
        .epc_next(epc_next), .trap_return(trap_return),
        .irq_sw_pending(irq_sw_pending), .irq_timer_pending(irq_timer_pending),
        .irq_ext_pending(irq_ext_pending), .retire(retire),
        .mstatus_mie(mstatus_mie), .mie_mtie(mie_mtie), .mie_meie(mie_meie),
        .mie_msie(mie_msie), .mtvec_base(mtvec_base), .epc_out(epc_out)
    );

    always #5 clk = ~clk;

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*32-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected) begin
                $display("TEST %0d PASS %0s", test_no, name);
            end
            else begin
                $display("TEST %0d FAIL %0s expected=%08h actual=%08h",
                         test_no, name, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task expect_bit;
        input actual;
        input expected;
        input [8*32-1:0] name;
        begin
            test_no = test_no + 1;
            if (actual === expected) begin
                $display("TEST %0d PASS %0s", test_no, name);
            end
            else begin
                $display("TEST %0d FAIL %0s expected=%b actual=%b",
                         test_no, name, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task csr_write;
        input [11:0] addr;
        input [31:0] value;
        begin
            @(negedge clk);
            csr_we = 1'b1;
            csr_waddr = addr;
            csr_wdata = value;
            @(posedge clk);
            #1;
            csr_we = 1'b0;
        end
    endtask

    task csr_read_check;        input [11:0] addr;
        input [31:0] expected;
        input [8*32-1:0] name;
        begin
            csr_addr = addr;
            #1;
            expect_word(csr_rdata, expected, name);
        end
    endtask

    task check_illegal;
        input [11:0] addr;
        input write_access;
        input expected;
        input [8*32-1:0] name;
        begin
            csr_check_en = 1'b1;
            csr_check_addr = addr;
            csr_check_write = write_access;
            #1;
            expect_bit(csr_illegal, expected, name);
            csr_check_en = 1'b0;
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);

        // ---- M-02：复位初值与位域掩码 ----
        csr_read_check(12'h300, 32'h0000_0000, "mstatus reset value");
        csr_read_check(12'h301, 32'h4000_0100, "misa reports RV32I");
        csr_read_check(12'h305, 32'h0000_0000, "mtvec reset value");

        csr_write(12'h300, 32'hffff_ffff);
        csr_read_check(12'h300, 32'h0000_0088, "mstatus keeps MIE/MPIE only");
        expect_bit(mstatus_mie, 1'b1, "mstatus.MIE reflected");

        csr_write(12'h304, 32'hffff_ffff);
        csr_read_check(12'h304, 32'h0000_0888, "mie keeps MSIE/MTIE/MEIE only");
        expect_bit(mie_msie, 1'b1, "mie.MSIE reflected");
        expect_bit(mie_mtie, 1'b1, "mie.MTIE reflected");
        expect_bit(mie_meie, 1'b1, "mie.MEIE reflected");

        // mtvec 只支持 Direct：写入 mode=11 必须被强制成 00。
        csr_write(12'h305, 32'h0000_1003);
        csr_read_check(12'h305, 32'h0000_1000, "mtvec forces direct mode");
        expect_word(mtvec_base, 32'h0000_1000, "mtvec base output");

        // mepc bit0 恒 0（无 C 扩展）。
        csr_write(12'h341, 32'h0000_2003);
        csr_read_check(12'h341, 32'h0000_2002, "mepc clears bit0");

        csr_write(12'h340, 32'h1234_5678);
        csr_read_check(12'h340, 32'h1234_5678, "mscratch full width");

        // mip 是只读窗口，直接反映输入电平。
        irq_sw_pending = 1'b1;
        irq_timer_pending = 1'b1;
        irq_ext_pending = 1'b1;
        csr_read_check(12'h344, 32'h0000_0888, "mip reflects pending inputs");
        irq_sw_pending = 1'b0;
        irq_timer_pending = 1'b0;
        irq_ext_pending = 1'b0;
        csr_read_check(12'h344, 32'h0000_0000, "mip follows inputs low");

        // ---- M-03：只读与未实现地址 ----
        check_illegal(12'h301, 1'b1, 1'b1, "write misa is illegal");
        check_illegal(12'h301, 1'b0, 1'b0, "read misa is legal");
        check_illegal(12'h344, 1'b1, 1'b1, "write mip is illegal");
        check_illegal(12'hC00, 1'b1, 1'b1, "write cycle is illegal");
        check_illegal(12'h3B0, 1'b0, 1'b1, "read pmpcfg0 is illegal");
        check_illegal(12'h7C0, 1'b1, 1'b1, "write unknown csr is illegal");
        check_illegal(12'hF14, 1'b0, 1'b1, "read mhartid is illegal");
        check_illegal(12'h300, 1'b1, 1'b0, "write mstatus is legal");

        // ---- M-01 的边界：非法判定不能影响已有状态 ----
        csr_write(12'h340, 32'hAAAA_5555);
        csr_check_en = 1'b1;
        csr_check_addr = 12'h3B0;
        csr_check_write = 1'b1;
        #1;
        csr_check_en = 1'b0;
        #1;
        csr_read_check(12'h340, 32'hAAAA_5555, "illegal access leaves state");

        // ---- Trap 进入 / MRET 返回的 mstatus 语义 ----
        // 先打开 MIE，再进入 Trap：MIE 必须清 0、MPIE 记下旧 MIE。
        csr_write(12'h300, 32'h0000_0008);
        @(negedge clk);
        trap_enter = 1'b1;
        trap_cause = 32'h0000_000B;
        trap_value = 32'h0000_0044;
        epc_next   = 32'h0000_0100;
        @(posedge clk);
        #1;
        trap_enter = 1'b0;
        csr_read_check(12'h341, 32'h0000_0100, "trap saves epc");
        csr_read_check(12'h342, 32'h0000_000B, "trap saves mcause");
        csr_read_check(12'h343, 32'h0000_0044, "trap saves mtval");
        csr_read_check(12'h300, 32'h0000_0080, "trap clears MIE and sets MPIE");
        csr_read_check(12'h344, 32'h0000_0000, "mip untouched by trap");

        // MRET：MIE <- MPIE，MPIE <- 1。
        @(negedge clk);
        trap_return = 1'b1;
        @(posedge clk);
        #1;
        trap_return = 1'b0;
        csr_read_check(12'h300, 32'h0000_0088, "mret restores MIE and sets MPIE");

        // ---- M-20：mcycle / minstret ----
        csr_read_check(12'hC00, dut.mcycle_q[31:0], "cycle low matches model");
        retires_before = dut.minstret_q;
        repeat (4) begin
            @(negedge clk);
            retire = 1'b1;
            @(posedge clk);
            #1;
            retire = 1'b0;
        end
        expect_word(dut.minstret_q - retires_before, 32'd4, "minstret counts 4 retires");

        if (failures == 0) begin
            $display("ALL CSR UNIT TEST PASS");
        end
        else begin
            $fatal(1, "CSR UNIT %0d TESTS FAIL", failures);
        end
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "CSR UNIT TIMEOUT");
    end
endmodule
