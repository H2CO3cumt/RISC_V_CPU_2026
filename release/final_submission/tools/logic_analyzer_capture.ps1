param(
  [string]$Port = '',
  [string]$Output = 'results',
  [int]$Runs = 1,
  [int]$Baud = 115200,
  [double]$TimeoutSec = 70,
  [string]$Modes = 'static,counter,uart,spi',
  [string]$Viewer = '',
  [string]$PreviewPath = '',
  [string]$FromCaptures = '',
  [int]$ClkHz = 85000000,
  [int]$Segments = 0,
  [double]$GapNs = 0,
  [switch]$Oneshot
)
# MES50HP 八通道逻辑分析仪 · 零依赖采集器
#
# 为什么有这一份：原上位机是 Python + tkinter + pyserial，评委机没装 Python 就跑不了。
# 本脚本只用 Windows 自带的 PowerShell 与 .NET 串口（System.IO.Ports），
# 协议、每模式参数、产物布局与 python/logic_analyzer_serial.py 完全一致：
#   产物 <Output>/logic_analyzer/<mode>/<mode>_NN.{log,vcd,html} + summary.json
# 其中 .html 是"双击就能用浏览器看波形"的自包含文件（模板 = waveform_viewer.html）。
#
# 协议（PC -> 板子，13 字节）：
#   A5 <mode> <data> <pd_lo> <pd_hi> <sd_lo> <sd_hi> <trig_type> <trig_mask> <trig_value> <pre> <post> <XOR>
# 板子回包（ASCII 文本）：... LA RAW count=<hex> trigger=<hex> <样本十六进制...> ... LA_DONE LA_READY
#
# 注意：Windows PowerShell 5.1 把无 BOM 的 .ps1 当 ANSI 解码，本文件含中文，必须保留 UTF-8 BOM。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$MODE_VALUES = @{ static = 0xA5; counter = 0x00; uart = 0xA5; spi = 0x3C }
$TRIGGERS = @{ level = 0; rise = 1; fall = 2 }

function Get-ModeConfig([string]$mode, [int]$data) {
  if ($mode -eq 'uart') {
    return @{ mode = 2; data = $data; pattern_div = 433; sample_div = 26;
              trigger_type = 2; trigger_mask = 1; trigger_value = 0; pre = 64; post = 191 }
  }
  if ($mode -eq 'spi') {
    return @{ mode = 3; data = $data; pattern_div = 3; sample_div = 0;
              trigger_type = 1; trigger_mask = 1; trigger_value = 1; pre = 4; post = 80 }
  }
  $m = if ($mode -eq 'counter') { 1 } else { 0 }
  return @{ mode = $m; data = $data; pattern_div = 3; sample_div = 0;
            trigger_type = 0; trigger_mask = 1; trigger_value = ($data -band 1); pre = 4; post = 4 }
}

function Get-Timebase([int]$ClockHz, [int]$SampleDiv) {
  # 硬件按 div_count >= sample_div 产生采样使能（rtl/capture_engine.v），
  # 所以相邻两个采样点相隔 sample_div + 1 个系统时钟；分频为 0 就是每拍都采。
  # 这里只做"采样点 -> 时间"的换算，不参与任何采集判决。
  $ns = 1000000000.0 * ($SampleDiv + 1) / $ClockHz
  return @{ sample_ns = $ns; sample_hz = 1000000000.0 / $ns }
}

function Format-TbJson($Tb) {
  # JSON 里必须用 InvariantCulture：中文 Windows 的 NumberToString 会写成 "317,46"，
  # 那个逗号会让 JSON.parse 直接失败、波形页白屏。
  $ns = $Tb.sample_ns.ToString('F6', [System.Globalization.CultureInfo]::InvariantCulture)
  $hz = $Tb.sample_hz.ToString('F3', [System.Globalization.CultureInfo]::InvariantCulture)
  return '"sample_ns":' + $ns + ',"sample_hz":' + $hz
}

function Build-Packet($cfg) {
  $values = @(0xA5, $cfg.mode, $cfg.data,
              ($cfg.pattern_div -band 0xFF), (($cfg.pattern_div -shr 8) -band 0xFF),
              ($cfg.sample_div -band 0xFF), (($cfg.sample_div -shr 8) -band 0xFF),
              $cfg.trigger_type, $cfg.trigger_mask, $cfg.trigger_value,
              $cfg.pre, $cfg.post)
  $checksum = 0
  foreach ($v in $values) { $checksum = $checksum -bxor $v }
  return [byte[]]($values + $checksum)
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

function Receive-Until($sp, [string]$marker, [double]$timeoutSec) {
  $sb = New-Object System.Text.StringBuilder
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
    $chunk = $sp.ReadExisting()
    if ($chunk) { [void]$sb.Append($chunk) }
    if ($sb.ToString().Contains($marker)) { return $sb.ToString() }
    Start-Sleep -Milliseconds 20
  }
  throw "串口超时：等不到 $marker（已收到 $($sb.Length) 个字符）"
}

