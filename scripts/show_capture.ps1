param(
  [string]$Vcd,
  [string]$Evidence = 'release/evidence',
  [switch]$NoLaunch,
  [string]$GtkWave
)
# Live-demo helper: open one captured VCD in GTKWave with all eight channels
# already inserted and the time axis zoomed to fit, so showing a waveform on
# stage does not depend on clicking through the signal tree by hand.
# Without -Vcd it picks the newest .vcd under the evidence directory.
# NOTE: ASCII-only on purpose - Windows PowerShell 5.1 reads .ps1 as ANSI.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not $Vcd) {
  $root = Join-Path $repo $Evidence
  if (-not (Test-Path -LiteralPath $root)) { throw "evidence directory not found: $root" }
  $latest = Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.vcd |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) {
    throw "no .vcd under $root - capture first: python python/logic_analyzer_serial.py COMx --mode uart --runs 1"
  }
  $Vcd = $latest.FullName
}
if (-not (Test-Path -LiteralPath $Vcd)) { throw "VCD not found: $Vcd" }
$Vcd = (Resolve-Path -LiteralPath $Vcd).Path
$dir = Split-Path -Parent $Vcd
$stem = [IO.Path]::GetFileNameWithoutExtension($Vcd)

# Capture summary comes from the firmware LA RAW line, so the sample count and
# trigger index printed here are same-source as the waveform itself.
$summary = ''
$logPath = Join-Path $dir "$stem.log"
if (Test-Path -LiteralPath $logPath) {
  $text = Get-Content -LiteralPath $logPath -Raw
  if ($text -match 'LA RAW count=([0-9a-fA-F]+) trigger=([0-9a-fA-F]+)') {
    $samples = [Convert]::ToInt32($Matches[1], 16)
    $trigger = [Convert]::ToInt32($Matches[2], 16)
    $summary = "samples=$samples trigger_index=$trigger"
  }
}

# The VCD top scope is "capture" and the eight channels are capture.ch0..ch7.
$signalList = (0..7 | ForEach-Object { '"capture.ch{0}"' -f $_ }) -join ' '
$tclPath = Join-Path $dir "$stem.show.tcl"
Set-Content -LiteralPath $tclPath -Encoding ascii -Value @(
  "gtkwave::addSignalsFromList [list $signalList]",
  'gtkwave::/Time/Zoom/Zoom_Full'
)

# Which GTKWave matters. Verified 2026-10-03 on this machine:
#   D:\oss-cad-suite\bin\gtkwave.exe          v4.0.0-prealpha -> rejects -S ("unknown
#       option -- S", built without Tcl) and aborts at startup because its gdk-pixbuf
#       svg loader (libpixbufloader-svg.dll) is referenced by loaders.cache but missing.
#   D:\Tools\iverilog-v12\gtkwave\bin\...     v3.3.100        -> accepts -S, works.
# So the known-good Icarus build is tried first and the PATH lookup is only a fallback;
# overriding the OS association for .vcd is a separate, user-side decision.
$gtkwave = $GtkWave
if (-not $gtkwave) {
  foreach ($candidate in @(
    'D:\Tools\iverilog-v12\gtkwave\bin\gtkwave.exe',
    'D:\Tools\gtkwave\bin\gtkwave.exe',
    'D:\oss-cad-suite\bin\gtkwave.exe'
  )) {
    if (Test-Path -LiteralPath $candidate) { $gtkwave = $candidate; break }
  }
}
if (-not $gtkwave) { $gtkwave = (Get-Command gtkwave -ErrorAction SilentlyContinue).Source }

Write-Host "VCD      $Vcd"
if ($summary) { Write-Host "CAPTURE  $summary" }
Write-Host "TCL      $tclPath"
if ($NoLaunch) {
  if ($gtkwave) { Write-Host "GTKWAVE  $gtkwave -f `"$Vcd`" -S `"$tclPath`"" }
  else { Write-Host 'GTKWAVE  not found in PATH' }
  exit 0
}
if (-not $gtkwave) { throw 'GTKWave not found; add it to PATH or use -NoLaunch to only write the Tcl script.' }
Start-Process -FilePath $gtkwave -ArgumentList @('-f', $Vcd, '-S', $tclPath)
Write-Host 'GTKWAVE  launched: capture.ch0..ch7 inserted, zoomed to fit'
