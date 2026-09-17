$ErrorActionPreference='Stop';$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'};$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH;New-Item -ItemType Directory -Force tmp/capture_engine|Out-Null
iverilog -g2012 -s tb_capture_engine -o tmp/capture_engine/tb rtl/capture_engine.v tb/tb_capture_engine.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};vvp tmp/capture_engine/tb;exit $LASTEXITCODE
