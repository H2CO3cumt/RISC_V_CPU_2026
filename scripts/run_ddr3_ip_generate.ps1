param(
  [string]$PdsRoot = $(if ($env:PDS_ROOT) { $env:PDS_ROOT } else { 'D:\Pango\PDS_2024.2-SP2' }),
  [string]$LicenseFile = '',
  [string]$InstanceName = 'ddr3_mes50hp',
  [string]$OutDir = '',
  [switch]$NoSynthesis
)
# 全程**无 GUI** 生成适配本板 MES50HP 的 HMIC_S DDR3 控制器 IP。
#
# ## 为什么要做成脚本
# PDS 的 IP Compiler 是图形界面工具，官方文档也写着"不能用命令行输入"。
# 但它有两个可脚本化的入口（本轮已实测可用）：
#   1. `ip_compiler.exe -c -n <名> -i <实例>.ipc -m <IP模型目录> … -pre <脚本>`
#      —— 无需任何人工点击即可创建实例数据文件（`.ipc`，XML，264 个参数）。
#   2. `ip_generate.exe -i <实例>.ipc …` —— 无需 GUI 即可生成 IP RTL 并综合。
# 把实例文件里的参数按本板改好（`scripts/ddr3_ipc_patch.py`），再调 ip_generate，
# 就得到本板配置的 IP —— 实测顶层 `MEM_DQ_WIDTH` 正确变成 32。
#
# ## 最容易踩的坑（实测）
# 位宽参数**必须成组改**：只改 `MEM_DQ_WIDTH=32` 而留着 `MEM_DQS_WIDTH=2`，
# 生成出的顶层**仍然是 16 位**（工具判定矛盾后回退）。必须同时给
# `MEM_DQS_WIDTH=4`、`MEM_DM_WIDTH=4`（都等于 DQ/8）。patch 脚本已处理。
#
# ## 安全边界
# 本脚本只创建/生成 IP 源码，**不综合整个工程、不布局布线、不出版本、不下载**，
# 输出只写到 `fpga/ddr3_smoke/ip/`，不影响任何交付工程或板上现有位流。
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$model=Join-Path $PdsRoot 'ip/system_ip/ipsxb_hmic_s/ipsxb_hmic_eval/ipsxb_hmic_s'
if(!(Test-Path -LiteralPath $model)){ throw "HMIC_S IP model not found: $model" }
$ipCompiler=Join-Path $PdsRoot 'bin/ip_compiler.exe'
$ipGenerate=Join-Path $PdsRoot 'bin/ip_generate.exe'
foreach($exe in @($ipCompiler,$ipGenerate)){
  if(!(Test-Path -LiteralPath $exe)){ throw "PDS tool not found: $exe (它属于 PGL50H 的 HMIC_S IP，需确认 IP 已安装)" }
}

if($LicenseFile){ $env:PANGO_LICENSE_FILE=(Resolve-Path -LiteralPath $LicenseFile).Path }
if(-not $env:PANGO_LICENSE_FILE){
  foreach($root in @($PdsRoot,(Split-Path $PdsRoot -Parent),'D:\ToolsSoftware\pango','D:\Downloads')){
    if(Test-Path -LiteralPath $root){
      $found=Get-ChildItem -LiteralPath $root -File -Include 'PDS-*.lic','pango*.lic','*.pango.lic','new_pds_*.lic' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($found){$env:PANGO_LICENSE_FILE=$found.FullName;break}
    }
  }
}
if(-not $env:PANGO_LICENSE_FILE){ Write-Warning 'PANGO_LICENSE_FILE unset; PDS may report Flow-0183.' }

