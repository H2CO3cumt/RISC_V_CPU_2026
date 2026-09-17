param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop';$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH;New-Item -ItemType Directory -Force tmp/logic_analyzer|Out-Null
iverilog -g2012 -s tb_logic_analyzer -o tmp/logic_analyzer/tb rtl/capture_engine.v rtl/logic_analyzer_pattern_gen.v rtl/logic_analyzer_mmio.v tb/tb_logic_analyzer.v;if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};vvp tmp/logic_analyzer/tb;exit $LASTEXITCODE
