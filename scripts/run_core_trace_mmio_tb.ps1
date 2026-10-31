param([string]$OutDir = 'tmp/core_trace_mmio')
$ErrorActionPreference='Stop'
$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}
$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force $OutDir|Out-Null
iverilog -g2012 -s tb_core_trace_mmio -o "$OutDir/tb" `
  rtl/trace_buffer.v rtl/core_trace_mmio.v rtl/application_mmio_mux.v rtl/application_mmio_mux3.v `
  tb/tb_core_trace_mmio.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
vvp "$OutDir/tb"
exit $LASTEXITCODE
