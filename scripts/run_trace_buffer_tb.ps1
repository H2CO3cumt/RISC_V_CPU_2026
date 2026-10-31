param([string]$OutDir = 'tmp/trace_buffer')
$ErrorActionPreference='Stop'
$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}
$env:PATH="$(Resolve-Path $iverilogRoot)\bin;"+$env:PATH
# 产物目录默认按项目惯例放 tmp/；个别受限环境（文件沙箱不允许在 tmp/ 下新建目录）
# 可用 -OutDir 指到别处，判据与输出不变。
New-Item -ItemType Directory -Force $OutDir|Out-Null
iverilog -g2012 -s tb_trace_buffer -o "$OutDir/tb" rtl/trace_buffer.v tb/tb_trace_buffer.v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
vvp "$OutDir/tb"
exit $LASTEXITCODE
