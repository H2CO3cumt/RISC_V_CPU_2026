param([string]$IcarusRoot=$(if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}))
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
$prefix=if($env:RISCV_PREFIX){$env:RISCV_PREFIX}else{'riscv-none-elf-'}
New-Item -ItemType Directory -Force tmp/pipeline_wb_hold | Out-Null
& "${prefix}gcc" '-march=rv32i' '-mabi=ilp32' '-mno-relax' '-nostdlib' '-nostartfiles' '-Wl,--no-relax' '-Wl,--build-id=none' '-Wl,-Ttext=0' tb/programs/task23_wb_hold.S -o tmp/pipeline_wb_hold/task23_wb_hold.elf
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objcopy" -O verilog --verilog-data-width=4 tmp/pipeline_wb_hold/task23_wb_hold.elf tmp/pipeline_wb_hold/task23_wb_hold.mem
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$sources=@('rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/task15_imem_adapter.v','tb/task15_ram_adapter.v','tb/task15_core_harness.v','tb/tb_pipeline_no_hazard.v')
foreach($random in 0,1){
  & iverilog -g2012 '-Ptb_pipeline_no_hazard.TRACE_COUNT=8' '-Ptb_pipeline_no_hazard.IMEM_DEPTH=9' '-Ptb_pipeline_no_hazard.EXPECT_STORES=2' "-Ptb_pipeline_no_hazard.RANDOM_DELAY=$random" '-Ptb_pipeline_no_hazard.INIT_FILE="tmp/pipeline_wb_hold/task23_wb_hold.mem"' -s tb_pipeline_no_hazard -o "tmp/pipeline_wb_hold/tb-$random" @sources
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  & vvp "tmp/pipeline_wb_hold/tb-$random"
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
}
Write-Host 'ALL PIPELINE WB-DURING-HOLD TEST PASS'
