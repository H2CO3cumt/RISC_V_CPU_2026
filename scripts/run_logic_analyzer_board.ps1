param([Parameter(Mandatory=$true)][string]$Port,[int]$Baud=115200,[int]$RunsPerMode=20,[string]$Output='release/evidence/logic_analyzer_board',[int]$ClockHz=85000000,[string]$MirrorText='HELLO,RISC-V',[switch]$IncludeCoreSource,[int]$CoreRuns=3)
$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
foreach($case in @(@('static','0xA5'),@('counter','0x00'),@('uart','0xA5'),@('spi','0x3C'))){
  $caseOutput=Join-Path $Output $case[0]
  & $python python/logic_analyzer_serial.py $Port --baud $Baud --runs $RunsPerMode --mode $case[0] --value $case[1] --output $caseOutput
  if($LASTEXITCODE -ne 0){throw "LOGIC ANALYZER PHYSICAL BOARD FAIL mode=$($case[0])"}
}
# 镜像模式：上位机把 $MirrorText 原样发到板子串口，逻辑分析仪抓的就是这根线本身
# （板级顶层把 uart0_rx 镜像到 J8-31/32，采集通道 ch7）。
# 判据是"从波形里解出来的字节必须逐字节等于发出去的字符串"，不是"解出了东西"。
$mirrorOutput=Join-Path $Output 'mirror'
& $python python/logic_analyzer_serial.py $Port --baud $Baud --runs $RunsPerMode --mode mirror --text $MirrorText --clock-hz $ClockHz --output $mirrorOutput
if($LASTEXITCODE -ne 0){throw "LOGIC ANALYZER PHYSICAL BOARD FAIL mode=mirror"}
$captures=$RunsPerMode*5
# 采集源=Core 内部观测点（0xA8 报文）：默认不跑，避免改变既有 "五模式 ×20 = 100/100"
# 这条已归档的验收口径与证据；要看 CPU 侧读数时显式加 -IncludeCoreSource。
if($IncludeCoreSource){
  $coreOutput=Join-Path $Output 'core'
  & $python python/logic_analyzer_serial.py $Port --baud $Baud --runs $CoreRuns --mode core --clock-hz $ClockHz --output $coreOutput
  if($LASTEXITCODE -ne 0){throw "LOGIC ANALYZER PHYSICAL BOARD FAIL mode=core"}
  $captures+=$CoreRuns
  Write-Host "LOGIC ANALYZER CORE SOURCE PASS captures=$CoreRuns source=core_probe"
}
Write-Host "LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=$captures mirror_text=$MirrorText"
