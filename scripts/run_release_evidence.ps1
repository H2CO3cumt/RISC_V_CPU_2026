$ErrorActionPreference='Stop'
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
& $python python/release_evidence.py
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
if(-not (Test-Path release/evidence/automated_metrics.json)){throw 'release metrics missing'}
Write-Host 'ALL RELEASE EVIDENCE TEST PASS'
