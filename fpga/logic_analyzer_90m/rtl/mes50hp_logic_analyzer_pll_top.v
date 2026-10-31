// 90m MHz 版 MES50HP 逻辑分析仪顶层：PLL + 原 mes50hp_logic_analyzer_top。
// 本文件只做“时钟生成 + 例化”，所有 CPU/SoC/逻辑分析仪逻辑仍复用未修改的
// mes50hp_logic_analyzer_top、pipeline_cpu 与各外设模块；PLL 位于 Core 之外。
//
// 频率方案与 pll_90m 一致：50 MHz / IDIV 1 = PFD 50 MHz，
// PFD x FDIV 17 = VCO 850 MHz，VCO / ODIV0 10 = 85.000 MHz（精确整数频率）。
// 与 80 MHz 版的唯一区别是 FDIV 16 -> 17。
//
// UART 波特率：85e6/115200 = 737.85 -> 737（整数除法），实际 115332 baud（+0.115%）。
//   115200 的 UART 帧约 87 us，±2% 内都能可靠采样，0.115% 完全在容差内。
module mes50hp_logic_analyzer_pll_top #(
 parameter CLK_HZ = 90000000
)(
 input wire clk_50m,input wire uart0_rx,output wire uart0_tx,output wire [7:0] led,
 input wire [7:0] capture_ch,output wire [7:0] loopback_tx
);
 localparam UART_BAUD_CYCLES = CLK_HZ / 115200;
 wire clk_90m, pll_locked;
 pll_90m u_pll(.clk_50m_in(clk_50m),.clk_90m(clk_90m),.pll_locked(pll_locked));

 // 顶层内部自复位：先等 PLL 锁定，再用 8 位计数器完成上电复位释放。
 // USE_EXTERNAL_RESET=0 的内部上电复位约定保持不变，只是改为 85 MHz 域计数。
 reg [7:0] por_count = 0; reg reset = 1;
 always @(posedge clk_90m) begin
  if(!pll_locked) begin por_count<=0; reset<=1; end
  else if(reset) begin por_count<=por_count+1'b1; if(&por_count) reset<=0; end
 end

 mes50hp_logic_analyzer_top #(.UART_BAUD_CYCLES(UART_BAUD_CYCLES)) u_soc(
  .clk_50m(clk_90m),.uart0_rx(uart0_rx),.uart0_tx(uart0_tx),.led(led),
  .capture_ch(capture_ch),.loopback_tx(loopback_tx));
endmodule
