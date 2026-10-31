param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
    [switch]$FailFast
)

# Task 17 formal regression runner.  Independent suites continue after a
# failure so one invocation reports the complete failure set.  A suite whose
# build prerequisite fails is reported as FAIL by that suite; dependent suites
# are intentionally not invoked by this script until they become standalone.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resolve_host.ps1')
$powerShell = Resolve-PowerShellHost

$suites = @(
    @{ Name = 'rv32i_and_candidate_trace'; Script = 'run_single_cycle_regression.ps1' },
    @{ Name = 'gcc_programs';              Script = 'run_c_program_regression.ps1' },
    @{ Name = 'core_data_backpressure';    Script = 'run_data_interface_tb.ps1' },
    @{ Name = 'interconnect_decode';       Script = 'run_interconnect_tb.ps1' },
    @{ Name = 'ram_only_core_soc';         Script = 'run_core_interconnect_tb.ps1' },
    @{ Name = 'uart_tx';                   Script = 'run_uart_tx_tb.ps1' },
    @{ Name = 'uart_rx';                   Script = 'run_uart_rx_tb.ps1' },
    @{ Name = 'uart_mmio_tx';              Script = 'run_uart_mmio_tb.ps1' },
    @{ Name = 'uart_mmio_rx';              Script = 'run_uart_mmio_rx_tb.ps1' },
    @{ Name = 'gpio_mmio';                 Script = 'run_gpio_mmio_tb.ps1' },
    @{ Name = 'uart_gpio_interconnect';    Script = 'run_peripheral_interconnect_tb.ps1' },
    @{ Name = 'uart_gpio_core_soc';        Script = 'run_soc_harness_tb.ps1' },
    @{ Name = 'independent_soc_golden';    Script = 'run_soc_config_tb.ps1' },
    @{ Name = 'gcc_evidence_golden';       Script = 'run_gcc_evidence_tb.ps1' }
)

$passed = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($suite in $suites) {
    Write-Output "[RUN ] $($suite.Name)"
    # 子进程 stderr 在 Windows PowerShell 5.1 里会被包成 ErrorRecord，
    # 配合 $ErrorActionPreference='Stop' 会把"测试其实 PASS"误判成中断；成败只看退出码。
    $ErrorActionPreference = 'Continue'
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $suite.Script) -IcarusRoot $IcarusRoot
    $suiteExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($suiteExit -eq 0) {
        $passed.Add($suite.Name)
        Write-Output "[PASS] $($suite.Name)"
    }
    else {
        $failed.Add($suite.Name)
        Write-Output "[FAIL] $($suite.Name) (exit=$suiteExit)"
        if ($FailFast) { break }
    }
}

Write-Output "SINGLE-CYCLE REFERENCE SUMMARY: $($passed.Count) passed, $($failed.Count) failed"
if ($failed.Count -ne 0) {
    Write-Output ("SINGLE-CYCLE REFERENCE FAILED SUITES: " + ($failed -join ', '))
    exit 1
}

Write-Output 'ALL SINGLE-CYCLE REFERENCE REGRESSION PASS (READY FOR single_cycle_stable FREEZE)'
exit 0
