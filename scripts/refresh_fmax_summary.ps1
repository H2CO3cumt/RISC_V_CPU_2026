param(
  [Parameter(Mandatory=$true)][string]$SweepProjectRoot,
  [Parameter(Mandatory=$true)][string]$Tag,
  [string]$SweepRoot = 'D:\RISC_V_CPU_2026\tmp\fmax_sweep'
)
# 在不重跑 PDS 的前提下，从已有扫描目录重新提取时序/资源汇总（CSV）。
# 关键点：必须按小节标题（Setup/Hold Summary(Slow Corner)）定位，
# 否则会把 Minimum Pulse Width 的 WPWS 行误当成 setup WNS。
$ErrorActionPreference='Stop'

function Get-SummaryRow([string[]]$Lines,[string]$Section){
  $start = -1
  for($i=0;$i -lt $Lines.Count;$i++){
    if($Lines[$i] -match [regex]::Escape($Section)){ $start=$i; break }
  }
  if($start -lt 0){ return $null }
  for($j=$start;$j -lt [Math]::Min($start+30,$Lines.Count);$j++){
    if($Lines[$j] -match '^\s*\S*(?:Inferred)?\s+(-?[\d\.]+)\s+(-?[\d\.]+)\s+(\d+)\s+(\d+)\s*$'){
      return @{ wns=[double]$Matches[1]; tns=[double]$Matches[2]; fail=[int]$Matches[3] }
    }
  }
  return $null
}

$rows=@()
foreach($d in (Get-ChildItem -LiteralPath $SweepProjectRoot -Directory | Sort-Object Name)){
  $rtr = Get-ChildItem -LiteralPath (Join-Path $d.FullName 'report_timing') -Filter '*.rtr' -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $rtr){continue}
  $L = Get-Content -LiteralPath $rtr.FullName
  $row = [ordered]@{ freq=$d.Name; target=''; est=''; wns=''; tns=''; fail=''; whs=''; ths=''; ths_fail=''; ds=''; lut=''; ff=''; drm='' }
  $head = ($L | Select-Object -First 60) -join "`n"
  $m = [regex]::Match($head, 'clk_50m\s+([\d\.]+) MHz\s+([\d\.]+) MHz\s+([\d\.]+)\s+([\d\.]+)\s+(-?[\d\.]+)')
  if($m.Success){ $row.target=$m.Groups[1].Value; $row.est=$m.Groups[2].Value }
  $s = Get-SummaryRow $L 'Setup Summary(Slow Corner)'
  if($s){ $row.wns=('{0:0.000}' -f $s.wns); $row.tns=('{0:0.000}' -f $s.tns); $row.fail=$s.fail }
  $h = Get-SummaryRow $L 'Hold Summary(Slow Corner)'
  if($h){ $row.whs=('{0:0.000}' -f $h.wns); $row.ths=('{0:0.000}' -f $h.tns); $row.ths_fail=$h.fail }
  $all = $L -join "`n"
  $row.ds = if($all -match 'All Constraints Met'){'MET'}else{'VIOLATED'}
  $syn = Join-Path $d.FullName 'synthesize\run.log'
  if(Test-Path -LiteralPath $syn){
    $S = Get-Content -LiteralPath $syn -Raw
    if($S -match 'Total LUTs:\s*(\d+)'){ $row.lut=$Matches[1] }
    if($S -match 'Total Registers:\s*(\d+)'){ $row.ff=$Matches[1] }
    if($S -match 'Total DRM18Ks\s*=\s*([\d\.]+)'){ $row.drm=$Matches[1] }
  }
  $rows += [pscustomobject]$row
}
$out = Join-Path $SweepRoot ("{0}_sweep_summary.csv" -f $Tag)
$rows | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
$rows | Format-Table -AutoSize target,ds,wns,tns,fail,whs,ths,est,lut,ff,drm
Write-Host "REFRESHED $out"
