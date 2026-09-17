`timescale 1ns/1ps

module tb_bram_smoke;
    reg clk = 1'b0;
    wire status_led_n;
    integer failures = 0;

    bram_smoke_top dut (
        .clk(clk),
        .status_led_n(status_led_n)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (3500) @(posedge clk);
        if (dut.state !== 3'd5) begin
            $display("TEST bram_smoke FAIL: expected PASS state, got %0d", dut.state);
            failures = failures + 1;
        end
        if (status_led_n !== 1'b0) begin
            $display("TEST bram_smoke FAIL: pass LED should be active low");
            failures = failures + 1;
        end
        if (dut.ram[0] !== 32'h1ACE_B00C || dut.ram[1023] === 32'hxxxx_xxxx) begin
            $display("TEST bram_smoke FAIL: RAM contents incorrect");
            failures = failures + 1;
        end
        if (failures == 0)
            $display("ALL BRAM SMOKE TEST PASS");
        else
            $display("BRAM SMOKE TEST FAIL: %0d failure(s)", failures);
        $finish;
    end
endmodule
