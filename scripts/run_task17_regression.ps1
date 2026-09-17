param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
    [switch]$FailFast
)

# Task 17 formal regression runner.  Independent suites continue after a
# failure so one invocation reports the complete failure set.  A suite whose
# build prerequisite fails is reported as FAIL by that suite; dependent suites
# are intentionally not invoked by this script until they become standalone.
$ErrorActionPreference = 'Stop'
$powerShell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $powerShell) { $powerShell = (Get-Command powershell -ErrorAction Stop).Source }

$suites = @(
    @{ Name = 'rv32i_and_candidate_trace'; Script = 'run_task13_regression.ps1' },
    @{ Name = 'gcc_programs';              Script = 'run_task14_regression.ps1' },
    @{ Name = 'core_data_backpressure';    Script = 'run_task15_data_interface_tb.ps1' },
    @{ Name = 'interconnect_decode';       Script = 'run_task15_interconnect_tb.ps1' },
    @{ Name = 'ram_only_core_soc';         Script = 'run_task15_core_interconnect_tb.ps1' },
    @{ Name = 'uart_tx';                   Script = 'run_uart_tx_tb.ps1' },
    @{ Name = 'uart_rx';                   Script = 'run_uart_rx_tb.ps1' },
    @{ Name = 'uart_mmio_tx';              Script = 'run_uart_mmio_tb.ps1' },
    @{ Name = 'uart_mmio_rx';              Script = 'run_uart_mmio_rx_tb.ps1' },
    @{ Name = 'gpio_mmio';                 Script = 'run_gpio_mmio_tb.ps1' },
    @{ Name = 'uart_gpio_interconnect';    Script = 'run_task16_peripheral_interconnect_tb.ps1' },
    @{ Name = 'uart_gpio_core_soc';        Script = 'run_task16_soc_harness_tb.ps1' },
    @{ Name = 'independent_soc_golden';    Script = 'run_task17_soc_config_tb.ps1' },
    @{ Name = 'gcc_evidence_golden';       Script = 'run_task17_gcc_evidence_tb.ps1' }
)

$passed = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($suite in $suites) {
    Write-Output "[RUN ] $($suite.Name)"
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $suite.Script) -IcarusRoot $IcarusRoot
    if ($LASTEXITCODE -eq 0) {
        $passed.Add($suite.Name)
        Write-Output "[PASS] $($suite.Name)"
    }
    else {
        $failed.Add($suite.Name)
        Write-Output "[FAIL] $($suite.Name) (exit=$LASTEXITCODE)"
        if ($FailFast) { break }
    }
}

Write-Output "TASK17 SUMMARY: $($passed.Count) passed, $($failed.Count) failed"
if ($failed.Count -ne 0) {
    Write-Output ("TASK17 FAILED SUITES: " + ($failed -join ', '))
    exit 1
}

Write-Output 'ALL TASK17 REGRESSION PASS (READY FOR single_cycle_stable FREEZE)'
exit 0
