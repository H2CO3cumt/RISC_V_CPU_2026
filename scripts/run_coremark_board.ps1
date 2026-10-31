param(
  [Parameter(Mandatory=$true)][string]$Port,
  [int]$Baud=115200,
  [int]$TimeoutSeconds=70,
  [int]$ClockHz=50000000,
  # 输出路径可覆盖：RV32IM 增强配置必须写到**自己的**文件里，绝不能覆盖
  # release/evidence/coremark_board.json —— 那个文件承载的是 50 MHz RV32I 基线
  # （claims_map §3.1 的证据指针指着它）。历史教训见 release/evidence/claims_map.md §12：
  # 跨批次覆盖是这份材料收口时发现的主要风险。
  [string]$OutputFile='release/evidence/coremark_uart.log',
  [string]$SummaryFile='release/evidence/coremark_board.json'
)
$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
New-Item -ItemType Directory -Force release/evidence | Out-Null
& $python python/coremark_serial.py $Port --baud $Baud --timeout $TimeoutSeconds --clock-hz $ClockHz --output $OutputFile --summary $SummaryFile
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host "COREMARK PHYSICAL BOARD ACCEPTANCE PASS summary=$SummaryFile clock_hz=$ClockHz"
