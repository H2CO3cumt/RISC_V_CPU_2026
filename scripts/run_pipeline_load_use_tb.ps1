param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/pipeline_load_use|Out-Null
$sources=@('rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/imem_adapter.v','tb/ram_adapter.v','tb/core_harness.v','tb/tb_pipeline_no_hazard.v')
# tb/data/load_use.mem 含 4 组相邻 load-use（0x08→0x0c、0x10→0x14、
# 0x18→0x1c、0x24→0x28），满速取指下 4 组都必须检出并插入气泡。
# 旧值 3 是取指“每两拍一条”时代的历史标定：当时取指空洞在 0x24→0x28 之间
# 插入了一个气泡，令该组相邻指令天然相隔两级而不再构成 load-use（既不检出、
# 也不需要停顿）。IF 达到每拍一条后，该组恢复为真正的相邻 load-use。
# 逐事件证据见 docs/debug_log.md。
iverilog -g2012 -P tb_pipeline_no_hazard.TRACE_COUNT=11 -P tb_pipeline_no_hazard.IMEM_DEPTH=11 -P tb_pipeline_no_hazard.EXPECT_LOAD_STALL=4 -P tb_pipeline_no_hazard.INIT_FILE='"tb/data/load_use.mem"' -s tb_pipeline_no_hazard -o tmp/pipeline_load_use/fixed @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_load_use/fixed
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
iverilog -g2012 -P tb_pipeline_no_hazard.TRACE_COUNT=11 -P tb_pipeline_no_hazard.IMEM_DEPTH=11 -P tb_pipeline_no_hazard.RANDOM_DELAY=1 -P tb_pipeline_no_hazard.INIT_FILE='"tb/data/load_use.mem"' -s tb_pipeline_no_hazard -o tmp/pipeline_load_use/random @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_load_use/random; exit $LASTEXITCODE
