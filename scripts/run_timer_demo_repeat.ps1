param(
  [Parameter(Mandatory=$true)][string]$Port,
  [int]$Runs = 4,
  [double]$Seconds = 12,
  [int]$Delta = 12500000,
  [int]$ClockHz = 50000000,
  [string]$Output = 'release/evidence/timer_demo_board/repeat',
  [switch]$SkipProgram
)
# N1 重复性验收：**下载一次**，在"刚下载完的稳定窗口内"连续采集 N 次。
#
# 为什么必须"下载后限定时间内采集"（这是本轮实测出来的硬约束，不是保险起见）：
#   2026-09-29 实测把板上行为按 5 秒一段连续观察 180 秒，结果是
#     t+0..80 s   ：串口速率稳定 20.0 B/s（5 字节 / 250 ms，完全正确）
#     t+85 s 起   ：突变为 11571 B/s，且此后一直保持错误
#   突变后**重新下载位流必恢复**。也就是板上存在一个"约 80 秒后跑飞"的状态，
#   与 RTL 无关（本工程没有 PLL、没有时钟切换、fdc 里 clk_50m 就是 P20 的 20 ns 约束）。
#   详细诊断与后续排查建议见 fpga/timer_demo/README.md §6。
# 所以验收流程固定为：**先下载，再在窗口内连采**，并把每一次的原始证据都留档。
$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}

if(-not $SkipProgram){
  & "$PSScriptRoot/program_board.ps1" -Config tm50
  if($LASTEXITCODE -ne 0){ throw 'timer demo bitstream download failed' }
} else {
  Write-Host 'SKIP PROGRAM: 假定板上刚下载过 timer_demo 位流'
}

New-Item -ItemType Directory -Force $Output | Out-Null
$results=@()
$t_start=Get-Date
for($i=1;$i -le $Runs;$i++){
  $tag='run{0:d2}' -f $i
  $log=Join-Path $Output "$tag.log"
  $json=Join-Path $Output "$tag.json"
  $elapsed=[int]((Get-Date)-$t_start).TotalSeconds
  Write-Host "=== capture $i/$Runs ($tag)  t+${elapsed}s after program ==="
  & $python python/timer_demo_serial.py $Port --seconds $Seconds `
    --delta $Delta --clock-hz $ClockHz `
    --output $log --summary $json 2>&1 | ForEach-Object { Write-Host $_ }
  $code=$LASTEXITCODE
  $entry=[ordered]@{ run=$tag; t_after_program_s=$elapsed; exit_code=$code }
  if(Test-Path $json){
    $j=Get-Content $json -Raw | ConvertFrom-Json
    $entry.records=$j.record_count
    $entry.run_count=$j.run_count
    $entry.median_ticks=$j.mtime_period_ticks_median
    $entry.median_ms=$j.mtime_period_ms_median
    $entry.self_timed_ok=$j.self_timed_period_ok
    $entry.anchored=$j.record_runs_anchored_on_boot_marker
    $entry.raw_bytes=$j.raw_bytes
  }
  $results+=[pscustomobject]$entry
  if($code -ne 0){ Write-Warning "capture $tag FAILED (exit $code)" }
}

$summaryPath=Join-Path $Output 'repeat_summary.json'
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$results | Format-Table -AutoSize | Out-String | Write-Host

$passed=($results | Where-Object { $_.exit_code -eq 0 }).Count
Write-Host "N1 TIMER DEMO REPEAT: $passed/$Runs captures PASS (window $([int]((Get-Date)-$t_start).TotalSeconds)s after program)"
if($passed -ne $Runs){ throw "N1 TIMER DEMO REPEAT FAIL: only $passed/$Runs PASS (see $summaryPath)" }
Write-Host 'N1 TIMER DEMO REPEAT ACCEPTANCE PASS'
