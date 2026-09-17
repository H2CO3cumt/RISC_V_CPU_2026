param([string]$IcarusRoot=$(if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}))
$ErrorActionPreference='Stop';$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/pipeline_error | Out-Null
$src=@('rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/task15_imem_adapter.v','tb/task15_ram_adapter.v','tb/tb_pipeline_error_observability.v')
& iverilog -g2012 -s tb_pipeline_error_observability -o tmp/pipeline_error/tb @src
if($LASTEXITCODE-ne0){exit $LASTEXITCODE}
& vvp tmp/pipeline_error/tb
exit $LASTEXITCODE
