param(
  [switch]$Quick,
  [switch]$RunPds,
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'})
)
$ErrorActionPreference='Stop'
$results = New-Object System.Collections.Generic.List[string]
. (Join-Path $PSScriptRoot 'resolve_host.ps1')
$powerShell = Resolve-PowerShellHost

function Run-Test([string]$name,[string]$script,[string[]]$arguments=@()) {
  Write-Host "=== $name ==="
  $resolved = (Resolve-Path -LiteralPath $script).Path
  # 子脚本的 stderr 在 Windows PowerShell 5.1 里会被包成 ErrorRecord；在
  # $ErrorActionPreference='Stop' 下即使写了 2>&1 也可能直接终止本脚本，
  # 于是"测试其实是 PASS"会被误判成整轮回归中断（本轮实测过 Task 30 Python/VCD）。
  # 这里临时放开错误动作，成败一律以子进程退出码判定，语义比依赖 stderr 更可靠。
  $ErrorActionPreference = 'Continue'
  & $powerShell -NoProfile -ExecutionPolicy Bypass -File $resolved @arguments 2>&1 | Tee-Object -Variable output
  $testExit = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if($testExit -ne 0){
    $results.Add("FAIL $name (exit $testExit)")
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
  # M 扩展（RV32IM）：单元级手算用例 + 流水线/单周期 Reference 端到端一致性。
  Run-Test 'M extension MDU unit' './scripts/run_mdu_tb.ps1'
  Run-Test 'M extension pipeline vs reference' './scripts/run_pipeline_m_ext_tb.ps1'
  Run-Test 'Task 17 single-cycle reference' './scripts/run_single_cycle_reference_regression.ps1'
  Run-Test 'Task 23 pipeline hazards/backpressure/reset/trace' './scripts/run_pipeline_regression.ps1'
  Run-Test 'Task 24 GCC single-cycle/pipeline equivalence' './scripts/run_gcc_pipeline_equivalence.ps1'
  Run-Test 'Task 25 performance events' './scripts/run_perf_monitor_tb.ps1'
  Run-Test 'Task 25 performance MMIO' './scripts/run_perf_mmio_tb.ps1'
  Run-Test 'FPGA data RAM runtime read/write closure' './scripts/run_soc_fpga_dmem_tb.ps1'
  Run-Test 'Task 26 MES50HP pipeline SoC simulation' './scripts/run_mes50hp_pipeline_soc_tb.ps1'
Run-Test 'A3 M-14 SoC timer interrupt (mtime/mtimecmp -> irq_timer_i)' './scripts/run_timer_irq_tb.ps1'
Run-Test 'A3 CSR unit' './scripts/run_csr_unit_tb.ps1'
Run-Test 'A3 precise trap/CSR/interrupt pipeline' './scripts/run_trap_pipeline_tb.ps1'
Run-Test 'A3 M-21 independent golden event judge' './scripts/run_trap_golden_judge.ps1'

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
  Run-Test 'Task 30 mirror capture (host string -> ch7 -> decoded text)' './scripts/run_logic_analyzer_mirror_tb.ps1'
Run-Test 'A6 logic-analyzer fault diagnosis (inject/capture/localize)' './scripts/run_logic_analyzer_fault_diag.ps1'
  # Commit-level trace visualisation (2026-10-21). Four layers, all Core-external:
  # the buffer itself, its MMIO slave plus the 3-way APP-window mux, the Python
  # judgements plus the pyUI input box, and the end-to-end run of the real SoC
  # top with the real firmware image.
  Run-Test 'Trace commit buffer unit' './scripts/run_trace_buffer_tb.ps1'
  Run-Test 'Trace MMIO + APP window 3-way mux' './scripts/run_core_trace_mmio_tb.ps1'
  Run-Test 'Trace Python judgements + pyUI input box' './scripts/run_trace_python.ps1'
  Run-Test 'Trace end-to-end SoC (real firmware, both phases)' './scripts/run_core_trace_soc_tb.ps1'

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
  # 【2026-09-30 交付配置切换】交付主位流 = 85 MHz PLL 版（fpga/logic_analyzer_85m）。
  # 50 MHz 版（fpga/logic_analyzer）改为已验证备用位流，仍单独校验存在性。
  Require-Artifact 'Final MES50HP logic-analyzer DELIVERY bitstream (85 MHz)' 'fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'
  Require-Artifact 'Verified fallback logic-analyzer bitstream (50 MHz)' 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit'
  Require-Artifact '85 MHz delivery board acceptance evidence' 'release/evidence/logic_analyzer_board_85m/spi/summary.json'
  Require-Artifact '85 MHz delivery soak evidence' 'release/evidence/logic_analyzer_board_85m_soak/r3/spi/summary.json'
  # 性能调优后新增交付物：80 MHz PLL 配置与调优归档（频率扫描结论的唯一证据来源）
  Require-Artifact 'CoreMark 80 MHz PLL bitstream' 'fpga/coremark_80m/generate_bitstream/mes50hp_coremark_pll_top.sbit'
  Require-Artifact 'Logic analyzer 80 MHz PLL bitstream' 'fpga/logic_analyzer_80m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'
  # 85 MHz PLL 变体（2026-09-30）：赛题"最高工作频率"指标的板级实测点，
  # 由 STATIC_RATIOF 16->17（VCO 850 MHz）得到 85.000 MHz 精确整数频率。
  Require-Artifact 'CoreMark 85 MHz PLL bitstream' 'fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit'
  # RV32IM + 交付时钟（2026-10-14 追加）：与交付同频的 M 扩展计分点
  Require-Artifact 'CoreMark 85 MHz RV32IM bitstream' 'fpga/coremark_im_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit'
  Require-Artifact '85 MHz RV32IM board CoreMark evidence' 'release/evidence/coremark_board_cmim85_20261014.json'
  # 同一份源码重建的 RV32I 同源对照点：CoreMark/LUT 的同源分母（旧 cm85 是 09-30 的旧 RTL）
  Require-Artifact 'CoreMark 85 MHz RV32I same-source bitstream' 'fpga/coremark_85m_r/generate_bitstream/mes50hp_coremark_pll_top.sbit'
  Require-Artifact '85 MHz RV32I same-source board CoreMark evidence' 'release/evidence/coremark_board_cm85r_20261014.json'
  Require-Artifact 'Logic analyzer 85 MHz PLL bitstream' 'fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'
  Require-Artifact '85 MHz board CoreMark evidence' 'release/evidence/coremark_board_cm85_20260930.json'
  # 提交级 trace（2026-10-21）：**附加演示位流**，不是交付位流；只校验它存在且两枪证据齐全，
  # 不改动上面任何一条交付位流的哈希与口径。
  Require-Artifact 'Trace 85 MHz PLL bitstream (additional demo, not the delivery bitstream)' 'fpga/trace85/generate_bitstream/mes50hp_trace_pll_top.sbit'
  Require-Artifact 'Trace phase-0 board evidence' 'release/evidence/trace85_board/trace_phase0.json'
  Require-Artifact 'Trace phase-1 board evidence' 'release/evidence/trace85_board/trace_phase1.json'
  # 0xAB 组合采集（波形 + 指令流按拍对齐）：2026-10-24 新增；
  # 判据里有一条是"波形里的数据访问脉冲数 = 对齐区间内的 load/store 条数"。
  Require-Artifact 'Trace wave+trace alignment README' 'release/evidence/trace85_board_wave/README.md'
  Require-Artifact 'Trace wave+trace alignment JSON' 'release/evidence/trace85_board_wave/trace_wave.json'
  # S1（DDR3 连通）板级复核：2026-10-24 重跑并留档。此前只有 ddr3_smoke/README 的记录，
  # 而 handoff_next §3.3 还挂着"停在下载之前"的历史告示，两边矛盾——现在有带日期的证据。
  Require-Artifact 'S1 DDR3 smoke board evidence' 'release/evidence/ddr3_s1/README.md'
  Require-Artifact 'S1 DDR3 smoke board log' 'release/evidence/ddr3_s1/ddr3_smoke_board_20261024.log'
  Require-Artifact 'N4 candidate board verification evidence' 'release/evidence/fmax_candidate_board/README.md'
  # Fmax 上界实测（2026-09-30）：CPU 板级上界 90 MHz；95 MHz 时序违例仅留档
  Require-Artifact 'CoreMark 90 MHz PLL bitstream' 'fpga/coremark_90m/generate_bitstream/mes50hp_coremark_pll_top.sbit'
  Require-Artifact 'CoreMark 95 MHz PLL bitstream (timing violated, archived)' 'fpga/coremark_95m/generate_bitstream/mes50hp_coremark_pll_top.sbit'
  Require-Artifact 'Logic analyzer 90 MHz PLL bitstream (SPI fails on board, archived)' 'fpga/logic_analyzer_90m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'
  Require-Artifact '90 MHz board CoreMark evidence' 'release/evidence/coremark_board_cm90_20260930.json'
  Require-Artifact 'Fmax ceiling report' 'release/evidence/fmax_ceiling/README.md'
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
# 显式退出码：本脚本靠 throw 表示失败，但 PowerShell 结束时会把 $LASTEXITCODE
# 留成"某条容忍过 stderr 的原生命令"的返回值（2026-10-24 实测：64 项全 PASS、
# 却带着 exit 1 出来，容易被外部 CI 或交接脚本误判成失败）。
exit 0
