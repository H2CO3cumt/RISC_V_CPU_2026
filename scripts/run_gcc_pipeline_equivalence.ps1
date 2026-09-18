param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop';$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH;New-Item -ItemType Directory -Force tmp/gcc_pipeline|Out-Null
$src=@('rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v','rtl/perf_monitor.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/pipeline_imem_adapter.v','tb/ram_adapter.v','tb/tb_gcc_pipeline.v')
function Compare-Trace([string]$expected,[string]$actual,[string]$label){
 $names=@('index','pc','instruction','rd_we','rd','rd_data','mem_we','mem_addr','mem_data','mem_wstrb');$e=@(Get-Content $expected|?{$_});$a=@(Get-Content $actual|?{$_});
 for($r=0;$r -lt [Math]::Max($e.Count,$a.Count);$r++){if($r -ge $e.Count -or $r -ge $a.Count){Write-Host "$label FIRST DIFFERENCE record=$r count expected=$($e.Count) actual=$($a.Count)";return $false};$x=@($e[$r]-split ' ');$y=@($a[$r]-split ' ');for($f=0;$f -lt 10;$f++){if($x[$f] -cne $y[$f]){Write-Host "$label FIRST DIFFERENCE record=$r field=$($names[$f]) expected=$($x[$f]) actual=$($y[$f]) pc=$($x[1]) instruction=$($x[2])";return $false}}};Write-Host "$label TRACE PASS ($($e.Count) records)";return $true
}
function Run-One([string]$name,[string]$define,[string]$software,[int]$random){
 $buildOutput=& make.exe -C $software all 2>&1;$buildCode=$LASTEXITCODE;$buildOutput|Out-Host;if($buildCode){return $false}
 $compileOutput=& iverilog -g2012 "-D$define" "-Ptb_gcc_pipeline.RANDOM_DELAY=$random" -s tb_gcc_pipeline -o "tmp/gcc_pipeline/$name-$random.out" $src 2>&1;$compileCode=$LASTEXITCODE;$compileOutput|Out-Host;if($compileCode){return $false}
 $simOutput=& vvp "tmp/gcc_pipeline/$name-$random.out" 2>&1;$simCode=$LASTEXITCODE;$simOutput|Out-Host;if($simCode){return $false}
 Copy-Item tmp/gcc_pipeline/trace.actual "tmp/gcc_pipeline/$name-$random.trace";Copy-Item tmp/gcc_pipeline/state.actual "tmp/gcc_pipeline/$name-$random.state";Copy-Item tmp/gcc_pipeline/perf.actual "tmp/gcc_pipeline/$name-$random.perf"
 $base="tests/golden/$name";$ok=Compare-Trace "$base/trace.golden" "tmp/gcc_pipeline/$name-$random.trace" "$name random=$random"
 if(Compare-Object @(Get-Content "$base/state.golden"|?{$_}) @(Get-Content "tmp/gcc_pipeline/$name-$random.state"|?{$_})){Write-Host "$name random=$random STATE FAIL";$ok=$false}else{Write-Host "$name random=$random STATE PASS"};return $ok
}
$ok=$true;foreach($case in @(@('c_smoke','GCC_PIPELINE_C_SMOKE','software/c_smoke'),@('array_control','GCC_PIPELINE_ARRAY_CONTROL','software/c_array_control'))){foreach($random in @(0,1)){$ok=(Run-One $case[0] $case[1] $case[2] $random)-and$ok}}
if(!$ok){exit 1};Write-Host 'ALL GCC PIPELINE TESTS PASS'
