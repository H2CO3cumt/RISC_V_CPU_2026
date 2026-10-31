param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = '',
  [int]$Iterations = 4000,
  [int]$ClockHz = 85000000
)
# 构建 **RV32IM + 85 MHz PLL** 的 CoreMark 计分位流（fpga/coremark_im_85m）。
#
# 为什么要有这一颗：`fpga/coremark_im`（RV32IM）只有 50 MHz 一点——
# 它的 .fdc 是 `create_clock clk_50m -period 20.000`，而 80/85/90 MHz 的计分工程
# 都建在 M 扩展之前、从未用新 RTL 重建。Score 虽然被频率归一化（CoreMark/MHz 不变），
# 但"与交付位流同频（85 MHz）的原始 Score"这一栏此前只有 rv32i 的 cm85 有。
#
# 做法：源文件取自 fpga/coremark_85m（同一颗 pll_85m + 同一个顶层），
# 只把程序镜像换成 **-march=rv32im** 的（4000 迭代）。
#   4000 迭代的理由：85 MHz 下每迭代约 439,975 拍 ⇒ 4000 次 ≈ 20.7 s。
#   2000 次只有约 10.35 s，正好卡在赛题"不低于 10 秒"的红线上，不留余量。
#   上限还有一条：CoreMark 的时钟读的是计数器低 32 位，85 MHz 下 2^32 拍 = 50.5 s，
#   20.7 s 远在安全区内。
#
# ⚠️ 镜像生成会 `make clean` + `make`，同一时刻只能有一个 CoreMark 构建；
#    必须把 OutputFile / MemoryDirectory / SimDirectory 全部指到本工程，
#    否则会覆盖 fpga/coremark（rv32i 交付镜像）。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'generate_coremark_fpga_memory.ps1') `
  -Iterations $Iterations -ClockHz $ClockHz -March 'rv32im' `
  -OutputFile 'fpga/coremark_im_85m/rtl/coremark_program_memory.v' `
  -MemoryDirectory 'fpga/coremark_im_85m/rtl' `
  -SimDirectory 'fpga/coremark_im_85m/rtl'
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }

$pds=Join-Path $PdsRoot 'bin/pds_shell.exe'
if(-not (Test-Path -LiteralPath $pds)){ throw "PDS not found: $pds" }
if($LicenseFile){ $env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path }
if(-not $env:PANGO_LICENSE_FILE){
  foreach($cand in @('D:\Downloads\new_pds_60452e195a32.lic')){
    if(Test-Path -LiteralPath $cand){ $env:PANGO_LICENSE_FILE=$cand; break }
  }
}
if(-not $env:PANGO_LICENSE_FILE){ Write-Warning 'PANGO_LICENSE_FILE 未设置，PDS 会报 Flow-0183' }
else { Write-Host "LICENSE $env:PANGO_LICENSE_FILE" }

$projectDir=Join-Path $repo 'fpga/coremark_im_85m'
Push-Location $projectDir
try {
  $started=Get-Date
  $recipeHash=(Get-FileHash -LiteralPath 'pds_recipe.tcl' -Algorithm SHA256).Hash
  $runRecipe=Join-Path $projectDir '.pds_cmim85_run.tcl'
  Copy-Item -LiteralPath 'pds_recipe.tcl' -Destination $runRecipe -Force
  try {
    $output = & $pds -file $runRecipe -project_name coremark_im_85m_generated 2>&1
    $code = $LASTEXITCODE
    $output | Tee-Object 'pds_coremark_im_85m_build.log'
    $joined = $output -join "`n"
    if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){
      throw 'coremark_im_85m PDS build failed; inspect pds_coremark_im_85m_build.log'
    }
  } finally {
    if(Test-Path -LiteralPath $runRecipe){ Remove-Item -LiteralPath $runRecipe -Force }
    if(Test-Path -LiteralPath (Join-Path $projectDir 'impl.tcl')){ Remove-Item -LiteralPath (Join-Path $projectDir 'impl.tcl') -Force }
  }
  if((Get-FileHash -LiteralPath 'pds_recipe.tcl' -Algorithm SHA256).Hash -ne $recipeHash){ throw 'PDS 修改了应当只读的 pds_recipe.tcl' }

  $bit=Get-ChildItem -Recurse -File -Filter '*.sbit' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $timing=Get-ChildItem -Recurse -File -Include '*.rtr' | Where-Object LastWriteTime -ge $started | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $bit){ throw 'PDS 报成功但没有新的 .sbit' }
  if(-not $timing){ throw 'PDS 报成功但没有新的时序报告' }

  Write-Host ''
  Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)"
  Write-Host "SHA256    $((Get-FileHash -LiteralPath $bit.FullName -Algorithm SHA256).Hash)"
  Write-Host "TIMING    $($timing.FullName)"
  $ds=(Select-String -LiteralPath $timing.FullName -Pattern 'Design Summary' | Select-Object -First 1).Line
  if($ds){ Write-Host "TIMING_SUMMARY $($ds.Trim())" }
  foreach($f in (Select-String -LiteralPath $timing.FullName -Pattern 'MHz' | Select-Object -First 3)){
    Write-Host ("CLOCK " + $f.Line.Trim())
  }
  # 资源（布局布线后）：CoreMark/LUT 的分母就是这里的 LUT 数
  $flowLog=Join-Path $projectDir 'flow.log'
  if(Test-Path -LiteralPath $flowLog){
    $lut=(Select-String -LiteralPath $flowLog -Pattern 'Total LUTs:' | Select-Object -Last 1).Line
    $ff =(Select-String -LiteralPath $flowLog -Pattern 'Total Registers:' | Select-Object -Last 1).Line
    if($lut){ Write-Host ("RESOURCE " + $lut.Trim()) }
    if($ff){ Write-Host ("RESOURCE " + $ff.Trim()) }
  }
} finally { Pop-Location }
Write-Host 'MES50HP COREMARK RV32IM 85MHz PDS BUILD PASS'
