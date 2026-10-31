param(
  [string]$PdsRoot = $(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'})
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project=Join-Path $repo 'fpga/coremark_ila'
$ipgen=Join-Path $PdsRoot 'bin/ip_generate.exe'
$pds=Join-Path $PdsRoot 'bin/pds_shell.exe'
if(!(Test-Path -LiteralPath $ipgen)){throw "PDS IP generator not found: $ipgen"}
if(!(Test-Path -LiteralPath $pds)){throw "PDS shell not found: $pds"}
if(!(Test-Path -LiteralPath $LicenseFile)){throw "PDS license not found: $LicenseFile"}
$env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path
[void](New-Item -ItemType Directory -Force -Path (Join-Path $project 'rtl'))
[void](New-Item -ItemType Directory -Force -Path (Join-Path $project 'constraints'))

# 与 Task 28 计分镜像保持一致：同样带 -PerfWindowAlign 1，否则这一步会把
# fpga/coremark 的共享镜像静默改回未窗口对齐版本（与已实测位流不一致）。
& (Join-Path $PSScriptRoot 'generate_coremark_fpga_memory.ps1') -Iterations 1000 -ClockHz 50000000 -AutoStart 0 -PerfWindowAlign 1
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
foreach($name in @('coremark_program_memory.v','coremark_imem.mem','coremark_drom.mem','coremark_ram.mem')){
  Copy-Item -LiteralPath (Join-Path $repo "fpga/coremark/rtl/$name") -Destination (Join-Path $project "rtl/$name") -Force
}
Copy-Item -LiteralPath (Join-Path $repo 'fpga/coremark/constraints/mes50hp_coremark.fdc') -Destination (Join-Path $project 'constraints/mes50hp_coremark_ila.fdc') -Force

$debugModel=Join-Path $PdsRoot 'ip/system_ip/ips_debug_core/ips_debug_core_eval/ips_debug_core'
$hubModel=Join-Path $PdsRoot 'ip/system_ip/ips_debug_core/ips_debug_core_eval/ips_jtag_hub'
$debugIpc=Join-Path $project 'ip/coremark_ila/coremark_ila.ipc'
$hubIpc=Join-Path $project 'ip/coremark_jtag_hub/coremark_jtag_hub.ipc'
& $ipgen -i $debugIpc -m $debugModel -family Logos -device PGL50H -pack FBG484 -speed '-6'
if($LASTEXITCODE -ne 0){throw 'DebugCore IP generation failed'}
& $ipgen -i $hubIpc -m $hubModel -family Logos -device PGL50H -pack FBG484 -speed '-6'
if($LASTEXITCODE -ne 0){throw 'JTAG Hub IP generation failed'}

Push-Location $project
try{
  $started=Get-Date
  $output=& $pds -file pds_recipe.tcl -project_name coremark_ila 2>&1
  $code=$LASTEXITCODE
  $output|Tee-Object pds_build.log
  $joined=$output -join "`n"
  if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){throw 'CoreMark DebugCore PDS build failed; inspect pds_build.log'}
  $bit=Get-ChildItem -Recurse -File -Filter '*.sbit'|Where-Object LastWriteTime -ge $started|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  $timing=Get-ChildItem -Recurse -File -Include '*.rtr','*timing*.rpt'|Where-Object LastWriteTime -ge $started|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  if(-not $bit -or -not $timing){throw 'Task 29 completed without fresh bitstream/timing report'}
  Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)"
  Write-Host "BITSTREAM_SHA256 $((Get-FileHash -LiteralPath $bit.FullName -Algorithm SHA256).Hash)"
  Write-Host "TIMING_REPORT $($timing.FullName)"
}finally{Pop-Location}
Write-Host 'MES50HP COREMARK DEBUGCORE PDS BUILD PASS'
