param([string]$TargetDirectoryName='final_submission')
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
# 交付包内的文本文件一律按"UTF-8 无 BOM"写出，Windows PowerShell 5.1 与 PowerShell 7 行为一致。
# 原因（2026-10-03 实测）：PS 5.1 的 `Set-Content -Encoding utf8` 会写入 BOM，
# 而 PDS 的 tcl 解释器不认 BOM——`pds_shell -file build_pds.tcl` 会直接报
#   E: Failed to execute the script : invalid command name "ï»¿#"
# 于是 README 里"需要从头重建时可执行 build_pds.tcl"这条路会失效。
# 现交付包内的 build_pds.tcl / .pds / .fdc / .v / .md 都是无 BOM 的，这里保持同一编码。
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-TextNoBom {
  param([string]$Path, [string]$Value)
  [System.IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
}
$TargetDirectoryName=$TargetDirectoryName.Trim()
if($TargetDirectoryName -notmatch '^[A-Za-z0-9_-]+$'){throw 'TargetDirectoryName must be a simple directory name'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseRoot=Join-Path $repo 'release'
$target=Join-Path $releaseRoot $TargetDirectoryName
if(Test-Path -LiteralPath $target){
  $resolved=[System.IO.Path]::GetFullPath($target)
  if(-not $resolved.StartsWith([System.IO.Path]::GetFullPath($releaseRoot),[System.StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe final submission path'}
  # 逐项删除而不是整目录删除：若某个文件被其它进程占用（典型情况是 PDS GUI 正打开
  # 该工程的 .pds.lock），整目录删除会中途失败并留下半成品发布包。这里跳过被占用的
  # 条目并告警，导出继续完成；.lock 本来就被审计的清单校验排除。
  foreach($item in Get-ChildItem -LiteralPath $resolved -Force){
    try{ Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop }
    catch{ Write-Warning "跳过被占用的条目（请关闭占用它的程序后重新导出）: $($item.Name)" }
  }
}
foreach($dir in @('rtl','constraints','firmware','tools','reports','bitstream','evidence','tb')){New-Item -ItemType Directory -Force (Join-Path $target $dir)|Out-Null}

# ============================================================================
# 【2026-09-30 交付配置切换】交付主位流由 50 MHz 版改为 **85 MHz PLL 版**。
# 理由：赛题指标第 (2) 条要"最高工作频率（满足时钟约束前提下的最高工作频率）"，
#       交付件本身工作在 85 MHz 才能自证，避免"报告写 85 MHz、交的位流却是 50 MHz"。
# 实现：板载 50 MHz 晶振 -> PLL（STATIC_RATIOF=17 => VCO 850 MHz，ODIV0=10）=> 85.000 MHz。
# 备用：**50 MHz 版工程 fpga/logic_analyzer 原样保留**，其位流作为"已验证备用位流"
#       一并随包提供（对应 docs/roadmap.md 任务 35"主版本失败时能切换已验证备用版本"）。
# 切换全部集中在这 6 个变量上；改回 50 MHz 只需把前 5 行换回：
#   'fpga/logic_analyzer' / 'mes50hp_logic_analyzer_top' / 'mes50hp_logic_analyzer.fdc'
#   / 'logic_analyzer_generated.pds' / 'release/evidence/logic_analyzer_board_final'
# ============================================================================
$srcProj      = 'fpga/logic_analyzer_85m'
$srcTop       = 'mes50hp_logic_analyzer_pll_top'
$srcFdcName   = 'mes50hp_logic_analyzer_85m.fdc'
$srcPds       = 'la85m_generated.pds'
$srcBrdEvid   = 'release/evidence/logic_analyzer_board_85m'
$fallbackSbit = 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit'

$rtlFiles=@('pipeline_cpu.v','branch_predictor.v','csr_unit.v','forward_unit.v','hazard_unit.v','perf_monitor.v','perf_mmio.v','capture_engine.v','logic_analyzer_pattern_gen.v','logic_analyzer_mmio.v','application_mmio_mux.v','regfile.v','alu.v','imm_gen.v','decoder.v','branch_unit.v','load_store_unit.v','soc_data_interconnect.v','uart_tx.v','uart_rx.v','uart_mmio.v','gpio_mmio.v','timer_mmio.v')
foreach($name in $rtlFiles){Copy-Item -LiteralPath (Join-Path $repo "rtl/$name") -Destination (Join-Path $target "rtl/$name")}

# 交付顶层：85 MHz 版是 pll_85m + mes50hp_logic_analyzer_pll_top + 原 mes50hp_logic_analyzer_top 三层
Copy-Item -LiteralPath (Join-Path $repo "$srcProj/rtl/pll_85m.v") -Destination (Join-Path $target 'rtl/pll_85m.v')
$pllTop=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$srcProj/rtl/$srcTop.v")
Write-TextNoBom -Path (Join-Path $target "rtl/$srcTop.v") -Value $pllTop
$top=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$srcProj/rtl/mes50hp_logic_analyzer_top.v")
$top=$top.Replace('logic_analyzer_imem','final_program_imem').Replace('logic_analyzer_dmem','final_program_dmem')
Write-TextNoBom -Path (Join-Path $target 'rtl/mes50hp_logic_analyzer_top.v') -Value $top
$memory=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$srcProj/rtl/logic_analyzer_program_memory.v")
$memory=$memory.Replace('logic_analyzer_imem','final_program_imem').Replace('logic_analyzer_dmem','final_program_dmem').Replace('LOGIC_ANALYZER_SIM','FINAL_SIM').Replace('fpga/logic_analyzer/rtl/logic_analyzer_program.mem','rtl/program.mem').Replace('rtl/logic_analyzer_program.mem','rtl/program.mem').Replace('generate_logic_analyzer_fpga_memory.ps1','firmware image generator')
Write-TextNoBom -Path (Join-Path $target 'rtl/program_memory.v') -Value $memory
Copy-Item -LiteralPath (Join-Path $repo "$srcProj/rtl/logic_analyzer_program.mem") -Destination (Join-Path $target 'rtl/program.mem')

$fdc=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$srcProj/constraints/$srcFdcName")
$fdc=$fdc.Replace('Task 30 physical loopback','Final physical loopback')
# 约束文件名必须与 .pds / build_pds.tcl 里 add_constraint 引用的名字一致，即 $srcFdcName。
# 历史 Bug（2026-10-03 修复）：这里曾写死成 'mes50hp_logic_analyzer.fdc'（50 MHz 版的旧名），
# 而导出的 .pds 与 build_pds.tcl 引用 'mes50hp_logic_analyzer_85m.fdc'，
# 导致交付包一打开就报 C: Flow-2003，综合直接以
# E: Flow-0002: File '.../constraints/mes50hp_logic_analyzer_85m.fdc' doesn't exist 失败。
Write-TextNoBom -Path (Join-Path $target "constraints/$srcFdcName") -Value $fdc

$recipe=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$srcProj/pds_recipe.tcl")
$recipe=$recipe.Replace('../../rtl/','rtl/').Replace('rtl/logic_analyzer_program_memory.v','rtl/program_memory.v')
Write-TextNoBom -Path (Join-Path $target 'build_pds.tcl') -Value $recipe
$project=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$srcProj/$srcPds")
$project=$project.Replace('../../rtl/','rtl/').Replace('rtl/logic_analyzer_program_memory.v','rtl/program_memory.v')
# PDS/ModelSim 联合仿真：开发工程里的波形 Testbench 在 tb/ 下，导出时同步搬过来，
# 并把 .pds 里的仿真源路径改写成交付包内的相对路径（见下方 Copy-Item）。
$project=$project.Replace('../../tb/','tb/')
Write-TextNoBom -Path (Join-Path $target 'MES50HP_RISCV_Logic_Analyzer.pds') -Value $project
Copy-Item -LiteralPath (Join-Path $repo 'tb/tb_msim_logic_analyzer_top.v') -Destination (Join-Path $target 'tb/tb_msim_logic_analyzer_top.v')

# ============================================================================
# 【2026-10-03 新增】CoreMark 85 MHz 跑分工程，做成与逻辑分析仪工程**同级同形**的
# PDS 工程（此前包里只有跑分 .sbit，没有 .pds：用户在 PDS GUI 里既打不开、也不方便
# 走 Programmer 下载/重建）。做法与逻辑分析仪工程完全一致：
#   源文件放包内 rtl/、约束放包内 constraints/、.pds 与 recipe 把 ../../rtl/ 改写成 rtl/。
# 复用关系：18 个 CPU/SoC 公共源文件与 pll_85m.v 两个工程共用包内那一份
#（pll_85m.v 已核对与跑分工程里那份逐字节相同）；跑分专用的是
#   coremark_program_memory.v + coremark_{imem,drom,ram}.mem + mes50hp_coremark_pll_top.v。
# ============================================================================
$cmProj = 'fpga/coremark_85m'
$cmPds  = 'coremark_85m_generated.pds'
foreach($name in @('coremark_program_memory.v','mes50hp_coremark_pll_top.v',
                   'coremark_imem.mem','coremark_drom.mem','coremark_ram.mem')){
  Copy-Item -LiteralPath (Join-Path $repo "$cmProj/rtl/$name") -Destination (Join-Path $target "rtl/$name")
}
Copy-Item -LiteralPath (Join-Path $repo "$cmProj/constraints/mes50hp_coremark_85m.fdc") -Destination (Join-Path $target 'constraints/mes50hp_coremark_85m.fdc')
$cmRecipe=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$cmProj/pds_recipe.tcl")
$cmRecipe=$cmRecipe.Replace('../../rtl/','rtl/')
Write-TextNoBom -Path (Join-Path $target 'build_coremark_pds.tcl') -Value $cmRecipe
$cmProject=Get-Content -Raw -Encoding UTF8 (Join-Path $repo "$cmProj/$cmPds")
$cmProject=$cmProject.Replace('../../rtl/','rtl/').Replace('../../tb/','tb/')
Write-TextNoBom -Path (Join-Path $target 'MES50HP_CoreMark_85M.pds') -Value $cmProject

Copy-Item -LiteralPath (Join-Path $repo 'software/logic_analyzer/start.S') -Destination (Join-Path $target 'firmware/start.S')
Copy-Item -LiteralPath (Join-Path $repo 'software/logic_analyzer/link.ld') -Destination (Join-Path $target 'firmware/link.ld')
$firmware=Get-Content -Raw -Encoding UTF8 (Join-Path $repo 'software/logic_analyzer/logic_analyzer.c')
$firmware=$firmware.Replace('LOGIC_ANALYZER_AUTOSTART','FINAL_AUTOSTART')
Write-TextNoBom -Path (Join-Path $target 'firmware/logic_analyzer_firmware.c') -Value $firmware
$makefile=@'
ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; set it to riscv-none-elf-)
endif
CC := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra -DFINAL_AUTOSTART=0
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,firmware.map
all: firmware.elf firmware.mem
firmware.elf: start.S logic_analyzer_firmware.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S logic_analyzer_firmware.c -lgcc
firmware.mem: firmware.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
clean:
	rm -f firmware.elf firmware.mem firmware.map
'@
Write-TextNoBom -Path (Join-Path $target 'firmware/Makefile') -Value $makefile
foreach($name in @('logic_analyzer.py','logic_analyzer_serial.py','mes50hp_validation_ui.py','waveform_panel.py','pyUI.py','pyUI_requirements.txt','waveform_viewer.html')){Copy-Item -LiteralPath (Join-Path $repo "python/$name") -Destination (Join-Path $target "tools/$name")}
Copy-Item -LiteralPath (Join-Path $repo 'docs/logic_analyzer_quick_start.md') -Destination (Join-Path $target '逻辑分析仪使用说明.md')
Copy-Item -LiteralPath (Join-Path $repo 'python/start_logic_analyzer.cmd') -Destination (Join-Path $target '启动逻辑分析仪.cmd')

# ============================================================================
# 【2026-10-03 零依赖化】评委机器上"点开就能用"：不装 Python、不装 GTKWave。
#   采集：tools/logic_analyzer_capture.ps1（Windows 自带 PowerShell + .NET 串口）
#         由包根目录 采集四模式.cmd 调用
#   看波形：tools/waveform_viewer.html（自包含浏览器查看器）+ 各次采集自动生成的
#         <模式>_00.html 与 波形预览.html（波形数据直接嵌在页面里）
# 这两条依赖以前是"评委机最大的打不开风险"：Python 没装 / .vcd 没有关联的波形软件。
# ============================================================================
Copy-Item -LiteralPath (Join-Path $repo 'scripts/logic_analyzer_capture.ps1') -Destination (Join-Path $target 'tools/logic_analyzer_capture.ps1')
Copy-Item -LiteralPath (Join-Path $repo 'python/capture_four_modes.cmd') -Destination (Join-Path $target '采集四模式.cmd')

# 【2026-10-03 新增】CoreMark 跑分也做成零依赖：tools/coremark_score.ps1 + 包根 跑分.cmd。
# 此前跑分上位机是 python/coremark_serial.py，评委机没装 Python + pyserial 就跑不了分，
# 与逻辑分析仪那条线不一致。现在两条线都是"双击 .cmd + Windows 自带 PowerShell"。
Copy-Item -LiteralPath (Join-Path $repo 'scripts/coremark_score.ps1') -Destination (Join-Path $target 'tools/coremark_score.ps1')
Copy-Item -LiteralPath (Join-Path $repo 'python/score_coremark.cmd') -Destination (Join-Path $target '跑分.cmd')

Copy-Item -LiteralPath (Join-Path $repo "$srcProj/generate_bitstream/$srcTop.sbit") -Destination (Join-Path $target 'bitstream/mes50hp_riscv_logic_analyzer.sbit')
# 已验证备用位流（50 MHz 版）：任务 35 要求"主版本失败时能切换已验证备用版本"
Copy-Item -LiteralPath (Join-Path $repo $fallbackSbit) -Destination (Join-Path $target 'bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit')
Copy-Item -LiteralPath (Join-Path $repo "$srcProj/report_timing/$srcTop.rtr") -Destination (Join-Path $target 'reports/timing.rtr')
Copy-Item -LiteralPath (Join-Path $repo $srcBrdEvid) -Destination (Join-Path $target 'evidence/logic_analyzer_board_final') -Recurse
# 板级实测波形总览页同时放到包根目录：评委双击就用浏览器看四种模式波形（不需要装任何软件）
$wavePreview=Join-Path $repo "$srcBrdEvid/波形预览.html"
if(-not (Test-Path -LiteralPath $wavePreview)){
  throw "缺少板级波形总览页 $wavePreview；先跑 scripts\logic_analyzer_capture.ps1 -FromCaptures <采集目录> 生成"
}
Copy-Item -LiteralPath $wavePreview -Destination (Join-Path $target '波形预览.html')

# ============================================================================
# CoreMark 跑分复现件（2026-09-30 新增）
# 目的：评委拿到本包，**不依赖任何开发工作区**就能自己下载、自己跑出 CoreMark 分数、
#       自己核对 EEMBC 官方 CRC。
# 包内按与开发仓库**相同的相对目录结构**存放（coremark/software/coremark +
# coremark/third_party/coremark），因此固件 Makefile 里的
# `-I../../third_party/coremark` 与 check-isa 用的 `../../scripts/...` 都能**原样工作**，
# 不需要改任何路径。
# ============================================================================
$cmDst = Join-Path $target 'coremark'
foreach($d in @('software/coremark','third_party/coremark','scripts','images','rebuild','expected')){
  New-Item -ItemType Directory -Force (Join-Path $cmDst $d) | Out-Null
}
# 一页复现说明（源文件在 docs/，与"逻辑分析仪使用说明.md"同一套做法：改源文件、导出时拷贝）
Copy-Item -LiteralPath (Join-Path $repo 'docs/coremark_reproduction.md') -Destination (Join-Path $cmDst '跑分复现说明.md')
# 跑分专用位流（85 MHz，与交付时钟一致）。注意它与本包逻辑分析仪位流不是同一个文件。
Copy-Item -LiteralPath (Join-Path $repo 'fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit') -Destination (Join-Path $target 'bitstream/mes50hp_coremark_85m.sbit')
# 跑分上位机（自包含，只依赖 pyserial；带 --clock-hz，能把 ticks 正确换算成秒）
Copy-Item -LiteralPath (Join-Path $repo 'python/coremark_serial.py') -Destination (Join-Path $target 'tools/coremark_serial.py')
# 跑分固件工程（port 层）
foreach($name in @('Makefile','start.S','core_portme.c','core_portme.h','ee_printf.c','link.ld')){
  Copy-Item -LiteralPath (Join-Path $repo "software/coremark/$name") -Destination (Join-Path $cmDst "software/coremark/$name")
}
# EEMBC 官方 CoreMark 源码（未改动）与 LICENSE
foreach($name in @('core_main.c','core_list_join.c','core_matrix.c','core_state.c','core_util.c','coremark.h','LICENSE.md','coremark.md5')){
  Copy-Item -LiteralPath (Join-Path $repo "third_party/coremark/$name") -Destination (Join-Path $cmDst "third_party/coremark/$name")
}
Copy-Item -LiteralPath (Join-Path $repo 'scripts/run_check_coremark_elf.sh') -Destination (Join-Path $cmDst 'scripts/run_check_coremark_elf.sh')
# 实际烧进 FPGA 的存储器镜像与存储器 RTL
foreach($name in @('coremark_imem.mem','coremark_drom.mem','coremark_ram.mem','coremark_program_memory.v')){
  Copy-Item -LiteralPath (Join-Path $repo "fpga/coremark_85m/rtl/$name") -Destination (Join-Path $cmDst "images/$name")
}
# PDS 重建件：配方、约束、顶层、PLL
foreach($rel in @('pds_recipe.tcl','constraints/mes50hp_coremark_85m.fdc','rtl/mes50hp_coremark_pll_top.v','rtl/pll_85m.v')){
  Copy-Item -LiteralPath (Join-Path $repo "fpga/coremark_85m/$rel") -Destination (Join-Path $cmDst ("rebuild/" + (Split-Path $rel -Leaf)))
}
# 金标准串口输出（评委逐行比对用）。用 .txt 而不是 .log：审计脚本对 .log 不做哈希校验。
Copy-Item -LiteralPath (Join-Path $repo 'release/evidence/coremark_uart_cm85_20260930.log') -Destination (Join-Path $cmDst 'expected/coremark_expected_output.txt')

$metrics=Get-Content -Raw -Encoding UTF8 (Join-Path $repo 'release/evidence/automated_metrics.json') | ConvertFrom-Json
$bitHash=(Get-FileHash -LiteralPath (Join-Path $repo "$srcProj/generate_bitstream/$srcTop.sbit") -Algorithm SHA256).Hash
$readme=@"
# MES50HP RISC-V 多协议逻辑分析仪最终版

唯一下载文件：``bitstream/mes50hp_riscv_logic_analyzer.sbit``（**85 MHz 版**）。
已验证备用文件：``bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit``（50 MHz 版，仅在主位流异常时使用）。

PDS 工程文件（**两个，都可以在 PDS 2024.2-SP2 里直接打开、查看源码/约束并下载或重建**）：

- ``MES50HP_RISCV_Logic_Analyzer.pds`` —— **逻辑分析仪应用**（交付主位流，85 MHz）。重建配方 ``build_pds.tcl``。
- ``MES50HP_CoreMark_85M.pds`` —— **CoreMark 跑分**（85 MHz）。重建配方 ``build_coremark_pds.tcl``。
  打开后 Top 是 ``mes50hp_coremark_pll_top``；CPU/SoC 源码与逻辑分析仪工程共用 ``rtl/``，
  跑分专用源文件是 ``rtl/coremark_program_memory.v`` + ``rtl/mes50hp_coremark_pll_top.v`` + ``rtl/coremark_*.mem``，
  约束是 ``constraints/mes50hp_coremark_85m.fdc``。

**看波形（不需要装任何软件）**：双击包根目录 ``波形预览.html``，浏览器里就是**本交付位流在实体板上实测抓到**的
四种模式波形（static / counter / uart / spi，标签切换、滚轮缩放、红色虚线是触发点）。
它同时也是通用查看器：把任意 `.vcd` 拖进去即可显示。

**接板子自己跑一遍（同样零依赖）**：下载**主位流** ``bitstream/mes50hp_riscv_logic_analyzer.sbit``（**85 MHz**），
按 J8 相邻脚对接好 8 根杜邦线（3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32），
然后**双击包根目录 ``采集四模式.cmd``**：它用 Windows 自带的 PowerShell 与 .NET 串口完成四模式采集，
不需要安装 Python；跑完自动打开输出目录，双击里面的 ``波形预览.html`` 或 ``<模式>\<模式>_00.html`` 看波形。
（包内仍保留 Python 图形界面上位机 ``启动逻辑分析仪.cmd``：**窗口里自带实时波形面板**，
勾「实时连续采集」就能边采边看，实测约 1.3 次/秒；装了 Python 就可以用这条更直观的路径。
完整说明与手动串口协议见 ``逻辑分析仪使用说明.md``。）
（``bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit`` 是**已验证备用位流**，只在主位流异常时切换使用。）

**CoreMark 跑分复现**：本包自带跑分专用位流 ``bitstream/mes50hp_coremark_85m.sbit``、
**可直接打开的跑分 PDS 工程** ``MES50HP_CoreMark_85M.pds``、EEMBC 官方 CoreMark 源码、跑分固件工程、
实际烧进 FPGA 的存储器镜像、上位机脚本与金标准输出，
**不依赖任何开发工作区**即可自己跑出分数并核对官方 CRC。
**跑分只需双击包根目录 ``跑分.cmd``**（Windows 自带功能，不需要装 Python；跑完自动打开
``results\coremark\``，双击里面的 ``跑分结果.html`` 就能看分数与逐项金标准核对）。
**一页说明见 ``coremark/跑分复现说明.md``**（期望结果：85 MHz 下 **Score 79.587**、
CoreMark/MHz **0.936**、官方 CRC **PASS**、运行 31.412 s）。

- 器件：PGL50H-6IFBG484；板载晶振 50 MHz，经片上 PLL 倍频到 **85 MHz** 供 CPU/SoC 使用
  （``pll_85m``：50 MHz / IDIV 1 = PFD 50 MHz，× FDIV 17 = VCO 850 MHz，/ ODIV0 10 = **85.000 MHz** 精确整数频率）。
  PDS 推导的生成时钟见 ``reports/timing.rtr``：请求 85.0000 MHz、估算 **90.0766 MHz**、slack **+0.663 ns**、**All Constraints Met**。
- CPU：RV32I 五级流水线，16 项直接映射 BTB，2-bit 饱和计数器；机器模式 CSR/Trap/MRET（`mstatus/mie/mtvec/mepc/mcause/mtval/mip` 等）与三根设备无关中断输入。
- 外设：片上 RAM、CP2102 UART、GPIO、性能计数器、8 通道 Raw 逻辑分析仪、机器定时器（`mtime`/`mtimecmp`，窗口 0x1000_3000，聚合出定时器中断）。
- J8 回环：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。
- 时序：All Constraints Met；慢角 setup WNS +$($metrics.final.setup_wns_ns) ns，hold WHS +$($metrics.final.hold_whs_ns) ns，估算 Fmax $($metrics.final.estimated_fmax_mhz) MHz。
- 综合资源：$($metrics.final.lut) LUT、$($metrics.final.ff) FF、$($metrics.final.drm) 个 DRM18K 等效块。
- bitstream SHA-256：$bitHash。

自动 RTL/软件/PDS 回归均已通过（`scripts\run_final_regression.ps1` → ALL AUTOMATED FINAL REGRESSION PASS）。

**实体板证据（2026-09-29 实测，当时对应 50 MHz 位流 ``BCAE040A…``）：**

- 位流下载：`scripts\program_board.ps1 -Config la50` 与 `-Config cm50` 均为 `PROGRAM PASS`，`done bit is 1`；
  （**当前交付主位流是 85 MHz 版**，下载请用 `-Config la85`；`la50` 现在是已验证备用配置）
- J8 四模式实板验收：`scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` →
  `LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80`（static/counter/uart/spi 各 20/20；各模式单次返回样本数 static 5、counter 5、uart 236、spi 85，触发位置依次 0/0/15/4；作品自带逻辑分析仪的 Raw 缓存深度为 256 样本，与 PDS DebugCore 探针的 512 样本不是一回事）；
- CoreMark 实板复现：`scripts\run_coremark_board.ps1 -Port COM11` →
  `COREMARK BOARD PASS clock_hz=50000000 ticks=1068006999 seconds=21.360 score_x1000=46816`
  （运行 21.36 秒，满足赛题"不少于 10 秒"）；
- **板级裸机中断（2026-09-30 完成）**：``fpga/timer_demo`` 最小板级工程，
  ``python python\timer_demo_board.py --port COM11 --seconds 6`` → 捕获 12 次周期性中断，
  计数序列 ``890123456789``、LED 序列 ``010101010101``；固件用 mtime 自计时，中断周期中位数
  **12,517,376 拍 = 250.348 ms**（预期 250.0 ms）。证据 ``release/evidence/timer_demo_board/``。
  ⚠️ 此项用的是 ``fpga/timer_demo`` **独立演示位流**（``5E58B421…``），不是本包的逻辑分析仪位流。
- **ILA 抓 Trap 进入/返回（2026-09-30 完成，M-24 收口）**：``fpga/timer_demo_ila`` 工程，192 位探针 × 512 样本。
  抓取 A（触发 ``ila_event_trap``）trap@256 / return@251；抓取 B（触发 ``ila_event_trap_return``）return@256 / trap@261。
  两次互为正/反向触发，``event_trap`` 与 ``event_trap_return`` 各产生**恰好一个**脉冲，``irq_timer`` 全程为 1，
  illegal/misaligned/bus_error 全程为 0。证据 ``fpga/timer_demo_ila/evidence/``（位流 ``452EE532…``）。
  由此 ``docs/trap_contract.md`` 的 **M-24 收口为 PASS**，矩阵 M-01…M-24 全部 PASS。
- **CoreMark 关键循环 ILA 波形（2026-09-30 完成）**：证据 ``release/evidence/ila_coremark/``。
- **80 MHz PLL 板级 CoreMark（2026-09-30 首次按当前批次实测）**：位流 ``F0743756…``，
  ``ticks=2670014377``、2500 迭代、**33.375 s**、Score **74.905**、CoreMark/MHz **0.936**、CRC **PASS**。
  证据 ``release/evidence/coremark_board_cm80_20260930.json``。
- **S1 DDR3 板级证据已独立落盘并复现（2026-09-30）**：``S1 DDR3 SMOKE BOARD PASS``（BIST err_cnt 全程 0），
  证据 ``release/evidence/ddr3_smoke_board/``（位流 ``FAEDF476…``）。
- **交付位流为 85 MHz 版，并已做稳定性 soak（2026-09-30）**：
  本包主位流工作在 85 MHz，J8 四模式 **80/80 PASS**，证据 ``evidence/logic_analyzer_board_final/``。
  50 MHz 版位流作为**已验证备用**一并提供（对应 ``docs/roadmap.md`` 任务 35「主版本失败时能切换已验证备用版本」）。

**读数纪律（引用板级数字前必读）**：

1. CoreMark 分数来自 **CoreMark 专用位流**（50 MHz ``DC95F9D0…`` / 80 MHz ``F0743756…`` /
   85 MHz ``751C692B…`` / 90 MHz ``664CD28C…``），**不是**本包的逻辑分析仪位流。
2. 板级 **CPI 有窗口敏感性**：同一颗位流实测过 1.494 与 1.508，而 ``ticks``/Score/``flushes`` 逐位相同。
   ⇒ **CPI 只能写 ≈1.50，不能写 1.508 这种四位精度**；Score/ticks 可照写。
3. ``run_coremark_board.ps1`` 无条件把 ``clock_hz`` 写成 50 MHz，跑 80 MHz 位流时它打印的 ``seconds``
   是错的（真实 33.375 s，不是 53.400 s）。

**已知未做（如实标注，不是"已完成"也不是"不适用"）**：

- **三轮断电一致性**：``run01`` 只做了"重新下载（Reset 等价）"，**没有真的断过电**；
  ``run02``/``run03`` 未做，**因为用户 2026-09-30 明确表示不做**（见 ``release/evidence/board/README.md``）。
- 80 MHz 逻辑分析仪回环（只有 50 MHz 有 80/80）；
- DDR3 **未接入 CPU 存储路径**，也没有任何 DDR3 吞吐/延迟数字；
- N4 的 89.25 MHz 候选位流**从未上板**。

**全部数字的出处见 ``release/evidence/claims_map.md``**（数字 ↔ 证据文件 ↔ 位流哈希对照表，含未宣称清单）。
再按 ``逻辑分析仪使用说明.md`` 跑 J8 四模式；CoreMark 用 ``scripts\run_coremark_board.ps1 -Port COM11``。
"@
Write-TextNoBom -Path (Join-Path $target 'README.md') -Value $readme

# 哈希清单必须与 audit_release_package.ps1 的"交付物集合"用同一套排除规则，否则导出会被
# 构建垃圾卡死：审计那边排除 .lock/.log 与 sim/ 中间产物，导出这边过去是全量哈希。
# 2026-10-09 实测：PDS 打开交付工程后 release/final_submission/pds.log 被别的进程独占，
# Get-FileHash 直接抛 ReadError，导出在最后一步中断——包内容已经写好，却缺
# SHA256SUMS.txt 与 zip，成了"看着像导出了、其实不完整"的半成品。
$files=Get-ChildItem -LiteralPath $target -File -Recurse |
  Where-Object { $_.Extension -notin @('.lock','.log') -and $_.Name -ne 'multiseed_summary.csv' -and $_.FullName -notmatch '[\\/]sim[\\/]' } |
  Sort-Object FullName
$lines=foreach($file in $files){$relative=Get-RelativePathCompat -Base $target -Path $file.FullName.Replace('\','/');"$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)  $relative"}
# 清单同样必须无 BOM：audit_release_package.ps1 用 '^([0-9A-F]{64})  (.+)$' 解析每一行，
# 带 BOM 时第一行会变成 "﻿<hash>  <path>"，审计直接判 malformed。
Write-TextNoBom -Path (Join-Path $target 'SHA256SUMS.txt') -Value (($lines -join "`r`n") + "`r`n")
$zip=Join-Path $releaseRoot 'MES50HP_RISCV_Logic_Analyzer_Final.zip'
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
# 打包同样要避开被独占的构建垃圾：Compress-Archive -Path <目录>/* 会把 pds.log 一起读进去，
# 一旦它被 PDS 或安全软件锁住就抛 ZipArchiveHelper UnauthorizedAccess（实测）。
# 有可打包文件时按文件清单打包并保持相对路径；一个都没有才退回整目录打包。
if($files.Count -gt 0){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  # 枚举值用整数传：Windows PowerShell 5.1 里 [System.IO.Compression.ZipArchiveMode]::Create
  # 这种"嵌套类型 + 静态成员"写法会报 TypeNotFound（实测），而构造参数按值绑定即可。
  $createMode=1        # ZipArchiveMode.Create
  $optimal=0           # CompressionLevel.Optimal
  $archive=[System.IO.Compression.ZipFile]::Open($zip,$createMode)
  try{
    foreach($file in $files){
      $relative=Get-RelativePathCompat -Base $target -Path $file.FullName.Replace('\','/')
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,$optimal)
    }
  } finally { $archive.Dispose() }
} else {
  Compress-Archive -Path (Join-Path $target '*') -DestinationPath $zip -CompressionLevel Optimal
}
Write-Host "FINAL SUBMISSION EXPORT PASS files=$($files.Count) zip=$zip"
