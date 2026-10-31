# MES50HP PGL50H-6IFBG484 板级定时器中断演示工程（M-24 / N1）。
# 在 fpga/timer_demo 目录下用 pds_shell 运行；由 scripts/run_timer_demo_pds.ps1 调用。
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
clean -all
add_design ../../rtl/pipeline_cpu.v
add_design ../../rtl/branch_predictor.v
add_design ../../rtl/csr_unit.v
add_design ../../rtl/forward_unit.v
add_design ../../rtl/hazard_unit.v
add_design ../../rtl/perf_monitor.v
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
# 定时器是 Core 外部的 SoC 外设（中断源在 SoC 侧，docs/trap_contract.md §4.2）：
# 少了这一行，TARGET_TIMER 窗口就没有实现，程序读 mtime 会一直拿到未映射错误。
add_design ../../rtl/timer_mmio.v
add_design rtl/timer_demo_program_memory.v
add_design rtl/mes50hp_timer_demo_top.v
add_constraint -fdc constraints/mes50hp_timer_demo.fdc
compile -force_to_run -top_module {work.mes50hp_timer_demo_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run -packing_io
place -force_to_run -optimize_multi_corner_timing
route -force_to_run
route_optimize -force_to_run -fix_hold_violation
report_timing -force_to_run
gen_bit_stream -force_to_run
