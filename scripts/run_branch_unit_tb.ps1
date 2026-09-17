param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH

New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -o tmp/tb_branch_unit rtl/branch_unit.v tb/tb_branch_unit.v
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

vvp tmp/tb_branch_unit
exit $LASTEXITCODE
