# apply_line_patches.ps1 - deterministic anchor-based line patcher.
#
# Why this exists: multi-line replacements in RTL carry long runs of alignment
# spaces. Reproducing them by hand is error-prone, and a failed exact match
# wastes a round trip. This tool matches only a SHORT anchor substring on the
# first matching line and then replaces a fixed number of whole lines.
#
# Patch file format (UTF-8, one or more blocks):
#   ### anchor: <substring that must appear on the first target line>
#   ### count: <how many existing lines to remove, 0 = pure insertion>
#   <replacement lines...>
#
# This file itself is pure ASCII on purpose so it never needs a UTF-8 BOM.
param(
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string]$Patch,
    [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Out) { $Out = $File }

$enc = New-Object System.Text.UTF8Encoding($false)
$raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).Path, [System.Text.Encoding]::UTF8)
$nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $raw -split "`r?`n"

$specs = @()
$cur = $null
foreach ($l in ([System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Patch).Path, [System.Text.Encoding]::UTF8))) {
    if ($l.StartsWith('### anchor: ')) {
        if ($cur) { $specs += $cur }
        $cur = @{ anchor = $l.Substring(11).TrimStart(); count = 0; body = New-Object System.Collections.ArrayList }
    }
    elseif ($l.StartsWith('### count: ')) {
        if (-not $cur) { throw 'count before anchor' }
        $cur.count = [int]$l.Substring(10)
    }
    elseif ($cur) {
        [void]$cur.body.Add($l)
    }
}
if ($cur) { $specs += $cur }
if ($specs.Count -eq 0) { throw 'no patch blocks found' }

foreach ($s in $specs) {
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Contains($s.anchor)) { $idx = $i; break }
    }
    if ($idx -lt 0) { throw "anchor not found: $($s.anchor)" }
    $before = @()
    if ($idx -gt 0) { $before = @($lines[0..($idx - 1)]) }
    $after = @()
    if (($idx + $s.count) -lt $lines.Count) { $after = @($lines[($idx + $s.count)..($lines.Count - 1)]) }
    $lines = $before + $s.body.ToArray() + $after
    Write-Host ("PATCH OK  -{0} +{1}  [{2}]" -f $s.count, $s.body.Count, $s.anchor)
}

[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $Out).Path, ($lines -join $nl), $enc)
Write-Host "PATCHED $Out"
