param(
  [string]$Port,
  [switch]$SkipPds
)
# Read-only preflight for the live demo: bitstream hashes, serial ports, host
# tooling, GTKWave, PDS programmers and the demo material files. It never
# downloads, never opens the serial port, so it is safe to rerun on stage.
# NOTE: ASCII-only on purpose - Windows PowerShell 5.1 reads .ps1 as ANSI.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$script:fail = 0
$script:warn = 0
function Report([string]$Name, [string]$State, [string]$Detail) {
  if ($State -eq 'FAIL') { $script:fail++ }
  if ($State -eq 'WARN') { $script:warn++ }
  '{0,-4} {1,-22} {2}' -f $State, $Name, $Detail
}

# Hashes are the ones measured on the delivered bitstreams; a mismatch means
# the file on this machine is not the version the demo numbers were recorded on.
# Refreshed 2026-09-30; source of truth for every demo number is
# release/evidence/claims_map.md. If a bitstream is rebuilt on purpose, update
# BOTH the hash here and the matching row in claims_map.md, or the on-stage
# preflight will stop the demo for the wrong reason.
$bitstreams = [ordered]@{
  # DELIVERY (2026-10-14)：在上一版（85 MHz PLL + 镜像抓取）基础上加入
  #   ① M 扩展（RV32IM，rtl/mdu.v 三段流水乘法 + 32 拍迭代除法）
  #   ② 采集源双源可选（MMIO 寄存器 18；J8 外部 / Core 内部观测点，0xA8 命令）
  #   ③ 采集源选择结果寄存一拍再进采集引擎（否则 spi 模式的全速采样路径余量不足，
  #      实测固件会永久卡死——与 09-30 在 90 MHz 上记录的症状一致）
  #   ④ 探针在板级顶层打一拍，切断"Core 事件逻辑 → 采集使能"的长组合路径
  # Previous hashes: 8908FD8C (10-12 build), 788F1CEB (10-03 baseline),
  #                  F7DFD321 (09-30 build), D991FE00/74707E2B (abandoned A6 segmented firmware).
  'la85 DELIVERY' = @{ Path = 'fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'; Sha = 'C017ED10195502739BEBF914DD3BC6F3CAA84C0EAEB6E9E97559248B003FAA4F' }
  # Verified fallback: the 50 MHz build, shipped alongside (roadmap Task 35 requires a fallback).
  # 2026-10-14 与 la85 用同一份源码重建（M 扩展 + 双源可选），板级 5 模式 ×1 冒烟复测 PASS。
  # Previous hash: FDDF038C（10-10 基线）。
  'la50 fallback' = @{ Path = 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit';      Sha = '8102634A23ACB68BF9EDA4110E48A3ECFE28186A4E76D0C5717856903986B012' }
  'la80 pll'      = @{ Path = 'fpga/logic_analyzer_80m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'; Sha = '0388100A6D4714027E98ADCA17512FE9C64318870D3559AC15F123860A3E8E2E' }
  'cm50 coremark' = @{ Path = 'fpga/coremark/generate_bitstream/mes50hp_coremark_top.sbit';                    Sha = 'DC95F9D087B7E29BB8780A46179FDE8D754563BB018B4E973FD08103232F5675' }
  'cm80 coremark' = @{ Path = 'fpga/coremark_80m/generate_bitstream/mes50hp_coremark_pll_top.sbit';            Sha = 'F0743756903BD5576BDBBC8A08C17CEAE1643A4BC3CA3F560CBAB75315359A75' }
  'cm85 coremark' = @{ Path = 'fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit';            Sha = '751C692B8780E3F05BD6D86E8E0F8BA34A83AFE899E5DA86FE7474C49CA970E9' }
  # RV32IM 计分配置（2026-10-14 新增）：与 cm50 同一份 RTL/程序，只换 -march=rv32im，
  # 2000 次迭代，板级 Score 113.642 / CoreMark/MHz 2.272（官方 CRC 全过）。
  'cmim coremark' = @{ Path = 'fpga/coremark_im/generate_bitstream/mes50hp_coremark_top.sbit';                 Sha = 'BE7A4FF31F2214AC12D230B4B48079B80C4A17A33C72F106ABAB407FD57D6F36' }
  # RV32IM + 交付时钟 85 MHz（2026-10-14 新增）：工程取自 cm85、只换 -march=rv32im + 4000 迭代，
  # 板级 Score 193.192 / CoreMark/MHz 2.272（官方 CRC 全过），All Constraints Met（WNS +0.250 ns）。
  'cmim85 coremark' = @{ Path = 'fpga/coremark_im_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit';       Sha = 'EE8B65360B0B07189C66460D813A6CC990FE87BE156AEA5BC7779B5D3C68D6F1' }
  # 同一份源码重建的 RV32I 同源对照点（85 MHz）：Score 79.587、ticks 与 09-30 归档位流逐位相同，
  # 资源/时序与 cmim85 逐项相同（4198 LUT / 3361 FF / WNS +0.250 ns）⇒ CoreMark/LUT 可同源比较。
  'cm85r coremark' = @{ Path = 'fpga/coremark_85m_r/generate_bitstream/mes50hp_coremark_pll_top.sbit';          Sha = 'EC71AFDD427720129EA7A91DEADC1B9FE6620262D7CD51CE072E980D3F1C3CB5' }
  'ila debugcore' = @{ Path = 'fpga/coremark_ila/generate_bitstream/mes50hp_coremark_top.sbit';                Sha = 'B6507CF177BAC2DF46EB3BCB0FB1E555207714561D6C725E614C3B20304BEDE2' }
}
foreach ($name in $bitstreams.Keys) {
  $full = Join-Path $repo $bitstreams[$name].Path
  if (-not (Test-Path -LiteralPath $full)) { Report $name FAIL 'missing bitstream'; continue }
  $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  if ($hash -ne $bitstreams[$name].Sha) { Report $name FAIL "SHA256 mismatch: $($hash.Substring(0,16))..." }
  else { Report $name OK "sha256=$($hash.Substring(0,16))..." }
}

$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$pyVersion = ''
try { $pyVersion = (& $python --version 2>&1) -join ' ' } catch { }
if ($pyVersion) {
  Report 'python' OK $pyVersion
  $serial = (& $python -c "import serial;print(serial.VERSION)" 2>&1) -join ' '
  if ($LASTEXITCODE -eq 0) { Report 'pyserial' OK "v$serial" } else { Report 'pyserial' FAIL 'pip install pyserial' }
} else {
  Report 'python' FAIL 'python not runnable'
}

$gtkwave = (Get-Command gtkwave -ErrorAction SilentlyContinue).Source
if (-not $gtkwave) {
  foreach ($candidate in @('D:\oss-cad-suite\bin\gtkwave.exe', 'D:\Tools\gtkwave\bin\gtkwave.exe')) {
    if (Test-Path -LiteralPath $candidate) { $gtkwave = $candidate; break }
  }
}
if ($gtkwave) { Report 'gtkwave' OK $gtkwave } else { Report 'gtkwave' WARN 'not found; waveform display unavailable' }

if (-not $SkipPds) {
  foreach ($tool in @('cdt_cfg.exe', 'cdt_dbg.exe')) {
    $full = Join-Path 'D:\Pango\PDS_2024.2-SP2\bin' $tool
    if (Test-Path -LiteralPath $full) { Report $tool OK $full } else { Report $tool FAIL 'PDS bin missing' }
  }
}

$ports = @()
try { $ports = [System.IO.Ports.SerialPort]::GetPortNames() } catch { }
if ($ports.Count -eq 0) {
  Report 'serial ports' WARN 'none enumerated; connect the CP2102 USB data cable'
} else {
  Report 'serial ports' OK ($ports -join ', ')
  if ($Port) {
    if ($ports -contains $Port) { Report "target $Port" OK 'present' } else { Report "target $Port" FAIL 'not enumerated' }
  } else {
    Report 'target port' WARN 'pass -Port COMx to pin the demo port'
  }
}

# NOTE: the demo capture entry point is scripts/logic_analyzer_capture.ps1
# (an earlier name, show_capture.ps1, is a compatibility shim - keep it listed
# only if it still exists, so a future rename cannot silently pass this check).
$needed = @(
  'scripts/program_board.ps1',
  'scripts/logic_analyzer_capture.ps1',
  'scripts/run_logic_analyzer_board.ps1',
  'scripts/run_coremark_board.ps1',
  'python/mes50hp_validation_ui.py',
  'python/waveform_viewer.html',
  'python/logic_analyzer_serial.py',
  'python/logic_analyzer.py',
  'python/coremark_serial.py',
  'release/materials/live_demo_script.md',
  'release/materials/field_recovery_card.md',
  'release/evidence/ila_coremark/README.md'
)
if (Test-Path -LiteralPath (Join-Path $repo 'scripts/show_capture.ps1')) {
  $needed += 'scripts/show_capture.ps1'
}
$missing = @()
foreach ($rel in $needed) { if (-not (Test-Path -LiteralPath (Join-Path $repo $rel))) { $missing += $rel } }
if ($missing.Count -eq 0) { Report 'demo files' OK "$($needed.Count) entries present" }
else { Report 'demo files' FAIL ("missing: " + ($missing -join ', ')) }

foreach ($dir in @('logic_analyzer_board_cpi50m', 'logic_analyzer_board_cpi80m', 'ila_coremark', 'coremark_uart_cpi50m.log')) {
  $full = Join-Path $repo "release/evidence/$dir"
  if (Test-Path -LiteralPath $full) {
    if ((Get-Item -LiteralPath $full).PSIsContainer) {
      $count = (Get-ChildItem -LiteralPath $full -Recurse -File | Measure-Object).Count
      Report "evidence $dir" OK "$count files"
    } else {
      Report "evidence $dir" OK "$((Get-Item -LiteralPath $full).Length) bytes"
    }
  } else { Report "evidence $dir" WARN 'missing' }
}

Write-Host ''
if ($script:fail -eq 0) {
  Write-Host "DEMO PREFLIGHT PASS warnings=$($script:warn)"
  exit 0
}
Write-Host "DEMO PREFLIGHT FAIL failures=$($script:fail) warnings=$($script:warn)"
exit 1
