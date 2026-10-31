param(
  [string]$PdsRoot = $(if($env:PDS_ROOT){$env:PDS_ROOT}else{'D:\Pango\PDS_2024.2-SP2'}),
  [int]$JsPort = 65420,
  [int]$TimeoutSeconds = 240,
  [switch]$SkipPangoScan
)
# 判定"现在插着的 USB 下载器到底是不是 Pango 的线"。
#
# 【为什么要单独做一个脚本】
#   N2 被卡住整整 3 轮，根因是**认错了硬件**：换端口只改变 COM 号，
#   改变不了设备身份。Pango 的 Fabric Debugger 靠 USB 描述符认线：
#       厂商 = SHENZHEN PANGO MICROSYSTEMS, INC.
#       描述 = PANGO USB CABLE II
#       以及一个真实序列号
#   三者齐备才会出现在 `Cable List` 里。
#
# 【本脚本给出的一票否决证据】
#   FTDI 器件的 **EEPROM 为空** 时：
#     - 描述回退成驱动默认（FT2232H = `Dual RS232-HS`）
#     - **没有序列号** —— Windows 实例路径会退化成 `6&xxxx&0&N` 这种端口路径
#     - 两个通道都变成 VCP 串口
#     - `FT_EE_Read` 返回 15 = FT_EEPROM_NOT_PROGRAMMED
#   只要看到这四条，就**一定不是** Pango 的线（Pango 的线必须烧过 EEPROM）。
#
# 用法：powershell -File scripts\check_jtag_cable.ps1
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Write-Host "==================== 1) Windows 侧的 FTDI 设备 ===================="
$ftdi = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'USB\VID_0403*' -or $_.InstanceId -like 'FTDIBUS*' }
if(-not $ftdi){ Write-Host "  (没有任何 FTDI 设备)" }
foreach($d in $ftdi){
  # 实例路径里 `USB\VID_0403&PID_6010\<X>` 的 <X> 就是序列号；空 EEPROM 时它是端口路径
  $serial = '?'
  if($d.InstanceId -match 'VID_0403&PID_6010\\(.+)$'){ $serial = $Matches[1] }
  $looksPath = $serial -match '^[0-9A-Fa-f]&'
  Write-Host ("  {0,-28} serial-ish='{1}'{2}" -f $d.FriendlyName, $serial, $(if($looksPath){'   <- 端口路径 => EEPROM 为空（无序列号）'}else{''}))
}

