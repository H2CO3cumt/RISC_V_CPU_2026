param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$powerShell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $powerShell) { $powerShell = (Get-Command powershell -ErrorAction Stop).Source }

$scripts = @(
    'run_regfile_tb.ps1',
    'run_alu_tb.ps1',
    'run_imm_gen_tb.ps1',
    'run_decoder_tb.ps1',
    'run_branch_unit_tb.ps1',
    'run_load_store_unit_tb.ps1',
    'run_dmem_tb.ps1',
    'run_imem_tb.ps1',
    'run_single_cycle_cpu_tb.ps1',
    'run_single_cycle_u_type_tb.ps1',
    'run_single_cycle_slti_tb.ps1',
    'run_single_cycle_shift_imm_tb.ps1',
    'run_single_cycle_logic_imm_tb.ps1',
    'run_single_cycle_load_align_tb.ps1',
    'run_single_cycle_store_align_tb.ps1',
    'run_single_cycle_branch_tb.ps1',
    'run_single_cycle_r_type_tb.ps1',
    'run_single_cycle_jalr_tb.ps1',
    'run_single_cycle_call_return_tb.ps1',
    'run_single_cycle_system_boundary_tb.ps1',
    'run_rv32ui_core_suite.ps1',
    'run_rv32ui_memory_suite.ps1'
)

foreach ($script in $scripts) {
    Write-Output "RUN $script"
    # Run each suite in a child process because the legacy suite scripts use
    # `exit` to return their status.
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $script) -IcarusRoot $IcarusRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Output 'ALL RV32I REGRESSION PASS'
