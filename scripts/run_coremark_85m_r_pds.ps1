param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = '',
  [int]$Iterations = 2500,
  [int]$ClockHz = 85000000
)
# 构建 **RV32I + 85 MHz PLL、用当前 RTL 重建** 的 CoreMark 计分位流（fpga/coremark_85m_r）。
#
# 为什么需要这一颗（"同源对照点"）：
#   归档的 `cm85` 位流是 **2026-09-30** 打的，那时 `rtl/` 里还没有 `mdu.v`，
#   所以它的资源是 **3657 LUT / APM 0**；而 `cmim85` 是当前 RTL（**4198 LUT / APM 4**）。
#   拿这两颗去算 CoreMark/LUT（=Score÷LUT）是**跨 RTL 修订比较**，分母不是同一份实现，
#   严格讲站不住。本工程用**与 cmim85 完全相同的源码**（同一份 `rtl/`、同一颗 `pll_85m`、
#   同一个顶层），只把程序镜像换成 `-march=rv32i`，于是：
#     同一份 RTL、同一个 85 MHz 时钟、同一份 CoreMark 程序，差别只有 -march。
#   预期：Score 仍是 **79.587**（rv32i 代码不执行 M 指令，RTL 仿真已证明 rv32i 周期逐位不变），
#   但 LUT 会涨到与 cmim85 同量级 ⇒ CoreMark/LUT 的对比变成**同源**。
#
# 迭代 2500（不是 4000）：rv32i 每迭代约 1,068,007 拍，4000 次要 50.3 s，
#   而 CoreMark 的时钟读的是计数器低 32 位、85 MHz 下 2^32 拍 = 50.53 s ⇒ 会绕回。
#   2500 次 = 2.67e9 拍 ≈ 31.4 s，安全且与归档 cm85 的迭代数一致（便于逐项对照）。
#
# ⚠️ 镜像生成会 `make clean` + `make`，同一时刻只能有一个 CoreMark 构建。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'generate_coremark_fpga_memory.ps1') `
  -Iterations $Iterations -ClockHz $ClockHz -March 'rv32i' `
  -OutputFile 'fpga/coremark_85m_r/rtl/coremark_program_memory.v' `
  -MemoryDirectory 'fpga/coremark_85m_r/rtl' `
  -SimDirectory 'fpga/coremark_85m_r/rtl'
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

$projectDir=Join-Path $repo 'fpga/coremark_85m_r'
Push-Location $projectDir
try {
  $started=Get-Date
  $recipeHash=(Get-FileHash -LiteralPath 'pds_recipe.tcl' -Algorithm SHA256).Hash
  $runRecipe=Join-Path $projectDir '.pds_cm85r_run.tcl'
  Copy-Item -LiteralPath 'pds_recipe.tcl' -Destination $runRecipe -Force
  try {
    $output = & $pds -file $runRecipe -project_name coremark_85m_r_generated 2>&1
    $code = $LASTEXITCODE
    $output | Tee-Object 'pds_coremark_85m_r_build.log'
    $joined = $output -join "`n"
    if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){
      throw 'coremark_85m_r PDS build failed; inspect pds_coremark_85m_r_build.log'
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
  $flowLog=Join-Path $projectDir 'flow.log'
  if(Test-Path -LiteralPath $flowLog){
    foreach($pat in @('Total LUTs:','Total Registers:')){
      $line=(Select-String -LiteralPath $flowLog -Pattern $pat | Select-Object -Last 1).Line
      if($line){ Write-Host ("RESOURCE " + $line.Trim()) }
    }
  }
} finally { Pop-Location }
Write-Host 'MES50HP COREMARK RV32I 85MHz (CURRENT RTL) PDS BUILD PASS'
