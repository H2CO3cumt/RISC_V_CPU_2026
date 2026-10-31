param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/pipeline_load_use|Out-Null
$sources=@('rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/imem_adapter.v','tb/ram_adapter.v','tb/core_harness.v','tb/tb_pipeline_no_hazard.v')
# tb/data/load_use_halt.mem ? 4 ??? load-use(0x08?0x0c?0x10?0x14?
# 0x18?0x1c?0x24?0x28),????? 4 ????????????
# ?? 3 ???"?????"???????:??????? 0x24?0x28 ??
# ???????,?????????????????? load-use(?????
# ??????)?IF ???????,?????????? load-use?
# ?????? docs/debug_log.md?
if($PSVersionTable.PSVersion.Major -ge 7){ $qs=[char]34 } else { $qs=[char]92+[char]34 }   # 5.1 needs backslash-quote, 7 needs a bare quote (see scripts/fix_ps_host_quote_escape.py)
$initDef='-DTB_PN_INIT_FILE='+$qs+'tb/data/load_use_halt.mem'+$qs
iverilog -g2012 '-DTB_PN_TRACE_COUNT=11' '-DTB_PN_IMEM_DEPTH=12' '-DTB_PN_EXPECT_LOAD_STALL=4' $initDef -s tb_pipeline_no_hazard -o tmp/pipeline_load_use/fixed @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_load_use/fixed
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
iverilog -g2012 '-DTB_PN_TRACE_COUNT=11' '-DTB_PN_IMEM_DEPTH=12' '-DTB_PN_RANDOM_DELAY=1' $initDef -s tb_pipeline_no_hazard -o tmp/pipeline_load_use/random @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_load_use/random; exit $LASTEXITCODE
