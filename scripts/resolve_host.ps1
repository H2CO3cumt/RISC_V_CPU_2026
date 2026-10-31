# 回归聚合脚本共用的 PowerShell 宿主解析。
#
# 为什么单独放一个文件：本机 PATH 里没有 WindowsPowerShell\v1.0（System32 下
# 并不列出该目录），而各个聚合脚本都要再起一个子宿主去跑单模块 Testbench。
# 原来每个脚本各写一遍 "Get-Command powershell -ErrorAction Stop"，一旦 PATH
# 里没有它，整个回归会在第一行就中断，且报错与真实功能无关。这里统一解析：
# 先 pwsh，再 PATH 里的 powershell，最后按固定路径兜底。解析结果放在
# $script:PowerShellHost，调用方不要另起变量名。
function Resolve-PowerShellHost {
    param([string]$ScriptRoot = $PSScriptRoot)

    $candidates = New-Object System.Collections.Generic.List[string]

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { $candidates.Add($pwsh.Source) }

    $ps5 = Get-Command powershell -ErrorAction SilentlyContinue
    if ($ps5) { $candidates.Add($ps5.Source) }

    if ($env:SystemRoot) {
        $candidates.Add((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    }
    $candidates.Add((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'))

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    throw "REGRESSION STOP: no PowerShell host found (pwsh / powershell / System32 fallback)"
}
