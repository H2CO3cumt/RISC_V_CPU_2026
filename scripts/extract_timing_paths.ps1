param(
  [Parameter(Mandatory=$true)][string]$Report,
  [int]$Top = 10,
  [string]$Out = ''
)
# 从 PDS 时序报告 (*.rtr) 提取最差 N 条路径的起点/终点/逻辑级数/逻辑与走线延迟占比。
# 报告格式：每条路径以 "Startpoint" 开始，包含 "Data arrival time ... Logic Levels: N"
# 与 "Logic: x ns(y%), Route: z ns"。
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $Report)){throw "Report not found: $Report"}
$L = Get-Content -LiteralPath $Report
$rows = New-Object System.Collections.Generic.List[object]
for($i=0;$i -lt $L.Count;$i++){
  if($L[$i] -notmatch '^\s*Startpoint\s*:\s*(.+?)\s*$'){continue}
  $sp=$Matches[1]; $ep=''; $pt=''; $arr=''; $ll=''; $logic=''; $route=''; $slack=''; $pct=''
  for($j=$i;$j -lt [Math]::Min($i+260,$L.Count);$j++){
    if($L[$j] -match '^\s*Endpoint\s*:\s*(.+?)\s*$'){$ep=$Matches[1]}
    if($L[$j] -match '^\s*Path Type\s*:\s*(.+?)\s*$'){$pt=$Matches[1]}
    if($L[$j] -match 'Data arrival time\s+([\d\.]+)\s+Logic Levels:\s*(\d+)'){$arr=$Matches[1];$ll=$Matches[2]}
    if($L[$j] -match 'Logic:\s*([\d\.]+)ns\(([\d\.]+)%\),\s*Route:\s*([\d\.]+)ns'){$logic=$Matches[1];$pct=$Matches[2];$route=$Matches[3]}
    if($L[$j] -match '^\s*Slack\s*\(\w+\)\s+(-?[\d\.]+)'){$slack=$Matches[1];break}
  }
  if($ep){
    $rows.Add([pscustomobject]@{
      path_type=$pt; startpoint=$sp; endpoint=$ep; arrival_ns=$arr; logic_levels=$ll
      logic_ns=$logic; logic_pct=$pct; route_ns=$route; slack_ns=$slack
    })
  }
}
$setup = $rows | Where-Object { $_.path_type -like 'max*' } | Sort-Object { [double]$_.slack_ns } | Select-Object -First $Top
$hold  = $rows | Where-Object { $_.path_type -like 'min*' } | Sort-Object { [double]$_.slack_ns } | Select-Object -First 3
Write-Host ("=== WORST {0} SETUP PATHS ({1}) ===" -f $Top,$Report)
$setup | Format-Table -AutoSize startpoint,endpoint,logic_levels,logic_ns,route_ns,slack_ns | Out-String -Width 400 | Write-Host
Write-Host "=== WORST 3 HOLD PATHS ==="
$hold | Format-Table -AutoSize startpoint,endpoint,logic_levels,arrival_ns,slack_ns | Out-String -Width 400 | Write-Host
if($Out){
  ($setup + $hold) | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
  Write-Host "PATHS CSV $Out"
}