function Sync-Ready($sp, [double]$timeoutSec) {
  # 板子可能已经在等命令（全程静默）；也可能刚复位还没打印完 LA_READY。
  $sb = New-Object System.Text.StringBuilder
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $quiet = [System.Diagnostics.Stopwatch]::StartNew()
  $quietLimit = [Math]::Min(0.5, $timeoutSec)
  while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
    $chunk = $sp.ReadExisting()
    if ($chunk) {
      [void]$sb.Append($chunk)
      $quiet.Restart()
      if ($sb.ToString().Contains('LA_READY')) { return $sb.ToString() }
    } elseif ($sb.Length -eq 0 -and $quiet.Elapsed.TotalSeconds -ge $quietLimit) {
      return ''
    }
    Start-Sleep -Milliseconds 20
  }
  throw '串口一直有数据但等不到 LA_READY（是不是下载了旧位流？）'
}

function Parse-Raw([string]$text) {
  $m = [regex]::Match($text, 'LA RAW count=([0-9a-fA-F]{1,8}) trigger=([0-9a-fA-F]{1,8})')
  if (-not $m.Success) { throw '板子回包里没有 LA RAW 行（固件不是最终版？）' }
  $count = [Convert]::ToInt32($m.Groups[1].Value, 16)
  $trigger = [Convert]::ToInt32($m.Groups[2].Value, 16)
  # [2026-10-03 修 bug] 只在 **LA RAW 那一行**里取样本，不能对整段回包做正则。
  # 旧实现在整个回包上匹配 \b[0-9a-fA-F]{1,8}\b，于是尾部
  # "UART:0000004A00000001 SPI:00000000" 与 "LA_DONE" 里的十六进制块也被算成采样点：
  # static 模式声明 5 个点会被读成 7 个，页面/VCD 的点数与 count 不符。
  # Python 那条路（logic_analyzer.py 的 parse_raw）本来就有这个行边界，这里补齐成一致行为。
  #
  # 注意：头行匹配结束时正好停在行尾，所以 $rest 是**以换行开头**的，
  # 必须先跳过行尾再去取下一行；否则取到的是那个空行（2026-10-03 实测踩到，会解析出 0 个样本）。
  $rest = $text.Substring($m.Index + $m.Length)
  $eol = [regex]::Match($rest, '\r?\n')
  if ($eol.Success) { $rest = $rest.Substring($eol.Index + $eol.Length) }
  $nextEol = [regex]::Match($rest, '\r?\n')
  $sampleLine = if ($nextEol.Success) { $rest.Substring(0, $nextEol.Index) } else { $rest }
  $tokens = [regex]::Matches($sampleLine, '\b[0-9a-fA-F]{1,8}\b')
  $samples = New-Object System.Collections.Generic.List[int]
  foreach ($t in $tokens) {
    if ($samples.Count -ge $count) { break }
    $samples.Add(([Convert]::ToInt32($t.Value, 16)) -band 0xFF)
  }
  # 点数与声明不符要**立刻失败**，不能带着一条"看起来还行"的短波形继续跑：
  # 否则页面显示一个和 count 不一致的点数，而没有任何一处会拦住它。
  if ($samples.Count -ne $count) {
    throw "LA RAW 声明 count=$count 但只解析出 $($samples.Count) 个采样点（回包被截断或格式变了？）"
  }
  return @{ samples = $samples.ToArray(); trigger = $trigger }
}

function Build-SegmentPacket($cfg, [int]$Windows) {
  # 分段命令（前缀 0xA6）：13 字节布局与单窗口完全一致，只有两处不同：
  #   [0]  = 0xA6（单窗口是 0xA5）
  #   [10] = 窗口数 N（单窗口命令里这个位置是 pre 低字节）
  # 校验和算法不变：前 12 字节逐字节异或。
  # **这个约定必须与固件和 python/logic_analyzer_serial.py 三处一致**，
  # 否则会把窗口数当成 pre 用（或反之），现象是"窗口采样点数为 0/异常"。
  #
  # pre/post 在分段模式下由**固件自己**设（命令里的这两个字节被忽略，固件固定 pre=16、post=111）：
  # 128 点的分段窗口塞不下单窗口模式的 pre=64/post=191 组合，而上位机也无法预知这一点。
  # 这里仍把 post 填成 111 只是为了让包内容可自解释，固件不读它。
  if ($Windows -lt 2 -or $Windows -gt 16) { throw "分段窗口数必须在 2..16 之间（1 窗请用单窗口命令）" }
  $segPost = 111
  $values = @(0xA6, $cfg.mode, $cfg.data,
              ($cfg.pattern_div -band 0xFF), (($cfg.pattern_div -shr 8) -band 0xFF),
              ($cfg.sample_div -band 0xFF), (($cfg.sample_div -shr 8) -band 0xFF),
              $cfg.trigger_type, $cfg.trigger_mask, $cfg.trigger_value,
              ($Windows -band 0xFF), ($segPost -band 0xFF))
  $checksum = 0
  foreach ($v in $values) { $checksum = $checksum -bxor $v }
  return ,([byte[]]($values + $checksum))
}

