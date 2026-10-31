param(
  [ValidateSet('la50','la80','la85','la90','tr85','cm50','cm80','cm85','cm85r','cm90','cm95','cmim','cmim85','ila','tm50','ddr3','tmila')][string]$Config='la50',
  [string]$BitstreamPath='',
  [int]$TimeoutSeconds=600,
  [switch]$UseDebugger
)
# 统一的 MES50HP 位流下载入口（替代临时散落的 tmp\*.tcl）。
#
#   la50 = 交付配置：50 MHz 逻辑分析仪      la80 = 80 MHz PLL 逻辑分析仪
#   cm50 = 50 MHz CoreMark                  cm80 = 80 MHz PLL CoreMark
#   ila  = CoreMark + DebugCore（Fabric Debugger 抓波形用）
#   tm50 = M-24/N1 板级周期性定时器中断演示（LED0 每 0.25 s 翻转 + 串口中断计数）
#
# -BitstreamPath <file>：下载任意 .sbit，用于板级验证候选/实验位流
#   （例如 release/artifacts/fmax_tuning_*/ 下的收紧约束候选）。
#   给了它就以它为准并忽略 -Config；工作文件用 custom_ 前缀，不覆盖命名配置的日志。
#   注意：验证候选位流时不要把候选拷到命名配置的路径上覆盖交付位流。
#
# 两种下载通道：
#   默认         cdt_cfg.exe（普通 JTAG 配置）
#   -UseDebugger cdt_dbg.exe 的 dbg_program：当板上当前位流含 DebugCore/Jtag Hub 时
#                JTAG 链被 Hub 接管，cdt_cfg 会报 Configuration-0009，这时必须走 Fabric Debugger。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pdsBin='D:\Pango\PDS_2024.2-SP2\bin'
$jsPort=65420
$workDir=Join-Path $repo 'tmp'

