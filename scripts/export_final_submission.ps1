param([string]$TargetDirectoryName='final_submission')
$ErrorActionPreference='Stop'
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
foreach($dir in @('rtl','constraints','firmware','tools','reports','bitstream','evidence')){New-Item -ItemType Directory -Force (Join-Path $target $dir)|Out-Null}

$rtlFiles=@('pipeline_cpu.v','branch_predictor.v','forward_unit.v','hazard_unit.v','perf_monitor.v','perf_mmio.v','capture_engine.v','logic_analyzer_pattern_gen.v','logic_analyzer_mmio.v','application_mmio_mux.v','regfile.v','alu.v','imm_gen.v','decoder.v','branch_unit.v','load_store_unit.v','soc_data_interconnect.v','uart_tx.v','uart_rx.v','uart_mmio.v','gpio_mmio.v')
foreach($name in $rtlFiles){Copy-Item -LiteralPath (Join-Path $repo "rtl/$name") -Destination (Join-Path $target "rtl/$name")}

$top=Get-Content -Raw (Join-Path $repo 'fpga/logic_analyzer/rtl/mes50hp_logic_analyzer_top.v')
$top=$top.Replace('logic_analyzer_imem','final_program_imem').Replace('logic_analyzer_dmem','final_program_dmem')
Set-Content -LiteralPath (Join-Path $target 'rtl/mes50hp_logic_analyzer_top.v') -Value $top -Encoding utf8
$memory=Get-Content -Raw (Join-Path $repo 'fpga/logic_analyzer/rtl/logic_analyzer_program_memory.v')
$memory=$memory.Replace('logic_analyzer_imem','final_program_imem').Replace('logic_analyzer_dmem','final_program_dmem').Replace('LOGIC_ANALYZER_SIM','FINAL_SIM').Replace('fpga/logic_analyzer/rtl/logic_analyzer_program.mem','rtl/program.mem').Replace('rtl/logic_analyzer_program.mem','rtl/program.mem').Replace('generate_logic_analyzer_fpga_memory.ps1','firmware image generator')
Set-Content -LiteralPath (Join-Path $target 'rtl/program_memory.v') -Value $memory -Encoding utf8
Copy-Item -LiteralPath (Join-Path $repo 'fpga/logic_analyzer/rtl/logic_analyzer_program.mem') -Destination (Join-Path $target 'rtl/program.mem')

$fdc=Get-Content -Raw (Join-Path $repo 'fpga/logic_analyzer/constraints/mes50hp_logic_analyzer.fdc')
$fdc=$fdc.Replace('Task 30 physical loopback','Final physical loopback')
Set-Content -LiteralPath (Join-Path $target 'constraints/mes50hp_logic_analyzer.fdc') -Value $fdc -Encoding utf8

$recipe=Get-Content -Raw (Join-Path $repo 'fpga/logic_analyzer/pds_recipe.tcl')
$recipe=$recipe.Replace('../../rtl/','rtl/').Replace('rtl/logic_analyzer_program_memory.v','rtl/program_memory.v')
Set-Content -LiteralPath (Join-Path $target 'build_pds.tcl') -Value $recipe -Encoding utf8
$project=Get-Content -Raw (Join-Path $repo 'fpga/logic_analyzer/logic_analyzer_generated.pds')
$project=$project.Replace('../../rtl/','rtl/').Replace('rtl/logic_analyzer_program_memory.v','rtl/program_memory.v')
Set-Content -LiteralPath (Join-Path $target 'MES50HP_RISCV_Logic_Analyzer.pds') -Value $project -Encoding utf8