function Parse-SegmentReply([string]$text) {
  # 分段回包：一行 `LA SEGMENTS n=<hex>`，随后 n 个 `LA RAW` 块。
  # 返回每窗的 { samples, trigger }。块数或点数对不上就**立刻失败**——
  # 悄悄少拼一段会得到一条"看着正常"的短波形，而没有任何一处会拦住它。
  $head = [regex]::Match($text, 'LA SEGMENTS n=([0-9a-fA-F]{1,8})')
  if (-not $head.Success) { throw '回包里没有 LA SEGMENTS 行（固件不是分段版？）' }
  $want = [Convert]::ToInt32($head.Groups[1].Value, 16)
  $tail = $text.Substring($head.Index + $head.Length)
  $marks = [regex]::Matches($tail, 'LA RAW count=([0-9a-fA-F]{1,8}) trigger=([0-9a-fA-F]{1,8})')
  if ($marks.Count -ne $want) { throw "声明 $want 段，实际收到 $($marks.Count) 个 LA RAW 块" }
  $windows = New-Object System.Collections.ArrayList
  for ($k = 0; $k -lt $marks.Count; $k++) {
    $start = $marks[$k].Index
    $end = if ($k + 1 -lt $marks.Count) { $marks[$k + 1].Index } else { $tail.Length }
    # 交给 Parse-Raw：它内部只认第一行、且校验"点数必须等于 count"
    $null = $windows.Add((Parse-Raw $tail.Substring($start, $end - $start)))
  }
  return $windows
}

function Decode-Uart([int[]]$Samples, [int]$Channel = 0, [int]$BitSamples = 16) {
  # 与 python/logic_analyzer.py 的 decode_uart 同一套判据：
  # stop 位无效时只前进 1 个采样点继续找真正的起始位（不记假 framing error）。
  $mask = 1 -shl $Channel
  $level = New-Object int[] $Samples.Length
  for ($i = 0; $i -lt $Samples.Length; $i++) { $level[$i] = if ($Samples[$i] -band $mask) { 1 } else { 0 } }
  $out = New-Object System.Collections.Generic.List[byte]
  $errors = 0
  $half = [Math]::Max(1, [int]($BitSamples / 2))
  $i = 1
  while (($i + $BitSamples * 9 + $half) -lt $level.Length) {
    if ($level[$i - 1] -eq 1 -and $level[$i] -eq 0) {
      $value = 0
      for ($bit = 0; $bit -lt 8; $bit++) {
        if ($level[$i + $BitSamples * ($bit + 1) + $half] -eq 1) { $value = $value -bor (1 -shl $bit) }
      }
      if ($level[$i + $BitSamples * 9 + $half] -eq 1) {
        $out.Add([byte]$value)
        $i += $BitSamples * 10
      } else {
        $i += 1
      }
    } else {
      $i += 1
    }
  }
  return @{ data = $out.ToArray(); errors = $errors }
}

function Decode-Spi([int[]]$Samples, [int]$Clock = 0, [int]$Mosi = 1, [int]$Cs = 2) {
  $cm = 1 -shl $Clock; $mm = 1 -shl $Mosi; $csm = 1 -shl $Cs
  $out = New-Object System.Collections.Generic.List[byte]
  $value = 0; $bits = 0; $previous = 0
  foreach ($sample in $Samples) {
    $active = -not ($sample -band $csm)
    $rising = ($previous -eq 0) -and [bool]($sample -band $cm)
    $previous = if ($sample -band $cm) { 1 } else { 0 }
    if ($active -and $rising) {
      $value = (($value -shl 1) -bor $(if ($sample -band $mm) { 1 } else { 0 })) -band 0xFF
      $bits++
      if ($bits -eq 8) { $out.Add([byte]$value); $value = 0; $bits = 0 }
    } elseif (-not $active) {
      $value = 0; $bits = 0
    }
  }
  return $out.ToArray()
}

function Write-Vcd([int[]]$Samples, [string]$Path, [int]$Channels = 8, [int]$Trigger = -1,
                   [double]$SampleNs = 0, $Segments = $null, [double]$GapNs = 0) {
  $ids = @(); for ($i = 0; $i -lt $Channels; $i++) { $ids += [char]([int][char]'!' + $i) }
  # 时间戳单位：给了每点纳秒就按真实时间标，否则退回"1 个时间单位 = 1 个采样点"的旧行为。
  # 纯整数 µs（1000/2000/5000 ns）仍按整数写，保证既有归档 VCD 不被改动。
  $step = 1; $scale = '1ns'
  if ($SampleNs -gt 0) {
    if ($SampleNs -ge 1000) {
      $round = [Math]::Round($SampleNs / 1000.0)
      if ([Math]::Abs($SampleNs - $round * 1000.0) -lt 0.5) {
        $step = [int][Math]::Max(1, $round); $scale = "${step}us"
      } else {
        $step = [int][Math]::Max(1, [Math]::Round($SampleNs)); $scale = "${step}ns"
      }
    } else {
      $step = [int][Math]::Max(1, [Math]::Round($SampleNs)); $scale = "${step}ns"
    }
  }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("`$date`n  generated by logic_analyzer_capture.ps1`n`$end`n")
  [void]$sb.Append("`$timescale $scale `$end`n`$scope module capture `$end`n")
  for ($i = 0; $i -lt $Channels; $i++) { [void]$sb.Append("`$var wire 1 $($ids[$i]) ch$i `$end`n") }
  [void]$sb.Append("`$upscope `$end`n`$enddefinitions `$end`n")
  # 段间空档要跳时间戳：接缝处只隔 1 拍的话，任何波形软件都会把两段看成连续采样。
  $gapUnits = 0
  if ($Segments -and $Segments.Count -gt 1 -and $GapNs -gt 0) {
    $unit = if ($scale.EndsWith('us')) { $step * 1000.0 } else { [double]$step }
    $gapUnits = [int][Math]::Max(1, [Math]::Round($GapNs / $unit))
  }
  $boundaries = @{}
  if ($Segments -and $Segments.Count -gt 1) {
    for ($k = 1; $k -lt $Segments.Count; $k++) { $boundaries[[int]$Segments[$k][0]] = $true }
  }
  $stamp = 0
  [void]$sb.Append("#$stamp`n")
  for ($i = 0; $i -lt $Channels; $i++) {
    $bit = if ($Samples.Length -gt 0) { ($Samples[0] -shr $i) -band 1 } else { 0 }
    [void]$sb.Append("$bit$($ids[$i])`n")
  }
  for ($t = 1; $t -lt $Samples.Length; $t++) {
    if ($gapUnits -gt 0 -and $boundaries.ContainsKey($t)) { $stamp += $gapUnits - 1 }
    $stamp += 1
    [void]$sb.Append("#$stamp`n")
    for ($i = 0; $i -lt $Channels; $i++) { [void]$sb.Append("$(($Samples[$t] -shr $i) -band 1)$($ids[$i])`n") }
  }
  if ($Trigger -ge 0 -and $Trigger -lt $Samples.Length) {
    [void]$sb.Append("`$comment trigger_index=$Trigger `$end`n")
  }
  if ($Segments -and $Segments.Count -gt 1) {
    [void]$sb.Append("`$comment segments=$($Segments.Count) first_segment_end=$([int]$Segments[0][1]) `$end`n")
  }
  [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.ASCIIEncoding))
}

