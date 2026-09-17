$ErrorActionPreference='Stop'
$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}
$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/coremark_fpga | Out-Null
try {
  & $PSScriptRoot/generate_coremark_fpga_memory.ps1 -Iterations 1 -ClockHz 1 -AutoStart 1
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  $src=@('rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/perf_monitor.v','rtl/perf_mmio.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','rtl/soc_data_interconnect.v','rtl/uart_tx.v','rtl/uart_rx.v','rtl/uart_mmio.v','rtl/gpio_mmio.v','fpga/task28_coremark/rtl/coremark_program_memory.v','fpga/task28_coremark/rtl/mes50hp_coremark_top.v','tb/tb_mes50hp_coremark.v')
  & iverilog -g2012 -DCOREMARK_SIM -s tb_mes50hp_coremark -o tmp/coremark_fpga/tb @src
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  & vvp tmp/coremark_fpga/tb
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  $uart=Get-Content -Raw tmp/coremark_fpga/uart.log
  foreach($needle in @('[0]crclist       : 0xe714','[0]crcmatrix     : 0x1fd7','[0]crcstate      : 0x8e3a','Correct operation validated.','COREMARK_DONE')){if(-not $uart.Contains($needle)){throw "COREMARK FPGA TOP OUTPUT missing '$needle'"}}
  Write-Host 'ALL COREMARK FPGA TOP TEST PASS'
} finally {
  & $PSScriptRoot/generate_coremark_fpga_memory.ps1 -Iterations 1000 -ClockHz 50000000 -AutoStart 0
  if($LASTEXITCODE -ne 0){throw 'Failed to restore final 1000-iteration FPGA image'}
}