if(-not $OutDir){ $OutDir = Join-Path $repo "fpga/ddr3_smoke/ip/$InstanceName" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$ipc = Join-Path $OutDir "$InstanceName.ipc"

function Stop-Tool($proc, $seconds){
  # 这两个工具完成工作后**不会自己退出**（会停在界面/等待状态），所以轮询文件与超时后强杀。
  $deadline=(Get-Date).AddSeconds($seconds)
  while((Get-Date) -lt $deadline){
    Start-Sleep -Seconds 2
    if($proc.HasExited){ return }
  }
  try{ $proc.Kill() }catch{}
}

# ---------------------------------------------------------------- 1) 创建实例
Write-Host "=== 1) 创建 IP 实例（无 GUI）==="
$log1=Join-Path $OutDir 'step1_create.log'
# 实例文件若已存在就**不要重跑创建**：`ip_compiler -c` 会用出厂默认值覆盖它，
# 而我们精心改好的分组参数就全没了。要重建请先手工删掉 .ipc。
if(Test-Path -LiteralPath $ipc){
  Write-Host ("    已有实例文件，跳过创建: {0} ({1} bytes)" -f $ipc, (Get-Item -LiteralPath $ipc).Length)
} else {
  $p1=Start-Process -FilePath $ipCompiler -PassThru -NoNewWindow -WorkingDirectory $OutDir `
    -ArgumentList @('-c','-n',$InstanceName,'-i',$ipc,'-m',$model,
                    '-family','Logos','-device','PGL50H','-pack','FBG484','-speed','-6',
                    '-tmp-dir',$OutDir) `
    -RedirectStandardOutput $log1 -RedirectStandardError (Join-Path $OutDir 'step1_create.err')
  Stop-Tool $p1 90
  if(!(Test-Path -LiteralPath $ipc)){ throw "实例文件未生成: $ipc（见 $log1）" }
  Write-Host ("    .ipc = {0}  ({1} bytes)" -f $ipc, (Get-Item -LiteralPath $ipc).Length)
}

# ------------------------------------------------- 2) 改成本板参数（含位宽成组改 + 分组修正）
Write-Host "=== 2) 改成本板参数 ==="
& python (Join-Path $repo 'scripts/ddr3_ipc_patch.py') --src $ipc --dst $ipc
if($LASTEXITCODE -ne 0){ throw 'IPC patch failed' }
# 分组参数必须紧跟着修正：出厂默认里"信号组名"和"CA 组槽号"自相矛盾（15 条），
# 会导致布局阶段 Place-0054。详见 scripts/ddr3_ipc_fix_groups.py 顶部说明。
Write-Host "    -- 按手册管脚修正 DDR3 分组参数 --"
& python (Join-Path $repo 'scripts/ddr3_ipc_fix_groups.py') --src $ipc
if($LASTEXITCODE -ne 0){ throw 'IPC group fix failed（分组参数不自洽就不要继续生成）' }

# ------------------------------------------------------------------- 3) 生成
Write-Host "=== 3) 生成 IP RTL（无 GUI）==="
$log3=Join-Path $OutDir 'step3_generate.log'
$args3=@('-i',$ipc,'-family','Logos','-device','PGL50H','-pack','FBG484','-speed','-6')
if($NoSynthesis){ $args3 += '-disable-syn' }
$p3=Start-Process -FilePath $ipGenerate -PassThru -NoNewWindow -WorkingDirectory $OutDir `
  -ArgumentList $args3 `
  -RedirectStandardOutput $log3 -RedirectStandardError (Join-Path $OutDir 'step3_generate.err')
Stop-Tool $p3 600

$out = Get-Content -LiteralPath $log3 -Raw -ErrorAction SilentlyContinue
if($out -notmatch 'Finished generating'){ throw "生成未完成，见 $log3" }
if($out -match 'Done:\s*(\d+)\s*error'){ $errs=[int]$Matches[1]; if($errs -ne 0){ throw "IP 生成报 $errs 个错误，见 $log3" } }

# ------------------------------------------------------------------- 4) 验证
Write-Host "=== 4) 验证生成结果的位宽 ==="
$top = Join-Path $OutDir "$InstanceName.v"
if(!(Test-Path -LiteralPath $top)){ throw "未找到生成的顶层: $top" }
$expected=@{ MEM_DQ_WIDTH='32'; MEM_DQS_WIDTH='4'; MEM_ROW_WIDTH='15'; MEM_COLUMN_WIDTH='10'; MEM_BANK_WIDTH='3' }
$bad=@()
foreach($k in $expected.Keys){
  $m=[regex]::Match((Get-Content -LiteralPath $top -Raw), "parameter\s+$k\s*=\s*(\d+)")
  $got = if($m.Success){ $m.Groups[1].Value } else { '(缺失)' }
  Write-Host ("    {0,-18} = {1}  (期望 {2})" -f $k, $got, $expected[$k])
  if($got -ne $expected[$k]){ $bad += "$k=$got(期望$($expected[$k]))" }
}
if($bad.Count -ne 0){
  throw ("位宽校验失败: " + ($bad -join ', ') + " —— 常见原因：位宽参数没有成组改（DQ/DQS/DM 必须都是 DQ/8 关系）")
}
$rtlCount=(Get-ChildItem (Join-Path $OutDir 'rtl') -Recurse -File -ErrorAction SilentlyContinue).Count
Write-Host ("    rtl/ 文件数 = {0}" -f $rtlCount)

# ------------------------------------------------- 5) 重打必须的厂商文件补丁
# 生成会整体重写 example_design/，所以每次生成后都要重打（补丁脚本幂等）。
Write-Host "=== 5) 重打厂商示例补丁（UART 分频）==="
& python (Join-Path $repo 'scripts/ddr3_reapply_vendor_patches.py')
if($LASTEXITCODE -ne 0){ throw '重打厂商补丁失败（串口分频不对，上板会乱码）' }

Write-Host ''
Write-Host "HMIC DDR3 IP HEADLESS GENERATION PASS"
Write-Host "  实例: $ipc"
Write-Host "  输出: $OutDir"
Write-Host "  下一步: 见 fpga/ddr3_smoke/README.md §5（改时钟到 P20、改 UART、综合、下载）"
