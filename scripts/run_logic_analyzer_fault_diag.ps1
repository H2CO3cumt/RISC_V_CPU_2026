param([string]$IcarusRoot = $(if ($env:IVERILOG_ROOT) { $env:IVERILOG_ROOT } else { 'D:\Tools\iverilog-v12' }))
$ErrorActionPreference='Stop'
$env:PATH="$(Resolve-Path $IcarusRoot)\bin;"+$env:PATH
New-Item -ItemType Directory -Force tmp/logic_analyzer_fault_diag | Out-Null
$src=@('rtl/capture_engine.v','tb/tb_logic_analyzer_fault_diag.v')
if($PSVersionTable.PSVersion.Major -ge 7){ $qs=[char]34 } else { $qs=[char]92+[char]34 }   # 5.1 needs backslash-quote, 7 needs a bare quote (see scripts/fix_ps_host_quote_escape.py)
# 四个场景覆盖"故障在触发后窗口内 / 触发前窗口内 / 窗口外 / 不注入"四种情形。
# 期望的定位结果由 python/logic_analyzer_fault_diag.py 自动核对，不看波形。
$scenarios=@(
  @{ Id=0; Tag='post';   Tick=60; Mask=0x02 },   # 触发点(64)之后：应定位到采集索引 4
  @{ Id=1; Tag='pre';    Tick=57; Mask=0x80 },   # 触发点之前：应定位到采集索引 1
  @{ Id=2; Tag='before'; Tick=40; Mask=0x04 },   # 窗口之外：不得报出任何差异
  @{ Id=3; Tag='none';   Tick=-1; Mask=0x00 }    # 基线：不得报出任何差异
)
$python = if($env:PYTHON) { $env:PYTHON } else { (Get-Command python -ErrorAction Stop).Source }
foreach($s in $scenarios){
  $tagDef="-DTB_FD_SCEN=$($s.Id)"
  $tickDef="-DTB_FD_INJ_TICK=$($s.Tick)"
  $maskDef=("-DTB_FD_INJ_MASK=8'h{0:x2}" -f $s.Mask)
  & iverilog -g2012 $tagDef $tickDef $maskDef -s tb_logic_analyzer_fault_diag -o "tmp/logic_analyzer_fault_diag/tb_$($s.Tag)" @src
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  & vvp "tmp/logic_analyzer_fault_diag/tb_$($s.Tag)"
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  & $python python/logic_analyzer_fault_diag.py
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
}
& $python python/logic_analyzer_fault_diag.py --summary
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
Write-Host 'ALL LOGIC ANALYZER FAULT DIAG PASS (4 scenarios)'
exit 0
