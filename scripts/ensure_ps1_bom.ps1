# ensure_ps1_bom.ps1 - add a UTF-8 BOM to every non-ASCII .ps1 that lost it.
# Why this exists: Windows PowerShell 5.1 decodes a BOM-less .ps1 as ANSI.
# A Chinese comment then becomes garbage bytes, and one of them can be a quote
# or brace, which produces a bogus "missing terminator" parse error far away.
# This file itself is pure ASCII on purpose, so it never needs the BOM.
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$bom = New-Object System.Text.UTF8Encoding($true)
$fixed = @()
Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' -File | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    if (($text -match '[^\u0000-\u007F]') -and (-not $hasBom)) {
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
        [System.IO.File]::WriteAllText($_.FullName, $text, $bom)
        $fixed += $_.Name
    }
}
if ($fixed.Count -eq 0) { Write-Host 'PS1 BOM CHECK PASS (nothing to fix)' }
else { Write-Host ("PS1 BOM FIXED: " + ($fixed -join ', ')) }
