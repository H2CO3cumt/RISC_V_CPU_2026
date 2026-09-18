param(
    [string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' })
)

$ErrorActionPreference = 'Stop'
$icarusRootFull = (Resolve-Path -LiteralPath $IcarusRoot).Path
$env:PATH = "$icarusRootFull\bin;" + $env:PATH
if(-not $env:RISCV_PREFIX){$env:RISCV_PREFIX='riscv-none-elf-'}
New-Item -ItemType Directory -Force -Path tmp | Out-Null

# 本套件依赖裸机镜像 software/mmio_demo/build/mmio_demo.mem，必须自己先构建，
# 不能依赖仓库里已有的旧产物（否则固件改名后会静默失败）。
& make.exe -C software/mmio_demo all
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

iverilog -g2012 -s tb_soc_harness -o tmp/soc_demo_harness `
    rtl/single_cycle_cpu.v rtl/regfile.v rtl/alu.v rtl/imm_gen.v rtl/decoder.v rtl/branch_unit.v rtl/load_store_unit.v `
    rtl/soc_data_interconnect.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_mmio.v rtl/gpio_mmio.v `
    tb/imem_adapter.v tb/ram_adapter.v tb/test_target.v tb/tb_soc_harness.v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp tmp/soc_demo_harness
exit $LASTEXITCODE
