param(
  [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$env:PATH = "$(Resolve-Path $IcarusRoot)\bin;" + $env:PATH
New-Item -ItemType Directory -Force tmp/branch_predictor | Out-Null

iverilog -g2012 -s tb_branch_predictor -o tmp/branch_predictor/tb `
  rtl/branch_predictor.v tb/tb_branch_predictor.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/branch_predictor/tb
exit $LASTEXITCODE
