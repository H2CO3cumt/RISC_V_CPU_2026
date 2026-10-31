param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = ''
)
# Build the trace85 bitstream (fpga/trace85).
#
# This is an ADDITIONAL demo bitstream for "commit-level trace visualisation".
# It must never replace the delivered la85 bitstream: that one carries the
# frozen 100/100 board acceptance evidence and the claims_map hashes.
#
# The recipe lives in fpga/trace85/pds_recipe.tcl.  It lists fetch_fifo.v and
# ras.v explicitly, because pipeline_cpu instantiates `ras` unconditionally and
# PDS fails the whole flow when a referenced module is undefined.
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectDir=Join-Path $repo 'fpga/trace85'
if(-not (Test-Path -LiteralPath $projectDir)){ throw "project dir missing: $projectDir" }

$pds=Join-Path $PdsRoot 'bin/pds_shell.exe'
if(-not (Test-Path -LiteralPath $pds)){ throw "PDS not found: $pds" }

if($LicenseFile){ $env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path }
if(-not $env:PANGO_LICENSE_FILE){
  foreach($cand in @('D:\Downloads\new_pds_60452e195a32.lic')){
    if(Test-Path -LiteralPath $cand){ $env:PANGO_LICENSE_FILE=$cand; break }
  }
}
if(-not $env:PANGO_LICENSE_FILE){
  $found=Get-ChildItem -LiteralPath 'D:\Downloads' -File -Filter '*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
  if($found){ $env:PANGO_LICENSE_FILE=$found.FullName }
}
if(-not $env:PANGO_LICENSE_FILE){ Write-Warning 'PANGO_LICENSE_FILE not set; PDS will fail with Flow-0183' }
else { Write-Host "LICENSE $env:PANGO_LICENSE_FILE" }

Push-Location $projectDir
try {
  $started=Get-Date
  $runRecipe=Join-Path $projectDir '.pds_trace85_run.tcl'
  Copy-Item -LiteralPath 'pds_recipe.tcl' -Destination $runRecipe -Force
  try {
    $output = & $pds -file $runRecipe -project_name trace85_generated 2>&1
    $code = $LASTEXITCODE
    $output | Tee-Object 'pds_trace85_build.log'
    $joined = $output -join "`n"
    if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){
      throw 'trace85 PDS build failed; inspect pds_trace85_build.log'
    }
  } finally {
    if(Test-Path -LiteralPath $runRecipe){ Remove-Item -LiteralPath $runRecipe -Force }
    if(Test-Path -LiteralPath (Join-Path $projectDir 'impl.tcl')){ Remove-Item -LiteralPath (Join-Path $projectDir 'impl.tcl') -Force }
  }

  $bit=Get-ChildItem -Recurse -File -Filter '*.sbit' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $timing=Get-ChildItem -Recurse -File -Include '*.rtr' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $bit){ throw 'PDS reported success but produced no new .sbit' }
  if(-not $timing){ throw 'PDS reported success but produced no new timing report' }

  Write-Host ''
  Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)"
  Write-Host "SHA256    $((Get-FileHash -LiteralPath $bit.FullName -Algorithm SHA256).Hash)"
  Write-Host "TIMING    $($timing.FullName)"
  $ds=(Select-String -LiteralPath $timing.FullName -Pattern 'Design Summary' | Select-Object -First 1).Line
  if($ds){ Write-Host "TIMING_SUMMARY $($ds.Trim())" }
  Select-String -LiteralPath $timing.FullName -Pattern 'LUT|Register|DRM|APM' -ErrorAction SilentlyContinue |
    Select-Object -First 8 | ForEach-Object { Write-Host $_.Line.Trim() }
} finally { Pop-Location }
Write-Host 'MES50HP TRACE 85 MHz PDS BUILD PASS'
