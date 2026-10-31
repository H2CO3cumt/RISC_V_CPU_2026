param(
  [Parameter(Mandatory=$true)][string]$Port,
  [string]$Output='release/evidence/logic_analyzer_board_85m/ui_source_check'
)
$ErrorActionPreference='Stop'
# 采集源（J8 外部 / Core 内部观测点）在**真实界面路径**上的实板检查。
# 驱动的是 pyUI 自己的 _run_logic_analyzer()：证据回答的是"点这个按钮会发生什么"。
# 四组"模式 × 采集源"组合 + 两次"不勾面板时显示值"检查；末行 UI BOARD CHECK PASS。
$python=if($env:PYTHON){$env:PYTHON}else{'python'}
New-Item -ItemType Directory -Force $Output | Out-Null
$log=Join-Path $Output 'pyui_board_check.log'
# -u：日志要能边跑边看（现场排障时不希望输出卡在缓冲区里）
& $python -u python/ui_source_board_check.py $Port 2>&1 | Tee-Object -FilePath $log
if($LASTEXITCODE -ne 0){throw "UI SOURCE BOARD CHECK FAIL port=$Port（日志 $log）"}
# 单文件演示器那一侧：同样要能从界面上切源，六模式自检必须全过
$single=Join-Path $Output 'singlefile_selftest.log'
& $python -u 逻辑分析仪演示.py --selftest $Port 2>&1 | Tee-Object -FilePath $single
if($LASTEXITCODE -ne 0){throw "SINGLE FILE SELFTEST FAIL port=$Port（日志 $single）"}
Write-Host "UI SOURCE BOARD ACCEPTANCE PASS port=$Port log=$log"
