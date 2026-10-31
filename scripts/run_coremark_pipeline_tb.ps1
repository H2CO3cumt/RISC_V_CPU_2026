param(
  [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
  [switch]$RandomDelay,
  [switch]$DisablePredictor,
  [int]$MaxCycles = 5000000,
  # S3:? 2 ???? I-Cache ??????(Off/On ???? TB???? Core??????)
  [switch]$EnableIcache,
  # S4:? 2 ???? D-Cache ??????;-DataSlowLatency ?????????
  [switch]$EnableDcache,
  [int]$DataSlowLatency = 0,
  # D-Cache ????:1 = ????;0 = ????(??"?? D-Cache ???",??????????)
  [int]$CacheEnD = 1,
  # ??:???????(0 = ??);>0 = ??? N ?? Core ???????
  [int]$XactLog = 0,
  # ??:????????(-TraceLen 0 = ??)
  [int]$TraceFrom = 0,
  [int]$TraceLen = 0,
  # ISA ??:?? rv32i(????)?? -March rv32im ????????
  # ??? TB???? Core ?? M ????,???? CoreMark ? Before/After?
  # ????????? build/ ??(??????????,????? fpga/ ?),
  # ???????????????
  [string]$March = 'rv32i',
  # M-extension multiply EX occupancy in cycles (rtl/mdu.v MUL_LAT): 3=baseline / 2=parallel PP / 1=combinational
  [int]$MulLat = $(if($env:MDU_MUL_LAT){[int]$env:MDU_MUL_LAT}else{2})
)
$ErrorActionPreference='Stop'
if(-not $env:RISCV_PREFIX){$env:RISCV_PREFIX='riscv-none-elf-'}
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
$copt=if($env:COREMARK_OPT){$env:COREMARK_OPT}else{"-O2"}
Write-Host ("COREMARK OPT = " + $copt)
New-Item -ItemType Directory -Force tmp/coremark | Out-Null
& make.exe -C software/coremark clean
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& make.exe -C software/coremark all ITERATIONS=1 CLOCK_HZ=1 AUTOSTART=1 MARCH=$March "COREMARK_OPT=$copt"
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host ("COREMARK ISA = " + $March)
$sources=@(
 'rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v',
 'rtl/perf_monitor.v','rtl/perf_mmio.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v',
 'rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v',
 'rtl/soc_data_interconnect.v','rtl/uart_tx.v','rtl/uart_rx.v',
 'rtl/uart_mmio.v','rtl/gpio_mmio.v','tb/pipeline_imem_adapter.v',
 'tb/ram_adapter.v','tb/tb_coremark_pipeline.v'
)
$delay=if($RandomDelay){1}else{0}
$predictor=if($DisablePredictor){0}else{1}
$ras=if($env:ENABLE_RAS){[int]$env:ENABLE_RAS}else{0}
$copt=if($env:COREMARK_OPT){$env:COREMARK_OPT}else{"-O2"}
$icache=if($EnableIcache){1}else{0}
if($icache -eq 1){ $sources += 'rtl/soc_icache_2way.v' }
$dcache=if($EnableDcache){1}else{0}
if($dcache -eq 1){ $sources += @('rtl/soc_dcache_2way.v','tb/dcache_coremark_adapter.v') }
# ??????:?????? -TraceLen ????? -P(?? 0 = ???)?
# TRACE_LEN ? TB ??"?????????????"????
#
# ?????????,??????????????"Icarus 12 ??????? -P ????
# invalid value specified for defparam"--**????**?????????????????
# UTF-8 BOM,PowerShell 5.1 ? ANSI/GBK ?????????????? BOM ?? -P ?????
# ??:???**???,?????? scripts\ensure_ps1_bom.ps1**(edit ????? BOM)?
# ??????**????????? ASCII**,??????????
$traceArgs=@()
if($TraceLen -gt 0){ $traceArgs=@("-Ptb_coremark_pipeline.TRACE_FROM=$TraceFrom","-Ptb_coremark_pipeline.TRACE_LEN=$TraceLen") }
Write-Host ("COREMARK TB CONFIG random_delay=$delay predictor=$predictor icache=$icache dcache=$dcache slow_latency=$DataSlowLatency max_cycles=$MaxCycles")
Write-Host ("IVERILOG = " + (Get-Command iverilog).Source)
& iverilog -g2012 "-Ptb_coremark_pipeline.RANDOM_DELAY=$delay" "-Ptb_coremark_pipeline.ENABLE_BRANCH_PREDICTOR=$predictor" "-Ptb_coremark_pipeline.MAX_CYCLES=$MaxCycles" "-Ptb_coremark_pipeline.ENABLE_ICACHE=$icache" "-Ptb_coremark_pipeline.ENABLE_DCACHE=$dcache" "-Ptb_coremark_pipeline.DATA_SLOW_LATENCY=$DataSlowLatency" "-Ptb_coremark_pipeline.CACHE_EN_D=$CacheEnD" "-Ptb_coremark_pipeline.ENABLE_RAS=$ras" "-Ptb_coremark_pipeline.MDU_MUL_LAT=$MulLat" "-Ptb_coremark_pipeline.XACT_LOG=$XactLog" @traceArgs -s tb_coremark_pipeline -o tmp/coremark/tb @sources
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$simLog="tmp/coremark/sim-$March-rd$delay-pred$predictor-ic$icache-dc$dcache-lat$DataSlowLatency-ras$ras.log"
& vvp tmp/coremark/tb 2>&1 | Tee-Object -FilePath $simLog
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$uart=Get-Content -Raw tmp/coremark/uart.log
# ?? ISA:CoreMark ?? COMPILER_FLAGS ????,?????????????
if(-not $uart.Contains("-march=$March")){throw "COREMARK ISA ECHO FAIL: uart.log does not report -march=$March"}
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
Copy-Item -Force tmp/coremark/uart.log "tmp/coremark/uart-$March-rd$delay-pred$predictor-ic$icache-dc$dcache-lat$DataSlowLatency-ras$ras.log"
Write-Host "ALL COREMARK PIPELINE TEST PASS march=$March random_delay=$delay predictor=$predictor icache=$icache dcache=$dcache data_latency=$DataSlowLatency"
