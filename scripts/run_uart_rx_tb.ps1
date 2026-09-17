param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_uart_rx -o tmp/uart_rx rtl/uart_rx.v tb/tb_uart_rx.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/uart_rx
exit $LASTEXITCODE
