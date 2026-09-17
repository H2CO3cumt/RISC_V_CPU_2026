param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_uart_mmio -o tmp/uart_mmio rtl/uart_tx.v rtl/uart_rx.v rtl/uart_mmio.v tb/tb_uart_mmio.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/uart_mmio
exit $LASTEXITCODE
