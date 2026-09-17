param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_task16_soc_harness -o tmp/task16_soc_harness `
    rtl/single_cycle_cpu.v rtl/regfile.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v rtl/branch_unit.v rtl/load_store_unit.v `
    rtl/soc_data_interconnect.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_mmio.v rtl/gpio_mmio.v `
    tb/task15_imem_adapter.v tb/task15_ram_adapter.v tb/task15_test_target.v tb/tb_task16_soc_harness.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/task16_soc_harness
exit $LASTEXITCODE
