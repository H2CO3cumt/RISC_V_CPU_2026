// trace85 位流顶层：PLL + mes50hp_trace_top。
//
// 与 fpga/logic_analyzer_85m/rtl/mes50hp_logic_analyzer_pll_top.v 同频同结构
//（50 MHz 输入 / IDIV 1 = PFD 50 MHz；x FDIV 17 = VCO 850 MHz；ODIV0 10 = 85.000 MHz），
// 唯一区别是例化的 SoC 顶层换成带提交级 trace 子窗口的 mes50hp_trace_top。
//
// 为什么单独做一个位流而不是改交付版 la85：la85 的位流哈希绑着
// 100/100 板级验收证据与 claims_map 的四份哈希，任何改动都会作废那批证据。
// 本工程是**附加**演示位流，la85 一个字节不动。
module mes50hp_trace_pll_top #(
 parameter CLK_HZ = 85_000_000
)(
 input wire clk_50m,input wire uart0_rx,output wire uart0_tx,output wire [7:0] led,
 input wire [7:0] capture_ch,output wire [7:0] loopback_tx
);
 // UART 波特率：85e6/115200 = 737.85 -> 737（整数除法），实际 115332 baud（+0.115%）。
 // 与 la85 完全相同，因为上位机与固件的帧格式都按这一档验证过。
 localparam UART_BAUD_CYCLES = CLK_HZ / 115200;
 wire clk_85m, pll_locked;
 pll_85m u_pll(.clk_50m_in(clk_50m),.clk_85m(clk_85m),.pll_locked(pll_locked));

 // 顶层内部自复位：先等 PLL 锁定，再用 8 位计数器完成上电复位释放。
 // USE_EXTERNAL_RESET=0 的内部上电复位约定与交付版一致，只是改在 85 MHz 域计数。
 reg [7:0] por_count = 0; reg reset = 1;
 always @(posedge clk_85m) begin
  if(!pll_locked) begin por_count<=0; reset<=1; end
  else if(reset) begin por_count<=por_count+1'b1; if(&por_count) reset<=0; end
 end

 mes50hp_trace_top #(.UART_BAUD_CYCLES(UART_BAUD_CYCLES),.TRACE_DEPTH(4096),.TRACE_AW(12)) u_soc(
  .clk_50m(clk_85m),.uart0_rx(uart0_rx),.uart0_tx(uart0_tx),.led(led),
  .capture_ch(capture_ch),.loopback_tx(loopback_tx));
endmodule
