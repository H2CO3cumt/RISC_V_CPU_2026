param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH

if (-not $env:RISCV_PREFIX) {
    throw 'RISCV_PREFIX is required, for example riscv-none-elf-.'
}

$tests = @(
    'add', 'addi', 'and', 'andi', 'auipc',
    'beq', 'bge', 'bgeu', 'blt', 'bltu', 'bne',
    'jal', 'jalr', 'lui', 'or', 'ori',
    'sll', 'slli', 'slt', 'slti', 'sltiu', 'sltu',
    'sra', 'srai', 'srl', 'srli', 'sub', 'xor', 'xori'
)

New-Item -ItemType Directory -Force -Path tmp | Out-Null

foreach ($test in $tests) {
    $elf = "tmp/rv32ui_$test.elf"
    $mem = 'tmp/rv32ui_current.mem'
    $sim = "tmp/tb_rv32ui_$test"

    Write-Output "RUN rv32ui-p-$test"
    & ($env:RISCV_PREFIX + 'gcc') -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles `
        -I tb/arch/riscv_tests -I third_party/riscv-tests/isa/macros/scalar `
        -T tb/arch/riscv_tests/link.ld -o $elf "third_party/riscv-tests/isa/rv32ui/$test.S"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & ($env:RISCV_PREFIX + 'objcopy') -O verilog --verilog-data-width=4 $elf $mem
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    iverilog -g2012 -s tb_rv32ui_core -o $sim `
        rtl/single_cycle_cpu.v rtl/regfile.v rtl/mdu.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v `
        rtl/branch_unit.v rtl/load_store_unit.v rtl/dmem.v rtl/imem.v tb/ram_adapter.v tb/imem_adapter.v tb/core_harness.v tb/tb_rv32ui_core.v
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    vvp $sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Output "ALL RV32UI CORE TESTS PASS"
