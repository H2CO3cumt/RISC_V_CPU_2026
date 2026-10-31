param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }), [int]$MulLat = 2)
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/mdu|Out-Null
# M 扩展的乘除法单元独立验收：乘法组合通路 + 除法 32 拍迭代通路。
iverilog -g2012 "-DMUL_LAT=$MulLat" -s tb_mdu -o tmp/mdu/tb rtl/mdu.v tb/tb_mdu.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/mdu/tb; exit $LASTEXITCODE
