param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH

New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -o tmp/tb_imm_gen rtl/imm_gen.v tb/tb_imm_gen.v
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

vvp tmp/tb_imm_gen
exit $LASTEXITCODE
