param(
  [string]$Port = 'COM11',
  [ValidateSet('cm50','cm80','cm85','cm85r','cm90','cmim','cmim85')][string]$Config = 'cm85'
)
# **板级 CoreMark 跑分**：下载对应 CoreMark 位流 -> 收发串口跑分 -> 打印分数。
#
# 为什么需要这个包装（而不是直接双击 run_coremark_board.ps1）：
#   1) run_coremark_board.ps1 会把结果**无条件写进** release/evidence/coremark_board.json，
#      那是登记在 claims_map.md 里的**规范证据**（50 MHz 点）。随手跑一次就把它覆盖掉，
#      会让材料与证据对不上。本脚本先备份、跑完把结果另存为带日期/频点的文件、再还原规范文件。
#   2) 跑分要先下载对应的 CoreMark 位流，中间还要发串口 'R' 启动，两步分开容易漏。
#
# 跑分口径（务必看 release/evidence/fmax_ceiling/README.md）：
#   - CoreMark 分数来自 **CoreMark 专用位流**，不是交付的逻辑分析仪位流；
#   - `run_coremark_board.ps1` 打印的 `clock_hz` 恒为 50000000，**跑 85/90 MHz 时它的
#     `seconds` 是错的**，真实耗时 = ticks / 实际时钟；
#   - 板级 CPI 有窗口敏感性（≈1.50），不要按四位有效数字引用。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ps51="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# 各频点的真实时钟与说明
$freq = @{
  cm50 = @{ Hz = 50000000; Label = '50 MHz'; Iter = 1000 }
  cm80 = @{ Hz = 80000000; Label = '80 MHz (PLL)'; Iter = 2500 }
  cm85 = @{ Hz = 85000000; Label = '85 MHz (PLL, 交付时钟)'; Iter = 2500 }
  # cm85r = 与 cmim85 **完全同源** 的 RV32I 对照点（用当前 RTL 重建）。
  # 归档的 cm85 是 09-30 的旧 RTL（3657 LUT、无乘法器），拿它算 CoreMark/LUT 属于跨修订比较；
  # 这一颗与 cmim85 同 RTL、同频率、同资源（4198 LUT / 3361 FF / WNS 都是 +0.250 ns），差别只有 -march。
  # 迭代 2500：rv32i 每迭代约 1,068,007 拍，4000 次要 50.3 s，而计数器低 32 位在 85 MHz 下 50.53 s 就绕回。
  cm85r = @{ Hz = 85000000; Label = '85 MHz (RV32I, 当前 RTL 同源对照点)'; Iter = 2500 }
  cm90 = @{ Hz = 90000000; Label = '90 MHz (PLL, CPU 板级上界)'; Iter = 2500 }
  # cmim = RV32IM（M 扩展）50 MHz 配置：与 cm50 同一份 RTL、同一份程序，只换 -march。
  # 迭代次数 2000 而不是 1000：RV32IM 下每迭代周期数约减半，1000 次迭代只有约 10 s，
  # 正好卡在赛题"运行时间不低于 10 秒"的红线上，2000 次留足余量。
  cmim = @{ Hz = 50000000; Label = '50 MHz (RV32IM, M 扩展)'; Iter = 2000 }
  # cmim85 = RV32IM + 交付时钟 85 MHz：与 cm85（rv32i，Score 79.587）同频同工程，
  # 只把程序镜像换成 -march=rv32im。迭代 4000 而不是 2000：85 MHz 下每迭代约 439,975 拍，
  # 2000 次只有约 10.35 s（正好压在"不低于 10 秒"红线上），4000 次约 20.7 s。
  cmim85 = @{ Hz = 85000000; Label = '85 MHz (RV32IM, M 扩展 + 交付时钟)'; Iter = 4000 }
}
$f = $freq[$Config]

Write-Host ''
Write-Host '=================================================='
Write-Host ("  板级 CoreMark 跑分   配置=$Config   频率=" + $f.Label)
Write-Host '=================================================='
Write-Host ''

