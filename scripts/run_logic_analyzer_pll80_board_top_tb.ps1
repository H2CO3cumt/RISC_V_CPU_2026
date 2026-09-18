param([string]$IcarusRoot = $(if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}))
# 80 MHz PLL 版逻辑分析仪顶层的 RTL 闭环测试。
# 覆盖：PLL 锁定与 12.5 ns 输出周期、80 MHz 域 UART 分频（694）无帧错误、
# 板级固件前缀、Capture Engine pre/trigger/post 精确计数。
# 真实 PLL 原语 GTP_PLL_E3 由 PDS 仿真库提供，本脚本用 tb/pll_80m_model.v 行为模型替代。
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/logic_analyzer_pll80 | Out-Null
$src=@(
 'rtl/pipeline_cpu.v','rtl/branch_predictor.v','rtl/forward_unit.v','rtl/hazard_unit.v',
 'rtl/perf_monitor.v','rtl/perf_mmio.v','rtl/capture_engine.v','rtl/logic_analyzer_pattern_gen.v',
 'rtl/logic_analyzer_mmio.v','rtl/application_mmio_mux.v','rtl/regfile.v','rtl/alu.v','rtl/imm_gen.v',
 'rtl/decoder.v','rtl/branch_unit.v','rtl/load_store_unit.v','rtl/soc_data_interconnect.v',
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
