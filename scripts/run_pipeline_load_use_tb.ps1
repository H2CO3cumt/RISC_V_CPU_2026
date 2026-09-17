param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/pipeline_load_use|Out-Null
$sources=@('rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/task15_imem_adapter.v','tb/task15_ram_adapter.v','tb/task15_core_harness.v','tb/tb_pipeline_no_hazard.v')
iverilog -g2012 -P tb_pipeline_no_hazard.TRACE_COUNT=11 -P tb_pipeline_no_hazard.IMEM_DEPTH=11 -P tb_pipeline_no_hazard.EXPECT_LOAD_STALL=3 -P tb_pipeline_no_hazard.INIT_FILE='"tb/data/task21_load_use.mem"' -s tb_pipeline_no_hazard -o tmp/pipeline_load_use/fixed @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_load_use/fixed
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
iverilog -g2012 -P tb_pipeline_no_hazard.TRACE_COUNT=11 -P tb_pipeline_no_hazard.IMEM_DEPTH=11 -P tb_pipeline_no_hazard.RANDOM_DELAY=1 -P tb_pipeline_no_hazard.INIT_FILE='"tb/data/task21_load_use.mem"' -s tb_pipeline_no_hazard -o tmp/pipeline_load_use/random @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_load_use/random; exit $LASTEXITCODE
