param(
  [string]$Destination = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RISC-V_CPU_2026_提交包_20261010.zip'),
  [string]$StageName = 'RISC-V_CPU_2026_提交包',
  [switch]$SkipStageClean
)
$ErrorActionPreference = 'Stop'
# ============================================================================
# 提交包打包器（2026-10-10 新增）
#
# 为什么要单独做一份：`release/final_submission`（+ 它的 zip）是**交付包**，
# 只含评委需要的东西；而比赛提交往往还要交"工程文件本身"（RTL/TB/固件/脚本/文档/
# FPGA 工程），两者不是一回事。本脚本把两者装进**一个**压缩包：
#
#   <StageName>/
#     先读我.txt          —— 包内容、当前位流哈希、怎么跑、哪些东西没放进来
#     01_交付包/          —— release/final_submission 原样（已过 audit_release_package.ps1）
#     02_工程源码/        —— 开发仓库的源码子集
#
# 明确排除（不是遗漏）：
#   release/materials/  —— 技术报告 docx/pdf 与答辩 PPT 是 2026-09-16/09-30 旧版
#                          （旧位流、四模式 80/80、深度 256、无镜像与读数），
#                          放进"最新工程文件"里会自相矛盾，用户 2026-10-10 决定不进包。
#   tmp/ .git/ release/ log/ results/ __pycache__/ 以及 fpga 各工程的综合/布局布线中间产物。
# ============================================================================
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bundleRoot = Join-Path $repo 'tmp\submission_bundle'
$stage = Join-Path $bundleRoot $StageName
$deliverySrc = Join-Path $repo 'release\final_submission'

if(-not (Test-Path -LiteralPath $deliverySrc -PathType Container)){throw "缺少交付包目录 $deliverySrc，先跑 scripts\export_final_submission.ps1"}
if(-not (Test-Path -LiteralPath (Join-Path $deliverySrc 'SHA256SUMS.txt') -PathType Leaf)){throw "交付包没有 SHA256SUMS.txt，先跑 scripts\export_final_submission.ps1"}

if((Test-Path -LiteralPath $stage) -and (-not $SkipStageClean)){Remove-Item -LiteralPath $stage -Recurse -Force}
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# 统一的递归拷贝：路径中任何一层目录名命中 $excludeDirs 就整支跳过，可再按扩展名过滤。
# 为什么不用 Copy-Item -Recurse：scripts/ 里藏着 node_modules（7796 个文件 / 320 MB），
# 整目录递归会把开发工具依赖一起塞进提交包（2026-10-10 实测踩到，包因此涨到 109 MB）。
$excludeDirs = @('node_modules','__pycache__','.git','sim','temp_projects','logbackup',
                 'compile','synthesize','place_route','device_map','.pytest_cache')
function Copy-Tree {
  param([string]$From,[string]$To,[string[]]$AllowedExt)
  Get-ChildItem -LiteralPath $From -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($From.Length).TrimStart('\')
    $parts = $rel.Split('\')
    if($parts | Where-Object { $excludeDirs -contains $_ }){ return }
    if($AllowedExt -and ($_.Extension -notin $AllowedExt)){ return }
    if($_.Extension -in @('.lock','.log')){ return }
    $dst = Join-Path $To $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
  }
}

# ---------- 1) 交付包 ----------
# 与 export/audit 用同一套排除规则（.lock/.log、sim/、temp_projects/），
# 保证 01_交付包 与"已过审计的那一份"逐文件一致，不多带开发过程垃圾。
$deliveryDst = Join-Path $stage '01_交付包'
New-Item -ItemType Directory -Force -Path $deliveryDst | Out-Null
Copy-Tree -From $deliverySrc -To $deliveryDst

# ---------- 2) 工程源码 ----------
$srcDst = Join-Path $stage '02_工程源码'
New-Item -ItemType Directory -Force -Path $srcDst | Out-Null
foreach($d in @('rtl','tb','software','python','scripts','docs','third_party')){
  Copy-Tree -From (Join-Path $repo $d) -To (Join-Path $srcDst $d)
}
foreach($f in @('AGENTS.md','AGENTS.local.md','逻辑分析仪演示.py')){
  Copy-Item -LiteralPath (Join-Path $repo $f) -Destination (Join-Path $srcDst $f) -Force
}

# FPGA 工程只收"源 + 约束 + 工程文件 + 位流 + 时序报告"，不收综合/布局布线中间产物
# （开发仓库里那些占 400+ MB，且每次重建都会变）。
$fpgaSrc = Join-Path $repo 'fpga'
$fpgaDst = Join-Path $srcDst 'fpga'
New-Item -ItemType Directory -Force -Path $fpgaDst | Out-Null
foreach($proj in (Get-ChildItem -LiteralPath $fpgaSrc -Directory | Sort-Object Name)){
  $pDst = Join-Path $fpgaDst $proj.Name
  New-Item -ItemType Directory -Force -Path $pDst | Out-Null
  foreach($sub in @('rtl','constraints','generate_bitstream','report_timing')){
    $from = Join-Path $proj.FullName $sub
    if(-not (Test-Path -LiteralPath $from)){ continue }
    Copy-Tree -From $from -To (Join-Path $pDst $sub) -AllowedExt @('.v','.fdc','.sbit','.rtr','.mem','.tcl')
  }
  Get-ChildItem -LiteralPath $proj.FullName -File |
    Where-Object { $_.Extension -in @('.pds','.tcl') } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $pDst $_.Name) -Force }
}

