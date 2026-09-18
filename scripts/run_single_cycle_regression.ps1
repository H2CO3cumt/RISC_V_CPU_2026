param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$powerShell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $powerShell) { $powerShell = (Get-Command powershell -ErrorAction Stop).Source }

# The repeated run is intentional: Task 13 requires reproducible results.
foreach ($pass in 1..2) {
    Write-Output "SINGLE-CYCLE REGRESSION PASS $pass"
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run_single_cycle_reference_trace_tb.ps1') -IcarusRoot $IcarusRoot
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run_rv32i_regression.ps1') -IcarusRoot $IcarusRoot
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Output 'ALL SINGLE-CYCLE REFERENCE REGRESSION PASS'
