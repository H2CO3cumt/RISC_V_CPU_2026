param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_task15_interconnect -o tmp/task15_interconnect `
    rtl/soc_data_interconnect.v tb/task15_test_target.v tb/tb_task15_interconnect.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/task15_interconnect
exit $LASTEXITCODE
