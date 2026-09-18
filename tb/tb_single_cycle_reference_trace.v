`timescale 1ns/1ps

// Task 13 candidate-reference test.  It checks the complete commit trace of
// the Task 11 program, repeats that program in a second CPU instance, and
// compares the resulting architectural state.
module tb_single_cycle_reference_trace;
    reg clk;
    reg reset;
    integer failures;
    integer trace_index;
    integer reg_index;

    wire        trace_valid_a;
    wire [31:0] trace_pc_a;
    wire [31:0] trace_instruction_a;
    wire        trace_rd_we_a;
    wire [4:0]  trace_rd_addr_a;
    wire [31:0] trace_rd_data_a;
    wire        trace_mem_we_a;
    wire [31:0] trace_mem_addr_a;
    wire [31:0] trace_mem_data_a;
    wire [3:0]  trace_mem_wstrb_a;

    wire        trace_valid_b;
    wire [31:0] trace_pc_b;
    wire [31:0] trace_instruction_b;
    wire        trace_rd_we_b;
    wire [4:0]  trace_rd_addr_b;
    wire [31:0] trace_rd_data_b;
    wire        trace_mem_we_b;
    wire [31:0] trace_mem_addr_b;
    wire [31:0] trace_mem_data_b;
    wire [3:0]  trace_mem_wstrb_b;

    core_harness #(
        .IMEM_DEPTH(12),
        .IMEM_INIT_FILE("tb/data/single_cycle_smoke.mem")
    ) dut_a (
        .clk(clk), .reset(reset),
        .trace_valid(trace_valid_a), .trace_pc(trace_pc_a),
        .trace_instruction(trace_instruction_a),
        .trace_rd_we(trace_rd_we_a), .trace_rd_addr(trace_rd_addr_a),
        .trace_rd_data(trace_rd_data_a), .trace_mem_we(trace_mem_we_a),
        .trace_mem_addr(trace_mem_addr_a), .trace_mem_data(trace_mem_data_a),
        .trace_mem_wstrb(trace_mem_wstrb_a)
    );

    core_harness #(
        .IMEM_DEPTH(12),
        .IMEM_INIT_FILE("tb/data/single_cycle_smoke.mem")
    ) dut_b (
        .clk(clk), .reset(reset),
        .trace_valid(trace_valid_b), .trace_pc(trace_pc_b),
        .trace_instruction(trace_instruction_b),
        .trace_rd_we(trace_rd_we_b), .trace_rd_addr(trace_rd_addr_b),
        .trace_rd_data(trace_rd_data_b), .trace_mem_we(trace_mem_we_b),
        .trace_mem_addr(trace_mem_addr_b), .trace_mem_data(trace_mem_data_b),
        .trace_mem_wstrb(trace_mem_wstrb_b)
    );

    always #5 clk = ~clk;

    task expect_trace;
        input [31:0] expected_pc;
        input [31:0] expected_instruction;
        input expected_rd_we;
        input [4:0] expected_rd_addr;
        input [31:0] expected_rd_data;
        input expected_mem_we;
        input [31:0] expected_mem_addr;
        input [31:0] expected_mem_data;
        input [3:0] expected_mem_wstrb;
        begin
            // Transactional Core inserts IF/MEM wait cycles.  Sample only the
            // architectural commit event, never an intermediate idle cycle.
            while (trace_valid_a !== 1'b1)
                @(posedge clk);
            if (trace_valid_a !== 1'b1 || trace_pc_a !== expected_pc ||
                trace_instruction_a !== expected_instruction ||
                trace_rd_we_a !== expected_rd_we || trace_rd_addr_a !== expected_rd_addr ||
                trace_rd_data_a !== expected_rd_data || trace_mem_we_a !== expected_mem_we ||
                trace_mem_addr_a !== expected_mem_addr || trace_mem_data_a !== expected_mem_data ||
                trace_mem_wstrb_a !== expected_mem_wstrb) begin
                $display("TRACE %0d FAIL: pc=%h inst=%h rd_we=%b rd=%0d rd_data=%h mem_we=%b mem_addr=%h mem_data=%h wstrb=%b",
                    trace_index, trace_pc_a, trace_instruction_a, trace_rd_we_a,
                    trace_rd_addr_a, trace_rd_data_a, trace_mem_we_a,
                    trace_mem_addr_a, trace_mem_data_a, trace_mem_wstrb_a);
                failures = failures + 1;
            end else
                $display("TRACE %0d PASS", trace_index);
            expect_repeated_trace;
        end
    endtask

    task expect_repeated_trace;
        begin
            if (trace_valid_a !== trace_valid_b || trace_pc_a !== trace_pc_b ||
                trace_instruction_a !== trace_instruction_b || trace_rd_we_a !== trace_rd_we_b ||
                trace_rd_addr_a !== trace_rd_addr_b || trace_rd_data_a !== trace_rd_data_b ||
                trace_mem_we_a !== trace_mem_we_b || trace_mem_addr_a !== trace_mem_addr_b ||
                trace_mem_data_a !== trace_mem_data_b || trace_mem_wstrb_a !== trace_mem_wstrb_b) begin
                $display("REPEAT TRACE %0d FAIL", trace_index);
                failures = failures + 1;
            end
        end
    endtask

    task expect_intentional_mismatch;
        begin
            if (trace_rd_data_a !== (trace_rd_data_a ^ 32'h0000_0001))
                $display("INTENTIONAL TRACE MISMATCH DETECTED: record %0d field rd_data", trace_index);
            else begin
                $display("INTENTIONAL TRACE MISMATCH NOT DETECTED");
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failures = 0;
        trace_index = 0;

        repeat (2) @(negedge clk);
        reset = 1'b0;
        #1;

        // PC, instruction, register side effect, then memory side effect.
        expect_trace(32'd0,  32'h00500093, 1'b1, 5'd1, 32'd5,  1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd4,  32'h00a00113, 1'b1, 5'd2, 32'd10, 1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd8,  32'h002081b3, 1'b1, 5'd3, 32'd15, 1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd12, 32'h00302023, 1'b0, 5'd0, 32'd0,  1'b1, 32'd0, 32'd15, 4'b1111); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd16, 32'h00002203, 1'b1, 5'd4, 32'd15, 1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd20, 32'h401202b3, 1'b1, 5'd5, 32'd10, 1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd24, 32'h00000313, 1'b1, 5'd6, 32'd0,  1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd28, 32'h00228463, 1'b0, 5'd0, 32'd0,  1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd36, 32'h008003ef, 1'b1, 5'd7, 32'd40, 1'b0, 32'b0, 32'b0, 4'b0); @(posedge clk); #1; trace_index = trace_index + 1;
        expect_trace(32'd44, 32'h00502223, 1'b0, 5'd0, 32'd0,  1'b1, 32'd4, 32'd10, 4'b1111); @(posedge clk); #1; trace_index = trace_index + 1;

        for (reg_index = 1; reg_index < 32; reg_index = reg_index + 1) begin
            if (dut_a.core.u_regfile.regs[reg_index] !== dut_b.core.u_regfile.regs[reg_index]) begin
                $display("STATE FAIL: x%0d A=%h B=%h", reg_index,
                    dut_a.core.u_regfile.regs[reg_index], dut_b.core.u_regfile.regs[reg_index]);
                failures = failures + 1;
            end
        end
        if (dut_a.ram.mem[0] !== dut_b.ram.mem[0] ||
            dut_a.ram.mem[1] !== dut_b.ram.mem[1]) begin
            $display("STATE FAIL: DMEM A=[%h,%h] B=[%h,%h]", dut_a.ram.mem[0],
                dut_a.ram.mem[1], dut_b.ram.mem[0], dut_b.ram.mem[1]);
            failures = failures + 1;
        end else
            $display("FINAL ARCHITECTURAL STATE PASS");

        // Demonstrate that a single altered trace field is identified as a mismatch.
        expect_intentional_mismatch;

        if (failures == 0)
            $display("ALL SINGLE-CYCLE CANDIDATE REFERENCE TEST PASS");
        else
            $fatal(1, "%0d TEST(S) FAILED", failures);
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "TEST timeout: candidate reference trace did not finish within 500 ns");
    end
endmodule