function Get-DecodeJson([string]$Mode, [switch]$Segmented) {
  # 波形页上的"帧边界 + 字节值标注"说明。必须与下面验收判据同源：
  # 判据是"解出的字节里含有模式字节"（Python 用 `in`、这里用 `-match`），
  # 板级实测 uart 与 spi **都只解出 1 个字节**（spi 窗口 85 点 = 1.8 个字节），所以统一框第 1 个。
  # 曾经按"SPI free-running、真实字节落在第 3 个"写成 3 —— 被实测证伪，
  # 会让离线重建直接报"只解出 1 个字节"而失败。标注与判据必须同源，这条是硬要求。
  #
  # -Segmented：分段窗口只有 128 点，而 16 点/比特的 UART 一帧要 160 点，**一帧装不下**；
  # 固件在分段模式把每比特压到 12 点（10 比特 = 120 点）。解码参数必须跟着改，
  # 否则波形上标的字节和判据用的字节不是同一个。
  if ($Mode -eq 'uart') {
    $bit = if ($Segmented) { 10 } else { 16 }
    return '"decode":{"protocol":"uart","channel":0,"bit_samples":' + $bit + ',"which":1},"tag_names":{"0":"UART_TX"}'
  }
  if ($Mode -eq 'spi') { return '"decode":{"protocol":"spi","clock":0,"mosi":1,"cs":2,"which":1},"tag_names":{"0":"SCLK","1":"MOSI","2":"CS"}' }
  return ''
}

