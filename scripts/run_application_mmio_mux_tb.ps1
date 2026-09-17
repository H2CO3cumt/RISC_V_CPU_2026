$ErrorActionPreference='Stop';$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'};$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH;New-Item -ItemType Directory -Force tmp/application_mux|Out-Null
iverilog -g2012 -s tb_application_mmio_mux -o tmp/application_mux/tb rtl/perf_mmio.v rtl/capture_engine.v rtl/logic_analyzer_pattern_gen.v rtl/logic_analyzer_mmio.v rtl/application_mmio_mux.v tb/tb_application_mmio_mux.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};vvp tmp/application_mux/tb;exit $LASTEXITCODE
