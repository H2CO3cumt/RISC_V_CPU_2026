param([Parameter(Mandatory=$true)][string]$Port,[int]$Baud=115200,[int]$TimeoutSeconds=70)
$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
New-Item -ItemType Directory -Force release/evidence | Out-Null
& $python python/coremark_serial.py $Port --baud $Baud --timeout $TimeoutSeconds --output release/evidence/coremark_uart.log --summary release/evidence/coremark_board.json
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host 'COREMARK PHYSICAL BOARD ACCEPTANCE PASS'
