$ErrorActionPreference='Stop'
$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}
$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH
if(-not $env:RISCV_PREFIX){$env:RISCV_PREFIX='riscv-none-elf-'}
& make -C software/logic_analyzer clean
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& make -C software/logic_analyzer all AUTOSTART=1
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
New-Item -ItemType Directory -Force tmp/logic_analyzer_soc | Out-Null
iverilog -g2012 -s tb_logic_analyzer_soc -o tmp/logic_analyzer_soc/tb rtl/*.v fpga/logic_analyzer/rtl/mes50hp_logic_analyzer_top.v tb/pipeline_imem_adapter.v tb/ram_adapter.v tb/tb_logic_analyzer_soc.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
vvp tmp/logic_analyzer_soc/tb
exit $LASTEXITCODE
