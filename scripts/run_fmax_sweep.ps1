param(
  [string]$SweepRoot = 'D:\RISC_V_CPU_2026\tmp\fmax_sweep',
  [string]$PdsRoot = $(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'}),
  [string[]]$Only = @(),
  [switch]$SkipBitstream
)
# 频率扫描：不改 RTL，只改 .fdc 的 create_clock -period，对同一份源码跑完整
# Compile -> Synthesize -> DevMap -> Place -> Route -> RouteOptimize -> ReportTiming。
# 目的：确认松约束下 PDS 报出的 Estimated Frequency 只是下界，得到真实天花板。
$ErrorActionPreference='Stop'
$pds = Join-Path $PdsRoot 'bin/pds_shell.exe'
if(-not (Test-Path -LiteralPath $pds)){throw "PDS not found: $pds"}
if(-not (Test-Path -LiteralPath $LicenseFile)){throw "License not found: $LicenseFile"}
$env:PANGO_LICENSE_FILE = (Resolve-Path -LiteralPath $LicenseFile).Path

$projects = Get-ChildItem -LiteralPath (Join-Path $SweepRoot 'fpga') -Directory | Sort-Object Name
if($Only.Count -gt 0){ $projects = $projects | Where-Object { $Only -contains $_.Name } }
if($projects.Count -eq 0){throw "No sweep projects under $SweepRoot\fpga"}

$jobs = @()
foreach($p in $projects){
  $dir = $p.FullName
  $recipe = Join-Path $dir 'pds_recipe.tcl'
  if(-not (Test-Path -LiteralPath $recipe)){throw "Missing recipe: $recipe"}
  $tcl = $recipe
  if($SkipBitstream){
    # 只到 report_timing：跳过 gen_bit_stream 以缩短扫描时间。
    $tcl = Join-Path $dir '_sweep_no_bitstream.tcl'
    (Get-Content -LiteralPath $recipe | Where-Object { $_ -notmatch '^\s*gen_bit_stream' }) | Set-Content -LiteralPath $tcl
  }
  $log = Join-Path $dir 'sweep_run.log'
  Write-Host "START $($p.Name)  dir=$dir"
  $jobs += Start-Job -Name $p.Name -ScriptBlock {
    param($pds,$dir,$tcl,$log,$lic)
    $env:PANGO_LICENSE_FILE = $lic
    Set-Location -LiteralPath $dir
    & $pds -file $tcl -project_name sweep_generated *>&1 | Tee-Object -FilePath $log
    exit $LASTEXITCODE
  } -ArgumentList $pds,$dir,$tcl,$log,$env:PANGO_LICENSE_FILE
}
Write-Host ("Launched {0} sweep jobs" -f $jobs.Count)
$jobs | Wait-Job | Out-Null
foreach($j in $jobs){
  $state = $j.State
  $out = Receive-Job -Job $j
  $name = $j.Name
  Remove-Job -Job $j -Force
  $dir = Join-Path (Join-Path $SweepRoot 'fpga') $name
  $rtr = Get-ChildItem -LiteralPath (Join-Path $dir 'report_timing') -Filter '*.rtr' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $perf = 'NO REPORT'
  if($rtr){
    $lines = Get-Content -LiteralPath $rtr.FullName
    $idx = ($lines | Select-String -Pattern 'Requested\s+Estimated\s+Requested\s+Estimated' | Select-Object -First 1).LineNumber
    if($idx){ $perf = ($lines[($idx+1)..($idx+3)] -join ' | ') }
  }
  Write-Host ("DONE {0} state={1} {2}" -f $name,$state,$perf)
}
Write-Host 'FMAX SWEEP FINISHED'
