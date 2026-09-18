dbg_connect -ip 127.0.0.1 -port 65420
dbg_scan_chain
dbg_program -device 0 -file {D:/RISC_V_CPU_2026/fpga/coremark_ila/generate_bitstream/mes50hp_coremark_top.sbit}
dbg_import_fic -device 0 -file {D:/RISC_V_CPU_2026/fpga/coremark_ila/mes50hp_coremark_top.fic}
dbg_delay -time 4000
dbg_fla_run -device 0 -fla 0
dbg_delay -time 4000
dbg_fla_trig_immd -device 0 -fla 0
dbg_delay -time 2000
dbg_fla_export_wf_data -device 0 -fla 0 -file {D:/RISC_V_CPU_2026/tmp/ila/coremark_ila.txt} -format txt
dbg_disconnect
dbg_close
