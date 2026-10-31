param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/timer_irq | Out-Null
$src=@(
  'rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v',
  'rtl/hazard_unit.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v',
  'rtl/branch_unit.v','rtl/load_store_unit.v',
  'rtl/soc_data_interconnect.v','rtl/timer_mmio.v',
  'tb/pipeline_imem_adapter.v','tb/ram_adapter.v','tb/tb_timer_irq.v'
)
& iverilog -g2012 -s tb_timer_irq -o tmp/timer_irq/tb @src
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& vvp tmp/timer_irq/tb
exit $LASTEXITCODE
