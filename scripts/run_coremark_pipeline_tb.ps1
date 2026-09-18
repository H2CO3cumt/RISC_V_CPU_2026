param(
  [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
  [switch]$RandomDelay,
  [switch]$DisablePredictor,
  [int]$MaxCycles = 5000000
)
$ErrorActionPreference='Stop'
if(-not $env:RISCV_PREFIX){$env:RISCV_PREFIX='riscv-none-elf-'}
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/coremark | Out-Null
& make.exe -C software/coremark clean
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& make.exe -C software/coremark all ITERATIONS=1 CLOCK_HZ=1 AUTOSTART=1
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$sources=@(
 'rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v',
 'rtl/perf_monitor.v','rtl/perf_mmio.v','rtl/regfile.v','rtl/alu.v',
 'rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v',
 'rtl/soc_data_interconnect.v','rtl/uart_tx.v','rtl/uart_rx.v',
 'rtl/uart_mmio.v','rtl/gpio_mmio.v','tb/pipeline_imem_adapter.v',
 'tb/ram_adapter.v','tb/tb_coremark_pipeline.v'
)
$delay=if($RandomDelay){1}else{0}
$predictor=if($DisablePredictor){0}else{1}
& iverilog -g2012 "-Ptb_coremark_pipeline.RANDOM_DELAY=$delay" "-Ptb_coremark_pipeline.ENABLE_BRANCH_PREDICTOR=$predictor" "-Ptb_coremark_pipeline.MAX_CYCLES=$MaxCycles" -s tb_coremark_pipeline -o tmp/coremark/tb @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$simLog="tmp/coremark/sim-random-$delay-predictor-$predictor.log"
& vvp tmp/coremark/tb 2>&1 | Tee-Object -FilePath $simLog
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$uart=Get-Content -Raw tmp/coremark/uart.log
$required=@(
 '2K performance run parameters for coremark.',
 '[0]crclist       : 0xe714',
 '[0]crcmatrix     : 0x1fd7',
 '[0]crcstate      : 0x8e3a',
 'Correct operation validated.',
 'COREMARK_DONE'
)
foreach($needle in $required){
 if(-not $uart.Contains($needle)){throw "COREMARK OUTPUT FAIL: missing '$needle'"}
}
if($uart.Contains('Errors detected')){throw 'COREMARK OUTPUT FAIL: benchmark reported errors'}
Copy-Item -Force tmp/coremark/uart.log "tmp/coremark/uart-random-$delay-predictor-$predictor.log"
Write-Host "ALL COREMARK PIPELINE TEST PASS random_delay=$delay predictor=$predictor"
