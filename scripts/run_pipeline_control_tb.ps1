param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/pipeline_control|Out-Null
$prefix=if($env:RISCV_PREFIX){$env:RISCV_PREFIX}else{'riscv-none-elf-'}
& "${prefix}gcc" '-march=rv32i' '-mabi=ilp32' '-mno-relax' '-nostdlib' '-nostartfiles' '-Wl,--no-relax' '-Wl,--build-id=none' '-Wl,-Ttext=0' tb/programs/control_flow.S -o tmp/pipeline_control/control_flow.elf
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objcopy" -O verilog --verilog-data-width=4 tmp/pipeline_control/control_flow.elf tmp/pipeline_control/control_flow.mem
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objdump" -d tmp/pipeline_control/control_flow.elf | Set-Content tmp/pipeline_control/control_flow.dis
$sources=@('rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/imem_adapter.v','tb/ram_adapter.v','tb/core_harness.v','tb/tb_pipeline_no_hazard.v')
if($PSVersionTable.PSVersion.Major -ge 7){ $qs=[char]34 } else { $qs=[char]92+[char]34 }   # 5.1 needs backslash-quote, 7 needs a bare quote (see scripts/fix_ps_host_quote_escape.py)
$initDef='-DTB_PN_INIT_FILE='+$qs+'tmp/pipeline_control/control_flow.mem'+$qs
iverilog -g2012 '-DTB_PN_TRACE_COUNT=13' '-DTB_PN_IMEM_DEPTH=20' '-DTB_PN_EXPECT_FLUSH=4' '-DTB_PN_PROGRAM_WORDS=19' $initDef -s tb_pipeline_no_hazard -o tmp/pipeline_control/fixed @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_control/fixed
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
iverilog -g2012 '-DTB_PN_TRACE_COUNT=13' '-DTB_PN_IMEM_DEPTH=20' '-DTB_PN_RANDOM_DELAY=1' $initDef -s tb_pipeline_no_hazard -o tmp/pipeline_control/random @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_control/random; exit $LASTEXITCODE
