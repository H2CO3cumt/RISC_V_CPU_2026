param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resolve_host.ps1')
$powerShell = Resolve-PowerShellHost

foreach ($scriptName in @('run_c_smoke_tb.ps1', 'run_c_array_control_tb.ps1')) {
    Write-Output "RUN $scriptName"
    # 子进程 stderr 在 Windows PowerShell 5.1 里会被包成 ErrorRecord，配合
    # $ErrorActionPreference='Stop' 会把"测试其实 PASS"误判成中断；成败只看退出码。
    $ErrorActionPreference = 'Continue'
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $scriptName) -IcarusRoot $IcarusRoot
    $suiteExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($suiteExit -ne 0) { exit $suiteExit }
}

Write-Output 'ALL C PROGRAM REGRESSION PASS'
