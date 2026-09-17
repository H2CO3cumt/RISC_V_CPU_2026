param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_gpio_mmio -o tmp/gpio_mmio rtl/gpio_mmio.v tb/tb_gpio_mmio.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/gpio_mmio
exit $LASTEXITCODE