# ---------- 3) 先读我.txt ----------
$la85 = (Get-FileHash -LiteralPath (Join-Path $repo 'fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit') -Algorithm SHA256).Hash
$la50 = (Get-FileHash -LiteralPath (Join-Path $repo 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit') -Algorithm SHA256).Hash
$cm85 = (Get-FileHash -LiteralPath (Join-Path $repo 'fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit') -Algorithm SHA256).Hash

$readme = @'
MES50HP RISC-V 多协议逻辑分析仪 —— 提交包
打包时间：2026-10-10
===============================================================================

这个压缩包里有两部分
--------------------------------------------------------------------------
  01_交付包/    可直接提交/直接给评委的那一份（= release/final_submission）。
                内含 README.md、SHA256SUMS.txt、两个可打开的 PDS 工程、交付位流、
                上位机（含零依赖 .cmd）、CoreMark 跑分复现件、板级实测证据。
  02_工程源码/  完整开发工程：RTL、Testbench、固件、上位机、脚本、项目文档
                （docs/）、以及 fpga/ 下每个 FPGA 工程的源码/约束/工程文件/位流。

先看哪份
--------------------------------------------------------------------------
  想直接跑起来看效果        → 01_交付包\README.md（零依赖：双击 .cmd + 浏览器）
  想审阅 RTL/架构/测试      → 02_工程源码\rtl、tb、docs
  想重建位流                → 01_交付包\里两个 .pds 工程（PDS 2024.2-SP2 直接打开）
  想核对该跑多少分、哪来的  → 02_工程源码\docs\competition_scoring.md、progress.md

位流 SHA-256（当前交付版本，2026-10-10 重建）
--------------------------------------------------------------------------
  逻辑分析仪 85 MHz（主）    __LA85__
  逻辑分析仪 50 MHz（备用）  __LA50__
  CoreMark 85 MHz（跑分用）  __CM85__
  ⚠ 紫光 PDS 的 .sbit 文件头带构建时间戳：同一份 RTL 重打一次，哈希就会变。
    因此"哈希是否等于某个固定值"不能用来判断工程是否被改过；上面的哈希只对应
    本包内这一份位流。

当前状态（都是可复现的实测结果）
--------------------------------------------------------------------------
  * 逻辑分析仪：5 种模式 ×20 次 = 100/100 通过（static / counter / uart / spi /
    镜像抓取），采集深度 2048 点。
  * 镜像抓取：上位机发一句 "HELLO,RISC-V"，板级 ch7 镜像 uart0_rx，
    逻辑分析仪把这句串口波形抓下来并解码，帧错误 0。
  * 时序：All Constraints Met；慢角 setup WNS +0.588 ns、hold WHS +0.310 ns，
    估算 Fmax 89.4721 MHz；资源 LUT 4479、FF 3610、DRM 6.0。
  * CoreMark（CoreMark 专用位流，85 MHz）：Score 79.587、
    CoreMark/MHz 0.936、EEMBC 官方 CRC PASS。
  * 自动化回归：scripts\run_final_regression.ps1 → ALL AUTOMATED FINAL REGRESSION PASS。
  * 交付包审计：EXPORT PASS files=296 / MANIFEST PASS files=3881 /
    AUDIT PASS final_files=297 / DEMO PREFLIGHT PASS warnings=0。

最快的一条演示路径
--------------------------------------------------------------------------
  1) 下载 01_交付包\bitstream\mes50hp_riscv_logic_analyzer.sbit（85 MHz 主位流）
  2) 按 J8 相邻脚接 8 根线：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32
  3) 双击 01_交付包\采集四模式.cmd  —— 不需要装 Python，跑完自动打开波形目录
  4) 想看"发字符串抓波形"那一路（镜像模式），在交付包目录用自带 PowerShell 跑：
       tools\logic_analyzer_capture.ps1 -Output results -Runs 1 -Modes static,counter,uart,spi,mirror
     装了 Python 的话，也可以直接跑包根目录的 逻辑分析仪演示.py（单文件，五种模式
     + 仪器读数 + VCD/HTML/Markdown 导出 + --selftest）。

