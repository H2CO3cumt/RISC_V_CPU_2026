# Windows PowerShell 5.1 会把无 BOM 的 .ps1 当 ANSI 解码；本文件含中文，必须有 BOM。
# 同样地，node 的 -e/-p 在现代 PowerShell 下会因引号转义炸掉，所以这里只调用 .js 文件。
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw 'node not found; the waveform viewer parser test needs node.' }

$html = Join-Path $repo 'python/waveform_viewer.html'
$harness = Join-Path $repo 'scripts/waveform_viewer_test.js'
# 默认目录必须是**真的存在采集产物**的那个：旧默认 release/final_submission/results/logic_analyzer
# 在本仓库里不存在，脚本会直接以"capture directory not found"退出（本轮实测）。
# 证据目录（含各模式的 .log/.vcd）才带得动 A 段"VCD 反解 vs 板子原始回包"的逐点比对。
$dir = if ($args.Count -ge 1 -and $args[0]) { $args[0] } else { 'release/evidence/logic_analyzer_board_85m' }
$dir = (Resolve-Path -LiteralPath (Join-Path $repo $dir) -ErrorAction SilentlyContinue)
if (-not $dir) { throw "capture directory not found: $dir" }

Write-Host "VIEWER $html"
Write-Host "CAPTURES $dir"
& $node $harness $html $dir.Path static counter uart spi
if ($LASTEXITCODE -ne 0) { throw "WAVEFORM VIEWER TEST FAIL (exit $LASTEXITCODE)" }
Write-Host 'WAVEFORM VIEWER PARSER TEST PASS'
