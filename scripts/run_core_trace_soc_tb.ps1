param(
  [string]$OutDir = 'tmp/core_trace_soc',
  [string]$LogFile = '',
  [switch]$Only1,
  [string]$PageDir = 'results/trace85_sim',
  [switch]$NoPage
)
$ErrorActionPreference='Stop'
$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}
$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force $OutDir|Out-Null
if(-not $LogFile){ $LogFile = Join-Path $OutDir 'uart.log' }
$absLog = [IO.Path]::GetFullPath($LogFile).Replace('\','/')
$vvpLog = Join-Path $OutDir 'vvp.log'

# Device under test is the real board-level SoC top plus the real firmware image.
$src=@(
  'rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v',
  'rtl/forward_unit.v','rtl/hazard_unit.v','rtl/perf_monitor.v','rtl/perf_mmio.v',
  'rtl/capture_engine.v','rtl/logic_analyzer_pattern_gen.v','rtl/logic_analyzer_mmio.v',
  'rtl/application_mmio_mux.v','rtl/application_mmio_mux3.v',
  'rtl/trace_buffer.v','rtl/core_trace_mmio.v',
  'rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v',
  'rtl/load_store_unit.v','rtl/soc_data_interconnect.v','rtl/timer_mmio.v',
  'rtl/uart_tx.v','rtl/uart_rx.v','rtl/uart_mmio.v','rtl/gpio_mmio.v',
  'fpga/trace85/rtl/logic_analyzer_program_memory.v','fpga/trace85/rtl/mes50hp_trace_top.v',
  'tb/tb_core_trace_soc.v'
)
$defs=@('-DLOGIC_ANALYZER_SIM')
if($Only1){ $defs += '-DTB_ONLY1' }
iverilog -g2012 @defs -s tb_core_trace_soc -o "$OutDir/tb" @src
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}

# vvp stdout is redirected to a file so the process can never block on a full
# pipe, and so a killed run still leaves evidence of how far it got.
$sw=[Diagnostics.Stopwatch]::StartNew()
& vvp "$OutDir/tb" "+LOG=$absLog" *> $vvpLog
$code=$LASTEXITCODE
$sw.Stop()
Get-Content $vvpLog | Select-Object -Last 60
Write-Host ("TRACE SOC VVP exit={0} wall={1:N1}s" -f $code, $sw.Elapsed.TotalSeconds)
Write-Host "TRACE SOC UART LOG $absLog"

# A PASS is not the whole story: the same log must also come out as the page the
# demo shows. Same log, same parser, same judgements -- the page is evidence.
if($code -eq 0 -and -not $NoPage){
  New-Item -ItemType Directory -Force $PageDir|Out-Null
  $mem='fpga/trace85/rtl/logic_analyzer_program.mem'
  python python/trace_view.py --log $LogFile --mem $mem --sent hello,rv --phase 0 --which 0 `
    --depth 1024 --html (Join-Path $PageDir 'trace_phase0.html')
  if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
  if(-not $Only1){
    python python/trace_view.py --log $LogFile --mem $mem --sent ABC --phase 1 --which 1 `
      --depth 1024 --html (Join-Path $PageDir 'trace_phase1.html')
    if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
  }
  Write-Host "TRACE SOC PAGES $PageDir"
}
exit $code
