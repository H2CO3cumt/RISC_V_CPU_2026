// MES50HP 板级 PLL wrapper：把 P20 的 50 MHz 固定晶振倍频到 90 MHz 供 CPU/SoC 使用。
// 该模块完全位于 CPU Core 之外（board wrapper 层）；pipeline_cpu 不感知 PLL，
// Core/SoC 统一事务接口与提交事件接口都不因本模块改变。
//
// 频率方案（PGL50H Logos PLL，VCO 必须落在 600~1250 MHz）：
//   CLKIN 50 MHz / IDIV(STATIC_RATIOI=1) = PFD 50 MHz     （PFD 允许 5~320 MHz）
//   PFD 50 MHz x FDIV(STATIC_RATIOF=18)  = VCO 900 MHz    （在 600~1250 MHz 内）
//   VCO 900 MHz / ODIV0(STATIC_RATIO0=10) = 90 MHz 输出
//   DUTY0 = ODIV0/2 = 5 对应 50% 占空比。
//
// 与 80 MHz 版的唯一区别就是 STATIC_RATIOF 16 -> 17（VCO 800 -> 850 MHz），
// 输出分频比 ODIV0 保持 10，因此得到 85.000 MHz 这个**整数**频率，没有小数误差。
//
// 这里直接例化原语 GTP_PLL_E3（与 PDS 自带例子 PGL25G_lvds4to1/ip/pll_tx 同源），
// 不引入外部 IP 文件依赖，保证配方只依赖仓库内源码。
//
// 复位策略：PLL 锁定（LOCK）+ 稳定计数器双重释放。
//   锁定前 reset 一直有效；锁定后再数 POR_CYCLES 个 85 MHz 周期才释放，
//   保证 BRAM 初始化与时钟稳定后再取第一条指令。
module pll_90m (
    input  wire clk_50m_in,
    output wire clk_90m,
    output wire pll_locked
);
    localparam real    CLKIN_FREQ   = 50.0;
    localparam integer STATIC_RATIOI = 1;
    localparam integer STATIC_RATIOM = 1;
    localparam integer STATIC_RATIOF = 18;   // <- 80 MHz 版是 16（VCO 800）；这里 17 => VCO 850
    localparam integer STATIC_RATIO0 = 10;   // 850 / 10 = 85.000 MHz
    localparam integer STATIC_DUTY0  = 5;
    // 未使用的 clkout1..4 保持 IP 默认 16 分频/16 占空比，不对外引出。
    localparam integer STATIC_RATIO_OFF = 16;
    localparam integer STATIC_DUTY_OFF  = 16;

    wire clkout0;
    wire [9:0] dyn_ratioi, dyn_ratio0, dyn_ratio1, dyn_ratio2, dyn_ratio3, dyn_ratio4, dyn_ratiof;
    wire [9:0] dyn_duty0, dyn_duty1, dyn_duty2, dyn_duty3, dyn_duty4;
    wire unused_lock_flag;
    wire unused_clkout1, unused_clkout2, unused_clkout3, unused_clkout4, unused_clkout5, unused_clkout0_ext;

    GTP_PLL_E3 #(
        .CLKIN_FREQ(CLKIN_FREQ),
        .PFDEN_EN("FALSE"),
        .VCOCLK_DIV2(1'b0),
        .DYNAMIC_RATIOI_EN("FALSE"),
        .DYNAMIC_RATIOM_EN("FALSE"),
        .DYNAMIC_RATIO0_EN("FALSE"),
        .DYNAMIC_RATIO1_EN("FALSE"),
        .DYNAMIC_RATIO2_EN("FALSE"),
        .DYNAMIC_RATIO3_EN("FALSE"),
        .DYNAMIC_RATIO4_EN("FALSE"),
        .DYNAMIC_RATIOF_EN("FALSE"),
        .STATIC_RATIOI(STATIC_RATIOI),
        .STATIC_RATIOM(STATIC_RATIOM),
        .STATIC_RATIO0(STATIC_RATIO0),
        .STATIC_RATIO1(STATIC_RATIO_OFF),
        .STATIC_RATIO2(STATIC_RATIO_OFF),
        .STATIC_RATIO3(STATIC_RATIO_OFF),
        .STATIC_RATIO4(STATIC_RATIO_OFF),
        .STATIC_RATIOF(STATIC_RATIOF),
        .DYNAMIC_DUTY0_EN("FALSE"),
        .DYNAMIC_DUTY1_EN("FALSE"),
        .DYNAMIC_DUTY2_EN("FALSE"),
        .DYNAMIC_DUTY3_EN("FALSE"),
        .DYNAMIC_DUTY4_EN("FALSE"),
        .STATIC_DUTY0(STATIC_DUTY0),
        .STATIC_DUTY1(STATIC_DUTY_OFF),
        .STATIC_DUTY2(STATIC_DUTY_OFF),
        .STATIC_DUTY3(STATIC_DUTY_OFF),
        .STATIC_DUTY4(STATIC_DUTY_OFF),
        .STATIC_PHASE0(3'b0),
        .STATIC_PHASE1(3'b0),
        .STATIC_PHASE2(3'b0),
        .STATIC_PHASE3(3'b0),
        .STATIC_PHASE4(3'b0),
        .STATIC_PHASEF(3'b0),
        .STATIC_CPHASE0(0),
        .STATIC_CPHASE1(0),
        .STATIC_CPHASE2(0),
        .STATIC_CPHASE3(0),
        .STATIC_CPHASE4(0),
        .STATIC_CPHASEF(0),
        .CLK_CAS1_EN("FALSE"),
        .CLK_CAS2_EN("FALSE"),
        .CLK_CAS3_EN("FALSE"),
        .CLK_CAS4_EN("FALSE"),
        .CLKOUT5_SEL(0),
        .CLKIN_BYPASS_EN("FALSE"),
        .CLKOUT0_SYN_EN("FALSE"),
        .CLKOUT0_EXT_SYN_EN("FALSE"),
        .CLKOUT1_SYN_EN("FALSE"),
        .CLKOUT2_SYN_EN("FALSE"),
        .CLKOUT3_SYN_EN("FALSE"),
        .CLKOUT4_SYN_EN("FALSE"),
        .CLKOUT5_SYN_EN("FALSE"),
        .INTERNAL_FB("ENABLE"),
        .EXTERNAL_FB("DISABLE"),
        .DYNAMIC_LOOP_EN("FALSE"),
        .LOOP_MAPPING_EN("FALSE"),
        .BANDWIDTH("OPTIMIZED")
    ) u_pll_90m (
        .CLKOUT0(clkout0),
        .CLKOUT0_EXT(unused_clkout0_ext),
        .CLKOUT1(unused_clkout1),
        .CLKOUT2(unused_clkout2),
        .CLKOUT3(unused_clkout3),
        .CLKOUT4(unused_clkout4),
        .CLKOUT5(unused_clkout5),
        .CLKSWITCH_FLAG(unused_lock_flag),
        .LOCK(pll_locked),
        .CLKIN1(clk_50m_in),
        .CLKIN2(1'b0),
        .CLKFB(1'b0),
        .CLKIN_SEL(1'b0),
        .CLKIN_SEL_EN(1'b0),
        .PFDEN(1'b0),
        .ICP_BASE(1'b0),
        .ICP_SEL(4'b0),
        .LPFRES_SEL(3'b0),
        .CRIPPLE_SEL(1'b0),
        .PHASE_SEL(3'b0),
        .PHASE_DIR(1'b0),
        .PHASE_STEP_N(1'b0),
        .LOAD_PHASE(1'b0),
        .RATIOM(7'b0),
        .RATIOI(dyn_ratioi),
        .RATIO0(dyn_ratio0),
        .RATIO1(dyn_ratio1),
        .RATIO2(dyn_ratio2),
        .RATIO3(dyn_ratio3),
        .RATIO4(dyn_ratio4),
        .RATIOF(dyn_ratiof),
        .DUTY0(dyn_duty0),
        .DUTY1(dyn_duty1),
        .DUTY2(dyn_duty2),
        .DUTY3(dyn_duty3),
        .DUTY4(dyn_duty4),
        .CLKOUT0_SYN(1'b0),
        .CLKOUT0_EXT_SYN(1'b0),
        .CLKOUT1_SYN(1'b0),
        .CLKOUT2_SYN(1'b0),
        .CLKOUT3_SYN(1'b0),
        .CLKOUT4_SYN(1'b0),
        .CLKOUT5_SYN(1'b0),
        .PLL_PWD(1'b0),
        .RST(1'b0),
        .RSTODIV(1'b0)
    );

    assign clk_90m = clkout0;
endmodule
