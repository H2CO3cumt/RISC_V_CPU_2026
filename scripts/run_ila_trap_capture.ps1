param(
  [ValidateSet('discover','capture')][string]$Mode = 'discover',
  [string]$PdsRoot  = $(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),
  [int]$JsPort      = 65420,
  [int]$DebugCore   = 0,
  [string]$FicFile  = '',
  # ---- 触发配置（默认值取自官方文档语义，别再凭猜）----
  # 官方模型（Fabric_Debugger_User_Guide §5.3.1）：
  #   一个 Trigger Unit **对应一个 Trigger Port** —— 本 DebugCore IP 只有一个
  #   192 位触发端口（trig0_i），所以就是 TU0。
  #   边沿**不是**用 Function 表达，而是写在 Value 里：
  #     Binary 进制下 X=不关心 0/1=固定值 R=上升沿 F=下降沿 B=任意跳变 N=无跳变
  #   ⇒ "抓 ila_event_trap(bit0) 上升沿" = Binary 值：除最低位为 R 外全部 X。
  #     Value 串按 MSB 在前书写，所以 bit0 是**最后一个**字符。
  [int]$TrigUnit     = 0,
  # 【合法值一律以工具自带的 -help 为准，不要照抄官方 PDF 的示例】
  #   `dbg_fla_set_trig_unit -help` 实测给出：
  #     -func  0~7 = ==, <>, >, >=, <, <=, In Range, Out of Range  ⇒ '==' 是 **0**，不是 1
  #     -radix 0~3 = Binary / Octal / Hex / Unsigned Decimal       ⇒ Binary 是 **0**
  #     -value  Binary 用 X/0/1/R/F/B/N
  #   踩过的坑：PDF 第 6 章示例写 `-func 1`，容易以为 1 就是 '=='；实际 1 是 '<>'，
  #   配上有边沿字符（R/F/B/N）的 Binary 值会被工具拒：
  #     E: The value of trigger unit is illegal or out of range...
  [int]$TrigFunc     = 0,        # 0 = '=='
  [int]$TrigRadix    = 0,        # 0 = Binary（选项顺序 Binary/Hex/Octal/UnsignedDecimal）
  [string]$TrigValue = '',       # 留空 = 自动生成"bit0 上升沿"的 192 位 X/R 串
  [string]$TrigExpr = 'TU0',
  [string]$WaveName = '',
  [int]$TimeoutSeconds = 600,
  [switch]$NoProgram,
  [string]$Bitstream = '',
  # 是否执行 dbg_fla_power_init：默认**不执行**（本 IP 的 INIT_ENABLE=false，见下方长注释）
  [switch]$DoPowerInit
)
# M-24 / N2：用 Fabric Debugger（cdt_dbg.exe）的 Tcl 接口抓"Trap 进入/返回"波形。
#
# 命令语义全部来自官方文档，不凭猜：
#   D:\Pango\PDS_2024.2-SP2\doc\Fabric_Debugger_User_Guide.pdf 第 6 章（Tcl 命令）
#   `cdt_dbg.exe` 支持的命令表可用 Tcl 的 `info commands` 列出（含 dbg_fla_* 系列）。
#
# 两种模式：
#   -Mode discover  只连上、扫链、导入 FIC、列出 DebugCore 的通道名与采样设置。
#                   **第一次必须先跑这个**：dbg_fla_* 的 -channel 名字要连上才知道，
#                   凭空写通道名一定会失败。
#   -Mode capture   按 -TrigExpr 设触发、跑一次、导出波形到 -OutFile。
#
# 【踩过的坑 1】不要用 Start-Job 包 cdt_dbg/cdt_cfg：
#   非交互作业里拿不到它们的输出，会一直等到超时（scripts\program_board.ps1 里有同样记录）。
#   这里统一用 Start-Process + 重定向到文件 + 轮询成功标志。
#
# 【踩过的坑 2】cdt_dbg 失败/超时后**不会自己退出**，残留进程会占着下载线，
#   下一次运行就会报 "E: No cable was found in system."。
#   所以本脚本每次开头都先清掉残留的 cdt_dbg 进程。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pdsBin=Join-Path $PdsRoot 'bin'
$dbgExe=Join-Path $pdsBin 'cdt_dbg.exe'
$jsExe =Join-Path $pdsBin 'cdt_js.exe'
if(!(Test-Path -LiteralPath $dbgExe)){throw "cdt_dbg.exe not found: $dbgExe"}
$work=Join-Path $repo 'tmp/ila'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$outFile=Join-Path $work "ila_$Mode.out"
$errFile=Join-Path $work "ila_$Mode.err"
$tclFile=Join-Path $work "ila_$Mode.tcl"
$waveFile=Join-Path $work 'trap_wave.txt'
$waveTcl=$waveFile.Replace('\','/')

# ---- 0) 清掉会占线的残留进程 ----
Get-Process cdt_dbg -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "CLEANUP stale cdt_dbg PID $($_.Id) (残留进程会占住下载线，导致下一步报 No cable)"
  Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 2

# ---- 1) 确保 JTAG 服务在跑 ----
$listening = netstat -ano | Select-String ":$JsPort\s+.*LISTENING"
if(!$listening){
  Write-Host "启动 JTAG 服务 cdt_js.exe (port $JsPort) ..."
  Start-Process -FilePath $jsExe -ArgumentList '-work_dir',$work,'-port',"$JsPort"
  $deadline=(Get-Date).AddSeconds(25)
  do{ Start-Sleep -Milliseconds 500; $listening=netstat -ano|Select-String ":$JsPort\s+.*LISTENING" }while(!$listening -and (Get-Date) -lt $deadline)
  if(!$listening){throw "JTAG 服务未在 $JsPort 监听"}
}

# ---- 2) 组装 Tcl ----
$lines=New-Object System.Collections.Generic.List[string]
$lines.Add("dbg_connect -ip 127.0.0.1 -port $JsPort")
$lines.Add("dbg_scan_chain")
if(!$NoProgram -and $Bitstream){
  $bit=$Bitstream.Replace('\','/')
  $lines.Add("dbg_program -device 0 -file {$bit}")
}
# 【重要】默认必须导入**本工程自己的** FIC：
#   FIC 里带的是探针通道映射（`Project.unit<0>.triggerChannel...`），
#   导错工程（例如 coremark_ila 的）会让通道名全错、触发也设不上。
#   本工程的 FIC 由 PDS 在工程根目录生成：fpga/timer_demo_ila/mes50hp_timer_demo_top.fic
if(!$FicFile){
  $cand=Join-Path $repo 'fpga/timer_demo_ila/mes50hp_timer_demo_top.fic'
  if(Test-Path -LiteralPath $cand){ $FicFile=$cand; Write-Host "FIC (default) $cand" }
}
if($FicFile){
  $fic=(Resolve-Path -LiteralPath $FicFile).Path.Replace('\','/')
  $lines.Add("dbg_import_fic -device 0 -file {$fic}")
}
# 【为什么默认不做 dbg_fla_power_init】（2026-09-30 实测定位）
#   本工程复用的 DebugCore IP 里 `INIT_ENABLE = false`（.ipc 第 53 行；
#   coremark_ila.v: `localparam INIT_ENABLE = 0;`），也就是**没有开 power-on init data**，
#   所以 `dbg_fla_power_init` 必然报：
#       W: Current core stays in reset status or died: ... 3. check the capture power on init data is enabled.
#       E: Debugger-0006: Command get_power_on_init_data exec unsuccessfully.
#   **而且手册写明**：Tcl 脚本里一条命令失败后，后续命令**不会**继续执行，
#   必须先 `clean` 清掉 Tcl 解释器的错误计数 —— 所以这一步失败会把后面的
#   配置/触发/导出**全部静默跳过**（现象就是"什么都没发生"）。
#   因此默认跳过它；需要时用 `-DoPowerInit` 打开，且后面一律补 `clean` 兜底。
if($DoPowerInit){
  $lines.Add("dbg_fla_power_init -device 0 -fla $DebugCore")
  $lines.Add("clean")
} else {
  $lines.Add("# dbg_fla_power_init skipped: this DebugCore IP has INIT_ENABLE=false")
}
$lines.Add("dbg_fla_get_bus -device 0 -fla $DebugCore")
$lines.Add("clean")
if($Mode -eq 'capture'){
  # 采样设置：单窗口 + 512 点（与 DebugCore IP 的配置一致）
  $lines.Add("dbg_fla_set_capture -device 0 -fla $DebugCore -type W -windows 1 -position 256")
  # ---- 触发单元：这次抓的就是"Trap 进入"那一位的上升沿 ----
  # 默认值是**按文档语义算出来的**，不是猜的：
  #   Trigger Unit = Trigger Port，本 IP 只有一个 192 位端口 ⇒ TU0；
  #   Binary 进制里 R 表示上升沿、X 表示不关心；
  #   bit0 = ila_event_trap（见 fpga/timer_demo_ila/mes50hp_timer_demo_top.fic 的
  #   Project.unit<0>.triggerChannel<0><0>），Value 串 MSB 在前 ⇒ bit0 在最后一位。
  if(!$TrigValue){ $TrigValue = ('X' * 191) + 'R' }
  # 【不要写成 `-value { $TrigValue }`！】（2026-09-30 实测踩坑）
  #   花括号会**原样保留里面的首尾空格**，于是值串变成 " XXX…R "，
  #   工具直接拒收：
  #       E: The value of trigger unit is illegal or out of range...
  #   实测：同一个 192 位 X/R 串，裸传（`-value $TrigValue`）**被接受**，
  #   套上 `{ ... }`（带空格）**被拒**。长度扫描也证明 192 位本身合法
  #   （128/136/160/176/192 全部 ACCEPTED）。
  $lines.Add("dbg_fla_set_trig_unit -device 0 -fla $DebugCore -unit $TrigUnit -func $TrigFunc -radix $TrigRadix -value $TrigValue")
  # 触发条件表达式：默认 TU0（即"上面那个单元满足"）。花括号按文档写，但**不留空格**。
  $lines.Add("dbg_fla_set_trig_cond -device 0 -fla $DebugCore -add trig_trap -active trig_trap -select trig_trap -set {$TrigExpr}")
  $lines.Add("dbg_fla_run -device 0 -fla $DebugCore")
  $lines.Add("dbg_delay -time 8000")
  $lines.Add("dbg_fla_stop -device 0 -fla $DebugCore")
  $wl = if($WaveName){ " -wave_name { $WaveName }" } else { '' }
  # 官方文档（Fabric_Debugger_User_Guide 第 5 章「[Export sample data]」）写明
  # 导出支持 **ASCII / VCD / TXT** 三种。这里**两种都导**：
  #   .vcd —— 标准波形格式，可直接用 GTKWave 打开（相当于可复现的"波形截图"），
  #           也能被脚本机械解析、与 fpga/timer_demo_ila/golden_trace.txt 的判据比对；
  #   .txt —— 便于人工快速查看与贴进材料。
  $waveVcd = $waveFile -replace '\.txt$','.vcd'
  $waveVcdTcl = $waveVcd.Replace('\','/')
  $lines.Add("dbg_fla_export_wf_data -device 0 -fla $DebugCore -file {$waveVcdTcl} -format vcd$wl")
  $lines.Add("dbg_fla_export_wf_data -device 0 -fla $DebugCore -file {$waveTcl} -format txt$wl")
}
$lines.Add("dbg_disconnect")
$lines.Add("dbg_close")
$lines | Set-Content -LiteralPath $tclFile -Encoding ascii
Write-Host "TCL $tclFile"

# ---- 3) 跑，并在看到终止标志或超时后收工 ----
Remove-Item -LiteralPath $outFile,$errFile -ErrorAction SilentlyContinue
$proc=Start-Process -FilePath $dbgExe -ArgumentList @('-file',$tclFile,'-work_dir',$work) -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$deadline=(Get-Date).AddSeconds($TimeoutSeconds)
$doneMarker = if($Mode -eq 'capture'){ 'dbg_fla_export_wf_data .* successfully' } else { 'dbg_fla_get_bus .* successfully' }
while((Get-Date) -lt $deadline){
  Start-Sleep -Seconds 4
  if($proc.HasExited){ break }
  $t=(Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue)
  if($t -match $doneMarker){ Start-Sleep -Seconds 6; break }
  if($t -match 'Debugger-0006|No cable was found'){ Start-Sleep -Seconds 3; break }
}
if(!$proc.HasExited){ try{$proc.Kill()}catch{} }
$text=(Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue)+(Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
$text | Set-Content -LiteralPath (Join-Path $work "ila_$Mode.log") -Encoding UTF8
$text

if($text -match 'No cable was found'){
  throw ('下载线未枚举到（Cable List 为空）。这是物理层问题，不是脚本问题：' +
         '请重新插拔 Pango USB 下载线/确认板子已上电，然后重跑。' +
         '排查依据见 docs/handoff_next.md 与 docs/progress.md 的 N2 记录。')
}
if($text -match 'Debugger-0006'){ throw 'Fabric Debugger 报错（见上面输出）' }

if($Mode -eq 'capture'){
  if(!(Test-Path -LiteralPath $waveFile)){ throw "波形文件未生成: $waveFile" }
  $len=(Get-Item -LiteralPath $waveFile).Length
  Write-Host "WAVEFORM $waveFile ($len bytes)"
  Write-Host "WAVEFORM_SHA256 $((Get-FileHash -LiteralPath $waveFile -Algorithm SHA256).Hash)"
  if($len -lt 100){ throw '波形文件过小，可能是空抓取' }
  Write-Host 'N2 ILA TRAP CAPTURE PASS'
} else {
  Write-Host 'N2 ILA DISCOVER PASS (把上面 dbg_fla_get_bus 列出的通道名记下来，再跑 -Mode capture)'
}
