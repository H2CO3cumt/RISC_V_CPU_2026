param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = ''
)
# 构建 85 MHz PLL 版 CoreMark 计分位流（fpga/coremark_85m）。
#
# 目的：给赛题"时钟频率：满足时钟约束前提下的最高工作频率"提供一个**板级实测**的
# CoreMark 分数点，而不是只报 PDS 估算的 Fmax。
# 与 80 MHz 版的唯一设计差别：pll_85m.v 的 STATIC_RATIOF 16 -> 17（VCO 850 MHz），
# ODIV0 仍 10 => 输出 85.000 MHz 精确整数频率。
#
# ⚠️ 镜像生成走 generate_coremark_85m_memory.ps1（直接写 fpga/coremark_85m/rtl），
#    绝不要用 generate_coremark_80m_memory.ps1 —— 那个会先写进 fpga/coremark/rtl/，
#    把交付的 50 MHz CoreMark 镜像覆盖掉。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'generate_coremark_85m_memory.ps1')
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

$projectDir=Join-Path $repo 'fpga/coremark_85m'
Push-Location $projectDir
try {
  $started=Get-Date
  $recipeHash=(Get-FileHash -LiteralPath 'pds_recipe.tcl' -Algorithm SHA256).Hash
  $runRecipe=Join-Path $projectDir '.pds_cm85m_run.tcl'
  Copy-Item -LiteralPath 'pds_recipe.tcl' -Destination $runRecipe -Force
  try {
    $output = & $pds -file $runRecipe -project_name coremark_85m_generated 2>&1
    $code = $LASTEXITCODE
    $output | Tee-Object 'pds_coremark85m_build.log'
    $joined = $output -join "`n"
    if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){
      throw 'coremark 85m PDS build failed; inspect pds_coremark85m_build.log'
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
  $freq=(Select-String -LiteralPath $timing.FullName -Pattern 'MHz' | Select-Object -First 3)
  foreach($f in $freq){ Write-Host ("CLOCK " + $f.Line.Trim()) }
} finally { Pop-Location }
Write-Host 'MES50HP COREMARK 85 MHz PDS BUILD PASS'
