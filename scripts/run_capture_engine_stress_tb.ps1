param([string]$IcarusRoot=$(if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}))
$ErrorActionPreference='Stop';$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH;New-Item -ItemType Directory -Force tmp/capture_stress|Out-Null
iverilog -g2012 -s tb_capture_engine_stress -o tmp/capture_stress/tb rtl/capture_engine.v tb/tb_capture_engine_stress.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};vvp tmp/capture_stress/tb;exit $LASTEXITCODE
