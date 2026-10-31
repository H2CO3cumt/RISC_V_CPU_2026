param(
  [string]$PdsRoot = $(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),
  [string]$LicenseFile = $(if($env:PANGO_LICENSE_FILE){$env:PANGO_LICENSE_FILE}else{'D:\Downloads\new_pds_60452e195a32.lic'})
)
# M-24 / N2：构建"Trap 进入/返回"板级 ILA 诊断位流。
#
# 与 scripts\run_coremark_ila_pds.ps1 的区别：
#   1) 顶层换成 fpga/timer_demo 的定时器中断演示（它每 250 ms 产生一次 Trap）；
#   2) **不重新生成 DebugCore IP**，直接复用 fpga/coremark_ila 里已经生成好的那份
#      （同一个"单一 192 位探针 / 50 MHz / 512 采样"配置），避免两份 IP 配置漂移。
#   3) 只加了一个 PDS_TIMER_DEMO_ILA 宏，N1 交付位流不受影响。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project=Join-Path $repo 'fpga/timer_demo_ila'
$srcProg=Join-Path $repo 'fpga/timer_demo'
$pds=Join-Path $PdsRoot 'bin/pds_shell.exe'
if(!(Test-Path -LiteralPath $pds)){throw "PDS shell not found: $pds"}
if(!(Test-Path -LiteralPath $LicenseFile)){throw "PDS license not found: $LicenseFile"}
$env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path

# 1) 复用的 DebugCore IP 必须在位
$ipFiles=@(
  'ip/coremark_ila/coremark_ila.v','ip/coremark_ila/coremark_ila.ipc',
  'ip/coremark_jtag_hub/coremark_jtag_hub.v','ip/coremark_jtag_hub/coremark_jtag_hub.ipc'
)
foreach($f in $ipFiles){
  $p=Join-Path $repo "fpga/coremark_ila/$f"
  if(!(Test-Path -LiteralPath $p)){throw "Reused DebugCore IP file missing: $p (先跑 scripts\run_coremark_ila_pds.ps1 生成 IP)"}
}

# 2) 程序镜像：从 fpga/timer_demo 复制，保证与 N1 位流用的是**同一份**镜像、不会漂移。
#    为什么必须复制到本工程的 rtl/ 下：timer_demo_program_memory.v 里
#    $readmemh 走的是相对 PDS 工作目录的 'rtl/timer_demo_program.mem'。
$progSrc=Join-Path $srcProg 'rtl/timer_demo_program.mem'
if(!(Test-Path -LiteralPath $progSrc)){throw "程序镜像缺失: $progSrc（先跑 scripts\generate_timer_demo_fpga_memory.ps1）"}
New-Item -ItemType Directory -Force -Path (Join-Path $project 'rtl') | Out-Null
Copy-Item -LiteralPath $progSrc -Destination (Join-Path $project 'rtl/timer_demo_program.mem') -Force
$progHash=(Get-FileHash -LiteralPath $progSrc -Algorithm SHA256).Hash
Write-Host "PROGRAM_MEM $progSrc"
Write-Host "PROGRAM_MEM_SHA256 $progHash"

# 3) PDS 全流程
Push-Location $project
try{
  $started=Get-Date
  $output=& $pds -file pds_recipe.tcl -project_name timer_demo_ila 2>&1
  $code=$LASTEXITCODE
  $output|Tee-Object pds_build.log
  $joined=$output -join "`n"
  if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){throw 'timer_demo_ila DebugCore PDS build failed; inspect pds_build.log'}
  $bit=Get-ChildItem -Recurse -File -Filter '*.sbit'|Where-Object LastWriteTime -ge $started|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  $timing=Get-ChildItem -Recurse -File -Include '*.rtr','*timing*.rpt'|Where-Object LastWriteTime -ge $started|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  if(-not $bit -or -not $timing){throw 'build completed without fresh bitstream/timing report'}
  Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)"
  Write-Host "BITSTREAM_SHA256 $((Get-FileHash -LiteralPath $bit.FullName -Algorithm SHA256).Hash)"
  Write-Host "TIMING_REPORT $($timing.FullName)"
  # 时序是否收敛：与其它构建脚本一致，出现违例就报出来
  $viol=& findstr /i /c:"violation" /c:"not met" "$($timing.FullName)" 2>$null
  if($viol){ Write-Host "TIMING_NOTE (inspect below)"; $viol | Select-Object -First 8 } else { Write-Host "TIMING CONSISTENT (no violation lines found)" }
}finally{Pop-Location}
Write-Host 'MES50HP TIMER DEMO ILA PDS BUILD PASS'
