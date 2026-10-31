# M-24 / N2 板级 ILA 诊断位流工程（观测 Trap 进入 / 返回）。
#
# 在 fpga/timer_demo_ila 目录下用 pds_shell 运行；由 scripts/run_timer_demo_ila_pds.ps1 调用。
#
# 【与已交付 N1 位流的关系 —— 必须保持不变】
#   本工程与 fpga/timer_demo **共用同一个顶层文件** `mes50hp_timer_demo_top.v`，
#   只是多定义了一个 `PDS_TIMER_DEMO_ILA` 宏（见 rtl/mes50hp_timer_demo_ila_top.v），
#   并把 Core 之外的 DebugCore/JTAG Hub 加进来。不定义该宏时顶层里那段探针完全看不到，
#   所以 **N1 交付位流不受任何影响**，也无需重新构建 N1。
#
# 【为什么必须单独一个工程而不是改 coremark_ila】
#   CoreMark 程序正常运行不产生 Trap，抓不到 Trap 进入/返回；
#   而 fpga/timer_demo 的固件**每 250 ms 产生一次机器定时器中断**，
#   Trap 进入 + mret 返回是周期性、可重复的，正好适合做 M-24 的 ILA 证据。
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
# 定时器是 Core 外部的 SoC 外设（中断源在 SoC 侧，docs/trap_contract.md §4.2）。
add_design ../../rtl/timer_mmio.v
# 程序镜像内存：**直接复用 fpga/timer_demo 的那份 RTL**，不复制一份会漂移的实现。
# 它内部走 `$readmemh("rtl/timer_demo_program.mem")`（相对 PDS 工作目录），
# 所以本工程 rtl/ 下必须有一份 .mem —— 由构建脚本每次从 fpga/timer_demo 复制过来。
add_design ../timer_demo/rtl/timer_demo_program_memory.v
add_design rtl/mes50hp_timer_demo_ila_top.v
# DebugCore + JTAG Hub：**直接复用 fpga/coremark_ila 已经生成好的 IP**
# （同一个"单一 192 位探针 / 50 MHz 采样 / 512 采样深度"配置），
# 不重复生成一份，避免两份 IP 配置互相漂移。
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_cfg_reg_file_v1_0.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_compare_256b_v1_0.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_data_capture_mem_v1_1.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_debug_core_v1_4.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_hub_decode_v1_3.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_rd_addr_gen_v1_4.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_storage_condition_v1_3.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_storage_qualification_v1_2.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_trig_unit_v1_3.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_trigger_condition_v1_3.v
add_design ../coremark_ila/ip/coremark_ila/rtl/ips_dbc_trigger_output_v1_2.v
add_design ../coremark_ila/ip/coremark_ila/coremark_ila.v
add_design ../coremark_ila/ip/coremark_jtag_hub/rtl/ips_jtag_hub_v1_5.v
add_design ../coremark_ila/ip/coremark_jtag_hub/coremark_jtag_hub.v
add_constraint -fdc constraints/mes50hp_timer_demo_ila.fdc
# 顶层模块名是**被 include 进来的模块名**，不是包装文件名（与 coremark_ila 一致）。
compile -force_to_run -top_module {work.mes50hp_timer_demo_top}
synthesize -force_to_run -ads -selected_syn_tool_opt 2
dev_map -force_to_run -packing_io
place -force_to_run -optimize_multi_corner_timing
route -force_to_run
route_optimize -force_to_run -fix_hold_violation
report_timing -force_to_run
gen_bit_stream -force_to_run
