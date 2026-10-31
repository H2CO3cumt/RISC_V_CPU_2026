param(
  [Parameter(Mandatory=$true)][string]$Port,
  [string]$Config='la85',
  [int]$ClockHz=85000000,
  [int]$Runs=3,
  [int]$Baud=115200,
  [double]$TimeoutSeconds=30,
  [string]$Output='release/evidence/core_probe_board'
)
# 逻辑分析仪"双源可选"的板级验收（Core 内部观测点这一半）。
#
# 判据（由 python/logic_analyzer_serial.py 的 mode == "core" 分支与
# python/core_probe_board.py 共同给出）：
#   1. 窗口点数 = pre + 触发 + post = 2048（全速采样 sample_div=0）；
#   2. 窗口里 ch7（trace_valid）提交脉冲 ≥ 8 —— 证明 Core 真的在跑；
#   3. 窗口里 ch0（i_req_valid）为高的拍 ≥ 8 —— 证明取指通道真的在工作；
#   4. 两组触发（ch6 event_flush / ch5 event_stall）都必须命中。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1。
$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
New-Item -ItemType Directory -Force $Output | Out-Null

Write-Host "CORE PROBE: programming $Config"
& "$PSScriptRoot\program_board.ps1" -Config $Config
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Start-Sleep -Seconds 2

Push-Location (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
try {
  & $python python/core_probe_board.py $Port --output $Output --runs $Runs `
      --baud $Baud --timeout $TimeoutSeconds --clock-hz $ClockHz
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
} finally { Pop-Location }
