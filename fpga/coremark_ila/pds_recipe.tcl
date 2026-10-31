set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
clean -all
add_design ../../rtl/pipeline_cpu.v
add_design ../../rtl/branch_predictor.v
add_design ../../rtl/csr_unit.v
add_design ../../rtl/forward_unit.v
add_design ../../rtl/hazard_unit.v
add_design ../../rtl/perf_monitor.v
add_design ../../rtl/perf_mmio.v
add_design ../../rtl/regfile.v
add_design ../../rtl/mdu.v
add_design ../../rtl/alu.v
add_design ../../rtl/imm_gen.v
add_design ../../rtl/decoder.v
add_design ../../rtl/branch_unit.v
add_design ../../rtl/load_store_unit.v
add_design ../../rtl/soc_data_interconnect.v
add_design ../../rtl/uart_tx.v
add_design ../../rtl/uart_rx.v
add_design ../../rtl/uart_mmio.v
add_design ../../rtl/gpio_mmio.v
add_design rtl/coremark_program_memory.v
add_design rtl/mes50hp_coremark_ila_top.v
add_design ip/coremark_ila/rtl/ips_dbc_cfg_reg_file_v1_0.v
add_design ip/coremark_ila/rtl/ips_dbc_compare_256b_v1_0.v
add_design ip/coremark_ila/rtl/ips_dbc_data_capture_mem_v1_1.v
add_design ip/coremark_ila/rtl/ips_dbc_debug_core_v1_4.v
add_design ip/coremark_ila/rtl/ips_dbc_hub_decode_v1_3.v
add_design ip/coremark_ila/rtl/ips_dbc_rd_addr_gen_v1_4.v
add_design ip/coremark_ila/rtl/ips_dbc_storage_condition_v1_3.v
add_design ip/coremark_ila/rtl/ips_dbc_storage_qualification_v1_2.v
add_design ip/coremark_ila/rtl/ips_dbc_trig_unit_v1_3.v
add_design ip/coremark_ila/rtl/ips_dbc_trigger_condition_v1_3.v
add_design ip/coremark_ila/rtl/ips_dbc_trigger_output_v1_2.v
add_design ip/coremark_ila/coremark_ila.v
add_design ip/coremark_jtag_hub/rtl/ips_jtag_hub_v1_5.v
add_design ip/coremark_jtag_hub/coremark_jtag_hub.v
add_constraint -fdc constraints/mes50hp_coremark_ila.fdc
compile -force_to_run -top_module {work.mes50hp_coremark_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run -packing_io
place -force_to_run -optimize_multi_corner_timing
route -force_to_run
route_optimize -force_to_run -fix_hold_violation
report_timing -force_to_run
gen_bit_stream -force_to_run
