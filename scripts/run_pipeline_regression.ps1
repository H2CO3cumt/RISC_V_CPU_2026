$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'resolve_host.ps1')
$powerShell = Resolve-PowerShellHost
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
 # 子进程 stderr 在 Windows PowerShell 5.1 里会被包成 ErrorRecord，配合
 # $ErrorActionPreference='Stop' 会把"测试其实 PASS"误判成中断；成败只看退出码。
 $ErrorActionPreference='Continue'
 & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test)
 $testExit=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 if($testExit -ne 0){throw "$test failed with exit code $testExit"}
}
Write-Host "ALL PIPELINE REGRESSION PASS ($($tests.Count) entries)"
