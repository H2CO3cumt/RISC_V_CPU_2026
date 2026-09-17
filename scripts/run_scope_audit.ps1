$ErrorActionPreference='Stop'
# 冻结范围审计：确认本届最终配置里没有出现已冻结功能（RLE/Cache/异常中断/AI/DDR/
# HDMI/PCIe/千兆网/I2C/16 通道）的实现，同时确认 16 项 BTB 仍然存在。
#
# 只扫描**源文件**：排除 PDS 构建产物（flow.log / synthesize / generate_bitstream 等）
# 与 Python 字节码缓存，否则工具自身的器件资源表（例如 PCIE 一列）会造成误报。
$banned = '\b(?:rle|cache|interrupt|exception|ai|ddr|hdmi|pcie|ethernet|i2c|16.?channel)\b'
$include = @('*.v','*.c','*.S','*.py','*.h','*.ld','*.tcl','*.fdc','*.md','*.ps1')
$skipDir = @('generate_bitstream','synthesize','place_route','route_optimize','device_map',
             'report_timing','compile','logbackup','bak','ip','__pycache__','node_modules',
             'build','.git')

function Get-ScopedFiles([string]$root){
  $pending = New-Object System.Collections.Generic.Queue[string]
  $pending.Enqueue((Resolve-Path -LiteralPath $root).Path)
  $files = New-Object System.Collections.Generic.List[string]
  while($pending.Count -gt 0){
    $dir = $pending.Dequeue()
    foreach($sub in (Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue)){
      if($skipDir -contains $sub.Name){continue}
      $pending.Enqueue($sub.FullName)
    }
    foreach($f in (Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue)){
      foreach($pattern in $include){
        if($f.Name -like $pattern){ $files.Add($f.FullName); break }
      }
    }
  }
  return $files
}

$violations = New-Object System.Collections.Generic.List[string]
$scanned = 0
foreach($root in @('rtl','fpga/task30_logic_analyzer','software/task30_logic_analyzer','python')) {
  if(-not (Test-Path -LiteralPath $root)){ continue }
  foreach($file in (Get-ScopedFiles $root)){
    $scanned++
    $matches = Select-String -LiteralPath $file -Pattern $banned -CaseSensitive:$false -ErrorAction SilentlyContinue
    foreach($m in $matches){
      $violations.Add(("{0}:{1}: {2}" -f $m.Path.Replace((Get-Location).Path + '\',''), $m.LineNumber, $m.Line.Trim()))
    }
  }
}
Write-Host "SCOPE AUDIT SCANNED files=$scanned roots=rtl,fpga/task30_logic_analyzer,software/task30_logic_analyzer,python"
if($violations.Count -ne 0) {
  $violations | Tee-Object tmp/scope_audit_fail.txt
  throw 'FROZEN FEATURE SCOPE AUDIT FAIL'
}
if(-not (Test-Path rtl/branch_predictor.v)){throw 'FINAL BRANCH PREDICTOR IS MISSING'}
if((Test-Path rtl/pipeline_cpu.v)) {
  $coreHash=(Get-FileHash rtl/pipeline_cpu.v -Algorithm SHA256).Hash
  Write-Host "pipeline_cpu_sha256=$coreHash"
}
# 正向检查：16 项直接映射 BTB 与 2-bit 饱和计数器必须在最终配置里
$btb = Get-Content -LiteralPath rtl/branch_predictor.v -Raw
if($btb -notmatch 'reg\s+valid\s*\[0:15\]'){throw 'FINAL BTB IS NOT 16-ENTRY'}
if($btb -notmatch "reg\s+\[1:0\]\s+counter\s*\[0:15\]"){throw 'FINAL BTB LACKS 2-BIT SATURATING COUNTERS'}
Write-Host 'SCOPE AUDIT PASS: 16-entry BTB + 2-bit counters present; no frozen RLE/cache/exception/device-specific Core implementation found'
exit 0
