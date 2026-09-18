param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_interconnect -o tmp/interconnect `
    rtl/soc_data_interconnect.v tb/test_target.v tb/tb_interconnect.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/interconnect
exit $LASTEXITCODE
