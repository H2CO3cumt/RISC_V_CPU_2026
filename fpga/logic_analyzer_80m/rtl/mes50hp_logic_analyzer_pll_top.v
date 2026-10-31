// 80 MHz 版 MES50HP 逻辑分析仪顶层：PLL + 原 mes50hp_logic_analyzer_top。
// 本文件只做“时钟生成 + 例化”，所有 CPU/SoC/逻辑分析仪逻辑仍复用未修改的
// mes50hp_logic_analyzer_top、pipeline_cpu 与各外设模块；PLL 位于 Core 之外。
//
// 频率方案与 pll_80m 一致：50 MHz / IDIV 1 = PFD 50 MHz，
// PFD x FDIV 16 = VCO 800 MHz，VCO / ODIV0 10 = 80.000 MHz。
// 直接把 pll_80m.v 一起加入工程复用（该文件同时被 CoreMark 80 MHz 工程使用）。
//
// UART 波特率：80e6/115200 = 694.44 -> 694，实际 115274 baud（-0.064%）。
module mes50hp_logic_analyzer_pll_top #(
 parameter CLK_HZ = 80_000_000
)(
 input wire clk_50m,input wire uart0_rx,output wire uart0_tx,output wire [7:0] led,
 input wire [7:0] capture_ch,output wire [7:0] loopback_tx
);
 localparam UART_BAUD_CYCLES = CLK_HZ / 115200;
 wire clk_80m, pll_locked;
 pll_80m u_pll(.clk_50m_in(clk_50m),.clk_80m(clk_80m),.pll_locked(pll_locked));

 // 顶层内部自复位：先等 PLL 锁定，再用 8 位计数器完成上电复位释放。
 // USE_EXTERNAL_RESET=0 的内部上电复位约定保持不变，只是改为 80 MHz 域计数。
 reg [7:0] por_count = 0; reg reset = 1;
 always @(posedge clk_80m) begin
  if(!pll_locked) begin por_count<=0; reset<=1; end
  else if(reset) begin por_count<=por_count+1'b1; if(&por_count) reset<=0; end
 end

 mes50hp_logic_analyzer_top #(.UART_BAUD_CYCLES(UART_BAUD_CYCLES)) u_soc(
  .clk_50m(clk_80m),.uart0_rx(uart0_rx),.uart0_tx(uart0_tx),.led(led),
  .capture_ch(capture_ch),.loopback_tx(loopback_tx));
endmodule
