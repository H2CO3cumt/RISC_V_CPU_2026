param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = ''
)
# 80 MHz PLL CoreMark 工程的 PDS 构建入口。
# 为什么需要：scripts/run_coremark_pds.ps1 只覆盖 50 MHz 那一套；
# 时序矩阵要求 50 MHz 与 80 MHz 两个点都用当前 RTL 重建，
# 否则"时序不退步"的结论只覆盖一半配置。
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'generate_coremark_80m_memory.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$pds = Join-Path $PdsRoot 'bin/pds_shell.exe'
if (-not (Test-Path -LiteralPath $pds)) { throw "PDS not found: $pds" }

if ($LicenseFile) { $env:PANGO_LICENSE_FILE = (Resolve-Path -LiteralPath $LicenseFile).Path }
if (-not $env:PANGO_LICENSE_FILE) {
  $found = Get-ChildItem -LiteralPath 'D:\Downloads' -File -Include 'new_pds_*.lic','PDS-*.lic','pango*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $env:PANGO_LICENSE_FILE = $found.FullName }
}
if (-not $env:PANGO_LICENSE_FILE) { Write-Warning 'PANGO_LICENSE_FILE 未设置，PDS 会报 Flow-0183。' }

$projectDir = (Resolve-Path (Join-Path $PSScriptRoot '../fpga/coremark_80m')).Path
$started = Get-Date
$hash = (Get-FileHash (Join-Path $projectDir 'pds_recipe.tcl') -Algorithm SHA256).Hash
$runRecipe = Join-Path $projectDir '.pds_coremark80m_run.tcl'

Push-Location $projectDir
$buildCode = 0
try {
  Copy-Item 'pds_recipe.tcl' $runRecipe -Force
  $output = & $pds -file $runRecipe -project_name coremark_80m_generated 2>&1
  $buildCode = $LASTEXITCODE
  $output | Tee-Object 'pds_coremark80m_build.log'
}
finally {
  Pop-Location
  if (Test-Path $runRecipe) { Remove-Item -LiteralPath $runRecipe -Force }
  $generated = Join-Path $projectDir 'impl.tcl'
  if (Test-Path $generated) { Remove-Item -LiteralPath $generated -Force }
}

$joined = ''
if (Test-Path (Join-Path $projectDir 'pds_coremark80m_build.log')) {
  $joined = (Get-Content (Join-Path $projectDir 'pds_coremark80m_build.log') -Raw)
}
if ($buildCode -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|ERROR:') {
  throw '80 MHz CoreMark PDS build failed; inspect pds_coremark80m_build.log'
}

$bit = Get-ChildItem -LiteralPath $projectDir -Recurse -File -Filter '*.sbit' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$timing = Get-ChildItem -LiteralPath $projectDir -Recurse -File -Include '*.rtr' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bit -or -not $timing) { throw 'PDS completed without fresh bitstream/timing report' }
if ((Get-FileHash (Join-Path $projectDir 'pds_recipe.tcl') -Algorithm SHA256).Hash -ne $hash) { throw 'PDS modified the source recipe' }

Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)"
Write-Host "TIMING_REPORT $($timing.FullName)"
Write-Host 'MES50HP COREMARK 80M PDS BUILD PASS'
