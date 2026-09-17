param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_uart_tx -o tmp/uart_tx rtl/uart_tx.v tb/tb_uart_tx.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/uart_tx
exit $LASTEXITCODE
