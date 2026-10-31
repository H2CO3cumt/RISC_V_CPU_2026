param(
  [Parameter(Mandatory=$true)][string]$Port,
  [int]$RunsPerMode = 20,
  [ValidateSet('1','2','3','all')][string]$Round = 'all',
  [switch]$SkipCoreMark,
  [int]$PauseSeconds = 0,
  [switch]$PowerCycled
)
# Task 35 验收「多次断电、Reset 和重新连接串口后演示结果一致」的自动化部分。
#
# 每一轮做同一套事，并落盘到 release/evidence/board/runNN：
#   1. 下载交付位流 la50 -> J8 四模式各 RunsPerMode 次采集（默认 80 次）
#   2. 下载计分位流 cm50 -> CoreMark，记录 ticks / crc / iterations
# 三轮跑完后比较：三轮的采集通过数、CoreMark ticks 与 crc 必须完全一致。
#
# 关于「断电」：脚本**无法**切断板子电源。用 -PauseSeconds N 会在轮次之间
# 打印醒目提示并等待 N 秒，让人在这段时间里断电 5 秒再上电；填 0 则只做
# 「重新下载 = 重新配置 FPGA」这种 Reset 等价动作。两种模式都会在 summary 里
# 如实记录本轮的复位方式，不要混报。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1（PS 5.1 读无 BOM 的 .ps1 会按 ANSI 解码）。
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$python = if($env:PYTHONIOENCODING){ $env:PYTHONIOENCODING = 'utf-8' } else { $env:PYTHONIOENCODING = 'utf-8' }
$py = if($env:PYTHON){ $env:PYTHON } else { 'python' }
$ps51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$boardRoot = Join-Path $repo 'release/evidence/board'

function Invoke-Round([int]$n, [string]$resetKind) {
  $dir = Join-Path $boardRoot ("run{0:D2}" -f $n)
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Write-Host ''
  Write-Host ("================ ROUND {0:D2}  (reset={1}) ================" -f $n, $resetKind)

  # ---- 1) 交付位流 + J8 四模式 ----
  Write-Host '--- 1/2 下载交付位流 la50 并跑 J8 四模式 ---'
  $pLog = Join-Path $dir 'program_la50.log'
  & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts/program_board.ps1') -Config la50 *>&1 |
    Tee-Object -FilePath $pLog | Select-String -Pattern 'PROGRAM PASS|done bit|SHA256' | ForEach-Object { Write-Host ("  " + $_) }
  if($LASTEXITCODE -ne 0){ throw "round ${n}: program la50 failed" }

  $laDir = Join-Path $dir 'logic_analyzer'
  $laLog = Join-Path $dir 'logic_analyzer.log'
  & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts/run_logic_analyzer_board.ps1') `
      -Port $Port -RunsPerMode $RunsPerMode -Output $laDir *>&1 |
    Tee-Object -FilePath $laLog | Select-Object -Last 3 | ForEach-Object { Write-Host ("  " + $_) }
  $laPass = ($LASTEXITCODE -eq 0)

  # ---- 2) 计分位流 + CoreMark ----
  $cm = $null
  if(-not $SkipCoreMark){
    Write-Host '--- 2/2 下载计分位流 cm50 并跑 CoreMark ---'
    $pLog2 = Join-Path $dir 'program_cm50.log'
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts/program_board.ps1') -Config cm50 *>&1 |
      Tee-Object -FilePath $pLog2 | Select-String -Pattern 'PROGRAM PASS|done bit' | ForEach-Object { Write-Host ("  " + $_) }
    if($LASTEXITCODE -ne 0){ throw "round ${n}: program cm50 failed" }

    $cmLog = Join-Path $dir 'coremark.log'
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts/run_coremark_board.ps1') -Port $Port -TimeoutSeconds 120 *>&1 |
      Tee-Object -FilePath $cmLog | Select-String -Pattern 'COREMARK BOARD PASS|COREMARK PHYSICAL' | ForEach-Object { Write-Host ("  " + $_) }
    if($LASTEXITCODE -ne 0){ throw "round ${n}: coremark failed" }

    Copy-Item (Join-Path $repo 'release/evidence/coremark_board.json') (Join-Path $dir 'coremark_board.json') -Force
    Copy-Item (Join-Path $repo 'release/evidence/coremark_uart.log')   (Join-Path $dir 'coremark_uart.log') -Force
    $cm = Get-Content -Raw (Join-Path $dir 'coremark_board.json') | ConvertFrom-Json
    # 从板子自己的串口输出里取 crcfinal（比只看 json 更硬）
    $uart = Get-Content -Raw (Join-Path $dir 'coremark_uart.log')
    $m = [regex]::Match($uart, 'crcfinal\s*:\s*(0x[0-9a-fA-F]+)')
    $crc = if($m.Success){ $m.Groups[1].Value } else { '' }
  }

  $laCount = 0
  if(Test-Path $laDir){ $laCount = (Get-ChildItem $laDir -Recurse -File).Count }
  $summary = [ordered]@{
    round             = $n
    reset_kind        = $resetKind
    timestamp         = (Get-Date -Format o)
    port              = $Port
    runs_per_mode     = $RunsPerMode
    la_pass           = $laPass
    la_files          = $laCount
    coremark_ticks    = if($cm){ $cm.ticks } else { $null }
    coremark_crcfinal = if($cm){ $crc } else { $null }
    coremark_iterations = if($cm){ $cm.iterations } else { $null }
    coremark_score_x1000 = if($cm){ $cm.score_x1000 } else { $null }
    coremark_validation  = if($cm){ $cm.validation } else { $null }
    coremark_cpi_x1000   = if($cm){ $cm.cpi_x1000 } else { $null }
    bitstream_la50_sha256  = 'BCAE040A3B96652BB4B73907FFA03178C05453C0E9CD07E5697E401845FDD184'
    bitstream_cm50_sha256  = 'DC95F9D087B7E29BB8780A46179FDE8D754563BB018B4E973FD08103232F5675'
  }
  $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'summary.json') -Encoding utf8
  Write-Host ("  -> {0}  la_pass={1} ticks={2} crc={3}" -f $dir, $laPass, $summary.coremark_ticks, $summary.coremark_crcfinal)
  return [pscustomobject]$summary
}

