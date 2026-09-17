param([switch]$RandomDelay,[int]$MaxCycles=5000000)
$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '..\third_party\coremark'
if(-not (Test-Path -LiteralPath (Join-Path $root 'core_main.c'))){
  throw "Official EEMBC CoreMark checkout is absent: $root"
}
& (Join-Path $PSScriptRoot 'run_coremark_pipeline_tb.ps1') -RandomDelay:$RandomDelay -MaxCycles $MaxCycles
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host 'OFFICIAL COREMARK TEST PASS'
