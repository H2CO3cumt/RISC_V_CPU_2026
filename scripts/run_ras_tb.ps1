param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
    [string]$OutDir     = 'tmp/ras'
)
$ErrorActionPreference = 'Stop'
$env:PATH = "$(Resolve-Path $IcarusRoot)\bin;" + $env:PATH

New-Item -ItemType Directory -Force $OutDir | Out-Null

$src = @(
    'rtl/ras.v',
    'tb/tb_ras.v'
)

# Both depths must pass. DEPTH=1 exercises the IMASK=0 pointer path, which is
# the easiest one to get wrong (an out-of-range array read returns X).
# Pass/fail is parsed from TB text output, not from vvp's exit code.
# NOTE: keep this file pure ASCII; Windows PowerShell 5.1 reads .ps1 as ANSI and
# mis-parses UTF-8 Chinese comments.
foreach ($depth in 8, 4, 2, 1) {
    Write-Host "=== DEPTH=$depth ==="

    & iverilog -g2012 "-Ptb_ras.DEPTH=$depth" -s tb_ras -o "$OutDir/tb$depth" @src
    if ($LASTEXITCODE -ne 0) {
        Write-Host "COMPILE FAILED (DEPTH=$depth)"
        exit 1
    }

    $out = & vvp "$OutDir/tb$depth"
    $txt = $out -join "`n"
    $out | Where-Object { $_ -match 'FAIL|ALL TEST PASS' } | ForEach-Object { Write-Host $_ }

    if ($txt -match 'TEST FAIL') {
        Write-Host "RAS TB: FAILED (DEPTH=$depth)"
        exit 1
    }
    if ($txt -notmatch 'ALL TEST PASS') {
        Write-Host "RAS TB: FAILED (DEPTH=$depth, missing ALL TEST PASS)"
        exit 1
    }
    Write-Host ""
}

Write-Host "RAS TB: ALL DEPTHS PASS"
exit 0
