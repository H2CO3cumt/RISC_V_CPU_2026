// MES50HP board wrapper for the board-independent BRAM smoke core.
// MES50HP LED1 is active high; the inner smoke core reports pass active low.
module mes50hp_bram_smoke_top (
    input  wire clk_50m,
    output wire led1
);
    wire status_led_n;

    bram_smoke_top core (
        .clk(clk_50m),
        .status_led_n(status_led_n)
    );

    assign led1 = ~status_led_n;
endmodule
