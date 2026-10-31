param(
  [int]$Iterations = 2500,
  [int]$ClockHz = 95000000,
  [int]$AutoStart = 0,
  [int]$PerfWindowAlign = 0,
  [string]$ProjectDir = 'fpga/coremark_95m'
)
# 生成 95 MHz CoreMark 板级程序镜像。
#
# 【与 generate_coremark_80m_memory.ps1 的关键区别 —— 别照抄那个】
# 80m 版本先把它自己的镜像写进 **fpga/coremark/rtl/**（50 MHz 交付工程），再拷到 80m 目录。
# 那意味着用 -ClockHz 95000000 调它，会**把交付的 50 MHz CoreMark 镜像覆盖掉**。
# 本脚本直接把 -OutputFile / -MemoryDirectory 指向 fpga/coremark_95m/rtl，
# 全程不碰 fpga/coremark/rtl/。
#
# 参数与 80 MHz 点保持一致（ITERATIONS=2500、AUTOSTART=0 等串口 'R'、
# PERF_WINDOW_ALIGN 跟随调用方），唯一的差别是 CLOCK_HZ=85_000_000，
# 它只影响固件里 COREMARK_CLOCK_HZ（用于 CoreMark 自报的 Total time）。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try{
  $dst=Join-Path $ProjectDir 'rtl'
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  & (Join-Path $PSScriptRoot 'generate_coremark_fpga_memory.ps1') `
      -Iterations $Iterations -ClockHz $ClockHz -AutoStart $AutoStart `
      -PerfWindowAlign $PerfWindowAlign `
      -OutputFile "$dst/coremark_program_memory.v" -MemoryDirectory $dst
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}

  # 仿真分支里的 $readmemh 路径要指向本工程目录（综合分支用相对 rtl/ 路径，无需改）。
  $target=Join-Path $dst 'coremark_program_memory.v'
  $text=Get-Content -LiteralPath $target -Raw
  $text=$text.Replace('fpga/coremark/rtl/','fpga/coremark_95m/rtl/')
  Set-Content -LiteralPath $target -Value $text -Encoding ascii -NoNewline

  Write-Host "COREMARK 95M MEMORY READY iterations=$Iterations clock_hz=$ClockHz dir=$dst"
}finally{Pop-Location}
