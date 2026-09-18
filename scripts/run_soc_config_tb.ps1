param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
New-Item -ItemType Directory -Force -Path tmp/gcc_evidence | Out-Null

$sources = @(
    'tb/imem_adapter.v', 'tb/ram_adapter.v',
    'rtl/single_cycle_cpu.v', 'rtl/regfile.v', 'rtl/alu.v', 'rtl/imm_gen.v', 'rtl/decoder.v', 'rtl/branch_unit.v', 'rtl/load_store_unit.v',
    'rtl/soc_data_interconnect.v', 'rtl/gpio_mmio.v', 'rtl/uart_tx.v', 'rtl/uart_rx.v', 'rtl/uart_mmio.v', 'tb/tb_soc_config.v'
)

function Compare-FirstDifference([string]$Expected, [string]$Actual, [string]$Label) {
    $expectedLines = @(Get-Content -LiteralPath $Expected | Where-Object { $_ -ne '' })
    $actualLines = @(Get-Content -LiteralPath $Actual | Where-Object { $_ -ne '' })
    $max = [Math]::Max($expectedLines.Count, $actualLines.Count)
    for ($index = 0; $index -lt $max; $index++) {
        $expectedLine = if ($index -lt $expectedLines.Count) { $expectedLines[$index] } else { '<EOF>' }
        $actualLine = if ($index -lt $actualLines.Count) { $actualLines[$index] } else { '<EOF>' }
        if ($expectedLine -cne $actualLine) {
            Write-Host "${Label} FIRST DIFFERENCE: record=$index expected=[$expectedLine] actual=[$actualLine]"
            return $false
        }
    }
    Write-Host "${Label} PASS"
    return $true
}

function Compare-TraceGolden([string]$Expected, [string]$Actual, [string]$Label) {
    $fieldNames = @('index', 'pc', 'instruction', 'rd_we', 'rd', 'rd_data', 'mem_we', 'mem_addr', 'mem_data', 'mem_wstrb')
    $expectedLines = @(Get-Content -LiteralPath $Expected | Where-Object { $_ -ne '' })
    $actualLines = @(Get-Content -LiteralPath $Actual | Where-Object { $_ -ne '' })
    $max = [Math]::Max($expectedLines.Count, $actualLines.Count)
    for ($record = 0; $record -lt $max; $record++) {
        if ($record -ge $expectedLines.Count -or $record -ge $actualLines.Count) {
            Write-Host "${Label} FIRST DIFFERENCE: record=$record expected=[$($expectedLines[$record])] actual=[$($actualLines[$record])]"
            return $false
        }
        $expectedFields = @($expectedLines[$record] -split ' ')
        $actualFields = @($actualLines[$record] -split ' ')
        for ($field = 0; $field -lt $fieldNames.Count; $field++) {
            if ($expectedFields[$field] -cne $actualFields[$field]) {
                Write-Host "${Label} FIRST DIFFERENCE: record=$record field=$($fieldNames[$field]) expected=$($expectedFields[$field]) actual=$($actualFields[$field]) pc=$($expectedFields[1]) instruction=$($expectedFields[2])"
                return $false
            }
        }
    }
    Write-Host "${Label} PASS"
    return $true
}

function Run-Config([string]$Name, [string]$Define) {
    $softwareDir = "software/$Name"
    & make.exe all -C $softwareDir
    if ($LASTEXITCODE -ne 0) { return $false }
    $output = "tmp/gcc_evidence/$Name.out"
    & iverilog -g2012 "-D$Define" -s tb_soc_config -o $output $sources
    if ($LASTEXITCODE -ne 0) { return $false }
    & vvp $output
    if ($LASTEXITCODE -ne 0) { return $false }

    $prefix = "tmp/gcc_evidence/${Name}_"
    $goldenPrefix = "tests/golden/$Name/"
    $expectedState = Join-Path $goldenPrefix 'state.golden'
    $expectedPerformance = Join-Path $goldenPrefix 'performance.golden'
    $expectedTrace = Join-Path $goldenPrefix 'trace.golden'
    $actualState = "${prefix}state.actual"
    $actualPerformance = "${prefix}perf.actual"
    $actualTrace = "${prefix}trace.actual"
    $run1Trace = "${prefix}trace.run1"
    $mutatedTrace = "${prefix}trace.mutated"
    $ok = (Compare-FirstDifference $expectedState $actualState "$Name state")
    $ok = (Compare-FirstDifference $expectedPerformance $actualPerformance "$Name performance") -and $ok
    $ok = (Compare-TraceGolden $expectedTrace $actualTrace "$Name trace golden") -and $ok
    Copy-Item -LiteralPath $actualTrace -Destination $run1Trace -Force
    & vvp $output
    if ($LASTEXITCODE -ne 0) { return $false }
    $ok = (Compare-FirstDifference $run1Trace $actualTrace "$Name repeated trace") -and $ok

    # Exercise both architectural side-effect fields without touching RTL.
    $mutated = @(Get-Content -LiteralPath $run1Trace)
    $fields = @($mutated[0] -split ' '); $fields[5] = 'deadbeef'; $mutated[0] = $fields -join ' '
    Set-Content -LiteralPath $mutatedTrace -Value $mutated
    if (Compare-TraceGolden $run1Trace $mutatedTrace "$Name intentional rd_data mutation") {
        Write-Output "$Name rd_data mutation was not detected"
        $ok = $false
    }
    $storeRecord = -1
    for ($index = 0; $index -lt $mutated.Count; $index++) { if ((@($mutated[$index] -split ' '))[6] -eq '1') { $storeRecord = $index; break } }
    $mutated = @(Get-Content -LiteralPath $run1Trace)
    $fields = @($mutated[$storeRecord] -split ' '); $fields[8] = 'deadbeef'; $mutated[$storeRecord] = $fields -join ' '
    Set-Content -LiteralPath $mutatedTrace -Value $mutated
    if (Compare-TraceGolden $run1Trace $mutatedTrace "$Name intentional mem_data mutation") {
        Write-Output "$Name mem_data mutation was not detected"
        $ok = $false
    }
    return $ok
}

$allOk = (Run-Config 'gpio_only' 'SOC_CONFIG_GPIO_ONLY')
$allOk = (Run-Config 'uart_only' 'SOC_CONFIG_UART_ONLY') -and $allOk
if (-not $allOk) { exit 1 }
Write-Output 'ALL SOC CONFIGURATION TESTS PASS'
