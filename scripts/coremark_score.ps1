param(
  [string]$Port = '',
  [int]$Baud = 115200,
  [double]$TimeoutSec = 140,
  [int]$ClockHz = 85000000,
  [string]$OutDir = 'results\coremark',
  [string]$FromLog = ''
)
# MES50HP CoreMark 跑分器 —— 零依赖版（Windows 自带 PowerShell + .NET 串口）
#
# 为什么有这一份：原来的跑分上位机是 python/coremark_serial.py，需要评委机装 Python + pyserial。
# 本脚本与它**同一套协议与判据**，但不依赖任何第三方软件：
#   ① 打开 CP2102 串口（自动识别，找不到可用 -Port COMx 指定）；
#   ② 每秒发一个字符 R —— 跑分位流是 AUTOSTART=0，靠这个字符启动；
#   ③ 收到 COREMARK_DONE 结束，落盘 原始日志 + JSON + 一张自包含的结果页(HTML)；
#   ④ 判据：四个官方 CRC、Correct operation validated.、运行时间 ≥10 秒；
#      并顺带与 85 MHz 金标准（ticks/分数/CoreMark每MHz）逐项核对。
#
# 注意：Windows PowerShell 5.1 把无 BOM 的 .ps1 当 ANSI 解码，本文件含中文，必须保留 UTF-8 BOM。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 85 MHz 交付配置的金标准（来自 release/final_submission/coremark/expected/）
$GOLDEN = @{
  '85000000' = @{ ticks = 2670014377; score_x1000 = 79587; cm_per_mhz_x1000 = 936; crcfinal = '0x5275' }
  '80000000' = @{ ticks = 2670014377; score_x1000 = 74905; cm_per_mhz_x1000 = 936; crcfinal = '0x5275' }
  '50000000' = @{ ticks = 1068006999; score_x1000 = 46816; cm_per_mhz_x1000 = 936; crcfinal = '0xd340' }
}

function Find-Cp210xPort {
  $ports = [System.IO.Ports.SerialPort]::GetPortNames()
  if (-not $ports) { return '' }
  $candidates = @()
  try {
    $candidates = Get-WmiObject Win32_PnPEntity -ErrorAction Stop |
      Where-Object { $_.Name -match '\(COM(\d+)\)' -and $_.Name -match 'CP210|Silicon Labs' } |
      ForEach-Object { 'COM' + ([regex]::Match($_.Name, '\(COM(\d+)\)').Groups[1].Value) }
  } catch { }
  foreach ($c in $candidates) { if ($ports -contains $c) { return $c } }
  return $ports[0]
}

function Get-Field([string]$Text, [string]$Pattern) {
  $m = [regex]::Match($Text, $Pattern)
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value
}

