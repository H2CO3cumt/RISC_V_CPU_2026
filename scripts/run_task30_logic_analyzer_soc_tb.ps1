$ErrorActionPreference='Stop'
$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}
$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH
if(-not $env:RISCV_PREFIX){$env:RISCV_PREFIX='riscv-none-elf-'}
& make -C software/task30_logic_analyzer clean
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& make -C software/task30_logic_analyzer all AUTOSTART=1
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
New-Item -ItemType Directory -Force tmp/task30_soc | Out-Null
iverilog -g2012 -s tb_task30_logic_analyzer_soc -o tmp/task30_soc/tb rtl/*.v fpga/task30_logic_analyzer/rtl/mes50hp_logic_analyzer_top.v tb/pipeline_imem_adapter.v tb/task15_ram_adapter.v tb/tb_task30_logic_analyzer_soc.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
vvp tmp/task30_soc/tb
exit $LASTEXITCODE
