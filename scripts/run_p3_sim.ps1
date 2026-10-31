param(
  [string]$Suite = 'all',
  [string]$Verbose_ = 'full'
)
$ErrorActionPreference='Stop'
# P3（S2/S3/S4）新增模块的仿真入口。
#
# 参数为什么都是字符串而不是 [switch]（踩过的坑）：
#   实测 PowerShell 5.1 在本文件上对 [switch] 参数做位置绑定会报
#   "Cannot convert value System.String to SwitchParameter" 或
#   "variable Suite with value all False would no longer be valid"
#   （即使显式传 -Suite all 也一样）。改成字符串 + 显式比较即可。
#   另外 `param()` 必须能在文件开头被解析到，长注释块放在它前面会让
#   参数绑定行为更不可预期，所以这里把 param 放在最前面。
#
# 用法：
#   powershell -File scripts\run_p3_sim.ps1                   # 全部 s2/s3/s4
#   powershell -File scripts\run_p3_sim.ps1 -Suite s3        # 只跑 S3
#   powershell -File scripts\run_p3_sim.ps1 -Verbose_ quiet   # 只打摘要
#
# 设计意图：P3 的 Cache/突发模块**全部位于 Core 外部**，与 Core 无关，
# 因此先用"独立 TB + 独立入口"验证功能与量化，再谈接进流水线测 CoreMark。
# 这样一旦 Cache 出问题，能一眼看出是模块本身还是集成问题。
#
# 为什么固定用 D:\Tools\iverilog-v12：
#   oss-cad-suite 的 Icarus 14 无法 elaborate `rtl/pipeline_cpu.v`
#   （报 "Unable to bind wire/reg/memory ... declaration after use"），
#   所以本工程统一用 Icarus 12。P3 的新模块虽然不依赖它，但入口保持一致，
#   将来把 TB 扩到流水线级时不用换工具。

$quiet = ($Verbose_ -eq 'quiet')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# iverilog 位置：优先环境变量 IVERILOG_ROOT，其次按已知安装点探测。
# 默认 D:\Tools\iverilog-v12：oss-cad-suite 的 Icarus 14 elaborate 不了
# `rtl/pipeline_cpu.v`，本工程统一用 12；P3 模块虽不依赖它，
# 但入口保持一致，将来把 TB 扩到流水线级时不用换工具。
$iver=$null
foreach($c in @($env:IVERILOG_ROOT,'D:\Tools\iverilog-v12','D:\Tools\iverilog','C:\iverilog')){
  if($c -and (Test-Path -LiteralPath (Join-Path $c 'bin\iverilog.exe'))){ $iver=Join-Path $c 'bin'; break }
}
if(-not $iver){ throw 'iverilog 未找到（试过 IVERILOG_ROOT 与 D:\Tools\iverilog-v12 等已知路径）' }
$iv=Join-Path $iver 'iverilog.exe'
$vp=Join-Path $iver 'vvp.exe'
Write-Host "IVERILOG $iver"

$work=Join-Path $repo 'tmp/p3'
New-Item -ItemType Directory -Force $work | Out-Null