function Write-CoremarkReport([string]$Path, $Result, [string]$Raw) {
  $badge = if ($Result.pass) { '#1a7f37' } else { '#b42318' }
  $badgeText = if ($Result.pass) { 'PASS' } else { 'FAIL' }
  $rows = @(
    @('CoreMark 分数',        ('{0:N3}' -f ($Result.score_x1000 / 1000.0))),
    @('CoreMark/MHz',         ('{0:N3}' -f ($Result.cm_per_mhz_x1000 / 1000.0))),
    @('Total ticks',          ('{0}' -f $Result.ticks)),
    @('运行时间',             ('{0:N3} s' -f ($Result.seconds_x1000 / 1000.0))),
    @('CPU 时钟',             ('{0:N0} Hz' -f $Result.clock_hz)),
    @('迭代次数',             ('{0}' -f $Result.iterations)),
    @('crclist / crcmatrix',  ('{0} / {1}' -f $Result.crclist, $Result.crcmatrix)),
    @('crcstate / crcfinal',  ('{0} / {1}' -f $Result.crcstate, $Result.crcfinal)),
    @('CPI（性能计数器推算）', ('{0:N3}（窗口敏感，只能写约数）' -f ($Result.cpi_x1000 / 1000.0))),
    @('官方自校验',           $(if ($Result.validated) { 'Correct operation validated.' } else { '未出现' })),
    @('运行时间 ≥10 s（赛题要求）', $(if ($Result.seconds_x1000 -ge 10000) { '满足' } else { '不满足' }))
  )
  $table = ($rows | ForEach-Object {
      '<tr><th style="text-align:left;padding:6px 14px 6px 0;color:#475467;font-weight:600">' +
      $_[0] + '</th><td style="padding:6px 0;font-family:Consolas,monospace">' + $_[1] + '</td></tr>'
    }) -join "`n"
  $checked = ($Result.golden_notes | ForEach-Object { '<li>' + $_ + '</li>' }) -join "`n"
  $html = @"
<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>CoreMark 跑分结果</title></head>
<body style="font:15px/1.6 'Microsoft YaHei',Segoe UI,sans-serif;max-width:900px;margin:32px auto;padding:0 18px;color:#101828">
<h1 style="margin:0 0 6px">MES50HP CoreMark 跑分结果
  <span style="background:$badge;color:#fff;border-radius:6px;padding:2px 12px;font-size:16px;vertical-align:middle">$badgeText</span></h1>
<p style="color:#475467;margin:0 0 18px">串口 $($Result.port) · 115200 8N1 · 由本页同目录的 coremark_uart.log 原始输出解析而来（本页不联网、不需要任何软件）</p>
<table style="border-collapse:collapse;margin-bottom:18px">$table</table>
<h2 style="font-size:16px;margin:18px 0 6px">与金标准核对</h2>
<ul style="margin:0 0 18px">$checked</ul>
<h2 style="font-size:16px;margin:18px 0 6px">原始串口输出</h2>
<pre style="background:#0e1420;color:#d7f9ff;padding:14px;border-radius:8px;overflow:auto;font:13px/1.45 Consolas,monospace">$([System.Net.WebUtility]::HtmlEncode($Raw))</pre>
</body></html>
"@
  [System.IO.File]::WriteAllText($Path, $html, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- 主流程
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$logPath = Join-Path $OutDir 'coremark_uart.log'
$jsonPath = Join-Path $OutDir 'coremark_board.json'
$htmlPath = Join-Path $OutDir '跑分结果.html'

if ($FromLog) {
  # 离线模式：不碰串口，只把已有的一次跑分原始输出重新判读并生成结果页。
  # 用途：① 没有板子时也能核对判据与报告；② 用包内金标准日志复算。
  $src = (Resolve-Path -LiteralPath $FromLog).Path
  $raw = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
  $Port = '(离线解析)'
  Write-Host "离线模式  从 $src 解析（不打开串口）"
} else {
  if (-not $Port) { $Port = Find-Cp210xPort }
  if (-not $Port) { throw '没有找到串口：请插好板载 CP2102 USB 线，或用 -Port COMx 指定' }

  Write-Host "串口      $Port  $Baud 8N1"
  Write-Host "CPU 时钟  $ClockHz Hz（用于把 ticks 换算成秒）"
  Write-Host "输出目录  $OutDir"
  Write-Host ''
  Write-Host '开始跑分：每秒发一个 R 启动，正常约 32 秒后结束……'

  $sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
  $sp.ReadTimeout = 200
  $sp.WriteTimeout = 2000
  $sp.Open()
  $sb = New-Object System.Text.StringBuilder
  try {
    $sp.DiscardInBuffer()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $nextStart = 0.0
    $nextReport = 10.0    # 每 10 秒报一次进度（见循环内注释）
    $key = [byte[]]@(0x52)   # 'R'
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
      if ($sw.Elapsed.TotalSeconds -ge $nextStart) {
        $sp.Write($key, 0, 1)
        $nextStart = $sw.Elapsed.TotalSeconds + 1.0
      }
      $chunk = $sp.ReadExisting()
      if ($chunk) { [void]$sb.Append($chunk) }
      if ($sb.ToString().Contains('COREMARK_DONE')) { break }
      # [2026-10-03 新增] 每 10 秒报一次进度。
      # 为什么：默认要等满 140 秒才结束，之前这 140 秒一个字都不打印，用户会以为卡死。
      if ($sw.Elapsed.TotalSeconds -ge $nextReport) {
        if ($sb.Length -eq 0) {
          Write-Host ("  已等待 {0,3:N0} 秒……尚未收到任何数据" -f $sw.Elapsed.TotalSeconds)
        } else {
          Write-Host ("  已等待 {0,3:N0} 秒……已收到 {1} 个字符" -f $sw.Elapsed.TotalSeconds, $sb.Length)
        }
        $nextReport += 10.0
      }
      Start-Sleep -Milliseconds 50
    }
  } finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
  }
  $raw = $sb.ToString()
}

