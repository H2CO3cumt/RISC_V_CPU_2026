param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = ''
)
$ErrorActionPreference='Stop'
$pds=Join-Path $PdsRoot 'bin/pds_shell.exe'
if(!(Test-Path -LiteralPath $pds)){throw "PDS not found: $pds"}
if($LicenseFile){$env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path}
if(-not $env:PANGO_LICENSE_FILE){
  $directRoots=@($PdsRoot,(Split-Path $PdsRoot -Parent),'D:\ToolsSoftware\pango','D:\Downloads')
  $nestedRoots=@((Join-Path $env:APPDATA 'pango'),(Join-Path $env:LOCALAPPDATA 'pango'))
  foreach($root in $directRoots){
    if(Test-Path -LiteralPath $root){
      $found=Get-ChildItem -LiteralPath $root -File -Include 'PDS-*.lic','pango*.lic','*.pango.lic','new_pds_*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($found){$env:PANGO_LICENSE_FILE=$found.FullName;break}
    }
  }
  if(-not $env:PANGO_LICENSE_FILE){foreach($root in $nestedRoots){
    if(Test-Path -LiteralPath $root){
      $found=Get-ChildItem -LiteralPath $root -Recurse -File -Include 'PDS-*.lic','pango*.lic','*.pango.lic','new_pds_*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($found){$env:PANGO_LICENSE_FILE=$found.FullName;break}
    }
  }}
}
if(-not $env:PANGO_LICENSE_FILE){Write-Warning 'PANGO_LICENSE_FILE is unset and no standard Pango license path was discovered; PDS will report Flow-0183.'}
$projectDir=(Resolve-Path (Join-Path $PSScriptRoot '../fpga/pipeline_soc')).Path
Push-Location $projectDir
try {
  $started=Get-Date
  $recipeHash=(Get-FileHash -LiteralPath pds_recipe.tcl -Algorithm SHA256).Hash
  $runRecipe=Join-Path $projectDir '.pds_pipeline_soc_run.tcl'
  Copy-Item -LiteralPath pds_recipe.tcl -Destination $runRecipe -Force
  try {
    $output=& $pds -file $runRecipe -project_name pipeline_soc_generated 2>&1
    $code=$LASTEXITCODE
    $output | Tee-Object pds_pipeline_build.log
    $joined=$output -join "`n"
    if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){
      throw 'PDS pipeline build failed; inspect pds_pipeline_build.log'
    }
  } finally {
    if(Test-Path -LiteralPath $runRecipe){Remove-Item -LiteralPath $runRecipe -Force}
    if(Test-Path -LiteralPath (Join-Path $projectDir 'impl.tcl')){Remove-Item -LiteralPath (Join-Path $projectDir 'impl.tcl') -Force}
  }
  $bit=Get-ChildItem -Recurse -File -Filter '*.sbit' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $timing=Get-ChildItem -Recurse -File -Include '*.rtr','*timing*.rpt','*timing*.txt' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $bit){throw 'PDS reported success but no fresh .sbit was generated'}
  if(-not $timing){throw 'PDS reported success but no fresh timing report was generated'}
  if((Get-FileHash -LiteralPath pds_recipe.tcl -Algorithm SHA256).Hash -ne $recipeHash){throw 'PDS modified the immutable source recipe pds_recipe.tcl'}
  Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)"
  Write-Host "TIMING_REPORT $($timing.FullName)"
} finally { Pop-Location }
Write-Host 'MES50HP PIPELINE PDS BUILD PASS'
