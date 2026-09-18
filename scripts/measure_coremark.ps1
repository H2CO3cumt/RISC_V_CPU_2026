param(
  [ValidateSet('cm50','cm80')][string]$Config='cm50',
  [string]$Port='',
  [int]$TimeoutSeconds=200,
  [switch]$SkipProgram
)
# 实体板 CoreMark 一键测量：下载对应位流 → 串口发送 'R' → 解析官方 CRC 与 Score。
#
#   cm50 = 50 MHz、1000 次迭代（计分点）
#   cm80 = 80 MHz PLL、2500 次迭代（频率项交叉验证点）
#
# 证据分别落到 release/evidence/coremark_board_<config>.json 与同名 .log。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repo
$python=if($env:PYTHON){$env:PYTHON}else{'D:\Python313\python.exe'}
if(-not (Test-Path -LiteralPath $python)){throw "找不到 Python: $python"}

$clockHz = if($Config -eq 'cm80'){80000000}else{50000000}

if(-not $SkipProgram){
  & (Join-Path $PSScriptRoot 'program_board.ps1') -Config $Config
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  Start-Sleep -Seconds 2
}

# 自动识别 CP210x 串口
if(-not $Port){
  $Port=(Get-CimInstance Win32_PnPEntity |
    Where-Object { $_.Name -match 'CP210|Silicon Labs' } |
    ForEach-Object { if($_.Name -match '(COM\d+)'){$Matches[1]} } |
    Select-Object -First 1)
}
if(-not $Port){throw '未找到 CP210x 串口，请确认底板 USB-UART 已连接'}
Write-Host "PORT     $Port  clock_hz=$clockHz"

$log=Join-Path $repo "release/evidence/coremark_uart_$Config.log"
$json=Join-Path $repo "release/evidence/coremark_board_$Config.json"
New-Item -ItemType Directory -Force (Join-Path $repo 'release/evidence') | Out-Null

& $python python/coremark_serial.py $Port --clock-hz $clockHz --timeout $TimeoutSeconds --output $log --summary $json
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host "COREMARK BOARD PASS config=$Config evidence=$json"
