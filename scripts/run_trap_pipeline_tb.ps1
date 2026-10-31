param(
  [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
  # -Cpu ????? RTL(?? tmp/adv_a0/A3_WIP_pipeline_cpu.v)????????,
  # ?????????????????????? rtl/pipeline_cpu.v?
  [string]$Cpu = 'rtl/pipeline_cpu.v'
)
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/trap_pipeline | Out-Null
if (-not (Test-Path -LiteralPath $Cpu)) { throw "CPU source not found: $Cpu" }
$src=@(
  $Cpu,'rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v',
  'rtl/hazard_unit.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v',
  'rtl/branch_unit.v','rtl/load_store_unit.v',
  'tb/pipeline_imem_adapter.v','tb/ram_adapter.v','tb/tb_trap_pipeline.v'
)
& iverilog -g2012 -s tb_trap_pipeline -o tmp/trap_pipeline/tb @src
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& vvp tmp/trap_pipeline/tb
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
# ???:????/???????? Testbench??????,?????,
# ?????? M-16(?? + ????:??????????????)?
& iverilog -g2012 -DTB_TRAP_RANDOM -s tb_trap_pipeline -o tmp/trap_pipeline/tb_rand @src
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& vvp tmp/trap_pipeline/tb_rand
exit $LASTEXITCODE
