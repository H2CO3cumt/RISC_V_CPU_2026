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
  # DELIVERY (2026-10-03): 85 MHz PLL build, firmware reverted to the verified baseline
  # (the segmented-capture firmware experiment was abandoned and rolled back; the
  #  program image hash E3C3CD4A... matches the archived baseline build bit for bit).
  # Previous hashes: F7DFD321 (09-30 build), D991FE00/74707E2B (abandoned A6 firmware).
  'la85 DELIVERY' = @{ Path = 'fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'; Sha = '788F1CEB273FA626DF4581FD46B65A2D90761D9A2B393D35FCEE0C111622DCE2' }
  # Verified fallback: the 50 MHz build, shipped alongside (roadmap Task 35 requires a fallback).
  'la50 fallback' = @{ Path = 'fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit';      Sha = 'BCAE040A3B96652BB4B73907FFA03178C05453C0E9CD07E5697E401845FDD184' }
  'la80 pll'      = @{ Path = 'fpga/logic_analyzer_80m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit'; Sha = '0388100A6D4714027E98ADCA17512FE9C64318870D3559AC15F123860A3E8E2E' }
  'cm50 coremark' = @{ Path = 'fpga/coremark/generate_bitstream/mes50hp_coremark_top.sbit';                    Sha = 'DC95F9D087B7E29BB8780A46179FDE8D754563BB018B4E973FD08103232F5675' }
  'cm80 coremark' = @{ Path = 'fpga/coremark_80m/generate_bitstream/mes50hp_coremark_pll_top.sbit';            Sha = 'F0743756903BD5576BDBBC8A08C17CEAE1643A4BC3CA3F560CBAB75315359A75' }
  'cm85 coremark' = @{ Path = 'fpga/coremark_85m/generate_bitstream/mes50hp_coremark_pll_top.sbit';            Sha = '751C692B8780E3F05BD6D86E8E0F8BA34A83AFE899E5DA86FE7474C49CA970E9' }
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
