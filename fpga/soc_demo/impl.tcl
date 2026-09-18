# Task 16 MES50HP batch project and implementation script.
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
clean -all
add_design ../../rtl/single_cycle_cpu.v
add_design ../../rtl/regfile.v
add_design ../../rtl/alu.v
add_design ../../rtl/imm_gen.v
add_design ../../rtl/decoder.v
add_design ../../rtl/branch_unit.v
add_design ../../rtl/load_store_unit.v
add_design ../../rtl/soc_data_interconnect.v
add_design ../../rtl/soc_fpga_memory.v
add_design ../../rtl/uart_tx.v
add_design ../../rtl/uart_rx.v
add_design ../../rtl/uart_mmio.v
add_design ../../rtl/gpio_mmio.v
add_design rtl/mes50hp_soc_demo_top.v
add_constraint -fdc constraints/mes50hp_soc_demo.fdc
compile -force_to_run -top_module {work.mes50hp_soc_demo_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run -packing_io
place -force_to_run -optimize_multi_corner_timing
route -force_to_run
route_optimize -force_to_run -fix_hold_violation
report_timing -force_to_run
gen_bit_stream -force_to_run
add_design "D:/RISC_V_CPU_2026/rtl/single_cycle_cpu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/regfile.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/alu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/imm_gen.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/decoder.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/branch_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/load_store_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_data_interconnect.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_fpga_memory.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_tx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_rx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/gpio_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/fpga/soc_demo/rtl/mes50hp_soc_demo_top.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/single_cycle_cpu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/regfile.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/alu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/imm_gen.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/decoder.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/branch_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/load_store_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_data_interconnect.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_fpga_memory.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_tx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_rx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/gpio_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/fpga/soc_demo/rtl/mes50hp_soc_demo_top.v" -library work
add_constraint "D:/RISC_V_CPU_2026/fpga/soc_demo/constraints/mes50hp_soc_demo.fdc"
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {work.mes50hp_soc_demo_top} 
synthesize -ads -selected_syn_tool_opt 2 
dev_map -packing_io 
place -optimize_multi_corner_timing 
route 
route_optimize -fix_hold_violation 
report_timing 
gen_bit_stream 
add_design "D:/RISC_V_CPU_2026/rtl/single_cycle_cpu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/regfile.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/alu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/imm_gen.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/decoder.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/branch_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/load_store_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_data_interconnect.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_fpga_memory.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_tx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_rx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/gpio_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/fpga/soc_demo/rtl/mes50hp_soc_demo_top.v" -library work
add_constraint "D:/RISC_V_CPU_2026/fpga/soc_demo/constraints/mes50hp_soc_demo.fdc"
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {work.mes50hp_soc_demo_top} 
synthesize -ads -selected_syn_tool_opt 2 
dev_map -packing_io 
place -optimize_multi_corner_timing 
route 
route_optimize -fix_hold_violation 
report_timing 
gen_bit_stream 
add_design "D:/RISC_V_CPU_2026/rtl/single_cycle_cpu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/regfile.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/alu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/imm_gen.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/decoder.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/branch_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/load_store_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_data_interconnect.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_fpga_memory.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_tx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_rx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/gpio_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/fpga/soc_demo/rtl/mes50hp_soc_demo_top.v" -library work
add_constraint "D:/RISC_V_CPU_2026/fpga/soc_demo/constraints/mes50hp_soc_demo.fdc"
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -force_to_run -top_module {work.mes50hp_soc_demo_top} 
synthesize -force_to_run -ads -selected_syn_tool_opt 2 
dev_map -force_to_run -packing_io 
place -force_to_run -optimize_multi_corner_timing 
route -force_to_run 
route_optimize -force_to_run -fix_hold_violation 
report_timing -force_to_run 
gen_bit_stream -force_to_run 
add_design "D:/RISC_V_CPU_2026/rtl/single_cycle_cpu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/regfile.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/alu.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/imm_gen.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/decoder.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/branch_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/load_store_unit.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_data_interconnect.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/soc_fpga_memory.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_tx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_rx.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/uart_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/rtl/gpio_mmio.v" -library work
add_design "D:/RISC_V_CPU_2026/fpga/soc_demo/rtl/mes50hp_soc_demo_top.v" -library work
add_constraint "D:/RISC_V_CPU_2026/fpga/soc_demo/constraints/mes50hp_soc_demo.fdc"
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -force_to_run -top_module {work.mes50hp_soc_demo_top} 
synthesize -force_to_run -ads -selected_syn_tool_opt 2 
dev_map -force_to_run -packing_io 
place -force_to_run -optimize_multi_corner_timing 
route -force_to_run 
route_optimize -force_to_run -fix_hold_violation 
report_timing -force_to_run 
gen_bit_stream -force_to_run 
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -force_to_run -top_module {work.mes50hp_soc_demo_top} 
synthesize -force_to_run -ads -selected_syn_tool_opt 2 
dev_map -force_to_run -packing_io 
place -force_to_run -optimize_multi_corner_timing 
route -force_to_run 
route_optimize -force_to_run -fix_hold_violation 
report_timing -force_to_run 
gen_bit_stream -force_to_run 
gen_bit_stream -force_to_run 
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -force_to_run -top_module {work.mes50hp_soc_demo_top} 
synthesize -force_to_run -ads -selected_syn_tool_opt 2 
dev_map -force_to_run -packing_io 
place -force_to_run -optimize_multi_corner_timing 
route -force_to_run 
route_optimize -force_to_run -fix_hold_violation 
report_timing -force_to_run 
gen_bit_stream -force_to_run 
set_option max_threads 0
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -force_to_run -top_module {work.mes50hp_soc_demo_top} 
synthesize -force_to_run -ads -selected_syn_tool_opt 2 
dev_map -force_to_run -packing_io 
place -force_to_run -optimize_multi_corner_timing 
route -force_to_run 
route_optimize -force_to_run -fix_hold_violation 
report_timing -force_to_run 
gen_bit_stream -force_to_run 
