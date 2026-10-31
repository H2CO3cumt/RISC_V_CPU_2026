param([string]$IcarusRoot = $(if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}))
# 80 MHz PLL ????????? RTL ?????
# ??:PLL ??? 12.5 ns ?????80 MHz ? UART ??(694)?????
# ???????Capture Engine pre/trigger/post ?????
# ?? PLL ?? GTP_PLL_E3 ? PDS ?????,???? tb/pll_80m_model.v ???????
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/logic_analyzer_pll80 | Out-Null
$src=@(
 'rtl/pipeline_cpu.v','rtl/fetch_fifo.v','rtl/ras.v','rtl/branch_predictor.v','rtl/csr_unit.v','rtl/forward_unit.v','rtl/hazard_unit.v',
 'rtl/perf_monitor.v','rtl/perf_mmio.v','rtl/capture_engine.v','rtl/logic_analyzer_pattern_gen.v',
 'rtl/logic_analyzer_mmio.v','rtl/application_mmio_mux.v','rtl/regfile.v','rtl/mdu.v','rtl/alu.v','rtl/imm_gen.v',
 'rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','rtl/soc_data_interconnect.v','rtl/timer_mmio.v',
 'rtl/uart_tx.v','rtl/uart_rx.v','rtl/uart_mmio.v','rtl/gpio_mmio.v',
 'tb/pll_80m_model.v',
 'fpga/coremark_80m/rtl/pll_80m.v',
 'fpga/logic_analyzer_80m/rtl/logic_analyzer_program_memory.v',
 'fpga/logic_analyzer_80m/rtl/mes50hp_logic_analyzer_top.v',
 'fpga/logic_analyzer_80m/rtl/mes50hp_logic_analyzer_pll_top.v',
 'tb/tb_logic_analyzer_pll80_board_top.v'
)
& iverilog -g2012 -DLOGIC_ANALYZER_SIM -s tb_logic_analyzer_pll80_board_top -o tmp/logic_analyzer_pll80/tb @src
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& vvp tmp/logic_analyzer_pll80/tb
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host 'LOGIC ANALYZER PLL80 BOARD TOP TEST PASS'
