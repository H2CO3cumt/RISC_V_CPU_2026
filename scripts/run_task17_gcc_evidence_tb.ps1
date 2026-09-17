param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'
$env:PATH = "$(Resolve-Path $IcarusRoot)\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp/task17 | Out-Null
$src=@('rtl/single_cycle_cpu.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v','rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','tb/task15_ram_adapter.v','tb/task15_imem_adapter.v','tb/task15_core_harness.v','tb/tb_task17_gcc_evidence.v')
function Compare-Trace([string]$e,[string]$a,[string]$label) {
  $names=@('index','pc','instruction','rd_we','rd','rd_data','mem_we','mem_addr','mem_data','mem_wstrb'); $el=@(Get-Content $e|?{$_});$al=@(Get-Content $a|?{$_});
  for($r=0;$r -lt [Math]::Max($el.Count,$al.Count);$r++){if($r -ge $el.Count -or $r -ge $al.Count){Write-Host "$label FIRST DIFFERENCE record=$r";return $false};$x=@($el[$r]-split ' ');$y=@($al[$r]-split ' ');for($f=0;$f -lt 10;$f++){if($x[$f] -cne $y[$f]){Write-Host "$label FIRST DIFFERENCE record=$r field=$($names[$f]) expected=$($x[$f]) actual=$($y[$f]) pc=$($x[1]) instruction=$($x[2])";return $false}}};Write-Host "$label PASS";return $true
}
function Run([string]$name,[string]$define,[string]$software) {
  & make.exe -C $software all;if($LASTEXITCODE){return $false}; & iverilog -g2012 "-D$define" -s tb_task17_gcc_evidence -o "tmp/task17/$name.out" $src;if($LASTEXITCODE){return $false};& vvp "tmp/task17/$name.out";if($LASTEXITCODE){return $false}
  $base="tests/task17_golden/$name";$actual="tmp/task17/${name}_";$ok=$true
  foreach($pair in @(@('state','state'),@('performance','perf'))){$e=@(Get-Content "$base/$($pair[0]).golden"|?{$_});$a=@(Get-Content "$actual$($pair[1]).actual"|?{$_});if(Compare-Object $e $a){Write-Host "$name $($pair[0]) FAIL";$ok=$false}else{Write-Host "$name $($pair[0]) PASS"}}
  $trace="$($actual)trace.actual";$ok=(Compare-Trace "$base/trace.golden" $trace "$name trace golden") -and $ok
  $m=@(Get-Content $trace);$p=@($m[0]-split ' ');$p[5]='deadbeef';$m[0]=$p -join ' ';Set-Content "tmp/task17/${name}_mutated.trace" $m;if(Compare-Trace $trace "tmp/task17/${name}_mutated.trace" "$name intentional rd_data mutation"){$ok=$false}
  return $ok
}
$ok=(Run 'c_smoke' 'TASK17_C_SMOKE' 'software/task14_c_smoke');$ok=(Run 'array_control' 'TASK17_ARRAY_CONTROL' 'software/task14_array_control') -and $ok;if(!$ok){exit 1};Write-Output 'ALL TASK17 GCC EVIDENCE TESTS PASS'
