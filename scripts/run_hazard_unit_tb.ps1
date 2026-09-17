param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/hazard_unit|Out-Null
iverilog -g2012 -s tb_hazard_unit -o tmp/hazard_unit/tb rtl/hazard_unit.v tb/tb_hazard_unit.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/hazard_unit/tb; exit $LASTEXITCODE
