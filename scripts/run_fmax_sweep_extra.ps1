param(
  [string]$SweepRoot = 'D:\RISC_V_CPU_2026\tmp\fmax_sweep',
  [string]$PdsRoot = $(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'}),
  [string]$Tag = 'x',
  [string]$Periods = '11.111,10.526,10.000,9.091,8.333'
)
# 追加频率点扫描：不改 RTL，只改 .fdc 的 create_clock -period，用于找真实失败频率。
# 命令行传 -Periods 时必须加引号，否则 PowerShell 会按逗号切分成数组再拼接成带空格的字符串。
# 注意：$Periods 声明为 [string]，不能再赋数组给它，否则会被强制转回字符串。用独立变量保存解析结果。
$parsedPeriods = New-Object System.Collections.Generic.List[double]
foreach($s in ([string]$Periods).Split([char]',')){
  $t = $s.Trim()
  if($t.Length -gt 0){ $parsedPeriods.Add([double]$t) }
}
$sweepPeriods = $parsedPeriods.ToArray()
if($sweepPeriods.Length -eq 0){throw 'Periods is empty; pass e.g. -Periods "11.111,10.526"'}
Write-Host ("Sweep periods: {0}" -f (($sweepPeriods | ForEach-Object { $_ }) -join ', '))
$ErrorActionPreference='Stop'
$pds = Join-Path $PdsRoot 'bin/pds_shell.exe'
if(-not (Test-Path -LiteralPath $pds)){throw "PDS not found: $pds"}
$env:PANGO_LICENSE_FILE = (Resolve-Path -LiteralPath $LicenseFile).Path
$fpgas = Join-Path $SweepRoot 'fpga'
$template = Join-Path $fpgas 'coremark_f050'
if(-not (Test-Path -LiteralPath $template)){throw "Template project missing: $template"}
$jobs=@()
foreach($p in $sweepPeriods){
  $mhz = [int][Math]::Round(1000.0/$p)
  $nm = 'coremark_{0}{1}' -f $Tag,([int][Math]::Round(1000000.0/$p)).ToString('00000')
  $d = Join-Path $fpgas $nm
  if(Test-Path -LiteralPath $d){Remove-Item -LiteralPath $d -Recurse -Force}
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $d 'constraints') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $d 'rtl') -Force | Out-Null
  Copy-Item (Join-Path $template 'pds_recipe.tcl') $d -Force
  Copy-Item (Join-Path $template 'rtl\*') (Join-Path $d 'rtl') -Force
  $body = 'create_clock -name {clk_50m} [get_ports {clk_50m}] -period {' + ('{0:0.000}' -f $p) + '} -waveform {0.000 ' + ('{0:0.000}' -f ($p/2)) + '}'
  $fdc = Get-Content -LiteralPath (Join-Path $template 'constraints\mes50hp_coremark.fdc')
  $fdc[0] = $body
  Set-Content -LiteralPath (Join-Path $d 'constraints\mes50hp_coremark.fdc') -Value $fdc
  $log = Join-Path $d 'sweep_run.log'
  Write-Host "START $nm period=$p ns target=$mhz MHz"
  $jobs += Start-Job -Name $nm -ScriptBlock {
    param($pds,$d,$log,$lic)
    $env:PANGO_LICENSE_FILE=$lic
    Set-Location -LiteralPath $d
    & $pds -file pds_recipe.tcl -project_name sweep_generated *>&1 | Tee-Object -FilePath $log
    exit $LASTEXITCODE
  } -ArgumentList $pds,$d,$log,$env:PANGO_LICENSE_FILE
}
$jobs | Wait-Job | Out-Null
foreach($j in $jobs){
  $nm=$j.Name
  Receive-Job -Job $j | Out-Null
  Remove-Job -Job $j -Force
  $d = Join-Path $fpgas $nm
  $rtr = Get-ChildItem -LiteralPath (Join-Path $d 'report_timing') -Filter '*.rtr' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $rtr){ Write-Host "DONE $nm  NO TIMING REPORT"; continue }
  $L = Get-Content -LiteralPath $rtr.FullName
  $perf = ($L | Select-String -Pattern '^\s*clk_50m\s+[\d\.]+ MHz' | Select-Object -First 1).Line
  $ds = ($L | Select-String -Pattern 'Design Summary' | Select-Object -First 1).Line
  $set = ($L | Select-String -Pattern '^ clk_50m\s+clk_50m\s+([-\d\.]+)\s+([-\d\.]+)\s+(\d+)' | Select-Object -First 1).Line
  Write-Host "DONE $nm"
  Write-Host "   $($perf.Trim())"
  Write-Host "   $($ds.Trim())   setup: $($set.Trim())"
}
Write-Host 'EXTRA SWEEP FINISHED'