# 名称 -> (顶层模块, 源文件列表)
$tests=[ordered]@{
  s2 = @{ Top='tb_soc_line_burst_adapter'; Src=@('rtl/soc_line_burst_adapter.v','tb/tb_soc_line_burst_adapter.v') }
  s3 = @{ Top='tb_soc_icache_2way';        Src=@('rtl/soc_icache_2way.v','tb/tb_soc_icache_2way.v') }
  s4 = @{ Top='tb_soc_dcache_2way';        Src=@('rtl/soc_dcache_2way.v','tb/tb_soc_dcache_2way.v') }
  # 集成适配器的独立 trace TB。CoreMark 集成尚未通过，所以它**允许失败**，
  # 但必须能被单独跑出来看见（`-Suite s4i`），避免"失败被藏起来"。
  s4i= @{ Top='tb_dcache_adapter_solo';    Src=@('rtl/soc_dcache_2way.v','tb/dcache_coremark_adapter.v','tb/tb_dcache_adapter_solo.v') }
  # 复刻 Core 真实握手节奏的 TB：证明"Cache 不能拒收请求"这个根因。
  # 目前**失败**（red），必须能被单独跑出来看见（`-Suite s4d`）。
  s4d= @{ Top='tb_dcache_core_drive';      Src=@('rtl/soc_dcache_2way.v','tb/dcache_coremark_adapter.v','tb/tb_dcache_core_drive.v') }
}
# `all` 只跑**已通过**的套件；s4i / s4d 需要显式指定
if($Suite -eq 'all'){ $tests.Remove('s4i'); $tests.Remove('s4d') }
if($Suite -ne 'all'){ $tests=@{ $Suite=$tests[$Suite] } }

$failed=@()
foreach($name in $tests.Keys){
  $t=$tests[$name]
  $missing=@($t.Src | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repo $_)) })
  if($missing.Count -ne 0){
    Write-Host ("SKIP {0}: 源文件尚未创建 -> {1}" -f $name, ($missing -join ', '))
    continue
  }
  $out=Join-Path $work "$name.vvp"
  $srcs=@($t.Src | ForEach-Object { Join-Path $repo $_ })
  # 【PS 5.1 纪律】本脚本的**字符串字面量一律用 ASCII**，中文只允许出现在注释里。
  # 原因（实测踩过两次）：BOM-less .ps1 会被 PS 5.1 按 ANSI/GBK 解码，UTF-8 的中文
  # 若紧挨着引号（如全角右括号 `）` 后面跟 `"`），GBK 会把那个引号当成双字节字符的
  # 后半个字节吃掉，于是报出"missing terminator"，而且行号还被整体偏移，极难定位。
  # 另外任何用 edit 工具改过本文件后，必须重跑 scripts\ensure_ps1_bom.ps1（edit 会去掉 BOM）。
  if($srcs.Count -eq 0){ throw ("P3 {0}: empty source list (config error)" -f $name) }
  Write-Host ("IVERILOG -s {0} <- {1}" -f $t.Top, ($t.Src -join ' '))
  Push-Location $repo
  try{
    $co=& $iv -g2005 -o $out -s $t.Top @srcs 2>&1
    if($LASTEXITCODE -ne 0){
      Write-Host ("COMPILE FAIL {0}" -f $name); $co | ForEach-Object { Write-Host "  $_" }
      $failed+=$name; continue
    }
    $log=& $vp $out 2>&1
    $code=$LASTEXITCODE
  } finally { Pop-Location }

  $log | Set-Content -LiteralPath (Join-Path $work "$name.log") -Encoding UTF8
  $pass=@($log | Select-String -Pattern '^TEST .* PASS').Count
  $fail=@($log | Select-String -Pattern '^TEST .* FAIL').Count
  $all =$log | Select-String -Pattern 'ALL S[234] .* TEST PASS'
  if($Quiet){ $log | Select-String -Pattern 'MEASUREMENT|reduction|ALL S|FATAL' | ForEach-Object { Write-Host "  $_" } }
  else { $log | ForEach-Object { Write-Host $_ } }

  if($code -ne 0 -or -not $all -or $fail -ne 0){
    Write-Host ("P3 {0}: FAIL (TEST PASS={1} FAIL={2} exit={3})" -f $name.ToUpper(), $pass, $fail, $code)
    $failed+=$name
  } else {
    Write-Host ("P3 {0}: PASS (TEST PASS={1})" -f $name.ToUpper(), $pass)
  }
  Write-Host ("  日志: tmp/p3/{0}.log" -f $name)
}

if($failed.Count -ne 0){ throw ("P3 SIM FAILED: " + ($failed -join ', ')) }
Write-Host 'P3 SIM ALL PASS'
