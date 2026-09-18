param([string]$PdsRoot=$(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),[string]$LicenseFile='')
$ErrorActionPreference='Stop'
& $PSScriptRoot/generate_coremark_fpga_memory.ps1 -Iterations 1000 -ClockHz 50000000 -AutoStart 0
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$pds=Join-Path $PdsRoot 'bin/pds_shell.exe';if(!(Test-Path -LiteralPath $pds)){throw "PDS not found: $pds"}
if($LicenseFile){$env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path}
if(-not $env:PANGO_LICENSE_FILE){$found=Get-ChildItem -LiteralPath 'D:\Downloads' -File -Include 'new_pds_*.lic','PDS-*.lic','pango*.lic' -ErrorAction SilentlyContinue|Select-Object -First 1;if($found){$env:PANGO_LICENSE_FILE=$found.FullName}}
$projectDir=(Resolve-Path "$PSScriptRoot/../fpga/coremark").Path
Push-Location $projectDir
try{
 $started=Get-Date;$hash=(Get-FileHash pds_recipe.tcl -Algorithm SHA256).Hash;$runRecipe=Join-Path $projectDir '.pds_coremark_run.tcl';Copy-Item pds_recipe.tcl $runRecipe -Force
 try{$output=& $pds -file $runRecipe -project_name coremark_generated 2>&1;$code=$LASTEXITCODE;$output|Tee-Object pds_coremark_build.log;$joined=$output -join "`n";if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){throw 'Task 28 PDS build failed; inspect pds_coremark_build.log'}}finally{if(Test-Path $runRecipe){Remove-Item -LiteralPath $runRecipe -Force};$generated=Join-Path $projectDir 'impl.tcl';if(Test-Path $generated){Remove-Item -LiteralPath $generated -Force}}
 $bit=Get-ChildItem -Recurse -File -Filter '*.sbit'|Where-Object LastWriteTime -ge $started|Sort-Object LastWriteTime -Descending|Select-Object -First 1;$timing=Get-ChildItem -Recurse -File -Include '*.rtr','*timing*.rpt'|Where-Object LastWriteTime -ge $started|Sort-Object LastWriteTime -Descending|Select-Object -First 1
 if(-not $bit -or -not $timing){throw 'Task 28 PDS completed without fresh bitstream/timing report'};if((Get-FileHash pds_recipe.tcl -Algorithm SHA256).Hash -ne $hash){throw 'PDS modified Task 28 source recipe'}
 Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)";Write-Host "TIMING_REPORT $($timing.FullName)"
}finally{Pop-Location}
Write-Host 'MES50HP COREMARK PDS BUILD PASS'
