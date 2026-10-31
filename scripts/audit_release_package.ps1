$ErrorActionPreference='Stop'
# PS 5.1 的 .NET Framework 没有 [System.IO.Path]::GetRelativePath（那是 .NET Core 才有的 API），
# 本机只有 Windows PowerShell 5.1，直接调用会抛 MethodNotFound。这里用 Uri 求相对路径，
# 语义与 GetRelativePath 一致（同为绝对路径时），并把分隔符统一成 / 以便清单跨平台可比。
function Get-RelativePathCompat {
  param([string]$Base, [string]$Path)
  $baseFull = [System.IO.Path]::GetFullPath($Base)
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  $baseUri = New-Object System.Uri (($baseFull.TrimEnd('\') + '\'))
  $pathUri = New-Object System.Uri ($pathFull)
  $rel = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
  return $rel.Replace('\','/')
}
$root='release/final_submission'

# ---------------------------------------------------------------------------
# 约束文件名不再写死，而是从交付工程自己引用的路径推导，并要求 build_pds.tcl 引用同一个文件。
# 历史 Bug（2026-10-03 修复）：export_final_submission.ps1 把 85 MHz 约束写成了 50 MHz 旧名
# mes50hp_logic_analyzer.fdc，而 .pds / build_pds.tcl 引用 mes50hp_logic_analyzer_85m.fdc；
# 旧审计恰好校验的是那个旧名，于是"审计 PASS、PDS 一打开就 C: Flow-2003 + 综合 E: Flow-0002"。
# 现在三处（.pds、build_pds.tcl、实际文件）必须同名同存，任何一处不一致都会让审计失败。
# ---------------------------------------------------------------------------
$pdsFile="$root/MES50HP_RISCV_Logic_Analyzer.pds"
$pdsText=Get-Content -Raw -Encoding UTF8 -LiteralPath $pdsFile
# 注意 @(...)：只有一条匹配时管道结果是**标量字符串**，直接写 $refs[0] 会取到第一个字符
# （本行曾因此得到 $fdcName='c'，报出 "missing .../constraints/c"）。
$fdcRefs=@([regex]::Matches($pdsText,'\(_file "(constraints/[^"]+\.fdc)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if($fdcRefs.Count -ne 1){throw "RELEASE AUDIT FAIL $pdsFile must reference exactly one .fdc, found: $($fdcRefs -join ', ')"}
$fdcRel=$fdcRefs[0]
$recipeRefs=@([regex]::Matches((Get-Content -Raw -Encoding UTF8 -LiteralPath "$root/build_pds.tcl"),'add_constraint\s+-fdc\s+(\S+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if($recipeRefs.Count -ne 1 -or $recipeRefs[0] -ne $fdcRel){
  throw "RELEASE AUDIT FAIL build_pds.tcl add_constraint ($($recipeRefs -join ', ')) does not match .pds constraint ($fdcRel)"
}

$required=@(
  "$root/README.md",
  "$root/SHA256SUMS.txt",
  "$root/MES50HP_RISCV_Logic_Analyzer.pds",
  "$root/启动逻辑分析仪.cmd",
  # 零依赖路径（2026-10-03）：采集用 Windows 自带 PowerShell，看波形用浏览器，
  # 这两条都不能缺，否则"评委机器上什么都没装"就打不开。
  "$root/采集四模式.cmd",
  # 跑分零依赖路径（2026-10-03）：与采集同一条思路——双击 .cmd + Windows 自带 PowerShell，
  # 不再要求评委机装 Python + pyserial。
  "$root/跑分.cmd",
  "$root/tools/coremark_score.ps1",
  "$root/波形预览.html",
  "$root/tools/logic_analyzer_capture.ps1",
  "$root/tools/waveform_viewer.html",
  "$root/tools/waveform_panel.py",
  "$root/tools/mes50hp_validation_ui.py",
  # 单文件上位机（2026-10-10 新增）：功能最全的一条路径（含镜像抓取 + 仪器读数），
  # 用户明确要求"一个 py 文件展示所有功能"，缺了它这轮的应用演示就没法在评委机上复现。
  # 注意 `启动逻辑分析仪.cmd` 仍指向 tools\pyUI.py，这是用户选定的启动路径，两者并存。
  "$root/逻辑分析仪演示.py",
  "$root/逻辑分析仪使用说明.md",
  # 提交级数据流（trace）上位机与离线回放样本（2026-10-28 新增）：
  # 第 ② 页一按「采集」就 import trace_view / trace_board，缺了它们
  # 界面还在、功能全废（最难解释的一种交付件）；样本缺了则没开发板的机器看不到热力图。
  # 这条曾经漏过：导出脚本 2026-10-22 就加了三份 trace 文件的拷贝，但包一直没重新导出，
  # 于是审计也没机会发现包里没有它们——把要求写进审计，才能在下一次重导时真的挡住。
  "$root/tools/trace_view.py",
  "$root/tools/trace_board.py",
  "$root/tools/samples/trace_hello_rv.log",
  "$root/离线演示.cmd",
  "$root/build_pds.tcl",
  # 跑分 85 MHz 工程（2026-10-03 新增）：与逻辑分析仪工程同级的可打开/可重建工程
  "$root/MES50HP_CoreMark_85M.pds",
  "$root/build_coremark_pds.tcl",
  "$root/rtl/mes50hp_coremark_pll_top.v",
  "$root/rtl/coremark_program_memory.v",
  "$root/rtl/coremark_imem.mem",
  "$root/constraints/mes50hp_coremark_85m.fdc",
  "$root/bitstream/mes50hp_riscv_logic_analyzer.sbit",
  "$root/reports/timing.rtr",
  # 必须与 MES50HP_RISCV_Logic_Analyzer.pds / build_pds.tcl 里引用的约束文件名一致。
  # 历史 Bug（2026-10-03 修复）：此处曾校验 50 MHz 旧名 mes50hp_logic_analyzer.fdc，
  # 于是"文件在、但名字不对"也能通过审计，而 PDS 综合照旧失败。
  "$root/$fdcRel",
  "$root/rtl/pipeline_cpu.v",
  "$root/rtl/mdu.v",
  "$root/rtl/branch_predictor.v",
  "$root/rtl/csr_unit.v",
"$root/rtl/timer_mmio.v",
  "$root/rtl/mes50hp_logic_analyzer_top.v",
  "$root/rtl/program_memory.v",
  "$root/rtl/program.mem",
  "$root/firmware/logic_analyzer_firmware.c",
  "$root/firmware/Makefile",
  "$root/evidence/logic_analyzer_board_final/static/summary.json",
  "$root/evidence/logic_analyzer_board_final/counter/summary.json",
  "$root/evidence/logic_analyzer_board_final/uart/summary.json",
  "$root/evidence/logic_analyzer_board_final/spi/summary.json",
  'release/MES50HP_RISCV_Logic_Analyzer_Final.zip',
  'release/artifacts/mes50hp_riscv_logic_analyzer.sbit',
  'release/artifacts/mes50hp_riscv_logic_analyzer_timing.rtr',
  'release/artifacts/logic_analyzer_firmware.mem',
  'release/build_manifest.txt',
  'release/SHA256SUMS.txt'
)

foreach($path in $required){
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "RELEASE AUDIT FAIL missing $path"}
  if((Get-Item -LiteralPath $path).Length -eq 0){throw "RELEASE AUDIT FAIL empty $path"}
}

# 位流哈希不再写死：以“唯一真实来源”工程的最新构建产物为准，
# 要求 final_submission 与 release/artifacts 两处副本都与它一致。
# 写死哈希会让审计在任何一次重新综合后必然失败（旧实现即是如此）。
# 【2026-09-30 交付配置切换】交付主位流由 50 MHz 版改为 **85 MHz PLL 版**，
# 因此真实来源从 fpga/logic_analyzer 改为 fpga/logic_analyzer_85m。
# 50 MHz 版工程保留，其位流作为已验证备用随包提供（下方单独校验其存在性）。
$sourceBitstream='fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'
if(-not (Test-Path -LiteralPath $sourceBitstream -PathType Leaf)){throw "RELEASE AUDIT FAIL missing $sourceBitstream"}
$expected=(Get-FileHash -LiteralPath $sourceBitstream -Algorithm SHA256).Hash
foreach($path in @(
  "$root/bitstream/mes50hp_riscv_logic_analyzer.sbit",
  'release/artifacts/mes50hp_riscv_logic_analyzer.sbit'
)){
  $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  if($actual -ne $expected){throw "RELEASE AUDIT FAIL hash $path expected=$expected (from $sourceBitstream) actual=$actual"}
}
# 备用位流（50 MHz 版）必须随包提供且与 50 MHz 工程一致
$fbSrc='fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit'
$fbDst="$root/bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit"
if(-not (Test-Path -LiteralPath $fbDst -PathType Leaf)){throw "RELEASE AUDIT FAIL missing fallback bitstream $fbDst"}
if((Get-FileHash -LiteralPath $fbDst -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $fbSrc -Algorithm SHA256).Hash){
  throw "RELEASE AUDIT FAIL fallback bitstream hash mismatch vs $fbSrc"
}

# CoreMark 跑分复现件（2026-09-30 新增）：交付包必须能让评委**自己跑出分数**。
# 位流、官方源码、固件工程、存储器镜像、上位机与金标准输出都在包内，逐个校验；
# 镜像还要与跑分工程里的那份逐字节一致，证明"包里给的镜像 = 位流里烧进去的镜像"。
$cmSrc='fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit'
$cmDst="$root/bitstream/mes50hp_coremark_85m.sbit"
if(-not (Test-Path -LiteralPath $cmSrc -PathType Leaf)){throw "RELEASE AUDIT FAIL missing $cmSrc"}
if(-not (Test-Path -LiteralPath $cmDst -PathType Leaf)){throw "RELEASE AUDIT FAIL missing $cmDst"}
if((Get-FileHash -LiteralPath $cmDst -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $cmSrc -Algorithm SHA256).Hash){
  throw "RELEASE AUDIT FAIL CoreMark bitstream hash mismatch vs $cmSrc"
}
foreach($rel in @(
  'coremark/跑分复现说明.md',
  'coremark/expected/coremark_expected_output.txt',
  'coremark/software/coremark/Makefile',
  'coremark/software/coremark/core_portme.c',
  'coremark/software/coremark/start.S',
  'coremark/third_party/coremark/core_main.c',
  'coremark/third_party/coremark/coremark.h',
  'coremark/third_party/coremark/LICENSE.md',
  'coremark/images/coremark_imem.mem',
  'coremark/images/coremark_drom.mem',
  'coremark/images/coremark_ram.mem',
  'coremark/rebuild/pds_recipe.tcl',
  'coremark/rebuild/pll_85m.v',
  'coremark/rebuild/mes50hp_coremark_pll_top.v',
  'coremark/rebuild/mes50hp_coremark_85m.fdc',
  'tools/coremark_serial.py'
)){
  $f=Join-Path $root $rel
  if(-not (Test-Path -LiteralPath $f -PathType Leaf)){throw "RELEASE AUDIT FAIL missing CoreMark reproduction file: $rel"}
  if((Get-Item -LiteralPath $f).Length -eq 0){throw "RELEASE AUDIT FAIL empty CoreMark reproduction file: $rel"}
}
foreach($m in @('coremark_imem.mem','coremark_drom.mem','coremark_ram.mem')){
  $a="$root/coremark/images/$m"; $b="fpga/coremark_85m/rtl/$m"
  if((Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash){
    throw "RELEASE AUDIT FAIL CoreMark image mismatch: $m"
  }
}

$manifest=@{}
# 必须按 UTF-8 读：清单里有中文文件名（启动逻辑分析仪.cmd / 逻辑分析仪使用说明.md），
# 而 Windows PowerShell 5.1 的 Get-Content 默认按 ANSI 解码，会把它们变成乱码，
# 于是"文件明明在清单里"却被判成 `final file not hashed`。
foreach($line in Get-Content -LiteralPath "$root/SHA256SUMS.txt" -Encoding UTF8){
  if($line -notmatch '^([0-9A-F]{64})  (.+)$'){throw "RELEASE AUDIT FAIL malformed final manifest line: $line"}
  $manifest[$Matches[2]]=$Matches[1]
}
# 交付清单校验排除 PDS/ModelSim 联合仿真的中间产物目录 $root/sim/：
# 在 PDS 里对交付工程点一次「Behavior Simulation」就会在 sim/behave 下生成
# modelsim.ini、run_behav*.tcl/bat、work 库和 vsim.wlf，这些是每次运行都会变的
# 构建垃圾，与 .lock/.log 同类，不应进入哈希清单。交付物本体（rtl/、constraints/、
# tb/、bitstream/ 等）仍然逐个哈希校验。
$distributionFiles=Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
  $_.Extension -notin @('.lock','.log') -and $_.Name -ne 'multiseed_summary.csv' -and
  $_.FullName -notmatch '[\\/](sim|temp_projects)[\\/]'
}
foreach($file in $distributionFiles){
  $relative=Get-RelativePathCompat -Base (Resolve-Path $root).Path -Path $file.FullName.Replace('\','/')
  if($relative -eq 'SHA256SUMS.txt'){continue}
  if(-not $manifest.ContainsKey($relative)){throw "RELEASE AUDIT FAIL final file not hashed $relative"}
  if((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $manifest[$relative]){throw "RELEASE AUDIT FAIL stale final hash $relative"}
}

$unexpected=Get-ChildItem -LiteralPath 'release/artifacts' -File | Where-Object {$_.Name -notin @(
  'mes50hp_riscv_logic_analyzer.sbit',
  'mes50hp_riscv_logic_analyzer_timing.rtr',
  'logic_analyzer_firmware.mem'
)}
if($unexpected){throw "RELEASE AUDIT FAIL legacy artifacts remain: $($unexpected.Name -join ', ')"}

# ---------------------------------------------------------------------------
# 【2026-10-03 新增】每个交付工程（.pds）引用的**设计源文件 / 约束文件 / 仿真源**都必须真实存在。
# 这条检查是被真实事故逼出来的：交付包曾缺少 .pds 引用的约束文件，于是
# "审计 PASS，但 PDS 一打开就 C: Flow-2003、综合直接 E: Flow-0002 失败"。
# 只校验输入类路径（rtl/ constraints/ tb/ 或 ../../），跳过 compile/ synthesize/ device_map/
# place_route/ report_timing/ generate_bitstream/ ——那些是构建产物，本来就该在包里不存在。
# ---------------------------------------------------------------------------
$pdsChecked=0
foreach($pdsFile in (Get-ChildItem -LiteralPath $root -Filter '*.pds' -File | Sort-Object Name)){
  $text=Get-Content -Raw -Encoding UTF8 -LiteralPath $pdsFile.FullName
  $refs=@([regex]::Matches($text,'\(_file "([^"]+)"') | ForEach-Object { $_.Groups[1].Value } |
          Where-Object { $_ -match '^(rtl/|constraints/|tb/|\.\./)' } | Sort-Object -Unique)
  if($refs.Count -eq 0){throw "RELEASE AUDIT FAIL $($pdsFile.Name) references no design sources"}
  foreach($rel in $refs){
    if(-not (Test-Path -LiteralPath (Join-Path $root $rel))){
      throw "RELEASE AUDIT FAIL $($pdsFile.Name) references missing file: $rel"
    }
  }
  Write-Host "PDS INPUTS OK  $($pdsFile.Name)  files=$($refs.Count)"
  $pdsChecked++
}
if($pdsChecked -lt 2){throw "RELEASE AUDIT FAIL expected at least 2 delivered PDS projects, found $pdsChecked"}

# 命名审计：交付包里不得再出现开发期的 taskNN 命名（或生成器痕迹）。
# 优先用 ripgrep；若本机 PATH 上没有 rg，则退回 PowerShell 自带实现，
# 保证审计在只装了 PDS 的机器上也能跑（原实现直接调用 rg，缺失时会中断审计）。
$namingTargets=@("$root/README.md","$root/rtl","$root/firmware","$root/constraints","$root/build_pds.tcl")
$naming=$null
if(Get-Command rg -ErrorAction SilentlyContinue){
  $naming=rg -n -i 'task[0-9]+|chatgpt|generated by.*task' @namingTargets 2>$null
  if($LASTEXITCODE -notin @(0,1)){throw 'RELEASE AUDIT FAIL naming audit command failed'}
} else {
  $naming=@()
  # 同样必须按 UTF-8 读，理由见上方清单解析处的注释。
  foreach($t in $namingTargets){
    if(Test-Path -LiteralPath $t -PathType Leaf){
      $naming+=Select-String -LiteralPath $t -Pattern 'task[0-9]+|chatgpt|generated by.*task' -AllMatches -Encoding UTF8 -ErrorAction SilentlyContinue
    } else {
      $naming+=Get-ChildItem -LiteralPath $t -Recurse -File -ErrorAction SilentlyContinue |
        Select-String -Pattern 'task[0-9]+|chatgpt|generated by.*task' -Encoding UTF8 -ErrorAction SilentlyContinue
    }
  }
}
if($naming){throw "RELEASE AUDIT FAIL development naming leaked into final submission:`n$($naming -join "`n")"}

Write-Host "RELEASE PACKAGE AUDIT PASS final_files=$($distributionFiles.Count) artifacts=3"
