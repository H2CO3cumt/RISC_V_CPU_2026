param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/forward_unit|Out-Null
iverilog -g2012 -s tb_forward_unit -o tmp/forward_unit/tb rtl/forward_unit.v tb/tb_forward_unit.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/forward_unit/tb; exit $LASTEXITCODE
