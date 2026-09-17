param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/pipeline_hazard_stress|Out-Null
$prefix=if($env:RISCV_PREFIX){$env:RISCV_PREFIX}else{'riscv-none-elf-'}
& "${prefix}gcc" '-march=rv32i' '-mabi=ilp32' '-mno-relax' '-nostdlib' '-nostartfiles' '-Wl,--no-relax' '-Wl,--build-id=none' '-Wl,-Ttext=0' tb/programs/task23_hazard_stress.S -o tmp/pipeline_hazard_stress/task23.elf
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objcopy" -O verilog --verilog-data-width=4 tmp/pipeline_hazard_stress/task23.elf tmp/pipeline_hazard_stress/task23.mem
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objdump" -d tmp/pipeline_hazard_stress/task23.elf | Set-Content tmp/pipeline_hazard_stress/task23.dis
$sources=@('rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/task15_imem_adapter.v','tb/task15_ram_adapter.v','tb/task15_core_harness.v','tb/tb_pipeline_no_hazard.v')
iverilog -g2012 -P tb_pipeline_no_hazard.TRACE_COUNT=20 -P tb_pipeline_no_hazard.IMEM_DEPTH=24 -P tb_pipeline_no_hazard.EXPECT_LOAD_STALL=2 -P tb_pipeline_no_hazard.EXPECT_FLUSH=3 -P tb_pipeline_no_hazard.EXPECT_STORES=2 -P tb_pipeline_no_hazard.INIT_FILE='"tmp/pipeline_hazard_stress/task23.mem"' -s tb_pipeline_no_hazard -o tmp/pipeline_hazard_stress/fixed @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_hazard_stress/fixed
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
iverilog -g2012 -P tb_pipeline_no_hazard.TRACE_COUNT=20 -P tb_pipeline_no_hazard.IMEM_DEPTH=24 -P tb_pipeline_no_hazard.EXPECT_STORES=2 -P tb_pipeline_no_hazard.RANDOM_DELAY=1 -P tb_pipeline_no_hazard.INIT_FILE='"tmp/pipeline_hazard_stress/task23.mem"' -s tb_pipeline_no_hazard -o tmp/pipeline_hazard_stress/random @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/pipeline_hazard_stress/random; exit $LASTEXITCODE