$bitstreams=[ordered]@{
  la50 = @{ Path=(Join-Path $repo 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit');          Note='交付配置: 逻辑分析仪 50 MHz' }
  la80 = @{ Path=(Join-Path $repo 'fpga/logic_analyzer_80m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit');  Note='逻辑分析仪 80 MHz PLL' }
  la85 = @{ Path=(Join-Path $repo 'fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit');  Note='逻辑分析仪 85 MHz PLL（板级实测最高可靠频率点）' }
  la90 = @{ Path=(Join-Path $repo 'fpga/logic_analyzer_90m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit');  Note='逻辑分析仪 90 MHz PLL（PDS 过但 SPI 模式板上挂死，仅用于复现上界）' }
  tr85 = @{ Path=(Join-Path $repo 'fpga/trace85/generate_bitstream/mes50hp_trace_pll_top.sbit');                      Note='提交级 trace 可视化 85 MHz PLL（附加演示位流，不是交付位流 la85）' }
  cm50 = @{ Path=(Join-Path $repo 'fpga/coremark/generate_bitstream/mes50hp_coremark_top.sbit');                      Note='CoreMark 50 MHz (上电等串口 R 启动)' }
  cm80 = @{ Path=(Join-Path $repo 'fpga/coremark_80m/generate_bitstream/mes50hp_coremark_pll_top.sbit');              Note='CoreMark 80 MHz PLL (上电等串口 R 启动)' }
  cm85 = @{ Path=(Join-Path $repo 'fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit');              Note='CoreMark 85 MHz PLL (上电等串口 R 启动)' }
  cm90 = @{ Path=(Join-Path $repo 'fpga/coremark_90m/generate_bitstream/mes50hp_coremark_pll_top.sbit');              Note='CoreMark 90 MHz PLL（CPU 板级上界：Score 84.269，上电等串口 R 启动）' }
  cm95 = @{ Path=(Join-Path $repo 'fpga/coremark_95m/generate_bitstream/mes50hp_coremark_pll_top.sbit');              Note='CoreMark 95 MHz PLL（PDS 时序违例，仅留档，不要上板当结果用）' }
  cmim = @{ Path=(Join-Path $repo 'fpga/coremark_im/generate_bitstream/mes50hp_coremark_top.sbit');                    Note='CoreMark 50 MHz RV32IM（M 扩展，上电等串口 R 启动）' }
  cmim85 = @{ Path=(Join-Path $repo 'fpga/coremark_im_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit');          Note='CoreMark 85 MHz RV32IM（M 扩展 + 交付时钟，上电等串口 R 启动）' }
  cm85r = @{ Path=(Join-Path $repo 'fpga/coremark_85m_r/generate_bitstream/mes50hp_coremark_pll_top.sbit');            Note='CoreMark 85 MHz RV32I（用当前 RTL 重建的同源对照点，上电等串口 R 启动）' }
  ila  = @{ Path=(Join-Path $repo 'fpga/coremark_ila/generate_bitstream/mes50hp_coremark_top.sbit');                  Note='CoreMark + DebugCore (ILA 波形)' }
  tm50 = @{ Path=(Join-Path $repo 'fpga/timer_demo/generate_bitstream/mes50hp_timer_demo_top.sbit');                  Note='M-24/N1 周期性定时器中断演示 (LED0 0.5 s 周期闪烁)' }
  ddr3 = @{ Path=(Join-Path $repo 'fpga/ddr3_smoke/generate_bitstream/mes50hp_ddr3_smoke_top.sbit');                  Note='S1 DDR3 冒烟 (HMIC_S BIST，串口 115200 读状态寄存器)' }
  tmila= @{ Path=(Join-Path $repo 'fpga/timer_demo_ila/generate_bitstream/mes50hp_timer_demo_top.sbit');            Note='M-24/N2 定时器中断 + DebugCore (ILA 抓 Trap 进入/返回，必须加 -UseDebugger)' }
}
if($BitstreamPath){
  if(-not (Test-Path -LiteralPath $BitstreamPath -PathType Leaf)){ throw "位流不存在: $BitstreamPath" }
  $target=@{ Path=(Resolve-Path -LiteralPath $BitstreamPath).Path; Note='自定义位流 (-BitstreamPath)' }
  $tag='custom'
} else {
  $target=$bitstreams[$Config]
  $tag=$Config
}
if(-not (Test-Path -LiteralPath $target.Path)){throw "位流不存在: $($target.Path)（先按 docs/reproduction.md 重新构建）"}
$hash=(Get-FileHash -LiteralPath $target.Path -Algorithm SHA256).Hash
Write-Host "CONFIG   $tag  ($($target.Note))"
Write-Host "BITSTREAM $($target.Path)"
Write-Host "SHA256   $hash"

# 1) 确保 JTAG 服务在跑
$listening = netstat -ano | Select-String ":$jsPort\s+.*LISTENING"
if(-not $listening){
  Write-Host "启动 JTAG 服务 cdt_js.exe (port $jsPort) ..."
  Start-Process (Join-Path $pdsBin 'cdt_js.exe') -ArgumentList '-work_dir',$workDir,'-port',"$jsPort"
  $deadline=(Get-Date).AddSeconds(25)
  do{ Start-Sleep -Milliseconds 500; $listening = netstat -ano | Select-String ":$jsPort\s+.*LISTENING" }while(-not $listening -and (Get-Date) -lt $deadline)
  if(-not $listening){throw "JTAG 服务未在 $jsPort 监听"}
}

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$tcl=Join-Path $workDir "program_$tag.tcl"
$log=Join-Path $workDir "program_$tag.log"
$bitForTcl=$target.Path.Replace('\','/')
if($UseDebugger){
  @"
dbg_connect -ip 127.0.0.1 -port $jsPort
dbg_scan_chain
dbg_program -device 0 -file {$bitForTcl}
dbg_disconnect
dbg_close
"@ | Set-Content -LiteralPath $tcl -Encoding ascii
  $exe=Join-Path $pdsBin 'cdt_dbg.exe'
} else {
  @"
cfg_connect -ip 127.0.0.1 -port $jsPort
cfg_scan_chain
cfg_assign_file -file {$bitForTcl} -device_index 0
cfg_program -device_index 0
cfg_disconnect
"@ | Set-Content -LiteralPath $tcl -Encoding ascii
  $exe=Join-Path $pdsBin 'cdt_cfg.exe'
}
Write-Host "下载通道 $([System.IO.Path]::GetFileName($exe))  tcl=$tcl"

# 2) 执行下载。cdt_cfg/cdt_dbg 成功后不会自己退出，因此用 Start-Process 重定向输出到
#    文件并轮询成功标志：成功即提前结束并结束进程。注意不要用 Start-Job 包住——非交互
#    作业里该工具的输出拿不到，会一直等到超时（实测过）。
$outFile=Join-Path $workDir "program_$tag.out"
$errFile=Join-Path $workDir "program_$tag.err"
Remove-Item -LiteralPath $outFile,$errFile -ErrorAction SilentlyContinue
$proc=Start-Process -FilePath $exe -ArgumentList @('-file',$tcl,'-work_dir',$workDir) -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$deadline=(Get-Date).AddSeconds($TimeoutSeconds)
$okMarkers='done bit is 1|COMMAND\[configure\] execute successfully|cfg_program -device_index 0 successfully|dbg_program .* successfully'
$text=''
while((Get-Date) -lt $deadline){
  Start-Sleep -Seconds 3
  $text=(Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
  if($text -match $okMarkers){ break }
  if($proc.HasExited){ break }
}
if(-not $proc.HasExited){ try{ $proc.Kill() }catch{} }
$text | Set-Content -LiteralPath $log -Encoding UTF8
if([string]::IsNullOrWhiteSpace($text)){ $text='' }

if($text -notmatch $okMarkers){
  Write-Host $text
  if($text -match 'Configuration-0009'){
    throw "下载失败：JTAG 链被 DebugCore 的 Jtag Hub 接管。请加 -UseDebugger 重试。日志: $log"
  }
  throw "下载失败，日志: $log"
}
Write-Host "PROGRAM PASS config=$tag"
($text -split "`n") | Select-String -Pattern 'done bit|configure successfully|Finish program' | Select-Object -Last 3
if($tag -in @('cm50','cm80')){
  Write-Host "提示：CoreMark 镜像上电后等待串口 'R' 才开跑；用 scripts\measure_coremark.ps1 会自动发送并采集。"
}
