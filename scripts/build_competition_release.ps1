param(
  [switch]$SkipPds,
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'})
)
$ErrorActionPreference='Stop'
$args=@()
if(-not $SkipPds){$args += @('-RunPds','-LicenseFile',$LicenseFile)}
& $PSScriptRoot/run_final_regression.ps1 @args
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& $PSScriptRoot/create_release_manifest.ps1
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host 'COMPETITION RELEASE AUTOMATED BUILD PASS'
