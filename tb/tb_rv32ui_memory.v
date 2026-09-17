`timescale 1ns/1ps

module tb_rv32ui_memory;
    localparam TOHOST_WORD_INDEX = 4096;
    localparam MAX_CYCLES = 5000;

    reg clk;
    reg reset;
    integer cycle_count;

    task15_core_harness #(
        .IMEM_DEPTH(8192),
        .DMEM_DEPTH(8192),
        .IMEM_INIT_FILE("tmp/rv32ui_current.mem")
    ) dut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    initial begin
        // The generated Verilog image uses 32-bit word addresses, matching
        // both imem and dmem array indexing.  This supplies the ELF .data
        // section required by the upstream Load/Store tests.
        $readmemh("tmp/rv32ui_current.mem", dut.ram.mem);

        clk = 1'b0;
        reset = 1'b1;
        cycle_count = 0;

        repeat (2) @(negedge clk);
        reset = 1'b0;

        while (cycle_count < MAX_CYCLES) begin
            @(posedge clk);
            #1;
            cycle_count = cycle_count + 1;
            if (dut.ram.mem[TOHOST_WORD_INDEX] === 32'd1) begin
                $display("TEST RV32UI MEMORY PASS (%0d cycles)", cycle_count);
                $finish;
            end
            if ((dut.ram.mem[TOHOST_WORD_INDEX] !== 32'd0) &&
                (dut.ram.mem[TOHOST_WORD_INDEX] !== 32'hxxxxxxxx)) begin
                $fatal(1, "TEST RV32UI MEMORY FAIL: tohost=%h after %0d cycles",
                       dut.ram.mem[TOHOST_WORD_INDEX], cycle_count);
            end
        end

        $fatal(1, "TEST RV32UI MEMORY TIMEOUT after %0d cycles", MAX_CYCLES);
    end
endmodule
