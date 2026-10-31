param([string]$IcarusRoot=$(if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}))
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
$prefix=if($env:RISCV_PREFIX){$env:RISCV_PREFIX}else{'riscv-none-elf-'}
New-Item -ItemType Directory -Force tmp/branch_predictor | Out-Null
& "${prefix}gcc" '-march=rv32i' '-mabi=ilp32' '-mno-relax' '-nostdlib' '-nostartfiles' '-Wl,--no-relax' '-Wl,--build-id=none' '-Wl,-Ttext=0' tb/programs/branch_predictor_loop.S -o tmp/branch_predictor/loop.elf
if($LASTEXITCODE-ne0){exit $LASTEXITCODE}
& "${prefix}objcopy" -O verilog --verilog-data-width=4 tmp/branch_predictor/loop.elf tmp/branch_predictor/loop.mem
if($LASTEXITCODE-ne0){exit $LASTEXITCODE}
$src=@('rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/imem_adapter.v','tb/ram_adapter.v','tb/tb_pipeline_branch_predictor.v')
& iverilog -g2012 -s tb_pipeline_branch_predictor -o tmp/branch_predictor/tb @src
if($LASTEXITCODE-ne0){exit $LASTEXITCODE}
& vvp tmp/branch_predictor/tb
exit $LASTEXITCODE