本包**没有**放进来什么（如实说明，不是遗漏）
--------------------------------------------------------------------------
  * 技术报告（docx/pdf）与答辩 PPT：仓库 release/materials 里那份是 2026-09-30 / 09-16
    的旧版（写的是旧位流、四模式 80/80、采集深度 256，且没有镜像抓取和仪器读数）。
    放进"最新工程文件"里会自相矛盾，故未收录；需要随包提交时请先更新到当前版本。
  * 演示视频：尚未录制。
  * 开发仓库的 tmp/、.git/、release/（除已摘出的交付包）、fpga 各工程的综合与布局
    布线中间产物：属于开发过程垃圾，不进提交包。
  * 三轮断电一致性测试：run01 只做了重新下载（Reset 等价），未真的断电；
    run02/run03 未做。

读数纪律（引用数字前请先读）
--------------------------------------------------------------------------
  * CoreMark 分数来自 **CoreMark 专用位流**，不是逻辑分析仪位流。
  * 板级 CPI 有窗口敏感性（同一颗位流实测过 1.494 与 1.508）：
    CPI 只能写 ≈1.50，Score/ticks 可照写。
  * 镜像模式的"位宽/推算波特率"带 −0.24% 量化误差（每比特 8 个采样点的取整），
    照实说明，不能当成测量精度。
'@

$readme = $readme.Replace('__LA85__', $la85).Replace('__LA50__', $la50).Replace('__CM85__', $cm85)
$bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText((Join-Path $stage '先读我.txt'), ($readme -replace "`r?`n", "`r`n"), $bom)

# ---------- 4) 打包 ----------
if(Test-Path -LiteralPath $Destination){ Remove-Item -LiteralPath $Destination -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
# 逐条 CreateEntryFromFile 而不是 CreateFromDirectory：.NET Framework（PS 5.1）的
# CreateFromDirectory 会把条目名写成反斜杠，Linux/macOS 的解压工具会把 "\" 当普通字符、
# 解出一堆名字里带反斜杠的文件。这里统一成 "/"，与 export_final_submission.ps1 的做法一致。
# 枚举值用整数传：PS 5.1 里 [ZipArchiveMode]::Create 这种写法会 TypeNotFound，构造参数按值绑定即可。
$createMode = 1        # ZipArchiveMode.Create
$optimal = 0           # CompressionLevel.Optimal
$archive = [System.IO.Compression.ZipFile]::Open($Destination, $createMode)
try {
  foreach($file in (Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)){
    $rel = $file.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $rel, $optimal)
  }
} finally { $archive.Dispose() }

$zipInfo = Get-Item -LiteralPath $Destination
$staged = Get-ChildItem -LiteralPath $stage -Recurse -File
$deliveryCount = (Get-ChildItem -LiteralPath $deliveryDst -Recurse -File).Count
Write-Host ("SUBMISSION BUNDLE PASS zip={0}" -f $zipInfo.FullName)
Write-Host ("  staged files={0}  delivery={1}  source={2}" -f `
  $staged.Count, $deliveryCount, ($staged.Count - $deliveryCount - 1))
Write-Host ("  zip size={0:N1} MB" -f ($zipInfo.Length/1MB))
