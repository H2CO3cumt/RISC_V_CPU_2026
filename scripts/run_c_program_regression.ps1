param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$powerShell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $powerShell) { $powerShell = (Get-Command powershell -ErrorAction Stop).Source }

foreach ($scriptName in @('run_c_smoke_tb.ps1', 'run_c_array_control_tb.ps1')) {
    Write-Output "RUN $scriptName"
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $scriptName) -IcarusRoot $IcarusRoot
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Output 'ALL C PROGRAM REGRESSION PASS'
