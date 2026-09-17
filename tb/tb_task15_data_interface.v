`timescale 1ns/1ps

module tb_task15_data_interface;
    reg clk;
    reg reset;
    integer failures;
    integer cycle_count;
    integer wait_cycles;
    integer instruction_wait_cycles;
    reg     holding_request;
    reg     holding_instruction_request;
    reg [31:0] held_addr;
    reg        held_write;
    reg [31:0] held_wdata;
    reg [3:0]  held_wstrb;
    reg [31:0] held_i_addr;

    wire        d_req_valid;
    wire        d_req_ready;
    wire [31:0] d_req_addr;
    wire        d_req_write;
    wire [31:0] d_req_wdata;
    wire [3:0]  d_req_wstrb;
    wire        d_rsp_valid;
    wire        d_rsp_ready;
    wire [31:0] d_rsp_rdata;
    wire        d_rsp_error;
    wire        i_req_valid;
    wire        i_req_ready;
    wire [31:0] i_req_addr;
    wire        i_rsp_valid;
    wire        i_rsp_ready;
    wire [31:0] i_rsp_data;
    wire        i_rsp_error;

    single_cycle_cpu #(
        .IMEM_DEPTH(12),
        .IMEM_INIT_FILE("tb/data/task11_single_cycle.mem")
    ) dut (
        .clk(clk),
        .reset(reset),
        .d_req_valid(d_req_valid),
        .d_req_ready(d_req_ready),
        .d_req_addr(d_req_addr),
        .d_req_write(d_req_write),
        .d_req_wdata(d_req_wdata),
        .d_req_wstrb(d_req_wstrb),
        .d_rsp_valid(d_rsp_valid),
        .d_rsp_ready(d_rsp_ready),
        .d_rsp_rdata(d_rsp_rdata),
        .d_rsp_error(d_rsp_error),
        .i_req_valid(i_req_valid), .i_req_ready(i_req_ready), .i_req_addr(i_req_addr),
        .i_rsp_valid(i_rsp_valid), .i_rsp_ready(i_rsp_ready), .i_rsp_data(i_rsp_data), .i_rsp_error(i_rsp_error)
    );

    task15_imem_adapter #(
        .DEPTH(12), .INIT_FILE("tb/data/task11_single_cycle.mem")
    ) imem (
        .clk(clk), .reset(reset), .req_valid(i_req_valid), .req_ready(i_req_ready), .req_addr(i_req_addr),
        .rsp_valid(i_rsp_valid), .rsp_ready(i_rsp_ready), .rsp_data(i_rsp_data), .rsp_error(i_rsp_error)
    );

    task15_ram_adapter #(.DEPTH(256)) ram (
        .clk(clk), .reset(reset),
        .req_valid(d_req_valid), .req_ready(d_req_ready),
        .req_addr(d_req_addr), .req_write(d_req_write),
        .req_wdata(d_req_wdata), .req_wstrb(d_req_wstrb),
        .rsp_valid(d_rsp_valid), .rsp_ready(d_rsp_ready),
        .rsp_rdata(d_rsp_rdata), .rsp_error(d_rsp_error)
    );

    always #5 clk = ~clk;

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input integer test_number;
        begin
            if (actual === expected)
                $display("TEST %0d PASS", test_number);
            else begin
                $display("TEST %0d FAIL: expected=%h actual=%h", test_number, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    // While valid is high and ready is low, the Core must keep all request
    // fields unchanged.  This catches a common backpressure/MMIO bug.
    always @(posedge clk) begin
        if (reset) begin
            holding_request <= 1'b0;
            wait_cycles     <= 0;
        end
        else if (d_req_valid && !d_req_ready) begin
            wait_cycles <= wait_cycles + 1;
            if (holding_request) begin
                if ((d_req_addr  !== held_addr)  ||
                    (d_req_write !== held_write) ||
                    (d_req_wdata !== held_wdata) ||
                    (d_req_wstrb !== held_wstrb)) begin
                    $display("REQUEST STABILITY FAIL");
                    failures <= failures + 1;
                end
            end
            else begin
                holding_request <= 1'b1;
                held_addr  <= d_req_addr;
                held_write <= d_req_write;
                held_wdata <= d_req_wdata;
                held_wstrb <= d_req_wstrb;
            end
        end
        else begin
            holding_request <= 1'b0;
        end
    end

    // IF_REQ follows the same valid/ready rule: the requested PC cannot
    // change while the instruction adapter applies backpressure.
    always @(posedge clk) begin
        if (reset) begin
            holding_instruction_request <= 1'b0;
            instruction_wait_cycles     <= 0;
        end
        else if (i_req_valid && !i_req_ready) begin
            instruction_wait_cycles <= instruction_wait_cycles + 1;
            if (holding_instruction_request) begin
                if (i_req_addr !== held_i_addr) begin
                    $display("INSTRUCTION REQUEST STABILITY FAIL");
                    failures <= failures + 1;
                end
            end
            else begin
                holding_instruction_request <= 1'b1;
                held_i_addr <= i_req_addr;
            end
        end
        else begin
            holding_instruction_request <= 1'b0;
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failures = 0;
        cycle_count = 0;
        wait_cycles = 0;
        instruction_wait_cycles = 0;
        holding_request = 1'b0;
        holding_instruction_request = 1'b0;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        // The original 10-instruction program now takes extra cycles because
        // the adapter intentionally inserts request and response waits.
        while ((dut.pc !== 32'd48) && (cycle_count < 200)) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        @(negedge clk);
        #1;

        expect_word(dut.u_regfile.regs[1], 32'd5,  1);
        expect_word(dut.u_regfile.regs[2], 32'd10, 2);
        expect_word(dut.u_regfile.regs[3], 32'd15, 3);
        expect_word(ram.mem[0],            32'd15, 4);
        expect_word(dut.u_regfile.regs[4], 32'd15, 5);
        expect_word(dut.u_regfile.regs[5], 32'd10, 6);
        expect_word(dut.u_regfile.regs[6], 32'd0,  7);
        expect_word(dut.u_regfile.regs[7], 32'd40, 8);
        expect_word(ram.mem[1],            32'd10, 9);
        expect_word(ram.write_side_effect_count, 32'd2, 10);

        if (wait_cycles > 0)
            $display("TEST 11 PASS: observed %0d backpressure cycle(s)", wait_cycles);
        else begin
            $display("TEST 11 FAIL: no backpressure was observed");
            failures = failures + 1;
        end

        if (cycle_count < 200)
            $display("TEST 12 PASS: program completed after %0d cycle(s)", cycle_count);
        else begin
            $display("TEST 12 FAIL: timeout waiting for PC=48");
            failures = failures + 1;
        end

        if (instruction_wait_cycles > 0)
            $display("TEST 13 PASS: observed %0d instruction backpressure cycle(s)", instruction_wait_cycles);
        else begin
            $display("TEST 13 FAIL: no instruction backpressure was observed");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("ALL TASK15 DATA INTERFACE TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);
        $finish;
    end
endmodule
