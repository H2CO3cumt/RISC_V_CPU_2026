param(
  [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }),
  # 正常执行 1~2 秒；给足余量，超时说明 TB 里某个 wait 死等（2026-10-14 曾经
  # 因此让整轮最终回归静默卡死 24 分钟以上，且 vvp 的 stdout 块缓冲不刷新，
  # 外层看不到任何线索）。
  [int]$TimeoutSeconds = 120
)
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/logic_analyzer|Out-Null
$iverilog = Join-Path (Resolve-Path $IcarusRoot).Path 'bin/iverilog.exe'
$vvp = Join-Path (Resolve-Path $IcarusRoot).Path 'bin/vvp.exe'
$exe = 'tmp/logic_analyzer/tb'
$log = 'tmp/logic_analyzer/tb_output.log'
& $iverilog -g2012 -s tb_logic_analyzer -o $exe rtl/capture_engine.v rtl/logic_analyzer_pattern_gen.v rtl/logic_analyzer_mmio.v tb/tb_logic_analyzer.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
# 输出重定向到文件：TTY 之外 vvp 的 stdout 是块缓冲，进程不退就一个字都看不到；
# 重定向之后即使被 Kill，也能拿到"跑到哪一步"的完整日志。
Remove-Item $log -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $vvp -ArgumentList $exe -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError 'tmp/logic_analyzer/tb_error.log'
if(-not $p.WaitForExit($TimeoutSeconds*1000)){
  try { $p.Kill() } catch { }
  $p.WaitForExit()
  Write-Host "LOGIC ANALYZER TB TIMEOUT after ${TimeoutSeconds}s (suspected dead wait; see $log)"
  Get-Content $log -ErrorAction SilentlyContinue
  exit 124
}
Get-Content $log -ErrorAction SilentlyContinue
Get-Content 'tmp/logic_analyzer/tb_error.log' -ErrorAction SilentlyContinue
exit $p.ExitCode
