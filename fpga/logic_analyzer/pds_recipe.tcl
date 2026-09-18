set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
clean -all
add_design ../../rtl/pipeline_cpu.v
add_design ../../rtl/branch_predictor.v
add_design ../../rtl/forward_unit.v
add_design ../../rtl/hazard_unit.v
add_design ../../rtl/perf_monitor.v
add_design ../../rtl/perf_mmio.v
add_design ../../rtl/capture_engine.v
add_design ../../rtl/logic_analyzer_pattern_gen.v
add_design ../../rtl/logic_analyzer_mmio.v
add_design ../../rtl/application_mmio_mux.v
add_design ../../rtl/regfile.v
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
add_design rtl/logic_analyzer_program_memory.v
add_design rtl/mes50hp_logic_analyzer_top.v
add_constraint -fdc constraints/mes50hp_logic_analyzer.fdc
compile -force_to_run -top_module {work.mes50hp_logic_analyzer_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run -packing_io
place -force_to_run -optimize_multi_corner_timing
route -force_to_run
route_optimize -force_to_run -fix_hold_violation
report_timing -force_to_run
gen_bit_stream -force_to_run
