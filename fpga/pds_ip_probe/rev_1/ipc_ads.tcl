# Generated at 2026-09-15 21:49

set_arch -family Logos -device PGL50H -package FBG484 -speedgrade -6
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_cfg_reg_file_v1_0.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_compare_256b_v1_0.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_data_capture_mem_v1_1.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_debug_core_v1_4.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_hub_decode_v1_3.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_rd_addr_gen_v1_4.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_storage_condition_v1_3.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_storage_qualification_v1_2.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_trig_unit_v1_3.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_trigger_condition_v1_3.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/rtl/ips_dbc_trigger_output_v1_2.v"
add_design "D:/RISC_V_CPU_2026/fpga/pds_ip_probe/debug_core.v"
compile -top_module debug_core
synthesize -ads
