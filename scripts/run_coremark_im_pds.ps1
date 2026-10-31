param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = '',
  [int]$Iterations = 1000,
  [int]$ClockHz = 50000000
)
# 构建 RV32IM 版 CoreMark 计分位流（fpga/coremark_im）。
#
# 目的：给"M 扩展"一个**板级实测**的 Before/After。基线是 fpga/coremark
# （同一份 RTL、同一份 TB、同一份程序，只有 -march 从 rv32i 换成 rv32im）。
#
# ⚠️ 镜像生成必须把 OutputFile / MemoryDirectory / SimDirectory 全部指到
#    fpga/coremark_im/rtl，否则会覆盖交付的 50 MHz rv32i 镜像。
#
# 需要**与交付同频（85 MHz）**的 RV32IM 计分位流时用同目录的
#    scripts\run_coremark_im_85m_pds.ps1   （工程 fpga/coremark_im_85m，同一颗 pll_85m）
# 两个频点的 CoreMark/MHz 相同（2.272），85 MHz 点只是把原始 Score 做到 193.192。
#
# NOTE: 本文件含中文，改完必须跑 scripts\ensure_ps1_bom.ps1。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'generate_coremark_fpga_memory.ps1') `
  -Iterations $Iterations -ClockHz $ClockHz -March 'rv32im' `
  -OutputFile 'fpga/coremark_im/rtl/coremark_program_memory.v' `
  -MemoryDirectory 'fpga/coremark_im/rtl' `
  -SimDirectory 'fpga/coremark_im/rtl'
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

$projectDir=Join-Path $repo 'fpga/coremark_im'
Push-Location $projectDir
try {
  $started=Get-Date
  $recipeHash=(Get-FileHash -LiteralPath 'pds_recipe.tcl' -Algorithm SHA256).Hash
  $runRecipe=Join-Path $projectDir '.pds_cmim_run.tcl'
  Copy-Item -LiteralPath 'pds_recipe.tcl' -Destination $runRecipe -Force
  try {
    $output = & $pds -file $runRecipe -project_name coremark_im_generated 2>&1
    $code = $LASTEXITCODE
    $output | Tee-Object 'pds_coremark_im_build.log'
    $joined = $output -join "`n"
    if($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:'){
      throw 'coremark_im PDS build failed; inspect pds_coremark_im_build.log'
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
Write-Host 'MES50HP COREMARK RV32IM PDS BUILD PASS'
