param([Parameter(Mandatory=$true)][string]$Port,[int]$Baud=115200,[int]$RunsPerMode=20,[string]$Output='release/evidence/logic_analyzer_board')
$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
foreach($case in @(@('static','0xA5'),@('counter','0x00'),@('uart','0xA5'),@('spi','0x3C'))){
  $caseOutput=Join-Path $Output $case[0]
  & $python python/logic_analyzer_serial.py $Port --baud $Baud --runs $RunsPerMode --mode $case[0] --value $case[1] --output $caseOutput
  if($LASTEXITCODE -ne 0){throw "LOGIC ANALYZER PHYSICAL BOARD FAIL mode=$($case[0])"}
}
Write-Host "LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=$($RunsPerMode*4)"
