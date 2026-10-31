param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/pipeline_reset_abort|Out-Null
iverilog -g2012 -s tb_pipeline_reset_abort -o tmp/pipeline_reset_abort/tb rtl/pipeline_cpu.v rtl/fetch_fifo.v rtl/ras.v rtl/branch_predictor.v rtl/csr_unit.v rtl/forward_unit.v rtl/hazard_unit.v rtl/regfile.v rtl/mdu.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v rtl/branch_unit.v rtl/load_store_unit.v tb/pipeline_imem_adapter.v tb/tb_pipeline_reset_abort.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_reset_abort/tb; exit $LASTEXITCODE
