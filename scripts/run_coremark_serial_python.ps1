$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
& $python python/test_coremark_serial.py
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
