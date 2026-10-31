param(
  [Parameter(Mandatory=$true)][string]$Port,
  [int]$Baud=115200,
  [double]$Seconds=12,
  [int]$Delta=12500000,
  [int]$ClockHz=50000000,
  [switch]$SkipProgram,
  [string]$Output='release/evidence/timer_demo_board'
)
# M-24/N1 实板验收：把 fpga/timer_demo 的位流下载到 MES50HP，再从 CP2102 读回
# 周期性定时器中断的串口证据。
#
# 两条证据一起构成 M-24 的"板级中断演示"：
#   1. 脚本自己判定的串口流（'=' 自检 + 逐次递增的中断计数 + LED 位交替 + 周期落在容差内）；
#   2. 人眼可见的 LED0 固定周期闪烁（0.5 s 一个完整亮灭周期，见 fpga/timer_demo/README.md）。
# 脚本不试图自动"看"LED——那需要摄像头；它只把可自动判定的部分做成 PASS/FAIL。
$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}

if(-not $SkipProgram){
  & "$PSScriptRoot/program_board.ps1" -Config tm50
  if($LASTEXITCODE -ne 0){ throw 'timer demo bitstream download failed' }
} else {
  Write-Host 'SKIP PROGRAM: 假定板上已经是要测的 timer_demo 位流'
}

$outDir=Join-Path $Output 'uart'
New-Item -ItemType Directory -Force $outDir | Out-Null
& $python python/timer_demo_serial.py $Port --baud $Baud --seconds $Seconds `
  --delta $Delta --clock-hz $ClockHz `
  --output (Join-Path $outDir 'uart_00.log') `
  --summary (Join-Path $Output 'timer_demo_board.json')
if($LASTEXITCODE -ne 0){ throw "N1 TIMER DEMO BOARD FAIL on port $Port" }

Write-Host "N1 TIMER DEMO BOARD ACCEPTANCE PASS port=$Port delta=$Delta"
Write-Host "证据: $(Join-Path $Output 'timer_demo_board.json') 与 $(Join-Path $outDir 'uart_00.log')"
Write-Host "请同时用肉眼/视频确认 LED0（板上 LED1，管脚 B2）以 0.5 s 为整周期闪烁。"
