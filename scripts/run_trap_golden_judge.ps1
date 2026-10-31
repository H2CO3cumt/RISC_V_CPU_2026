param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/trap_golden | Out-Null
$src=@(
  'rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v',
  'rtl/hazard_unit.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v',
  'rtl/branch_unit.v','rtl/load_store_unit.v',
  'tb/pipeline_imem_adapter.v','tb/ram_adapter.v','tb/tb_trap_golden.v'
)
& iverilog -g2012 -s tb_trap_golden -o tmp/trap_golden/tb @src
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& vvp tmp/trap_golden/tb
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
# ????????:?????????,?? Core ?????????????
$python = if($env:PYTHON) { $env:PYTHON } else { (Get-Command python -ErrorAction Stop).Source }
& $python python/trap_golden_judge.py
exit $LASTEXITCODE
