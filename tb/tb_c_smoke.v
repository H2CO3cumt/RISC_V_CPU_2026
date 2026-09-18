`timescale 1ns/1ps

module tb_c_smoke;
    reg clk;
    reg reset;
    integer failures;
    integer cycle_count;
    reg bss_clear_observed;

    core_harness #(
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("software/c_smoke/build/c_smoke_sum.mem")
    ) dut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && dut.trace_mem_we &&
            dut.trace_mem_addr == 32'h00000200 &&
            dut.trace_mem_data == 32'd0)
            bss_clear_observed <= 1'b1;
    end

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

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failures = 0;
        cycle_count = 0;
        bss_clear_observed = 1'b0;

        #1;
        dut.ram.mem[128] = 32'hDEADBEEF;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        while (cycle_count < 2000 && dut.ram.mem[128] !== 32'd45) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        #1;

        expect_word({31'd0, bss_clear_observed}, 32'd1,        1);
        expect_word(dut.core.u_regfile.regs[2],        32'h000003F0, 2);
        expect_word(dut.ram.mem[255],          32'h00000020, 3);
        expect_word(dut.ram.mem[128],          32'd45,       4);

        if (failures == 0)
            $display("ALL C SMOKE TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end

    initial begin
        #25000;
        $fatal(1, "TEST timeout: Task 14 program did not store result");
    end
endmodule
