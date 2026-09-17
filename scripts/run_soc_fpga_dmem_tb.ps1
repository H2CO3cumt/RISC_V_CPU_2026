param(
  [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$env:PATH = "$(Resolve-Path $IcarusRoot)\bin;" + $env:PATH
New-Item -ItemType Directory -Force tmp/soc_fpga_dmem | Out-Null

iverilog -g2012 -s tb_soc_fpga_dmem -o tmp/soc_fpga_dmem/tb `
  rtl/soc_fpga_memory.v tb/tb_soc_fpga_dmem.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/soc_fpga_dmem/tb
exit $LASTEXITCODE