Copy-Item -LiteralPath (Join-Path $repo 'software/logic_analyzer/start.S') -Destination (Join-Path $target 'firmware/start.S')
Copy-Item -LiteralPath (Join-Path $repo 'software/logic_analyzer/link.ld') -Destination (Join-Path $target 'firmware/link.ld')
$firmware=Get-Content -Raw (Join-Path $repo 'software/logic_analyzer/logic_analyzer.c')
$firmware=$firmware.Replace('LOGIC_ANALYZER_AUTOSTART','FINAL_AUTOSTART')
Set-Content -LiteralPath (Join-Path $target 'firmware/logic_analyzer_firmware.c') -Value $firmware -Encoding utf8
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
Set-Content -LiteralPath (Join-Path $target 'firmware/Makefile') -Value $makefile -Encoding utf8
foreach($name in @('logic_analyzer.py','logic_analyzer_serial.py','mes50hp_validation_ui.py','pyUI.py','pyUI_requirements.txt')){Copy-Item -LiteralPath (Join-Path $repo "python/$name") -Destination (Join-Path $target "tools/$name")}
Copy-Item -LiteralPath (Join-Path $repo 'docs/logic_analyzer_quick_start.md') -Destination (Join-Path $target '逻辑分析仪使用说明.md')
Copy-Item -LiteralPath (Join-Path $repo 'python/start_logic_analyzer.cmd') -Destination (Join-Path $target '启动逻辑分析仪.cmd')

Copy-Item -LiteralPath (Join-Path $repo 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit') -Destination (Join-Path $target 'bitstream/mes50hp_riscv_logic_analyzer.sbit')
Copy-Item -LiteralPath (Join-Path $repo 'fpga/logic_analyzer/report_timing/mes50hp_logic_analyzer_top.rtr') -Destination (Join-Path $target 'reports/timing.rtr')
Copy-Item -LiteralPath (Join-Path $repo 'release/evidence/logic_analyzer_board_final') -Destination (Join-Path $target 'evidence/logic_analyzer_board_final') -Recurse

$metrics=Get-Content -Raw (Join-Path $repo 'release/evidence/automated_metrics.json') | ConvertFrom-Json
$bitHash=(Get-FileHash -LiteralPath (Join-Path $repo 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit') -Algorithm SHA256).Hash
$readme=@"
# MES50HP RISC-V 多协议逻辑分析仪最终版

唯一下载文件：``bitstream/mes50hp_riscv_logic_analyzer.sbit``。

PDS 工程文件：``MES50HP_RISCV_Logic_Analyzer.pds``。在 PDS 2024.2-SP2 中直接打开即可查看源码、顶层和约束；需要从头重建时也可在本目录执行 ``build_pds.tcl``。

逻辑分析仪使用：下载唯一最终 bitstream，按 J8 相邻脚对接好 8 根杜邦线，然后双击 ``启动逻辑分析仪.cmd``。完整操作和故障处理见 ``逻辑分析仪使用说明.md``。

- 器件：PGL50H-6IFBG484；系统时钟：50 MHz。
- CPU：RV32I 五级流水线，16 项直接映射 BTB，2-bit 饱和计数器。
- 外设：片上 RAM、CP2102 UART、GPIO、性能计数器、8 通道 Raw 逻辑分析仪。
- J8 回环：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。
- 时序：All Constraints Met；慢角 setup WNS +$($metrics.final.setup_wns_ns) ns，hold WHS +$($metrics.final.hold_whs_ns) ns，估算 Fmax $($metrics.final.estimated_fmax_mhz) MHz。
- 综合资源：$($metrics.final.lut) LUT、$($metrics.final.ff) FF、$($metrics.final.drm) 个 DRM18K 等效块。
- bitstream SHA-256：$bitHash。

自动 RTL/软件/PDS 回归均已通过。实体板 JTAG 下载 DONE=1，J8 static/counter/UART/SPI 四模式各 20 次、共 80/80 PASS；证据随包提供。
"@
Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $readme -Encoding utf8

$files=Get-ChildItem -LiteralPath $target -File -Recurse | Sort-Object FullName
$lines=foreach($file in $files){$relative=[System.IO.Path]::GetRelativePath($target,$file.FullName).Replace('\','/');"$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)  $relative"}
$lines|Set-Content -LiteralPath (Join-Path $target 'SHA256SUMS.txt') -Encoding utf8
$zip=Join-Path $releaseRoot 'MES50HP_RISCV_Logic_Analyzer_Final.zip'
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
Compress-Archive -Path (Join-Path $target '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Host "FINAL SUBMISSION EXPORT PASS files=$($files.Count) zip=$zip"
