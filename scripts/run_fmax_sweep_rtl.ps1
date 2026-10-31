param(
  [Parameter(Mandatory=$true)][string]$Tag,
  [string]$SweepRoot = 'D:\RISC_V_CPU_2026\tmp\fmax_sweep',
  [string]$PdsRoot   = $(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'}),
  [string]$Periods = '20.000,16.667,14.286,13.333,12.500,11.765',
  [string]$RtlSource = 'D:\RISC_V_CPU_2026\rtl',
  [string]$MemorySource = 'D:\RISC_V_CPU_2026\fpga\coremark\rtl',
  [string]$RecipeSource = 'D:\RISC_V_CPU_2026\fpga\coremark\pds_recipe.tcl',
  [string]$FdcSource = 'D:\RISC_V_CPU_2026\fpga\coremark\constraints\mes50hp_coremark.fdc',
  # 扫描工程里写出的 .fdc 文件名：必须与 $RecipeSource 里 add_constraint 指向的名字一致，
  # 否则约束根本没被加载（历史缺陷：这里曾把名字写死成 coremark 的，
  # 于是拿 logic_analyzer 的配方扫描时 fdc 名字对不上，扫描结果全部是"无约束"的）。
  [string]$FdcName = 'mes50hp_coremark.fdc'
)
# 频率扫描复现脚本（T0 / T4）。
# 每个频率点使用完全隔离的工程目录：project/<tag>-<freq>/，并通过 ../../rtl 引用
# 该 tag 专属的 RTL 快照快照目录 <tag>_rtl/，绝不污染 fpga/coremark 的正式产物。
# 运行前记录 RTL/FDC SHA-256，运行后输出时序表，保证 Before/After 可比。
$ErrorActionPreference='Stop'
$pds = Join-Path $PdsRoot 'bin/pds_shell.exe'
if(-not (Test-Path -LiteralPath $pds)){throw "PDS not found: $pds"}
$env:PANGO_LICENSE_FILE = (Resolve-Path -LiteralPath $LicenseFile).Path

$list = New-Object System.Collections.Generic.List[double]
foreach($s in ([string]$Periods).Split([char]',')){ $t=$s.Trim(); if($t.Length -gt 0){ $list.Add([double]$t) } }
$sweepPeriods = $list.ToArray()
if($sweepPeriods.Length -eq 0){throw 'Periods is empty'}

$rtlDir = Join-Path $SweepRoot ("{0}_rtl" -f $Tag)
$projDir = Join-Path $SweepRoot ("{0}_proj" -f $Tag)
if(Test-Path -LiteralPath $rtlDir){Remove-Item -LiteralPath $rtlDir -Recurse -Force}
if(Test-Path -LiteralPath $projDir){Remove-Item -LiteralPath $projDir -Recurse -Force}
New-Item -ItemType Directory -Path $rtlDir -Force | Out-Null
New-Item -ItemType Directory -Path $projDir -Force | Out-Null
Copy-Item (Join-Path $RtlSource '*.v') $rtlDir -Force
$hashes = Get-ChildItem -LiteralPath $rtlDir -Filter '*.v' | Sort-Object Name |
  ForEach-Object { "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $_.Name }
$hashes | Set-Content -LiteralPath (Join-Path $SweepRoot ("{0}_rtl_sha256.txt" -f $Tag))
Write-Host ("RTL SNAPSHOT tag={0} dir={1} files={2}" -f $Tag,$rtlDir,$hashes.Count)
Write-Host ("FDC SHA256 {0}" -f (Get-FileHash -LiteralPath $FdcSource -Algorithm SHA256).Hash)

$jobs=@()
foreach($p in $sweepPeriods){
  $mhz = [int][Math]::Round(1000.0/$p)
  $d = Join-Path $projDir ("f{0:00000}" -f [int][Math]::Round(1000000.0/$p))
  New-Item -ItemType Directory -Path (Join-Path $d 'constraints') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $d 'rtl') -Force | Out-Null
  Copy-Item -LiteralPath $RecipeSource -Destination (Join-Path $d 'pds_recipe.tcl') -Force
  Copy-Item (Join-Path $MemorySource '*') (Join-Path $d 'rtl') -Force
  $fdc = Get-Content -LiteralPath $FdcSource
  $fdc[0] = 'create_clock -name {clk_50m} [get_ports {clk_50m}] -period {' + ('{0:0.000}' -f $p) + '} -waveform {0.000 ' + ('{0:0.000}' -f ($p/2)) + '}'
  Set-Content -LiteralPath (Join-Path $d ('constraints\' + $FdcName)) -Value $fdc
  # 把 ../../rtl 指向本 tag 的 RTL 快照
  $depth = ($d.Substring($SweepRoot.Length).Trim('\').Split('\')).Count
  $rel = ('../' * $depth) + ("{0}_rtl" -f $Tag)
  $recipe = Get-Content -LiteralPath (Join-Path $d 'pds_recipe.tcl') -Raw
  $recipe = $recipe.Replace('../../rtl/', ($rel + '/'))
  Set-Content -LiteralPath (Join-Path $d 'pds_recipe.tcl') -Value $recipe -NoNewline
  Write-Host "START $($d) target=$mhz MHz rel_rtl=$rel"
  $jobs += Start-Job -Name ("f{0:00000}" -f [int][Math]::Round(1000000.0/$p)) -ScriptBlock {
    param($pds,$d,$lic)
    $env:PANGO_LICENSE_FILE=$lic
    Set-Location -LiteralPath $d
    & $pds -file pds_recipe.tcl -project_name sweep *>&1 | Tee-Object -FilePath sweep_run.log | Out-Null
    exit $LASTEXITCODE
  } -ArgumentList $pds,$d,$env:PANGO_LICENSE_FILE
}
$jobs | Wait-Job | Out-Null
$rows=@()
foreach($j in $jobs){
  $nm=$j.Name
  $st=$j.State
  Receive-Job -Job $j | Out-Null
  Remove-Job -Job $j -Force
  $d = Join-Path $projDir $nm
  $rtr = Get-ChildItem -LiteralPath (Join-Path $d 'report_timing') -Filter '*.rtr' -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $row = [ordered]@{ freq=$nm; state=$st; target=''; est=''; wns=''; tns=''; fail=''; whs=''; ths=''; ds=''; lut=''; ff=''; drm='' }
  if($rtr){
    $L = Get-Content -LiteralPath $rtr.FullName
    # Performance Summary 行：target MHz / estimated MHz / period / est period / slack
    $m = $L | Select-String -Pattern '^\s*\S+\s+([\d\.]+) MHz\s+([\d\.]+) MHz\s+([\d\.]+)\s+([\d\.]+)\s+(-?[\d\.]+)\s*$' | Select-Object -First 1
    if($m){ $row.target=$m.Matches[0].Groups[1].Value; $row.est=$m.Matches[0].Groups[2].Value }
    # Setup/Hold 数字必须按小节定位：报告里 Minimum Pulse Width / Fast Corner 等小节
    # 也是同样的 `名字 名字 数字 数字 整数 整数` 形态，不分小节会取到错误的 slack
    # （历史缺陷：曾把 Minimum Pulse Width(Slow Corner) 的 4.365 当成 85 MHz 的 WNS）。
    $section=''
    foreach($line in $L){
      $sec = [regex]::Match($line,'^\s*([A-Za-z][^:]*?)\s*:\s*$')
      if($sec.Success){ $section=$sec.Groups[1].Value.Trim(); continue }
      $num = [regex]::Match($line,'^\s*\S+\s+\S+\s+(-?[\d\.]+)\s+(-?[\d\.]+)\s+(\d+)\s+(\d+)\s*$')
      if(-not $num.Success){ continue }
      if($section -eq 'Setup Summary(Slow Corner)'){
        $row.wns=$num.Groups[1].Value; $row.tns=$num.Groups[2].Value; $row.fail=$num.Groups[3].Value
      } elseif($section -eq 'Hold Summary(Slow Corner)'){
        $row.whs=$num.Groups[1].Value; $row.ths=$num.Groups[2].Value
      }
    }
    $row.ds = if(($L | Select-String -Pattern 'All Constraints Met').Count -gt 0){'MET'}else{'VIOLATED'}
  }
  $syn = Join-Path $d 'synthesize\run.log'
  if(Test-Path -LiteralPath $syn){
    $S = Get-Content -LiteralPath $syn
    $l = $S | Select-String -Pattern 'Total LUTs:\s*(\d+)' | Select-Object -First 1
    if($l){ $row.lut=$l.Matches[0].Groups[1].Value }
    $f = $S | Select-String -Pattern 'Total Registers:\s*(\d+)' | Select-Object -First 1
    if($f){ $row.ff=$f.Matches[0].Groups[1].Value }
    $r = $S | Select-String -Pattern 'Total DRM18Ks\s*=\s*([\d\.]+)' | Select-Object -First 1
    if($r){ $row.drm=$r.Matches[0].Groups[1].Value }
  }
  $rows += [pscustomobject]$row
  Write-Host ("DONE {0} state={1} WNS={2} fail={3} WHS={4} {5} LUT={6} FF={7} DRM={8}" -f `
    $nm,$st,$row.wns,$row.fail,$row.whs,$row.ds,$row.lut,$row.ff,$row.drm)
}
$summary = Join-Path $SweepRoot ("{0}_sweep_summary.csv" -f $Tag)
$rows | Export-Csv -LiteralPath $summary -NoTypeInformation -Encoding UTF8
Write-Host ("SUMMARY {0}" -f $summary)
Write-Host 'RTL SWEEP FINISHED'