function Write-ViewerHtml([string]$Template, [string]$Path, $Datasets) {
  $html = [System.IO.File]::ReadAllText($Template, [System.Text.Encoding]::UTF8)
  $marker = 'window.WAVEFORMS = null; // __WAVEFORMS_JSON__'
  if (-not $html.Contains($marker)) { throw "波形模板缺少数据占位行：$Template" }
  $html = $html.Replace($marker, "window.WAVEFORMS = $Datasets;")
  [System.IO.File]::WriteAllText($Path, $html, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- 主流程
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $Viewer) {
  foreach ($cand in @((Join-Path $scriptDir 'waveform_viewer.html'),
                      (Join-Path $scriptDir '../python/waveform_viewer.html'))) {
    if (Test-Path -LiteralPath $cand) { $Viewer = (Resolve-Path -LiteralPath $cand).Path; break }
  }
}
if (-not $Viewer -or -not (Test-Path -LiteralPath $Viewer)) {
  throw '找不到 waveform_viewer.html（波形查看模板），请与采集脚本放在同一目录'
}

if (-not $Port) { $Port = Find-Cp210xPort }
if (-not $Port) { throw '没有找到串口：请插好板载 CP2102 USB 线，或用 -Port COMx 指定' }
$modeList = @($Modes.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($m in $modeList) { if (-not $MODE_VALUES.ContainsKey($m)) { throw "未知模式：$m（可用 static,counter,uart,spi）" } }

# 时基自检：四种模式各自的采样率与真实时间窗，先打印出来，避免"标错了没人发现"。
foreach ($m in $modeList) {
  $tb = Get-Timebase $ClkHz (Get-ModeConfig $m $MODE_VALUES[$m]).sample_div
  Write-Host ("时基      {0,-7} 采样率 {1,10:F1} Hz  每点 {2,10:F3} ns" -f $m, $tb.sample_hz, $tb.sample_ns) `
    -ForegroundColor DarkGray
}
Write-Host ''

Write-Host "串口      $Port  $Baud 8N1"
Write-Host "输出目录  $Output"
Write-Host "波形模板  $Viewer"
Write-Host ''

# ---------------------------------------------------------------- 离线重建
# -FromCaptures <目录>：不碰串口，只把已有的 <mode>/<mode>_00.log 重建成波形页 + 总览页。
# 用途：① 交付包里预置板级实测波形（评委屈不接板子也能看）；
#       ② 波形模板升级后，不用重新采集就能刷新所有页面。
if ($FromCaptures) {
  $root = (Resolve-Path -LiteralPath $FromCaptures).Path
  $sets = @()
  foreach ($mode in $modeList) {
    $modeDir = Join-Path $root $mode
    $logPath = Join-Path $modeDir "${mode}_00.log"
    if (-not (Test-Path -LiteralPath $logPath)) { Write-Host "跳过 $mode（没有 $logPath）" -ForegroundColor Yellow; continue }
    # [2026-10-03 分段] -Segments N：把同目录下的 <mode>_00.._0(N-1).log 拼成一条长波形。
    # 段与段之间**没有被采样**（固件回传上一窗 + 收下一包配置），必须标出接缝与空档；
    # 这里用 -GapNs 给出实测值，或退回估计值并标注为"估计"。
    $segCount = if ($Segments -gt 1) { $Segments } else { 1 }
    $mergedSamples = New-Object System.Collections.Generic.List[int]
    # 用 ArrayList 存 [起点, 终点] 对。**不要**用 New-Object 'System.Collections.Generic.List[int[]]'：
    # Windows PowerShell 5.1 解析不了这种泛型嵌套语法，会静默返回 $null，
    # 之后所有 .Add()/索引都变成 null 传播（本轮实测报 op_Subtraction 与 NullArray）。
    $segRanges = New-Object System.Collections.ArrayList
    $firstTrigger = -1
    for ($k = 0; $k -lt $segCount; $k++) {
      $segLog = Join-Path $modeDir ('{0}_{1:d2}.log' -f $mode, $k)
      if (-not (Test-Path -LiteralPath $segLog)) {
        if ($segCount -gt 1) { throw "分段离线重建：缺少 $segLog" }
        break
      }
      $segParsed = Parse-Raw ([System.IO.File]::ReadAllText($segLog, [System.Text.Encoding]::ASCII))
      $start = $mergedSamples.Count
      foreach ($v in $segParsed.samples) { $mergedSamples.Add($v) }
      $null = $segRanges.Add(@([int]$start, [int]($mergedSamples.Count - 1)))
      if ($k -eq 0) { $firstTrigger = $segParsed.trigger }
    }
    if ($mergedSamples.Count -eq 0) { Write-Host "跳过 $mode（日志里没有样本）" -ForegroundColor Yellow; continue }
    $samples = $mergedSamples.ToArray()
    $segArr = $null
    if ($segRanges.Count -gt 1) {
      $segArr = @()
      foreach ($pair in $segRanges) { $segArr += , @([int]$pair[0], [int]$pair[1]) }
    }
    $parsed = @{ samples = $samples; trigger = $firstTrigger }
    # 解码按段进行：跨段的两个采样点在真实时间里隔了几十毫秒，拼帧会解出根本不存在的字节。
    # 段内样本与原日志一致，所以用首个日志的解码结果做同源校验即可（分段时逐段校验）。
    $picked = $null
    for ($k = 0; $k -lt $segCount; $k++) {
      $segLog = Join-Path $modeDir ('{0}_{1:d2}.log' -f $mode, $k)
      if (-not (Test-Path -LiteralPath $segLog)) { break }
      $segParsed = Parse-Raw ([System.IO.File]::ReadAllText($segLog, [System.Text.Encoding]::ASCII))
      if ($mode -eq 'uart') {
        $d = Decode-Uart $segParsed.samples 0 16
        if ($d.data.Count -lt 1) { throw "离线重建：uart 第 $($k + 1) 段没解出任何字节，无法在波形页上框出第 1 个" }
        if ($null -eq $picked) { $picked = $d.data[0] }
      } elseif ($mode -eq 'spi') {
        $sb2 = Decode-Spi $segParsed.samples 0 1 2
        if ($sb2.Count -lt 1) { throw "离线重建：spi 第 $($k + 1) 段没解出任何字节，无法在波形页上框出第 1 个" }
        if ($null -eq $picked) { $picked = $sb2[0] }
      }
    }
    if ($null -ne $picked -and $picked -ne $MODE_VALUES[$mode]) {
      throw ("离线重建：页面将框出的字节是 0x{0:x2}，与模式字节 0x{1:x2} 不一致（判据与标注必须同源）" -f $picked, $MODE_VALUES[$mode])
    }
    $pickNote = if ($null -ne $picked) { " 框出=0x$('{0:x2}' -f $picked)" } else { '' }
    # 离线重建拿不到原始位流的时钟，只能用 -ClkHz 给的频率反推；页面上的时间轴以此为准。
    $tb = Get-Timebase $ClkHz (Get-ModeConfig $mode $MODE_VALUES[$mode]).sample_div
    $dec = Get-DecodeJson $mode
    $decPart = if ($dec) { ',' + $dec } else { '' }
    $segPart = ''
    $segNote = ''
    if ($segArr) {
      $gap = if ($GapNs -gt 0) { $GapNs } else { 19000000.0 }
      $gapSource = if ($GapNs -gt 0) { '实测' } else { '估计' }
      $segJson = ($segArr | ForEach-Object { '[' + $_[0] + ',' + $_[1] + ']' }) -join ','
      $segPart = ',"segments":[' + $segJson + '],"gap_ns":' + $gap.ToString('F1', [System.Globalization.CultureInfo]::InvariantCulture)
      $segNote = " 分段 $($segArr.Count) 段 × $($segArr[0][1] - $segArr[0][0] + 1) 点 · 段间未采样 $gapSource $([Math]::Round($gap / 1000000.0, 1)) ms"
    }
    $note = "mode=$mode samples=$($samples.Length) trigger=$firstTrigger$pickNote$segNote 板级实测（$([IO.Path]::GetFileName($logPath))）"
    $one = '{"name":"' + $mode + ' 模式（板级实测）","channels":8,"samples":[' +
           (($samples) -join ',') + '],"trigger":' + $firstTrigger + ',"note":"' + $note + '",' +
           (Format-TbJson $tb) + $decPart + $segPart + '}'
    $sets += $one
    $stem = if ($segArr) { '{0}_seg{1:d2}' -f $mode, $segArr.Count } else { "${mode}_00" }
    if ($segArr) {
      # 分段长波形同时落一份 VCD：时间戳在接缝处跳过 gap，波形软件里也看得出空档。
      $gapForVcd = if ($GapNs -gt 0) { $GapNs } else { 19000000.0 }
      Write-Vcd $samples (Join-Path $modeDir "$stem.vcd") 8 $firstTrigger $tb.sample_ns $segArr $gapForVcd
    }
    $page = Join-Path $modeDir "$stem.html"
    Write-ViewerHtml $Viewer $page "[$one]"
    Write-Host "波形页    $page"
  }
  if ($sets.Count -eq 0) { throw "在 $root 下没有找到任何 <mode>/<mode>_00.log" }
  $preview = if ($PreviewPath) { $PreviewPath } else { Join-Path $root '波形预览.html' }
  Write-ViewerHtml $Viewer $preview ('[' + ($sets -join ',') + ']')
  Write-Host "总览页    $preview"
  Write-Host "LOGIC ANALYZER WAVEFORM REBUILD PASS pages=$($sets.Count)"
  exit 0
}

# ---------------------------------------------------------------- 固件分段（0xA6）
# -Segments N -Oneshot：一次配置连续采 N 窗，由**固件自己**衔接（采完一窗立刻 arm 下一窗），
# 段间空档从旧路径的约 19 ms 降到"读出 + 重新 arm"（约 15 µs 量级）。
# 段边界仍然保留、仍然如实标注：段与段之间照样没有被采样。
if ($Oneshot) {
  if ($Segments -lt 2) { throw '-Oneshot 需要 -Segments N（N≥2）：一次配置采 N 窗才有意义' }
  $sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
  $sp.ReadTimeout = 200
  $sp.WriteTimeout = 2000
  $sp.Open()
  $segFailures = 0
  try {
    $sp.DiscardInBuffer()
    [void](Sync-Ready $sp ([Math]::Min($TimeoutSec, 3.0)))
    foreach ($mode in $modeList) {
      $value = $MODE_VALUES[$mode]
      $cfg = Get-ModeConfig $mode $value
      $modeDir = Join-Path (Join-Path $Output 'logic_analyzer') $mode
      New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
      try {
        $packet = Build-SegmentPacket $cfg $Segments
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $sp.Write($packet, 0, $packet.Length)
        $raw = Receive-Until $sp 'LA_READY' $TimeoutSec
        $sw.Stop()
        if ($raw -match 'LA_CONFIG_ERROR') { throw '固件回了 LA_CONFIG_ERROR（窗口数不在 2..16，或校验和不对）' }
        if (-not $raw.Contains('LA_DONE')) { throw '分段采集没有收到 LA_DONE' }
        $windows = Parse-SegmentReply $raw
        $merged = New-Object System.Collections.Generic.List[int]
        $segArr = @()
        foreach ($w in $windows) {
          $start = $merged.Count
          foreach ($v in $w.samples) { $merged.Add($v) }
          $segArr += , @([int]$start, [int]($merged.Count - 1))
        }
        $samples = $merged.ToArray()
        $firstTrigger = $windows[0].trigger
        $tb = Get-Timebase $ClkHz $cfg.sample_div
        # 段间空档：优先用 -GapNs 给出的实测值；否则用估计值并**在页面上标"估计"**。
        # 另打印一次墙钟总耗时做量级自检：若远大于"回传全部字节所需时间"，说明上面那个估计偏小。
        $gap = if ($GapNs -gt 0) { $GapNs } else { 15000.0 }
        $gapSource = if ($GapNs -gt 0) { '实测' } else { '估计' }
        $txEstimateMs = ($samples.Length * 9.0 / $Baud) * 1000.0
        Write-Host ("  分段 {0} 段 × {1} 点 · 墙钟 {2:F1} ms（纯回传估计 {3:F1} ms）· 段间空档 {4}" -f `
          $windows.Count, ($segArr[0][1] - $segArr[0][0] + 1), $sw.Elapsed.TotalMilliseconds, $txEstimateMs, $gapSource) `
          -ForegroundColor DarkGray

        $stem = '{0}_seg{1:d2}' -f $mode, $windows.Count
        [System.IO.File]::WriteAllText((Join-Path $modeDir "$stem.log"), $raw, (New-Object System.Text.ASCIIEncoding))
        Write-Vcd $samples (Join-Path $modeDir "$stem.vcd") 8 $firstTrigger $tb.sample_ns $segArr $gap
        # 判据与页面标注同源：逐段解码，页面框第 1 段的第 1 个字节，这里就验它
        $picked = $null
        $decodedBySeg = @()
        foreach ($w in $windows) {
          if ($mode -eq 'uart') {
            $d = Decode-Uart $w.samples 0 10
            $decodedBySeg += $d.data.Count
            if ($null -eq $picked -and $d.data.Count -ge 1) { $picked = $d.data[0] }
          } elseif ($mode -eq 'spi') {
            $s2 = Decode-Spi $w.samples 0 1 2
            $decodedBySeg += $s2.Count
            if ($null -eq $picked -and $s2.Count -ge 1) { $picked = $s2[0] }
          }
        }
        if ($null -ne $picked -and $picked -ne $value) {
          throw ("页面将框出的字节是 0x{0:x2}，与模式字节 0x{1:x2} 不一致（判据与标注必须同源）" -f $picked, $value)
        }
        $pickNote = if ($null -ne $picked) { " 框出=0x$('{0:x2}' -f $picked)" } else { '' }
        $dec = Get-DecodeJson $mode -Segmented
        $decPart = if ($dec) { ',' + $dec } else { '' }
        $segJson = ($segArr | ForEach-Object { '[' + $_[0] + ',' + $_[1] + ']' }) -join ','
        $note = "mode=$mode samples=$($samples.Length) trigger=$firstTrigger$pickNote 固件分段 $($segArr.Count) 段 × $($segArr[0][1] - $segArr[0][0] + 1) 点 · 段间未采样 $gapSource $([Math]::Round($gap / 1000.0, 3)) us 每段解码字节数=$($decodedBySeg -join '/')"
        $one = '{"name":"' + $mode + ' 分段长波形（' + $segArr.Count + ' 段 · 固件一次配置）","channels":8,"samples":[' +
               (($samples) -join ',') + '],"trigger":' + $firstTrigger + ',"note":"' + $note + '",' +
               (Format-TbJson $tb) + ',"segments":[' + $segJson + '],"gap_ns":' +
               $gap.ToString('F1', [System.Globalization.CultureInfo]::InvariantCulture) + $decPart + '}'
        $page = Join-Path $modeDir "$stem.html"
        Write-ViewerHtml $Viewer $page "[$one]"
        Write-Host ("LOGIC ANALYZER SEGMENTED ONESHOT PASS mode={0} segments={1} samples={2} per_segment={3} gap_ns={4:F0} gap_source={5}" -f `
          $mode, $segArr.Count, $samples.Length, ($segArr[0][1] - $segArr[0][0] + 1), $gap, $(if ($GapNs -gt 0) { 'measured' } else { 'estimate' }))
        Write-Host ("    波形页 {0}" -f $page)
      } catch {
        $segFailures++
        Write-Host ("LOGIC ANALYZER SEGMENTED ONESHOT FAIL mode={0}: {1}" -f $mode, $_.Exception.Message) -ForegroundColor Red
      }
    }
  } finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
  }
  Write-Host ''
  if ($segFailures -gt 0) {
    Write-Host "LOGIC ANALYZER CAPTURE FAIL failures=$segFailures" -ForegroundColor Red
    exit 1
  }
  Write-Host "LOGIC ANALYZER SEGMENTED ONESHOT ALL PASS segments=$Segments output=$Output"
  exit 0
}

$sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout = 200
$sp.WriteTimeout = 2000
$sp.Open()
$failures = 0
$previewSets = @()
try {
  $sp.DiscardInBuffer()
  [void](Sync-Ready $sp ([Math]::Min($TimeoutSec, 3.0)))

  foreach ($mode in $modeList) {
    $value = $MODE_VALUES[$mode]
    $cfg = Get-ModeConfig $mode $value
    $packet = Build-Packet $cfg
    $modeDir = Join-Path (Join-Path $Output 'logic_analyzer') $mode
    New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
    $summaries = @()
    for ($run = 0; $run -lt $Runs; $run++) {
      try {
        $sp.Write($packet, 0, $packet.Length)
        $raw = Receive-Until $sp 'LA_READY' $TimeoutSec
        if (-not $raw.Contains('LA_DONE')) { throw '这一轮没有收到 LA_DONE' }
        $parsed = Parse-Raw $raw
        $samples = $parsed.samples
        $trigger = $parsed.trigger
        if ($samples.Length -eq 0 -or $trigger -ge $samples.Length) {
          throw "采集数据无效：samples=$($samples.Length) trigger=$trigger"
        }
        $stem = '{0}_{1:d2}' -f $mode, $run
        # 先把板子原始回包与 VCD 落盘：物理采集失败也要可查
        [System.IO.File]::WriteAllText((Join-Path $modeDir "$stem.log"), $raw, (New-Object System.Text.ASCIIEncoding))
        Write-Vcd $samples (Join-Path $modeDir "$stem.vcd") 8 $trigger

        $uartData = Decode-Uart $samples 0 16
        $spiData = Decode-Spi $samples 0 1 2
        $uartHex = (($uartData.data | ForEach-Object { '{0:x2}' -f $_ }) -join '')
        $spiHex = (($spiData | ForEach-Object { '{0:x2}' -f $_ }) -join '')

        if ($mode -eq 'static' -and ($samples | Where-Object { $_ -ne $value }).Count -gt 0) {
          throw ('static 回环不符：期望 0x{0:x2}' -f $value)
        }
        if ($mode -eq 'counter' -and (($samples | Sort-Object -Unique).Count -lt 2)) {
          throw 'counter 采样值没有变化'
        }
        if ($mode -eq 'uart' -and ($uartHex -notmatch ('{0:x2}' -f $value) -or $uartData.errors -gt 0)) {
          throw "UART 解码不符：$uartHex errors=$($uartData.errors)"
        }
        if ($mode -eq 'spi' -and ($spiHex -notmatch ('{0:x2}' -f $value))) {
          throw "SPI 解码不符：$spiHex"
        }
        # 判据与页面标注必须同源：页面上框出来的那个字节，就是这里判定用的那个。
        $decodeWhich = 1
        if ($mode -eq 'uart' -and $uartData.data.Count -lt $decodeWhich) {
          throw "UART 只解出 $($uartData.data.Count) 个字节，页面无法框出第 $decodeWhich 个"
        }
        if ($mode -eq 'spi' -and $spiData.Count -lt $decodeWhich) {
          throw "SPI 只解出 $($spiData.Count) 个字节，页面无法框出第 $decodeWhich 个"
        }
        $pickedValue = if ($mode -eq 'uart') { $uartData.data[$decodeWhich - 1] } elseif ($mode -eq 'spi') { $spiData[$decodeWhich - 1] } else { $null }
        if ($null -ne $pickedValue -and $pickedValue -ne $value) {
          throw ("页面框出的第 {0} 个字节是 0x{1:x2}，但判据用的是模式字节 0x{2:x2}；两者必须一致" -f $decodeWhich, $pickedValue, $value)
        }

        # 自包含波形页：双击用浏览器打开即可看，不需要 GTKWave
        $tb = Get-Timebase $ClkHz $cfg.sample_div
        $note = "mode=$mode samples=$($samples.Length) trigger=$trigger 采样率=$('{0:F4}' -f ($tb.sample_hz / 1000000.0))MHz 窗口=$('{0:F3}' -f ($tb.sample_ns * $samples.Length / 1000.0))us"
        if ($mode -eq 'uart') { $note += " UART解码=$uartHex" }
        if ($mode -eq 'spi') { $note += " SPI解码=$spiHex" }
        $dec = Get-DecodeJson $mode
        $decPart = if ($dec) { ',' + $dec } else { '' }
        $one = '{"name":"' + $mode + ' 模式 第' + ($run + 1) + '次","channels":8,"samples":[' +
               (($samples) -join ',') + '],"trigger":' + $trigger + ',"note":"' + $note + '",' +
               (Format-TbJson $tb) + $decPart + '}'
        Write-ViewerHtml $Viewer (Join-Path $modeDir "$stem.html") "[$one]"
        # 每个模式各留一次，最后拼成"四模式总览页"
        if ($run -eq 0) { $previewSets += $one }

        $summaries += [ordered]@{ run = $run; mode = $mode; value = $value; samples = $samples.Length;
                                 trigger = $trigger; sample_ns = $tb.sample_ns; sample_hz = $tb.sample_hz;
                                 uart = $uartHex; uart_errors = $uartData.errors; spi = $spiHex }
        Write-Host ("LOGIC ANALYZER BOARD RUN {0}/{1} PASS mode={2} samples={3} trigger={4} window_ns={5:F3}" -f ($run + 1), $Runs, $mode, $samples.Length, $trigger, ($tb.sample_ns * $samples.Length))
        Write-Host ("    波形页 {0}" -f (Join-Path $modeDir "$stem.html"))
      } catch {
        $failures++
        Write-Host ("LOGIC ANALYZER BOARD RUN {0}/{1} FAIL mode={2}: {3}" -f ($run + 1), $Runs, $mode, $_.Exception.Message) -ForegroundColor Red
      }
    }
    $jsonPath = Join-Path $modeDir 'summary.json'
    [System.IO.File]::WriteAllText($jsonPath, (($summaries | ConvertTo-Json -Depth 5) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
  }
} finally {
  if ($sp.IsOpen) { $sp.Close() }
  $sp.Dispose()
}

Write-Host ''
if ($failures -gt 0) {
  Write-Host "LOGIC ANALYZER CAPTURE FAIL failures=$failures" -ForegroundColor Red
  Write-Host '排查顺序：① 位流是不是 bitstream\mes50hp_riscv_logic_analyzer.sbit  ② J8 八组相邻脚是否接牢（3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32）  ③ 串口是否被别的程序占用'
  exit 1
}
$outRoot = Join-Path $Output 'logic_analyzer'
$preview = if ($PreviewPath) { $PreviewPath } else { Join-Path $outRoot '波形预览.html' }
if ($previewSets.Count -gt 0) {
  Write-ViewerHtml $Viewer $preview ('[' + ($previewSets -join ',') + ']')
  Write-Host "四模式总览页 $preview"
}
Write-Host "LOGIC ANALYZER CAPTURE PASS 输出=$outRoot"
Write-Host '双击上面列出的 .html 波形页，用浏览器即可查看波形（不需要安装任何软件）。'
exit 0
