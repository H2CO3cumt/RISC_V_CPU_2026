$ErrorActionPreference='Stop'
# 范围审计：确认最终配置里没有出现**暂不实现**的功能
# （RLE/AI/HDMI/PCIe/千兆网/I2C/16 通道）的实现，同时确认 16 项 BTB 仍然存在。
#
# ## 2026-09-29 更新：Cache / burst / DDR3 / 异常中断 已纳入，不再列入暂不实现清单
#
# 2026-09-29 已确认 `AGENTS.md` §1.14 的范围变更：I-Cache / D-Cache / burst /
# 外部 DDR3 由"本届不做"改为"本届要做"（异常/中断更早就在 A3 轮次纳入）。
# 因此本审计原先的 banned 列表（含 cache / ddr / interrupt / exception）已过时，
# 会把**合法的新增代码与说明性注释**一律判为违规——实测它拦下了 S2 的新模块，
# 报的是 `soc_line_burst_adapter.v:140: // 【为什么写操作不走缓存】S2 阶段不做 D-Cache…`
# 这种**恰恰在说"不做"**的注释。
#
# 处理办法（不是把注释改得躲开关键词，那会让审计失去意义）：
#   1. banned 列表只保留**仍不在本届范围**的功能；
#   2. 新增一条前置一致性检查：放开限制必须有**可查证的记录**（`AGENTS.md` §1.14
#      含范围变更说明）。若有人悄悄放开限制而没改规则文件，本审计会直接失败。
#
# 只扫描**源文件**：排除 PDS 构建产物（flow.log / synthesize / generate_bitstream 等）
# 与 Python 字节码缓存，否则工具自身的器件资源表（例如 PCIE 一列）会造成误报。
$banned = '\b(?:rle|ai|yolo|hdmi|pcie|ethernet|i2c|16.?channel)\b'
$include = @('*.v','*.c','*.S','*.py','*.h','*.ld','*.tcl','*.fdc','*.md','*.ps1')
$skipDir = @('generate_bitstream','synthesize','place_route','route_optimize','device_map',
             'report_timing','compile','logbackup','bak','ip','__pycache__','node_modules',
             'build','.git')

# 前置检查：放开限制必须有规则记录，否则本审计拒绝在"未经确认就放开"的仓库上通过。
# ⚠️ 判据用**含 ASCII 的串**（I-Cache / 2026-09-29），不要用纯中文字面量：
#    本脚本以 UTF-8(无 BOM) 保存，PowerShell 5.1 会用 ANSI 读脚本源码，
#    纯中文比较串会被解码弄坏而永远匹配不上（第一次就是这么失败的）。
$agents = Get-Content -LiteralPath 'AGENTS.md' -Raw -Encoding UTF8
if($agents -notmatch 'I-Cache' -or $agents -notmatch '2026-09-29'){
  throw 'SCOPE AUDIT FAIL: AGENTS.md lacks the scope-change record (I-Cache / 2026-09-29) though cache/ddr keywords were relaxed'
}
Write-Host 'SCOPE AUDIT PRECONDITION OK: AGENTS.md records the scope change (cache/burst/DDR3 now in scope)'

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
foreach($root in @('rtl','fpga/logic_analyzer','fpga/trace85','software/logic_analyzer','python')) {
  if(-not (Test-Path -LiteralPath $root)){ continue }
  foreach($file in (Get-ScopedFiles $root)){
    $scanned++
    $matches = Select-String -LiteralPath $file -Pattern $banned -CaseSensitive:$false -ErrorAction SilentlyContinue
    foreach($m in $matches){
      $violations.Add(("{0}:{1}: {2}" -f $m.Path.Replace((Get-Location).Path + '\',''), $m.LineNumber, $m.Line.Trim()))
    }
  }
}
Write-Host "SCOPE AUDIT SCANNED files=$scanned roots=rtl,fpga/logic_analyzer,fpga/trace85,software/logic_analyzer,python"
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
Write-Host 'SCOPE AUDIT PASS: 16-entry BTB + 2-bit counters present; no frozen RLE/AI/HDMI/PCIe/Ethernet/I2C/16-channel implementation found'
exit 0
