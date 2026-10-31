param(
  [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
  [switch]$AllowHandoff,
  [switch]$DisablePredictor,
  [int]$MaxCycles = 4000000
)
# T1:CPI ?????????? Core ????,??????? RTL?
# ????????? coremark_imem/coremark_dmem ????,???????
# PERF_WINDOW_ALIGN=1 ?????(? start_time() ? perf_clear ????)?
$ErrorActionPreference='Stop'
if(-not $env:RISCV_PREFIX){$env:RISCV_PREFIX='riscv-none-elf-'}
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/cpi | Out-Null
& make.exe -C software/coremark clean
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& make.exe -C software/coremark all ITERATIONS=1 CLOCK_HZ=1 AUTOSTART=1 PERF_WINDOW_ALIGN=1
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$sources=@(
 'rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v',
 'rtl/perf_monitor.v','rtl/perf_mmio.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v',
 'rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v',
 'rtl/soc_data_interconnect.v','rtl/uart_tx.v','rtl/uart_rx.v',
 'rtl/uart_mmio.v','rtl/gpio_mmio.v',
 'tb/cpi_board_memory_model.v','tb/tb_cpi_attribution.v'
)
$handoff=if($AllowHandoff){1}else{0}
$predictor=if($DisablePredictor){0}else{1}
$tag="handoff$handoff-predictor$predictor"
$simLog="tmp/cpi/attribution-$tag.log"
& iverilog -g2012 "-Ptb_cpi_attribution.ALLOW_HANDOFF=$handoff" "-Ptb_cpi_attribution.ENABLE_BRANCH_PREDICTOR=$predictor" "-Ptb_cpi_attribution.MAX_CYCLES=$MaxCycles" -s tb_cpi_attribution -o tmp/cpi/tb @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& vvp tmp/cpi/tb 2>&1 | Tee-Object -FilePath $simLog
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Copy-Item -Force tmp/cpi/cycle_trace.log "tmp/cpi/cycle_trace-$tag.log"
Copy-Item -Force tmp/cpi/pc_hist.csv "tmp/cpi/pc_hist-$tag.csv"
& D:\Python313\python.exe python\cpi_attribution_report.py --pc-hist "tmp/cpi/pc_hist-$tag.csv" --log $simLog
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host "CPI ATTRIBUTION DONE tag=$tag log=$simLog"
