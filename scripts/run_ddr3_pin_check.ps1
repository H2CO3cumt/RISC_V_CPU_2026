param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = ''
)
# S1 前置校验：把按手册生成的 DDR3 管脚约束丢给 PDS 走 compile → synthesize → dev_map，
# 确认它能被接受**并且真的落到管脚上**。
#
# 为什么值得做：`fpga/ddr3_smoke/constraints/ddr3_pins_from_manual.fdc` 是我们自己
# 按 MES50HP 手册生成的（厂商模板 65/69 个管脚与本板不符，不能用）。在把它交给
# HMIC IP 生成器之前，先用 PDS 自己验一遍，可以把"管脚名写错/占位符写错/电平写错"
# 这类问题在**消耗任何综合时间之前**暴露出来。
#
# 安全边界（重要）：
#   - 只跑 compile + synthesize + dev_map，**不做布局布线、不出版本**；
#   - 只操作 tmp/ddr3/pin_check 这个临时工程；
#   - 不触碰 fpga/logic_analyzer、fpga/coremark、fpga/coremark_80m、fpga/timer_demo。
#   因此这个脚本不可能影响板上任何现有位流。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Write-Host '=== 1) 生成桩顶层与校验配方 ==='
& python "$repo\scripts\ddr3_pin_check_gen.py"
if($LASTEXITCODE -ne 0){ throw 'stub generation failed' }

$pds=Join-Path $PdsRoot 'bin/pds_shell.exe'
if(!(Test-Path -LiteralPath $pds)){ throw "PDS not found: $pds" }
if($LicenseFile){ $env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path }
if(-not $env:PANGO_LICENSE_FILE){
  foreach($root in @($PdsRoot,(Split-Path $PdsRoot -Parent),'D:\ToolsSoftware\pango','D:\Downloads')){
    if(Test-Path -LiteralPath $root){
      $found=Get-ChildItem -LiteralPath $root -File -Include 'PDS-*.lic','pango*.lic','*.pango.lic','new_pds_*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($found){$env:PANGO_LICENSE_FILE=$found.FullName;break}
    }
  }
}
if(-not $env:PANGO_LICENSE_FILE){ Write-Warning 'PANGO_LICENSE_FILE unset; PDS may report Flow-0183.' }

$proj=Join-Path $repo 'tmp/ddr3/pin_check'
Write-Host '=== 2) PDS: compile -> synthesize -> dev_map ==='
Push-Location $proj
try {
  $output = & $pds -file (Join-Path $proj 'pds_recipe.tcl') -project_name ddr3_pin_check 2>&1
  $code=$LASTEXITCODE
  $output | Tee-Object (Join-Path $proj 'pin_check.log')
} finally { Pop-Location }

$joined = $output -join "`n"
$errs   = ([regex]::Matches($joined, '(?m)^E: ')).Count
$crit   = ([regex]::Matches($joined, 'critical warning')).Count
# dev_map 的利用率表里 IO 那一行给出实际落地的管脚数
$ioLine = ($output | Select-String -Pattern '^\|\s*IO\s*\|\s*(\d+)\s*\|' | Select-Object -First 1)
$ioUsed = if($ioLine){ [int]$ioLine.Matches[0].Groups[1].Value } else { -1 }

Write-Host ''
Write-Host "PDS exit code      : $code"
Write-Host "E: 行数            : $errs"
Write-Host "落地的 IO 管脚数   : $ioUsed  (期望 71)"
if($errs -ne 0 -or $code -ne 0){ throw "DDR3 pin check FAILED (E=$errs, exit=$code); see $proj\pin_check.log" }
if($ioUsed -ne 71){ throw "DDR3 pin check FAILED: 只有 $ioUsed 个 IO 落地，期望 71" }
Write-Host 'DDR3 PIN CONSTRAINT CHECK PASS（71 个管脚全部被 PDS 接受并落到管脚上）'
