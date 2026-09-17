param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
$output = Join-Path $env:TEMP 'tb_bram_smoke.out'

& (Join-Path $icarusRootFull 'bin\iverilog.exe') -g2012 -s tb_bram_smoke -o $output `
    (Join-Path $root 'fpga\bram_smoke\rtl\bram_smoke_top.v') `
    (Join-Path $root 'tb\tb_bram_smoke.v')
if ($LASTEXITCODE -ne 0) { throw 'Icarus compilation failed.' }

& (Join-Path $icarusRootFull 'bin\vvp.exe') $output
if ($LASTEXITCODE -ne 0) { throw 'BRAM smoke simulation failed.' }
