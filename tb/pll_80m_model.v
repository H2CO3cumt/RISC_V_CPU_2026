`timescale 1ns/1ps
// GTP_PLL_E3 仿真行为模型（仅用于 Icarus RTL 仿真）。
// 真实原语由 PDS 仿真库提供；这里按 pll_80m.v 使用的静态参数复现
// 「IDIV=1, FDIV=16, ODIV0=10，输入 50 MHz 得到 80 MHz」的行为，
// 带一小段锁定延迟，便于 testbench 检查锁定握手与输出频点是否正确。
// 参数端口必须与真实原语同名同类型，否则 pll_80m.v 的具名参数绑定会失败。
module GTP_PLL_E3 #(
 parameter real CLKIN_FREQ = 50.0,
 parameter PFDEN_EN = "FALSE",
 parameter VCOCLK_DIV2 = 1'b0,
 parameter DYNAMIC_RATIOI_EN = "FALSE",
 parameter DYNAMIC_RATIOM_EN = "FALSE",
 parameter DYNAMIC_RATIO0_EN = "FALSE",
 parameter DYNAMIC_RATIO1_EN = "FALSE",
 parameter DYNAMIC_RATIO2_EN = "FALSE",
 parameter DYNAMIC_RATIO3_EN = "FALSE",
 parameter DYNAMIC_RATIO4_EN = "FALSE",
 parameter DYNAMIC_RATIOF_EN = "FALSE",
 parameter integer STATIC_RATIOI = 1,
 parameter integer STATIC_RATIOM = 1,
 parameter integer STATIC_RATIO0 = 10,
 parameter integer STATIC_RATIO1 = 16,
 parameter integer STATIC_RATIO2 = 16,
 parameter integer STATIC_RATIO3 = 16,
 parameter integer STATIC_RATIO4 = 16,
 parameter integer STATIC_RATIOF = 16,
 parameter DYNAMIC_DUTY0_EN = "FALSE",
 parameter DYNAMIC_DUTY1_EN = "FALSE",
 parameter DYNAMIC_DUTY2_EN = "FALSE",
 parameter DYNAMIC_DUTY3_EN = "FALSE",
 parameter DYNAMIC_DUTY4_EN = "FALSE",
 parameter integer STATIC_DUTY0 = 5,
 parameter integer STATIC_DUTY1 = 16,
 parameter integer STATIC_DUTY2 = 16,
 parameter integer STATIC_DUTY3 = 16,
 parameter integer STATIC_DUTY4 = 16,
 parameter [2:0] STATIC_PHASE0 = 3'b000,
 parameter [2:0] STATIC_PHASE1 = 3'b000,
 parameter [2:0] STATIC_PHASE2 = 3'b000,
 parameter [2:0] STATIC_PHASE3 = 3'b000,
 parameter [2:0] STATIC_PHASE4 = 3'b000,
 parameter [2:0] STATIC_PHASEF = 3'b000,
 parameter integer STATIC_CPHASE0 = 0,
 parameter integer STATIC_CPHASE1 = 0,
 parameter integer STATIC_CPHASE2 = 0,
 parameter integer STATIC_CPHASE3 = 0,
 parameter integer STATIC_CPHASE4 = 0,
 parameter integer STATIC_CPHASEF = 0,
 parameter CLK_CAS1_EN = "FALSE",
 parameter CLK_CAS2_EN = "FALSE",
 parameter CLK_CAS3_EN = "FALSE",
 parameter CLK_CAS4_EN = "FALSE",
 parameter integer CLKOUT5_SEL = 0,
 parameter CLKIN_BYPASS_EN = "FALSE",
 parameter CLKOUT0_SYN_EN = "FALSE",
 parameter CLKOUT0_EXT_SYN_EN = "FALSE",
 parameter CLKOUT1_SYN_EN = "FALSE",
 parameter CLKOUT2_SYN_EN = "FALSE",
 parameter CLKOUT3_SYN_EN = "FALSE",
 parameter CLKOUT4_SYN_EN = "FALSE",
 parameter CLKOUT5_SYN_EN = "FALSE",
 parameter INTERNAL_FB = "ENABLE",
 parameter EXTERNAL_FB = "DISABLE",
 parameter DYNAMIC_LOOP_EN = "FALSE",
 parameter LOOP_MAPPING_EN = "FALSE",
 parameter BANDWIDTH = "OPTIMIZED"
)(
 output wire CLKOUT0,
 output wire CLKOUT1,
 output wire CLKOUT2,
 output wire CLKOUT3,
 output wire CLKOUT4,
 output wire CLKOUT5,
 output wire CLKOUT0_EXT,
 output wire CLKSWITCH_FLAG,
 output wire LOCK,
 input wire CLKIN1,
 input wire CLKIN2,
 input wire CLKFB,
 input wire CLKIN_SEL,
 input wire CLKIN_SEL_EN,
 input wire PFDEN,
 input wire ICP_BASE,
 input wire [3:0] ICP_SEL,
 input wire [2:0] LPFRES_SEL,
 input wire CRIPPLE_SEL,
 input wire [2:0] PHASE_SEL,
 input wire PHASE_DIR,
 input wire PHASE_STEP_N,
 input wire LOAD_PHASE,
 input wire [6:0] RATIOM,
 input wire [9:0] RATIOI,
 input wire [9:0] RATIO0,
 input wire [9:0] RATIO1,
 input wire [9:0] RATIO2,
 input wire [9:0] RATIO3,
 input wire [9:0] RATIO4,
 input wire [9:0] RATIOF,
 input wire [9:0] DUTY0,
 input wire [9:0] DUTY1,
 input wire [9:0] DUTY2,
 input wire [9:0] DUTY3,
 input wire [9:0] DUTY4,
 input wire CLKOUT0_SYN,
 input wire CLKOUT0_EXT_SYN,
 input wire CLKOUT1_SYN,
 input wire CLKOUT2_SYN,
 input wire CLKOUT3_SYN,
 input wire CLKOUT4_SYN,
 input wire CLKOUT5_SYN,
 input wire PLL_PWD,
 input wire RST,
 input wire RSTODIV
);
 // 输出周期 = 输入周期 * IDIV * ODIV0 / FDIV：50 MHz 输入时 20 * 1 * 10 / 16 = 12.5 ns
 localparam real IN_PERIOD_NS  = 1000.0/CLKIN_FREQ;
 localparam real OUT_PERIOD_NS = IN_PERIOD_NS*STATIC_RATIOI*STATIC_RATIO0/STATIC_RATIOF;

 reg clkout = 0;
 reg lock = 0;
 integer i;

 initial begin
  // 模拟真实 PLL 的锁定建立时间：上电后经过若干输入周期再拉高 LOCK
  @(posedge CLKIN1);
  for(i=0;i<20;i=i+1) @(posedge CLKIN1);
  lock = 1;
  // 半周期延时；本文件 `timescale 1ns/1ps，因此 OUT_PERIOD_NS/2 = 6.25 即 6.25 ns
  forever begin
   #(OUT_PERIOD_NS/2.0);
   clkout = ~clkout;
  end
 end

 assign CLKOUT0 = clkout;
 assign CLKOUT1 = 1'b0;
 assign CLKOUT2 = 1'b0;
 assign CLKOUT3 = 1'b0;
 assign CLKOUT4 = 1'b0;
 assign CLKOUT5 = 1'b0;
 assign CLKOUT0_EXT = 1'b0;
 assign CLKSWITCH_FLAG = 1'b0;
 assign LOCK = lock;
endmodule