# ---- 1) 保护规范证据 ----
$ev = Join-Path $repo 'release/evidence'
$canonJson = Join-Path $ev 'coremark_board.json'
$canonLog  = Join-Path $ev 'coremark_uart.log'
$backup = Join-Path $repo 'tmp/coremark_canonical_backup'
New-Item -ItemType Directory -Force -Path $backup | Out-Null
if(Test-Path $canonJson){ Copy-Item $canonJson (Join-Path $backup 'coremark_board.json') -Force }
if(Test-Path $canonLog){  Copy-Item $canonLog  (Join-Path $backup 'coremark_uart.log')   -Force }

# ---- 2) 下载位流 ----
Write-Host "[1/3] 下载 CoreMark 位流 $Config ..."
& $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts/program_board.ps1') -Config $Config
if($LASTEXITCODE -ne 0){ throw "位流下载失败（$Config）。板子接好了吗？" }
Start-Sleep -Seconds 2

# ---- 3) 跑分（结果直接写进带时间戳的文件，规范证据一次都不碰）----
#
# [2026-10-14 改] 原来靠"先备份规范文件、跑完再还原"来保护 release/evidence/coremark_board.json，
# 但那只在这个包装脚本被使用时才成立：直接调 run_coremark_board.ps1 仍会覆盖它。
# 现在 run_coremark_board.ps1 支持 -OutputFile/-SummaryFile，这里**从一开始就把结果
# 写到带时间戳的名字上**，规范证据根本不会被打开。备份仍保留，作为额外的兜底。
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dstName = "coremark_board_${Config}_$stamp"
$dstJson = Join-Path $ev "$dstName.json"
$dstLog  = Join-Path $ev "coremark_uart_${Config}_$stamp.log"
Write-Host ''
Write-Host "[2/3] 发送串口 'R' 启动并采集（约 30-60 秒）..."
& $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts/run_coremark_board.ps1') `
  -Port $Port -TimeoutSeconds 180 -ClockHz $f.Hz -OutputFile $dstLog -SummaryFile $dstJson
if($LASTEXITCODE -ne 0){ throw '跑分失败，见上面的串口输出' }

# ---- 4) 核对规范证据未被改动 ----
Write-Host ''
Write-Host '[3/3] 核对规范证据 ...'
if((Test-Path (Join-Path $backup 'coremark_board.json')) -and
   (Get-FileHash (Join-Path $backup 'coremark_board.json') -Algorithm SHA256).Hash -ne
   (Get-FileHash $canonJson -Algorithm SHA256).Hash){
  throw '规范证据 coremark_board.json 被改动了，请检查'
}
Write-Host '  规范证据 coremark_board.json 未被改动'

$j = Get-Content -Raw (Join-Path $ev "$dstName.json") | ConvertFrom-Json
$secs = [math]::Round($j.ticks / $f.Hz, 3)
Write-Host ''
Write-Host '==================== 跑分结果 ===================='
Write-Host ("  配置            : $Config  (" + $f.Label + ")")
Write-Host ("  迭代次数        : " + $j.iterations)
Write-Host ("  ticks           : " + $j.ticks)
Write-Host ("  真实耗时        : $secs s   ( = ticks / " + $f.Hz + " )")
Write-Host ("  CoreMark 分数   : " + ($j.score_x1000 / 1000))
Write-Host ("  CoreMark/MHz    : " + ($j.coremark_per_mhz_x1000 / 1000))
Write-Host ("  官方 CRC        : " + $j.validation)
Write-Host ("  CPI（窗口敏感） : ≈" + [math]::Round($j.cpi_x1000 / 1000, 2))
Write-Host '=================================================='
Write-Host ("  本次结果另存为  : release/evidence/$dstName.json")
Write-Host  '  规范证据 coremark_board.json 已还原（未被覆盖）'
Write-Host ''
Write-Host '  注意：run_coremark_board.ps1 打印的 seconds 一律按 50 MHz 算，'
Write-Host  '        跑 85/90 MHz 时它是错的；上表"真实耗时"才是对的。'
Write-Host ''