Write-Host "==================== 2) D2XX 视角 + EEPROM 状态 ===================="
$cs = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class FtdiChk {
  [DllImport(@"D:\Pango\PDS_2024.2-SP2\driver\amd64\ftd2xx64.dll", CallingConvention = CallingConvention.Cdecl)] public static extern uint FT_CreateDeviceInfoList(ref uint n);
  [DllImport(@"D:\Pango\PDS_2024.2-SP2\driver\amd64\ftd2xx64.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)] public static extern uint FT_ListDevices(IntPtr a1, StringBuilder a2, uint flags);
  [DllImport(@"D:\Pango\PDS_2024.2-SP2\driver\amd64\ftd2xx64.dll", CallingConvention = CallingConvention.Cdecl)] public static extern uint FT_Open(int idx, ref IntPtr h);
  [DllImport(@"D:\Pango\PDS_2024.2-SP2\driver\amd64\ftd2xx64.dll", CallingConvention = CallingConvention.Cdecl)] public static extern uint FT_Close(IntPtr h);
  [DllImport(@"D:\Pango\PDS_2024.2-SP2\driver\amd64\ftd2xx64.dll", CallingConvention = CallingConvention.Cdecl)] public static extern uint FT_EE_Read(IntPtr h, byte[] pData);
}
'@
try{
  Add-Type -TypeDefinition $cs -ErrorAction Stop
  $n=[uint32]0; [void][FtdiChk]::FT_CreateDeviceInfoList([ref]$n)
  Write-Host ("  D2XX 设备数 = $n")
  for($i=0;$i -lt $n;$i++){
    $sb=New-Object System.Text.StringBuilder 256
    [void][FtdiChk]::FT_ListDevices([IntPtr]$i,$sb,[uint32]0x40000002)
    $h=[IntPtr]::Zero; $st=[FtdiChk]::FT_Open($i,[ref]$h); $ee='n/a'
    if($st -eq 0){
      $buf=New-Object byte[] 4096
      [BitConverter]::GetBytes([uint32]0).CopyTo($buf,0)
      [BitConverter]::GetBytes([uint32]::MaxValue).CopyTo($buf,4)
      [BitConverter]::GetBytes([uint32]0).CopyTo($buf,8)
      $ee=[FtdiChk]::FT_EE_Read($h,$buf)
      [void][FtdiChk]::FT_Close($h)
    }
    Write-Host ("  [{0}] 描述='{1}'  EEPROM_status={2}{3}" -f $i, $sb.ToString(), $ee,
                $(if($ee -eq 15){'  <- FT_EEPROM_NOT_PROGRAMMED = EEPROM 为空'}else{''}))
  }
}catch{ Write-Host ("  D2XX 读取失败: " + $_.Exception.Message) }

Write-Host "==================== 3) Pango 的 Cable List（最终判据）===================="
if($SkipPangoScan){
  Write-Host "  (已跳过)"
} else {
  $bin=Join-Path $PdsRoot 'bin'
  $jsPort=$JsPort
  if(-not (netstat -ano | Select-String ":$jsPort\s+.*LISTENING")){
    Write-Host "  启动 JTAG 服务 cdt_js.exe ..."
    Start-Process (Join-Path $bin 'cdt_js.exe') -ArgumentList '-work_dir',(Join-Path $repo 'tmp'),'-port',"$jsPort"
    $dl=(Get-Date).AddSeconds(25)
    do{ Start-Sleep -Milliseconds 500 }while(-not (netstat -ano|Select-String ":$jsPort\s+.*LISTENING") -and (Get-Date) -lt $dl)
  }
  Get-Process cdt_dbg -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 2
  $tcl=Join-Path $repo 'tmp/ila/cable_check.tcl'
  New-Item -ItemType Directory -Force -Path (Split-Path $tcl) | Out-Null
  @"
dbg_connect -ip 127.0.0.1 -port $jsPort
dbg_scan_chain
dbg_disconnect
dbg_close
"@ | Set-Content -LiteralPath $tcl -Encoding ascii
  $out=Join-Path $repo 'tmp/ila/cable_check.out'
  Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
  $p=Start-Process -FilePath (Join-Path $bin 'cdt_dbg.exe') -ArgumentList @('-file',$tcl,'-work_dir',(Join-Path $repo 'tmp')) -PassThru -NoNewWindow -RedirectStandardOutput $out
  # 【2026-09-30 修的 bug】旧实现在看到 'Cable List' + 'open_cable' 两个词之后就
  # `Start-Sleep 6` 然后**直接 Kill**，根本不等 dbg_scan_chain 出结果，
  # 于是永远落到 else 分支打印"Cable List 为空 => 不是 Pango 的下载线"——
  # 而实测 open_cable 是成功的、线是好的。**那是假警报，害人不浅。**
  # 正确做法：等进程自然退出（open_cable 实测可能耗时 60 s 以上，所以超时默认给到 240 s），
  # 退出后再读完整输出；只有超时才 Kill，并明确标注"结果可能不完整"。
  $dl=(Get-Date).AddSeconds($TimeoutSeconds)
  $exited=$false
  while((Get-Date) -lt $dl){
    Start-Sleep -Seconds 3
    if($p.HasExited){ $exited=$true; break }
  }
  if(-not $exited){ try{$p.Kill()}catch{} }
  Start-Sleep -Seconds 2   # 让重定向的 stdout 落盘
  $t=Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue
  ($t -split "`n") | Where-Object { $_ -match 'Cable|No cable|PGL50H|done bit|IDCODE|Debugger-|open_cable|scan_chain' } | ForEach-Object { "  " + $_.Trim() }
  Write-Host ""
  if(-not $exited){ Write-Host "  ==> 注意：$TimeoutSeconds 秒内未退出，已强制结束，下面的判定可能不完整（可用 -TimeoutSeconds 加大重试）" }
  # 判定顺序：先看有没有真的列出 cable index；退一步，只要 open_cable 成功就说明线在；
  # 只有明确报"没有线/打开失败"才判否。不要因为没匹配到某个词就下否定结论。
  if($t -match 'Cable index'){
    Write-Host "  ==> 判定：Pango 看到线了（Cable List 有条目），可以进入抓取/下载流程"
  } elseif($t -match 'open_cable.*execute successfully' -or $t -match 'PANGO USB CABLE II'){
    Write-Host "  ==> 判定：open_cable 成功、驱动识别为 PANGO USB CABLE II => **线是好的**。"
    Write-Host "      （本次输出里没有 'Cable index' 行，可能只是该命令不打印链条目；"
    Write-Host "        最终判据请用 scripts\program_board.ps1 下载一次看 'The done bit is 1'。）"
  } elseif($t -match 'No cable|open_cable.*fail|Debugger-') {
    Write-Host "  ==> 判定：明确报错/找不到线 => 现在这颗**不是** Pango 的下载线（或它 EEPROM 为空）"
  } else {
    Write-Host "  ==> 判定：输出里既没有成功也没有失败标志，无法判定。请把完整日志 tmp/ila/cable_check.out 发出来。"
  }
}
