param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference = 'Stop'
$env:PATH = "$(Resolve-Path -LiteralPath $IcarusRoot)\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null
iverilog -g2012 -s tb_mes50hp_soc_demo -o tmp/mes50hp_soc_demo rtl/single_cycle_cpu.v rtl/regfile.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v rtl/branch_unit.v rtl/load_store_unit.v rtl/soc_data_interconnect.v rtl/soc_fpga_memory.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_mmio.v rtl/gpio_mmio.v fpga/soc_demo/rtl/mes50hp_soc_demo_top.v tb/tb_mes50hp_soc_demo.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
vvp tmp/mes50hp_soc_demo
exit $LASTEXITCODE
