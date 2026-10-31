param([string]$IcarusRoot=$(if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}))
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
$prefix=if($env:RISCV_PREFIX){$env:RISCV_PREFIX}else{'riscv-none-elf-'}
New-Item -ItemType Directory -Force tmp/pipeline_wb_hold | Out-Null
& "${prefix}gcc" '-march=rv32i' '-mabi=ilp32' '-mno-relax' '-nostdlib' '-nostartfiles' '-Wl,--no-relax' '-Wl,--build-id=none' '-Wl,-Ttext=0' tb/programs/wb_hold.S -o tmp/pipeline_wb_hold/wb_hold.elf
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objcopy" -O verilog --verilog-data-width=4 tmp/pipeline_wb_hold/wb_hold.elf tmp/pipeline_wb_hold/wb_hold.mem
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$sources=@('rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/imem_adapter.v','tb/ram_adapter.v','tb/core_harness.v','tb/tb_pipeline_no_hazard.v')
foreach($random in 0,1){
if($PSVersionTable.PSVersion.Major -ge 7){ $qs=[char]34 } else { $qs=[char]92+[char]34 }   # 5.1 needs backslash-quote, 7 needs a bare quote (see scripts/fix_ps_host_quote_escape.py)
$initDef='-DTB_PN_INIT_FILE='+$qs+'tmp/pipeline_wb_hold/wb_hold.mem'+$qs
  & iverilog -g2012 '-DTB_PN_TRACE_COUNT=8' '-DTB_PN_IMEM_DEPTH=9' '-DTB_PN_EXPECT_STORES=2' "-DTB_PN_RANDOM_DELAY=$random" $initDef -s tb_pipeline_no_hazard -o "tmp/pipeline_wb_hold/tb-$random" @sources
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  & vvp "tmp/pipeline_wb_hold/tb-$random"
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
}
Write-Host 'ALL PIPELINE WB-DURING-HOLD TEST PASS'