# ---------- 收集要跑的轮次 ----------
$rounds = if($Round -eq 'all'){ @(1,2,3) } else { @([int]$Round) }
foreach($r in $rounds){
  # 诚实起见：脚本**无法**确认板子是否真的被断过电。只有调用者用 -PowerCycled
  # 明确声明"这一轮之前我确实断了电"，才记成 power-cycle；否则一律记 re-download。
  $resetKind = 're-download (reset-equivalent, FPGA reconfigured)'
  if($PauseSeconds -gt 0){
    Write-Host ''
    Write-Host ('*' * 72)
    Write-Host ("  请现在对板子断电 5 秒，再重新上电。$PauseSeconds 秒后自动继续。")
    Write-Host '  （脚本不能替你断电，也不能验证你是否断了电）'
    Write-Host ('*' * 72)
    for($s = $PauseSeconds; $s -gt 0; $s -= 10){ Write-Host ("    剩余 $s 秒 ..."); Start-Sleep -Seconds ([Math]::Min(10,$s)) }
    $resetKind = 're-download after pause (power-off NOT verified by script)'
  }
  if($PowerCycled){ $resetKind = 'power-cycle asserted by operator + re-download' }
  $null = Invoke-Round -n $r -resetKind $resetKind
}

# ---------- 比对：读取磁盘上所有已存在的 runNN，跨多次调用也成立 ----------
New-Item -ItemType Directory -Force -Path $boardRoot | Out-Null
$found = @()
foreach($n in 1..3){
  $sj = Join-Path $boardRoot ("run{0:D2}/summary.json" -f $n)
  if(Test-Path $sj){ $found += (Get-Content -Raw $sj | ConvertFrom-Json) }
}
if($found.Count -ge 2){
  Write-Host ''
  Write-Host '================ 轮次一致性比对 ================'
  $ok = $true
  $r1 = $found[0]
  foreach($x in $found){
    Write-Host ("  run{0:D2}  reset={1}" -f $x.round, $x.reset_kind)
    Write-Host ("        la_pass={0}  ticks={1}  crc={2}  iterations={3}  score_x1000={4}  cpi_x1000={5}" -f `
      $x.la_pass, $x.coremark_ticks, $x.coremark_crcfinal, $x.coremark_iterations, $x.coremark_score_x1000, $x.coremark_cpi_x1000)
    if(-not $x.la_pass){ $ok = $false; Write-Host "    !! 本轮逻辑分析仪采集未全过" }
    if(-not $SkipCoreMark){
      if($x.coremark_ticks -ne $r1.coremark_ticks){ $ok = $false; Write-Host ("    !! ticks 与 run{0:D2} 不一致" -f $r1.round) }
      if($x.coremark_crcfinal -ne $r1.coremark_crcfinal){ $ok = $false; Write-Host ("    !! crcfinal 与 run{0:D2} 不一致" -f $r1.round) }
      if($x.coremark_iterations -ne $r1.coremark_iterations){ $ok = $false; Write-Host ("    !! iterations 与 run{0:D2} 不一致" -f $r1.round) }
      if($x.coremark_validation -ne 'PASS'){ $ok = $false; Write-Host '    !! CRC 校验未 PASS' }
    }
  }
  @{ rounds = $found; consistent = $ok; compared_at = (Get-Date -Format o) } | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $boardRoot 'consistency.json') -Encoding utf8
  Write-Host ''
  if($ok){ Write-Host 'BOARD ROUND CONSISTENCY PASS' } else { throw 'BOARD ROUND CONSISTENCY FAIL' }
} else {
  Write-Host ("目前只有 {0} 轮证据；跑满 2 轮以上才会做比对。" -f $found.Count)
}
Write-Host ("证据目录: " + $boardRoot)
