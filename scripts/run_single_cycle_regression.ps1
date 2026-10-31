param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resolve_host.ps1')
$powerShell = Resolve-PowerShellHost

# The repeated run is intentional: Task 13 requires reproducible results.
# 子进程 stderr 在 Windows PowerShell 5.1 里会被包成 ErrorRecord，配合
# $ErrorActionPreference='Stop' 会把"测试其实 PASS"误判成脚本中断；成败只看退出码。
foreach ($pass in 1..2) {
    Write-Output "SINGLE-CYCLE REGRESSION PASS $pass"
    $ErrorActionPreference = 'Continue'
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run_single_cycle_reference_trace_tb.ps1') -IcarusRoot $IcarusRoot
    $traceExit = $LASTEXITCODE
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run_rv32i_regression.ps1') -IcarusRoot $IcarusRoot
    $rv32iExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($traceExit -ne 0) { exit $traceExit }
    if ($rv32iExit -ne 0) { exit $rv32iExit }
}

Write-Output 'ALL SINGLE-CYCLE REFERENCE REGRESSION PASS'
