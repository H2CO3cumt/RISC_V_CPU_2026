$ErrorActionPreference='Stop'
$powerShell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $powerShell) { $powerShell = (Get-Command powershell -ErrorAction Stop).Source }
$tests=@(
 'run_forward_unit_tb.ps1',
 'run_hazard_unit_tb.ps1',
 'run_pipeline_no_hazard_tb.ps1',
 'run_pipeline_forward_tb.ps1',
 'run_pipeline_load_use_tb.ps1',
 'run_pipeline_control_tb.ps1',
 'run_pipeline_hazard_stress_tb.ps1',
 'run_pipeline_wb_hold_tb.ps1',
 'run_pipeline_reset_abort_tb.ps1',
 'run_branch_predictor_tb.ps1',
 'run_pipeline_branch_predictor_tb.ps1',
 'run_pipeline_error_observability_tb.ps1',
 'run_pipeline_smoke_tb.ps1'
)
foreach($test in $tests){
 Write-Host "RUN $test"
 # Each standalone test exits explicitly; isolate it so the aggregator can
 # continue through every fixed/random hazard case.
 & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test)
 if($LASTEXITCODE -ne 0){throw "$test failed with exit code $LASTEXITCODE"}
}
Write-Host "ALL TASK23 PIPELINE REGRESSION PASS ($($tests.Count) entries)"
