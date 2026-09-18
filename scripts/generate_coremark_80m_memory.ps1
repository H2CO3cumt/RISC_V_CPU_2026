param(
  [int]$Iterations = 2500,
  [int]$ClockHz = 80000000,
  [int]$AutoStart = 0,
  [int]$PerfWindowAlign = 0,
  [string]$ProjectDir = 'fpga/coremark_80m'
)
# 生成 80 MHz CoreMark 板级程序镜像。
# 复用未修改的 scripts/generate_coremark_fpga_memory.ps1（50 MHz 基线仍由它生成），
# 再把 IMEM/DROM/RAM 镜像和 coremark_program_memory.v 复制到 80 MHz 工程目录，
# 并修正 `ifdef COREMARK_SIM 分支里指向 50 MHz 工程目录的 $readmemh 绝对路径，
# 保证 RTL 仿真脚本在 80 MHz 工程上也能直接读镜像。
# -PerfWindowAlign 1：在 start_time() 里清零性能计数器，使七项计数器与 ticks 同口径。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try{
  $src="fpga/coremark/rtl"
  & (Join-Path $PSScriptRoot 'generate_coremark_fpga_memory.ps1') -Iterations $Iterations -ClockHz $ClockHz -AutoStart $AutoStart `
      -PerfWindowAlign $PerfWindowAlign `
      -OutputFile "$src/coremark_program_memory.v" -MemoryDirectory $src
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}

  $dst=Join-Path $ProjectDir 'rtl'
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  foreach($name in @('coremark_program_memory.v','coremark_imem.mem','coremark_drom.mem','coremark_ram.mem')){
    Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $dst $name) -Force
  }
  # 仿真分支路径改为本工程目录（综合分支用相对 rtl/ 路径，无需修改）。
  $target=Join-Path $dst 'coremark_program_memory.v'
  $text=Get-Content -LiteralPath $target -Raw
  $text=$text.Replace('fpga/coremark/rtl/','fpga/coremark_80m/rtl/')
  Set-Content -LiteralPath $target -Value $text -Encoding ascii -NoNewline
  Write-Host "COREMARK 80M MEMORY READY iterations=$Iterations clock_hz=$ClockHz dir=$dst"
}finally{Pop-Location}
