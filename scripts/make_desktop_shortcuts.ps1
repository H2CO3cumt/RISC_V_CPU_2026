# 在桌面建立「RISC-V_最新交付」文件夹，放齐当前交付产物的快捷方式。
#
# 为什么要有这份脚本（而不是手工在桌面上点）：
#   1. 桌面上旧的入口会静默过期——上位机、波形页、位流换了一代，快捷方式还指着上一代，
#      现场双击打开的是旧工具，而且在台上根本看不出来。这里把"入口指向哪个文件"
#      变成可复查、可重跑的一行行代码。
#   2. 交付配置会切换（50 MHz → 85 MHz PLL），切换时只需要改这份脚本里的路径并重跑，
#      不会漏掉某一个入口。
#   3. 每个入口在建立前都先 Test-Path：目标不存在就跳过并打印，绝不建立指向空气的快捷方式。
#
# 用法（Windows PowerShell 5.1 或 PowerShell 7 都可）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make_desktop_shortcuts.ps1
# 参数：
#   -Desktop <路径>   默认 $env:USERPROFILE\Desktop，便于换机器/测试
#   -RepoRoot <路径>  默认本脚本的上一级目录
#
# 本文件含中文，必须保留 UTF-8 BOM：Windows PowerShell 5.1 会把无 BOM 的 .ps1 当 ANSI 解码。
param(
  [string]$Desktop = (Join-Path $env:USERPROFILE 'Desktop'),
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$folder = Join-Path $Desktop 'RISC-V_最新交付'

if (-not (Test-Path -LiteralPath $Desktop)) { throw "桌面目录不存在：$Desktop" }
New-Item -ItemType Directory -Force -Path $folder | Out-Null

$sh = New-Object -ComObject WScript.Shell
$script:made = 0
$script:skipped = @()

function New-Lnk {
  param([string]$Name, [string]$Target, [string]$Desc = '')
  # '.' 表示仓库根自身；其余按相对路径拼。Join-Path 对 '..' 这类写法在中文路径下容易出岔，
  # 所以显式特判。
  $full = if ($Target -eq '.') { $repo } else { Join-Path $repo $Target }
  if (-not (Test-Path -LiteralPath $full)) {
    Write-Host ("  [跳过] 目标不存在: {0}  ({1})" -f $Name, $Target)
    $script:skipped += "$Name -> $Target"
    return
  }
  $item = Get-Item -LiteralPath $full
  $lnk = $sh.CreateShortcut((Join-Path $folder $Name))
  $lnk.TargetPath = $item.FullName
  # 目录型快捷方式不能设 WorkingDirectory 成目录本身之外的东西；文件则取其所在目录。
  if (-not $item.PSIsContainer) { $lnk.WorkingDirectory = $item.DirectoryName }
  if ($Desc) { $lnk.Description = $Desc }
  $lnk.Save()
  $script:made++
  Write-Host ("  {0,-46} -> {1}" -f $Name, $Target)
}

Write-Host "桌面出口目录：$folder"
Write-Host "仓库根：      $repo"
Write-Host ''
Write-Host '=== 位流（下载到板子用）==='
New-Lnk '01_主位流_逻辑分析仪_85MHzPLL.sbit.lnk' 'release\final_submission\bitstream\mes50hp_riscv_logic_analyzer.sbit' '交付主位流：85 MHz PLL，逻辑分析仪四模式 320 次采集零失败'
New-Lnk '02_备用位流_逻辑分析仪_50MHz.sbit.lnk' 'release\final_submission\bitstream\mes50hp_riscv_logic_analyzer_50m_fallback.sbit' '已验证备用位流：50 MHz'
New-Lnk '03_位流_CoreMark_85MHzPLL.sbit.lnk' 'fpga\coremark_85m\generate_bitstream\mes50hp_coremark_pll_top.sbit' 'CoreMark 计分位流（85 MHz PLL）'
New-Lnk '04_位流_CoreMark_50MHz.sbit.lnk' 'fpga\coremark\generate_bitstream\mes50hp_coremark_top.sbit' 'CoreMark 计分位流（50 MHz）'
New-Lnk '05_位流_ILA诊断_DebugCore.sbit.lnk' 'fpga\coremark_ila\generate_bitstream\mes50hp_coremark_top.sbit' '含 DebugCore，抓 CPU 内部流水线波形用'
Write-Host '=== 上位机（现场演示入口）==='
New-Lnk '06_上位机_启动逻辑分析仪.lnk' 'release\final_submission\启动逻辑分析仪.cmd' '上位机 GUI 启动入口（交付包内，自带工具副本；停在第①页八通道波形，需接板子）'
# 2026-10-28 新增：没有开发板也能看第②页（寄存器热力图）。页面顶部会显示「离线回放」徽标，
# 与"板子刚采的一枪"明确区分；两者是两条独立入口，不要混用。
New-Lnk '06b_上位机_离线演示_无板可看.lnk' 'release\final_submission\离线演示.cmd' '第②页寄存器热力图离线回放（不需要开发板，顶部有「离线回放」徽标，判据仅供参考）'
New-Lnk '07_上位机_四模式采集.lnk' 'release\final_submission\采集四模式.cmd' '零依赖采集：Windows 自带 PowerShell + .NET 串口'
New-Lnk '08_波形总览页_双击看波形.lnk' 'release\final_submission\波形预览.html' '四模式波形 + UART/SPI 解码标注，浏览器直接打开'
New-Lnk '09_上位机_GUI源码.lnk' 'python\mes50hp_validation_ui.py' '上位机 GUI 源码（仓库版，Tkinter + 实时波形面板）'
New-Lnk '10_上位机_串口采集.lnk' 'python\logic_analyzer_serial.py' '命令行串口采集 + VCD + 波形页'
New-Lnk '11_上位机_解码与VCD.lnk' 'python\logic_analyzer.py' 'Raw 解析 / UART-SPI 解码 / VCD 导出'
New-Lnk '12_波形查看器模板.lnk' 'python\waveform_viewer.html' '页面模板（采集脚本与 Python 上位机共用同一个）'
New-Lnk '13_上位机使用说明.lnk' 'release\final_submission\逻辑分析仪使用说明.md' '接线 / 操作顺序 / 常见失败'
Write-Host '=== FPGA 工程与证据 ==='
New-Lnk '14_FPGA工程_PDS打开.lnk' 'release\final_submission\MES50HP_RISCV_Logic_Analyzer.pds' 'PDS 工程：RTL / 顶层 / 约束 / 时序'
New-Lnk '15_板级实测波形_85MHz.lnk' 'release\evidence\logic_analyzer_board_85m\波形预览.html' '交付位流的板级实测波形页'
New-Lnk '16_ILA波形与证据.lnk' 'release\evidence\ila_coremark' '512 拍 CoreMark 流水线波形（IPC 0.635 / CPI 1.575）'
Write-Host '=== 交付包与材料 ==='
New-Lnk '17_最终交付包_文件夹.lnk' 'release\final_submission' '与审计通过的交付包内容一致'
New-Lnk '18_最终交付包_zip.lnk' 'release\MES50HP_RISCV_Logic_Analyzer_Final.zip' '可分发的 zip'
New-Lnk '19_技术报告PDF.lnk' 'release\materials\technical_report.pdf' '技术报告（以 claims_map.md 的数字为准）'
New-Lnk '20_答辩PPT.lnk' 'release\materials\defense_presentation.pptx' '答辩演示稿'
New-Lnk '21_现场演示Runbook.lnk' 'docs\demo_runbook.md' '分镜 + 命令 + 预期输出'
New-Lnk '22_性能与CPI分析.lnk' 'docs\coremark_cpi_analysis.md' 'CPI 归因与 Score 提升记录'
New-Lnk '23_项目仓库.lnk' '.' '完整源码仓库（权威开发状态）'

# 交付包目录的内容会随导出更新，但快捷方式指向的是"创建时存在的那个文件"；
# 只要路径不变就无需重建。位流/材料换了名字才需要重跑本脚本。
Write-Host ''
Write-Host "建立 $script:made 个快捷方式，跳过 $($script:skipped.Count) 个。"
if ($script:skipped.Count) {
  Write-Host '跳过清单（目标不存在，先确认产物路径再重跑）：'
  $script:skipped | ForEach-Object { Write-Host "  $_" }
}
Write-Host 'DESKTOP SHORTCUTS READY'