[System.IO.File]::WriteAllText($logPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("收到 {0} 个字符，已存 {1}" -f $raw.Length, $logPath)
Write-Host ''

if ($raw.Length -eq 0) {
  Write-Host 'COREMARK SCORE FAIL 没有收到任何串口输出' -ForegroundColor Red
  Write-Host '排查（按顺序）：'
  Write-Host '  ① 板上是不是跑分位流？bitstream\mes50hp_coremark_85m.sbit（**逻辑分析仪那颗不能跑分**）'
  Write-Host '     在 PDS 里打开 MES50HP_CoreMark_85M.pds → Programmer → 选上面这个 .sbit → 下载'
  Write-Host '  ② 下载后不要按复位；本工具每秒发一个 R 启动（AUTOSTART=0）'
  Write-Host '  ③ 串口是否被 PDS 串口终端 / 其它串口工具占用（会弹 Access denied）'
  Write-Host '  ④ 波特率必须 115200 8N1，串口要选 CP210x 那个（不是 CH340/其它）'
  exit 1
}

# 收到数据但不是 CoreMark：最常见是板上还跑着逻辑分析仪固件 —— 直接点出来，省得猜。
if ($raw -match 'LA_READY|LA RAW|LA_DONE') {
  Write-Host 'COREMARK SCORE FAIL 板上运行的是**逻辑分析仪固件**（收到 LA_READY/LA RAW）' -ForegroundColor Red
  Write-Host '请先下载跑分位流：bitstream\mes50hp_coremark_85m.sbit'
  Write-Host '（PDS → 打开 MES50HP_CoreMark_85M.pds → Programmer → 选该 .sbit → 下载；下载后不要按复位）'
  exit 1
}

# ---- 判据（与 python/coremark_serial.py 完全一致）----
$markers = @('[0]crclist       : 0xe714', '[0]crcmatrix     : 0x1fd7', '[0]crcstate      : 0x8e3a')
$missing = @($markers | Where-Object { -not $raw.Contains($_) })
$validated = $raw.Contains('Correct operation validated.')
$ticks = Get-Field $raw 'Total ticks\s*:\s*(\d+)'
$iterations = Get-Field $raw 'Iterations\s*:\s*(\d+)'
$score = Get-Field $raw 'CoreMark score x1000\s*:\s*(\d+)'
$cmPerMhz = Get-Field $raw 'CoreMark/MHz x1000\s*:\s*(\d+)'
$crclist = Get-Field $raw '\[0\]crclist\s*:\s*(0x[0-9a-fA-F]+)'
$crcmatrix = Get-Field $raw '\[0\]crcmatrix\s*:\s*(0x[0-9a-fA-F]+)'
$crcstate = Get-Field $raw '\[0\]crcstate\s*:\s*(0x[0-9a-fA-F]+)'
$crcfinal = Get-Field $raw '\[0\]crcfinal\s*:\s*(0x[0-9a-fA-F]+)'
$perf = [regex]::Match($raw, 'PERF cycle=([0-9a-fA-F]+) instret=([0-9a-fA-F]+)')

$problems = @()
if ($missing.Count -gt 0) { $problems += ('缺少官方 CRC 标记: ' + ($missing -join ', ')) }
if (-not $validated) { $problems += '缺少 Correct operation validated.' }
foreach ($pair in @(@('Total ticks', $ticks), @('Iterations', $iterations), @('CoreMark score x1000', $score), @('CoreMark/MHz x1000', $cmPerMhz))) {
  if (-not $pair[1]) { $problems += ('缺少字段: ' + $pair[0]) }
}
$secondsX1000 = $null
if ($ticks) {
  $secondsX1000 = [int]([int64]$ticks * 1000 / $ClockHz)
  if ($secondsX1000 -lt 10000) { $problems += ('运行时间不足 10 秒（{0:N3} s）' -f ($secondsX1000 / 1000.0)) }
}
$cpiX1000 = $null
if ($perf.Success) {
  $cycles = [Convert]::ToInt64($perf.Groups[1].Value, 16)
  $instret = [Convert]::ToInt64($perf.Groups[2].Value, 16)
  if ($instret -gt 0) { $cpiX1000 = [int]($cycles * 1000 / $instret) }
}

# ---- 与金标准逐项核对（不一致只告警，不作为失败）----
$goldenNotes = @()
$goldenKey = [string]$ClockHz
if ($GOLDEN.ContainsKey($goldenKey)) {
  $g = $GOLDEN[$goldenKey]
  $goldenNotes += ("ticks 金标准 {0} → 实测 {1} —— {2}" -f $g.ticks, $ticks, $(if ([int64]$ticks -eq $g.ticks) { '一致' } else { '不一致' }))
  $goldenNotes += ("分数 金标准 {0} → 实测 {1} —— {2}" -f $g.score_x1000, $score, $(if ([int]$score -eq $g.score_x1000) { '一致' } else { '不一致' }))
  $goldenNotes += ("CoreMark/MHz 金标准 {0} → 实测 {1}" -f $g.cm_per_mhz_x1000, $cmPerMhz)
  $goldenNotes += ("crcfinal 金标准 {0} → 实测 {1}" -f $g.crcfinal, $crcfinal)
} else {
  $goldenNotes += ("该频点（{0} Hz）没有内置金标准，只做 CRC 与时间判据" -f $ClockHz)
}
$goldenNotes += 'PERF 行的 cycle/instret 等计数器有窗口敏感性（约 ±1%），两次实跑不同属正常，不得据此写精确 CPI'

$result = [ordered]@{
  validation = $(if ($problems.Count -eq 0) { 'PASS' } else { 'FAIL' })
  pass = ($problems.Count -eq 0)
  port = $Port
  clock_hz = $ClockHz
  ticks = if ($ticks) { [int64]$ticks } else { $null }
  iterations = if ($iterations) { [int]$iterations } else { $null }
  score_x1000 = if ($score) { [int]$score } else { $null }
  cm_per_mhz_x1000 = if ($cmPerMhz) { [int]$cmPerMhz } else { $null }
  seconds_x1000 = $secondsX1000
  cpi_x1000 = $cpiX1000
  crclist = $crclist; crcmatrix = $crcmatrix; crcstate = $crcstate; crcfinal = $crcfinal
  validated = $validated
  problems = $problems
  golden_notes = $goldenNotes
}
[System.IO.File]::WriteAllText($jsonPath, (($result | ConvertTo-Json -Depth 5) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-CoremarkReport $htmlPath $result $raw

Write-Host '---- 结果 ----'
if ($ticks) { Write-Host ("Total ticks      {0}" -f $ticks) }
if ($secondsX1000) { Write-Host ("运行时间         {0:N3} s（= ticks / {1} Hz）" -f ($secondsX1000 / 1000.0), $ClockHz) }
if ($score) { Write-Host ("CoreMark 分数    {0:N3}" -f ([int]$score / 1000.0)) }
if ($cmPerMhz) { Write-Host ("CoreMark/MHz     {0:N3}" -f ([int]$cmPerMhz / 1000.0)) }
if ($crcfinal) { Write-Host ("crcfinal         {0}" -f $crcfinal) }
Write-Host ''
$goldenNotes | ForEach-Object { Write-Host ("  · " + $_) }
Write-Host ''
Write-Host ("结果 JSON   {0}" -f $jsonPath)
Write-Host ("结果页      {0}   ← 双击用浏览器打开" -f $htmlPath)
Write-Host ''

if ($problems.Count -gt 0) {
  Write-Host ("COREMARK SCORE FAIL " + ($problems -join '; ')) -ForegroundColor Red
  exit 1
}
Write-Host ("COREMARK SCORE PASS port={0} clock_hz={1} ticks={2} seconds={3:N3} score_x1000={4}" -f `
  $Port, $ClockHz, $ticks, ($secondsX1000 / 1000.0), $score)
exit 0
