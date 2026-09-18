`timescale 1ns/1ps

module tb_c_array_control;
    reg clk;
    reg reset;
    integer failures;
    integer cycle_count;
    reg result_bss_clear_observed;
    reg false_result_bss_clear_observed;

    core_harness #(
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("software/c_array_control/build/c_array_control_imem.mem")
    ) dut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && dut.trace_mem_we &&
            dut.trace_mem_addr == 32'h00000204 &&
            dut.trace_mem_data == 32'd0)
            result_bss_clear_observed <= 1'b1;
        if (!reset && dut.trace_mem_we &&
            dut.trace_mem_addr == 32'h00000208 &&
            dut.trace_mem_data == 32'd0)
            false_result_bss_clear_observed <= 1'b1;
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
        #1;
        $readmemh("software/c_array_control/build/c_array_control_dmem.mem", dut.ram.mem);
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failures = 0;
        cycle_count = 0;
        result_bss_clear_observed = 1'b0;
        false_result_bss_clear_observed = 1'b0;

        #2;
        dut.ram.mem[129] = 32'hDEADBEEF;
        dut.ram.mem[130] = 32'hCAFEBABE;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        while (cycle_count < 3000 && dut.ram.mem[130] !== 32'hFFFFFFFF) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        #1;

        expect_word({31'd0, result_bss_clear_observed}, 32'd1,        1);
        expect_word({31'd0, false_result_bss_clear_observed}, 32'd1,  2);
        expect_word(dut.ram.mem[128],                      32'd3,  3);
        expect_word(dut.ram.mem[129],                      32'd18, 4);
        expect_word(dut.ram.mem[130],               32'hFFFFFFFF, 5);
        expect_word(dut.ram.mem[255],                 32'h00000020, 6);

        if (failures == 0)
            $display("ALL C ARRAY CONTROL TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);

        $finish;
    end

    initial begin
        #35000;
        $fatal(1, "TEST timeout: Task 14 array/control program did not store result");
    end
endmodule
