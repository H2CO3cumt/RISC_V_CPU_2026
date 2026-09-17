param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop';$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH;New-Item -ItemType Directory -Force tmp/perf_mmio|Out-Null
iverilog -g2012 -s tb_perf_mmio -o tmp/perf_mmio/tb rtl/perf_mmio.v tb/tb_perf_mmio.v;if($LASTEXITCODE-ne0){exit $LASTEXITCODE};vvp tmp/perf_mmio/tb;exit $LASTEXITCODE
