$ErrorActionPreference='Stop'
./scripts/run_gcc_pipeline_equivalence.ps1
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
python python/performance_report.py
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
if(-not (Test-Path tmp/performance_report.md)){throw 'performance report missing'}
Write-Output 'ALL PERFORMANCE REPORT TEST PASS'
