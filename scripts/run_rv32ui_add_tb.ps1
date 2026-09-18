param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH

if (-not $env:RISCV_PREFIX) {
    throw 'RISCV_PREFIX is required, for example riscv-none-elf-.'
}

New-Item -ItemType Directory -Force -Path tmp | Out-Null

& ($env:RISCV_PREFIX + 'gcc') -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles `
    -I tb/arch/riscv_tests -I third_party/riscv-tests/isa/macros/scalar `
    -T tb/arch/riscv_tests/link.ld -o tmp/rv32ui_add.elf `
    third_party/riscv-tests/isa/rv32ui/add.S
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& ($env:RISCV_PREFIX + 'objcopy') -O verilog --verilog-data-width=4 `
    tmp/rv32ui_add.elf tmp/rv32ui_add.mem
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

iverilog -g2012 -s tb_rv32ui_add -o tmp/tb_rv32ui_add `
    rtl/single_cycle_cpu.v rtl/regfile.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v `
    rtl/branch_unit.v rtl/load_store_unit.v rtl/dmem.v rtl/imem.v tb/ram_adapter.v tb/imem_adapter.v tb/core_harness.v `
    tb/tb_rv32ui_add.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/tb_rv32ui_add
exit $LASTEXITCODE
