param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_data_interface -o tmp/data_interface `
    rtl/single_cycle_cpu.v rtl/regfile.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v `
    rtl/branch_unit.v rtl/load_store_unit.v `
    tb/ram_adapter.v tb/imem_adapter.v tb/tb_data_interface.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/data_interface
exit $LASTEXITCODE
