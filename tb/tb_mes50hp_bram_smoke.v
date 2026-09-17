`timescale 1ns/1ps

module tb_mes50hp_bram_smoke;
    reg clk_50m = 1'b0;
    wire led1;
    integer failures = 0;

    mes50hp_bram_smoke_top dut (
        .clk_50m(clk_50m),
        .led1(led1)
    );

    always #5 clk_50m = ~clk_50m;

    initial begin
        repeat (3500) @(posedge clk_50m);
        if (dut.core.state !== 3'd5) begin
            $display("TEST mes50hp_bram_smoke FAIL: state=%0d", dut.core.state);
            failures = failures + 1;
        end
        if (led1 !== 1'b1) begin
            $display("TEST mes50hp_bram_smoke FAIL: LED1 should be high on PASS");
            failures = failures + 1;
        end
        if (dut.core.ram[0] !== 32'h1ACE_B00C) begin
            $display("TEST mes50hp_bram_smoke FAIL: RAM[0]=%h", dut.core.ram[0]);
            failures = failures + 1;
        end
        if (failures == 0)
            $display("ALL MES50HP BRAM SMOKE TEST PASS");
        else
            $display("MES50HP BRAM SMOKE TEST FAIL: %0d failure(s)", failures);
        $finish;
    end
endmodule
