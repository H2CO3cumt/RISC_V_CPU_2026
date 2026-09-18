param(
  [switch]$Quick,
  [switch]$RunPds,
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'})
)
$ErrorActionPreference='Stop'
$results = New-Object System.Collections.Generic.List[string]
$powerShell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $powerShell) { $powerShell = (Get-Command powershell -ErrorAction Stop).Source }

function Run-Test([string]$name,[string]$script,[string[]]$arguments=@()) {
  Write-Host "=== $name ==="
  $resolved = (Resolve-Path -LiteralPath $script).Path
  & $powerShell -NoProfile -ExecutionPolicy Bypass -File $resolved @arguments 2>&1 | Tee-Object -Variable output
  if($LASTEXITCODE -ne 0){
    $results.Add("FAIL $name (exit $LASTEXITCODE)")
    throw "FINAL REGRESSION STOP: $name"
  }
  $results.Add("PASS $name")
}

function Require-Artifact([string]$name,[string]$path) {
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
    $results.Add("FAIL $name (missing $path)")
    throw "FINAL REGRESSION STOP: missing $path"
  }
  $item=Get-Item -LiteralPath $path
  if($item.Length -eq 0){throw "FINAL REGRESSION STOP: empty $path"}
  $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $results.Add("PASS $name bytes=$($item.Length) sha256=$hash")
}

New-Item -ItemType Directory -Force tmp | Out-Null
try {
  Run-Test 'Task 12 complete RV32I' './scripts/run_rv32i_regression.ps1'
  Run-Test 'Task 17 single-cycle reference' './scripts/run_single_cycle_reference_regression.ps1'
  Run-Test 'Task 23 pipeline hazards/backpressure/reset/trace' './scripts/run_pipeline_regression.ps1'
  Run-Test 'Task 24 GCC single-cycle/pipeline equivalence' './scripts/run_gcc_pipeline_equivalence.ps1'
  Run-Test 'Task 25 performance events' './scripts/run_perf_monitor_tb.ps1'
  Run-Test 'Task 25 performance MMIO' './scripts/run_perf_mmio_tb.ps1'
  Run-Test 'FPGA data RAM runtime read/write closure' './scripts/run_soc_fpga_dmem_tb.ps1'
  Run-Test 'Task 26 MES50HP pipeline SoC simulation' './scripts/run_mes50hp_pipeline_soc_tb.ps1'

  if(-not $Quick){
    Run-Test 'Task 28 official CoreMark fixed latency' './scripts/run_coremark_pipeline_tb.ps1'
    Run-Test 'Task 28 official CoreMark random backpressure' './scripts/run_coremark_pipeline_tb.ps1' @('-RandomDelay')
    Run-Test 'Task 28 initialized FPGA memory model' './scripts/run_coremark_fpga_tb.ps1'
  }
  Run-Test 'Task 28 serial result parser' './scripts/run_coremark_serial_python.ps1'

  Run-Test 'Task 30 capture engine' './scripts/run_capture_engine_tb.ps1'
  Run-Test 'Task 30 20-run capture/reset stress' './scripts/run_capture_engine_stress_tb.ps1'
  Run-Test 'Task 30 programmable loopback generator' './scripts/run_logic_analyzer_pattern_tb.ps1'
  Run-Test 'Task 30 logic-analyzer MMIO' './scripts/run_logic_analyzer_tb.ps1'
  Run-Test 'Task 30 application MMIO mux' './scripts/run_application_mmio_mux_tb.ps1'
  Run-Test 'Task 30 interactive board-top/UART protocol' './scripts/run_logic_analyzer_board_top_tb.ps1'
  Run-Test 'Task 30 80 MHz PLL board-top/UART/capture' './scripts/run_logic_analyzer_pll80_board_top_tb.ps1'
  Run-Test 'Task 30 software/SoC integration' './scripts/run_logic_analyzer_soc_tb.ps1'
  Run-Test 'Task 30 Python/VCD tools' './scripts/run_logic_analyzer_python.ps1'

  Run-Test 'Task 29 performance report' './scripts/run_performance_report.ps1'
  Run-Test 'Task 29 PDS/CoreMark evidence extraction' './scripts/run_release_evidence.ps1'
  Run-Test 'Task 33 frozen-scope audit' './scripts/run_scope_audit.ps1'

  if($RunPds){
    Run-Test 'Task 26 PDS build' './scripts/run_mes50hp_pipeline_pds.ps1' @('-LicenseFile',$LicenseFile)
    Run-Test 'Task 28 PDS build' './scripts/run_coremark_pds.ps1' @('-LicenseFile',$LicenseFile)
    Run-Test 'Task 29 CoreMark DebugCore PDS build' './scripts/run_coremark_ila_pds.ps1' @('-LicenseFile',$LicenseFile)
    Run-Test 'Task 30 PDS build' './scripts/run_logic_analyzer_pds.ps1' @('-LicenseFile',$LicenseFile)
  }

  if(-not (Test-Path 'third_party/coremark/core_main.c')){throw 'Official CoreMark source is missing'}
  Require-Artifact 'Final MES50HP logic-analyzer bitstream' 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit'
  # 性能调优后新增交付物：80 MHz PLL 配置与调优归档（频率扫描结论的唯一证据来源）
  Require-Artifact 'CoreMark 80 MHz PLL bitstream' 'fpga/coremark_80m/generate_bitstream/mes50hp_coremark_pll_top.sbit'
  Require-Artifact 'Logic analyzer 80 MHz PLL bitstream' 'fpga/logic_analyzer_80m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'
  Require-Artifact 'CoreMark 50 MHz optimized bitstream' 'release/artifacts/fmax_tuning_2026-09-17/coremark_50m_optimized.sbit'
  Require-Artifact 'Logic analyzer 50 MHz optimized bitstream' 'release/artifacts/fmax_tuning_2026-09-17/la_50m_optimized.sbit'
  Require-Artifact 'Pre-tuning logic analyzer bitstream archive' 'release/artifacts/fmax_tuning_2026-09-17/la_50m_pre_tuning_ARCHIVE.sbit'
  # CPI 优化专项（2026-09-17）：取指满速交接后的四套位流，全部已实体板实测
  Require-Artifact 'CPI tuning CoreMark 50 MHz bitstream' 'release/artifacts/cpi_tuning_2026-09-17/coremark_50m_cpi.sbit'
  Require-Artifact 'CPI tuning CoreMark 80 MHz PLL bitstream' 'release/artifacts/cpi_tuning_2026-09-17/coremark_80m_pll_cpi.sbit'
  Require-Artifact 'CPI tuning logic analyzer 50 MHz bitstream' 'release/artifacts/cpi_tuning_2026-09-17/la_50m_cpi.sbit'
  Require-Artifact 'CPI tuning logic analyzer 80 MHz PLL bitstream' 'release/artifacts/cpi_tuning_2026-09-17/la_80m_pll_cpi.sbit'
  Require-Artifact 'CPI tuning board evidence 50 MHz' 'release/evidence/coremark_board_cpi50m.json'
  Require-Artifact 'CPI tuning board evidence 80 MHz PLL' 'release/evidence/coremark_board_cpi80m.json'
} catch {
  Write-Host $_
  $results | Set-Content tmp/final_regression_summary.txt
  exit 1
}
$results | Tee-Object tmp/final_regression_summary.txt
Write-Host 'ALL AUTOMATED FINAL REGRESSION PASS'
Write-Host 'Physical JTAG/UART/loopback evidence is tracked separately and cannot be fabricated without an attached MES50HP.'
