param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop';$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH;New-Item -ItemType Directory -Force tmp/perf_monitor|Out-Null
iverilog -g2012 -s tb_perf_monitor -o tmp/perf_monitor/tb rtl/perf_monitor.v tb/tb_perf_monitor.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};vvp tmp/perf_monitor/tb;exit $LASTEXITCODE
