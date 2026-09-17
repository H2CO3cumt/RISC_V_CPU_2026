$ErrorActionPreference='Stop'
$banned = '\b(?:rle|cache|interrupt|exception|ai|ddr|hdmi|pcie|ethernet|i2c|16.?channel)\b'
$violations = @()
foreach($root in @('rtl','fpga/task30_logic_analyzer','software/task30_logic_analyzer','python')) {
  if(Test-Path $root) {
    $violations += rg -n -i --glob '*.v' --glob '*.c' --glob '*.S' --glob '*.py' $banned $root 2>$null
  }
}
if($violations.Count -ne 0) { $violations | Tee-Object tmp/scope_audit_fail.txt; throw 'FROZEN FEATURE SCOPE AUDIT FAIL' }
if((Test-Path rtl/pipeline_cpu.v) -and (Test-Path fpga/task26_pipeline_soc/rtl/mes50hp_pipeline_soc_top.v)) {
  $coreHash=(Get-FileHash rtl/pipeline_cpu.v -Algorithm SHA256).Hash
  Write-Host "pipeline_cpu_sha256=$coreHash"
}
if(-not (Test-Path rtl/branch_predictor.v)){throw 'FINAL BRANCH PREDICTOR IS MISSING'}
Write-Host 'SCOPE AUDIT PASS: final BTB present; no frozen RLE/cache/exception/device-specific Core implementation found'
exit 0
