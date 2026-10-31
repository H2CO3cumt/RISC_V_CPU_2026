# MES50HP DDR3 冒烟工程 PDS 配方（由 scripts/ddr3_gen_smoke_recipe.py 生成，勿手改）。
#
# 与交付工程完全隔离：只读写 fpga/ddr3_smoke/，不触碰
# fpga/logic_analyzer、fpga/coremark、fpga/coremark_80m、fpga/timer_demo。
#
# DDR3 占 Bank 3 的 1.5 V；板级时钟/UART/LED 是 3.3 V —— 两侧电平由
# constraints/mes50hp_ddr3_smoke.fdc 分别声明，不混用。
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
clean -all

# ---- 1) 我们的板级顶层 ----
add_design rtl/mes50hp_ddr3_smoke_top.v

# ---- 2) HMIC_S IP 生成的 RTL（含加密 .vp）----
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_calib_mux_v1_3.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_calib_top_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_control_path_adj_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_data_slice_dqs_gate_cal_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_data_slice_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_data_slice_wrlvl_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_dfi_v1_4.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_dll_update_ctrl_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_dqs_gate_coarse_cal_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_dqs_rddata_align_v1_3.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_dqsi_rdel_cal_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_drift_ctrl_v1_5.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_gate_update_ctrl_v1_5.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_gatecal_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_info_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_init_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_main_ctrl_v1_5.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_rdcal_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_reset_ctrl_v1_6.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_rst_debounce_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_slice_rddata_align_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_slice_top_v1_7.v
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_training_ctrl_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_upcal_v1_5.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_wdata_path_adj_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ddrphy/ipsxb_ddrphy_wrlvl_v1_0.vp
add_design ip/ddr3_mes50hp/rtl/ipsxb_rst_sync_v1_1.v
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/distributed_fifo/ipsxb_distributed_fifo_v1_0.v
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/distributed_fifo/rtl/ipsxb_distributed_fifo_ctr_v1_0.v
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/distributed_fifo/rtl/ipsxb_distributed_fifo_v1_0_distributed_fifo_v1_0.v
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/distributed_fifo/rtl/ipsxb_distributed_sdpram_v1_0_distributed_fifo_v1_0.v
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_apb_cross_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_calib_delay_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_cfg_apb_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcd_bm_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcd_rowaddr_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcd_sm_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcd_top_v1_3.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcp_back_ctrl_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcp_buf_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcp_out_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dcp_top_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_dfi_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_lp_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_mrs_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_prefetch_fifo_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_rdatapath_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_reg_fifo2_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_ui_axi_v1_2a.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_wdatapath_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_wdp_align_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_wdp_dcp_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/ipsxb_mcdq_wrapper_v1_3.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_com_timing_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_tfaw_timing_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_tfaw_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_timing_act2wr_pass_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_timing_act_pass_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_timing_pre_pass_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_timing_rd_pass_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_timing_ref_pass_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_timing_wr_pass_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/mcdq_ctrl/syn_mod/ipsxb_mcdq_trc_timing_v1_2.vp
add_design ip/ddr3_mes50hp/rtl/pll/ipsxb_ddrphy_pll_v1_7.v

# ---- 3) IP 实例根目录的顶层包装（<实例>.v / <实例>_ddrphy_top.v）----
add_design ip/ddr3_mes50hp/ddr3_mes50hp.v
add_design ip/ddr3_mes50hp/ddr3_mes50hp_ddrphy_top.v
add_design ip/ddr3_mes50hp/ddr3_mes50hp_tmpl.v

# ---- 4) 厂商 Example Design ----
add_design ip/ddr3_mes50hp/example_design/rtl/axi_bist_top_v1_0.v
add_design ip/ddr3_mes50hp/example_design/rtl/prbs15_64bit_v1_0.v
add_design ip/ddr3_mes50hp/example_design/rtl/prbs31_128bit_v1_0.v
add_design ip/ddr3_mes50hp/example_design/rtl/test_ddr.v
add_design ip/ddr3_mes50hp/example_design/rtl/test_main_ctrl_v1_0.v
add_design ip/ddr3_mes50hp/example_design/rtl/test_rd_ctrl_v1_0.v
add_design ip/ddr3_mes50hp/example_design/rtl/test_wr_ctrl_v1_0.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_clk_gen_32bit.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_cmd_parser_32bit.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_seu_rs232_intf.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_seu_uart_rx.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_seu_uart_tx.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_uart_ctrl_32bit.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_uart_ctrl_top_32bit.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_ctrl_32bit/ipsxb_ver_ctrl_32bit.v
add_design ip/ddr3_mes50hp/example_design/rtl/uart_rd_lock.v

# ---- 5) 约束（按 MES50HP 手册生成，**不是** IP 自带那份）----
add_constraint -fdc constraints/mes50hp_ddr3_smoke.fdc

compile -force_to_run -top_module {work.mes50hp_ddr3_smoke_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run -packing_io
place -force_to_run -optimize_multi_corner_timing
route -force_to_run
route_optimize -force_to_run -fix_hold_violation
report_timing -force_to_run
gen_bit_stream -force_to_run
