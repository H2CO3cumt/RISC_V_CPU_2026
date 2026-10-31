param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/csr_unit | Out-Null
$sources=@('rtl/csr_unit.v','tb/tb_csr_unit.v')
& iverilog -g2012 -s tb_csr_unit -o tmp/csr_unit/tb @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& vvp tmp/csr_unit/tb
exit $LASTEXITCODE
