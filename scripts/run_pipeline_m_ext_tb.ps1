param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }), [int]$MulLat = 2)
$ErrorActionPreference='Stop'; $env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH; New-Item -ItemType Directory -Force tmp/mext|Out-Null
$prefix=if($env:RISCV_PREFIX){$env:RISCV_PREFIX}else{'riscv-none-elf-'}
# M ????:??? -march=rv32im ??(RV32I ?????? mul/div)?
& "${prefix}gcc" '-march=rv32im' '-mabi=ilp32' '-mno-relax' '-nostdlib' '-nostartfiles' '-Wl,--no-relax' '-Wl,--build-id=none' '-Wl,-Ttext=0' tb/programs/m_ext.S -o tmp/mext/m_ext.elf
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objcopy" -O verilog --verilog-data-width=4 tmp/mext/m_ext.elf tmp/mext/m_ext.mem
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "${prefix}objdump" -d tmp/mext/m_ext.elf | Set-Content tmp/mext/m_ext.dis
$sources=@('rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/imem_adapter.v','tb/ram_adapter.v','tb/core_harness.v','tb/tb_pipeline_m_ext.v')
if($PSVersionTable.PSVersion.Major -ge 7){ $qs=[char]34 } else { $qs=[char]92+[char]34 }
$initDef='-DTB_ME_INIT_FILE='+$qs+'tmp/mext/m_ext.mem'+$qs; $latDef='-DTB_ME_MUL_LAT='+$MulLat
# ???????????????:?????????????/????????,
# ?"??????????"???????????
iverilog -g2012 $initDef $latDef -s tb_pipeline_m_ext -o tmp/mext/fixed @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/mext/fixed
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
iverilog -g2012 $initDef $latDef '-DTB_ME_RANDOM_DELAY=1' -s tb_pipeline_m_ext -o tmp/mext/random @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp tmp/mext/random; exit $LASTEXITCODE
