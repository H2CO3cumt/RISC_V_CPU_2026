param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = '',
  # 交付镜像的 delta（拍）= 50 MHz 下 0.25 s。改这个数会让板上 LED 周期跟着变。
  [int]$Delta = 12500000
)
# M-24 / N1：MES50HP 板级定时器中断演示工程的 PDS 构建入口。
#
# 结构照 scripts/run_logic_analyzer_pds.ps1（同一套许可证探测、同一套"recipe 不可变"检查），
# 但**只操作 fpga/timer_demo**：不动 fpga/logic_analyzer（已交付位流）与其它工程。
$ErrorActionPreference = 'Stop'

# 1) 先重新生成**交付镜像**（真实 delta = 12_500_000）。
#    取指 BRAM 的 $readmemh 在 PDS compile 阶段读取的是 fpga/timer_demo/rtl/timer_demo_program.mem，
#    所以这一步必须在 PDS 之前完成，否则会把上一次仿真用的小 delta 打进位流。
& "$PSScriptRoot/generate_timer_demo_fpga_memory.ps1" -Delta $Delta
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$pds = Join-Path $PdsRoot 'bin/pds_shell.exe'
if (!(Test-Path -LiteralPath $pds)) { throw "PDS not found: $pds" }
if ($LicenseFile) { $env:PANGO_LICENSE_FILE = (Resolve-Path -LiteralPath $LicenseFile).Path }
if (-not $env:PANGO_LICENSE_FILE) {
  $directRoots = @($PdsRoot, (Split-Path $PdsRoot -Parent), 'D:\ToolsSoftware\pango', 'D:\Downloads')
  $nestedRoots = @((Join-Path $env:APPDATA 'pango'), (Join-Path $env:LOCALAPPDATA 'pango'))
  foreach ($root in $directRoots) {
    if (Test-Path -LiteralPath $root) {
      $found = Get-ChildItem -LiteralPath $root -File -Include 'PDS-*.lic', 'pango*.lic', '*.pango.lic', 'new_pds_*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) { $env:PANGO_LICENSE_FILE = $found.FullName; break }
    }
  }
  if (-not $env:PANGO_LICENSE_FILE) {
    foreach ($root in $nestedRoots) {
      if (Test-Path -LiteralPath $root) {
        $found = Get-ChildItem -LiteralPath $root -Recurse -File -Include 'PDS-*.lic', 'pango*.lic', '*.pango.lic', 'new_pds_*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $env:PANGO_LICENSE_FILE = $found.FullName; break }
      }
    }
  }
}
if (-not $env:PANGO_LICENSE_FILE) { Write-Warning 'PANGO_LICENSE_FILE is unset and no standard Pango license path was discovered; PDS will report Flow-0183.' }

$projectDir = (Resolve-Path (Join-Path $PSScriptRoot '../fpga/timer_demo')).Path
Push-Location $projectDir
try {
  $started = Get-Date
  $recipeHash = (Get-FileHash -LiteralPath pds_recipe.tcl -Algorithm SHA256).Hash
  $runRecipe = Join-Path $projectDir '.pds_timer_demo_run.tcl'
  Copy-Item -LiteralPath pds_recipe.tcl -Destination $runRecipe -Force
  try {
    $output = & $pds -file $runRecipe -project_name timer_demo_generated 2>&1
    $code = $LASTEXITCODE
    $output | Tee-Object pds_timer_demo_build.log
    $joined = $output -join "`n"
    if ($code -ne 0 -or $joined -match 'Flow-0183|license failed|Check license failed|Executing .* failed|ERROR:') {
      throw 'Timer demo PDS build failed; inspect pds_timer_demo_build.log'
    }
  } finally {
    if (Test-Path -LiteralPath $runRecipe) { Remove-Item -LiteralPath $runRecipe -Force }
    # PDS 位流脚本会在构建后删除自己生成的 impl.tcl（git 里表现为"删除"，属正常）。
    if (Test-Path -LiteralPath (Join-Path $projectDir 'impl.tcl')) { Remove-Item -LiteralPath (Join-Path $projectDir 'impl.tcl') -Force }
  }

  # 时序结论必须从**本次构建**的报告里取，不能引用别的工程/别的批次。
  $timing = Get-ChildItem -Recurse -File -Include '*.rtr' | Where-Object LastWriteTime -ge $started |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $bit = Get-ChildItem -Recurse -File -Filter '*.sbit' | Where-Object LastWriteTime -ge $started |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $bit) { throw 'PDS reported success but no fresh .sbit was generated' }
  if (-not $timing) { throw 'PDS reported success but no fresh timing report was generated' }
  if ((Get-FileHash -LiteralPath pds_recipe.tcl -Algorithm SHA256).Hash -ne $recipeHash) {
    throw 'PDS modified the immutable source recipe pds_recipe.tcl'
  }

  $met = Select-String -LiteralPath $timing.FullName -Pattern 'All Constraints Met' -Quiet
  Write-Host "TIMING_REPORT $($timing.FullName)"
  Write-Host "ALL_CONSTRAINTS_MET $met"
  Write-Host "BITSTREAM $($bit.FullName) ($($bit.Length) bytes)"
  Write-Host "BITSTREAM_SHA256 $((Get-FileHash -LiteralPath $bit.FullName -Algorithm SHA256).Hash)"
  if (-not $met) { throw "Timer demo timing not met; see $($timing.FullName)" }
} finally { Pop-Location }
Write-Host 'MES50HP TIMER DEMO PDS BUILD PASS'
