param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp | Out-Null

iverilog -g2012 -s tb_peripheral_interconnect -o tmp/peripheral_interconnect `
    rtl/soc_data_interconnect.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_mmio.v rtl/gpio_mmio.v `
    tb/ram_adapter.v tb/test_target.v tb/tb_peripheral_interconnect.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/peripheral_interconnect
exit $LASTEXITCODE
