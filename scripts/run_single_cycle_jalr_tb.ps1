param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH

New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_single_cycle_jalr -o tmp/tb_single_cycle_jalr `
    rtl/single_cycle_cpu.v rtl/regfile.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v `
    rtl/branch_unit.v rtl/load_store_unit.v rtl/dmem.v rtl/imem.v tb/task15_ram_adapter.v tb/task15_imem_adapter.v tb/task15_core_harness.v `
    tb/tb_single_cycle_jalr.v
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

vvp tmp/tb_single_cycle_jalr
exit $LASTEXITCODE
