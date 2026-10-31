$ErrorActionPreference='Stop'
# PS 5.1 的 .NET Framework 没有 [System.IO.Path]::GetRelativePath（那是 .NET Core 才有的 API），
# 本机只有 Windows PowerShell 5.1，直接调用会抛 MethodNotFound。这里用 Uri 求相对路径，
# 语义与 GetRelativePath 一致（同为绝对路径时），并把分隔符统一成 / 以便清单跨平台可比。
function Get-RelativePathCompat {
  param([string]$Base, [string]$Path)
  $baseFull = [System.IO.Path]::GetFullPath($Base)
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  $baseUri = New-Object System.Uri (($baseFull.TrimEnd('\') + '\'))
  $pathUri = New-Object System.Uri ($pathFull)
  $rel = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
  return $rel.Replace('\','/')
}
$releaseRoot=Join-Path (Resolve-Path '.').Path 'release'
$artifactRoot=Join-Path $releaseRoot 'artifacts'
New-Item -ItemType Directory -Force $artifactRoot | Out-Null

# 最终交付只保留一套可下载配置；阶段性 bitstream 仍留在各自 FPGA
# 工程目录作为开发证据，不再混入最终 artifacts。
foreach($legacy in @('pipeline_soc.sbit','pipeline_soc_timing.rtr','coremark_stable.sbit','coremark_stable_timing.rtr','coremark_debug_ila.sbit','coremark_debug_ila_timing.rtr','logic_analyzer_p0.sbit','logic_analyzer_p0_timing.rtr','coremark_imem.mem','coremark_drom.mem','coremark_ram.mem','logic_analyzer_program.mem')){
  $legacyPath=Join-Path $artifactRoot $legacy
  if(Test-Path -LiteralPath $legacyPath){Remove-Item -LiteralPath $legacyPath -Force}
}

# 【2026-09-30 交付配置切换】交付主位流改为 85 MHz PLL 版（fpga/logic_analyzer_85m）。
# 50 MHz 版工程保留作已验证备用，其位流由 export_final_submission.ps1 放进交付包。
$artifacts=@(
  @('fpga/logic_analyzer_85m/generate_bitstream/mes50hp_logic_analyzer_pll_top.sbit','mes50hp_riscv_logic_analyzer.sbit'),
  @('fpga/logic_analyzer_85m/report_timing/mes50hp_logic_analyzer_pll_top.rtr','mes50hp_riscv_logic_analyzer_timing.rtr'),
  @('fpga/logic_analyzer_85m/rtl/logic_analyzer_program.mem','logic_analyzer_firmware.mem')
)
foreach($pair in $artifacts){
  if(-not (Test-Path -LiteralPath $pair[0])){throw "Release artifact missing: $($pair[0])"}
  Copy-Item -LiteralPath $pair[0] -Destination (Join-Path $artifactRoot $pair[1]) -Force
}

$roots=@('AGENTS.md','AGENTS.local.md','rtl','tb','scripts','python','software','docs','third_party/coremark',
         'fpga/pipeline_soc','fpga/coremark','fpga/coremark_ila','fpga/logic_analyzer',
         'release/materials','release/evidence','release/board_validation','release/HANDOFF.md')
$files=foreach($root in $roots){
  if(Test-Path -LiteralPath $root -PathType Leaf){Get-Item -LiteralPath $root;continue}
  if(Test-Path -LiteralPath $root -PathType Container){
    Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
      $_.FullName -notmatch '[\\/]\.git[\\/]' -and
      $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
      $_.FullName -notmatch '[\\/](synthesize|map|place|route|route_optimize|generate_bitstream)[\\/]' -and
      $_.Name -ne 'pds.log' -and
      $_.Extension -ne '.lock'
      # Generated PDS project descriptors are retained for direct board reopening;
      # large implementation databases remain excluded by the stage-directory rule.
    }
  }
}
$files += Get-ChildItem -LiteralPath $artifactRoot -File
$zipPath=Join-Path $releaseRoot 'MES50HP_board_validation_package.zip'
if(Test-Path -LiteralPath $zipPath -PathType Leaf){$files += Get-Item -LiteralPath $zipPath}
$files = $files | Sort-Object FullName -Unique
$repoRoot=(Resolve-Path '.').Path
$hashLines=foreach($file in $files){
  $relative=Get-RelativePathCompat -Base $repoRoot -Path $file.FullName.Replace('\','/')
  $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
  "$hash  $relative"
}
$hashLines | Set-Content -LiteralPath (Join-Path $releaseRoot 'SHA256SUMS.txt') -Encoding ascii

$gitHead=git rev-parse HEAD 2>$null
if(-not $gitHead){$gitHead='NO_COMMIT'}
$gitDirty=if(git status --porcelain 2>$null){'dirty'}else{'clean'}
$pdsVersion='D:\Pango\PDS_2024.2-SP2'
$iverilogRoot=if($env:IVERILOG_ROOT){$env:IVERILOG_ROOT}else{'D:\Tools\iverilog-v12'}
$iverilogExe=Join-Path $iverilogRoot 'bin\iverilog.exe'
$iverilogVersion=(& $iverilogExe -V 2>&1 | Select-Object -First 1)
$gccVersion=(& riscv-none-elf-gcc --version 2>&1 | Select-Object -First 1)
$coremarkHead=git -C third_party/coremark rev-parse HEAD 2>$null
@(
  'release_id=competition_final_candidate',
  "generated=$(Get-Date -Format o)",
  "git=$gitHead",
  "git_dirty=$gitDirty",
  "coremark_git=$coremarkHead",
  "pipeline_cpu_sha256=$((Get-FileHash rtl/pipeline_cpu.v -Algorithm SHA256).Hash)",
  "pds=$pdsVersion",
  "iverilog=$iverilogVersion",
  "gcc=$gccVersion",
  'device=PGL50H-6IFBG484',
  'clock_hz=50000000',
  'scope=Task0-30,Task32,Task33-35;Task31 RLE frozen;advanced:BTB+Trap M-01..M-24 PASS,high-item-1 I/D cache+burst+DDR3 S1-S4 done (S2 PASS, S3/S4 stop-loss default OFF)',
  'board_results=all measured on MES50HP 2026-09-29/30. la50 J8 loopback 80/80 PASS release/evidence/logic_analyzer_board_final (+re-verified 2026-09-30 release/evidence/logic_analyzer_board_recheck_20260930); coremark 50MHz ticks=1068006999 score_x1000=46816 cm_per_mhz_x1000=936 crcfinal=0xd340 PASS release/evidence/coremark_board.json (bitstream DC95F9D0); coremark 80MHz-PLL ticks=2670014377 iters=2500 seconds=33.375 score_x1000=74905 cm_per_mhz_x1000=936 crcfinal=0x5275 PASS release/evidence/coremark_board_cm80_20260930.json (bitstream F0743756); bare-metal timer irq N1 12 irqs self-timed median 12517376 ticks=250.348ms release/evidence/timer_demo_board; ILA trap enter/return N2 M-24 PASS fpga/timer_demo_ila/evidence; coremark key-loop ILA release/evidence/ila_coremark; S1 DDR3 smoke board PASS release/evidence/ddr3_smoke_board (bitstream FAEDF476, BIST err_cnt 0, re-run 2026-09-30); board round run01 re-download consistency PASS release/evidence/board/run01',
  'board_reading_rules=board CPI is window-sensitive: same cm50 bitstream gave CPI 1.494 and 1.508 with IDENTICAL ticks/score/flushes -> quote CPI as approx 1.50 only, never 1.508. run_coremark_board.ps1 writes clock_hz=50000000 unconditionally, so its seconds field is WRONG for the 80MHz config (real 33.375s, not 53.400s). CoreMark numbers come from CoreMark-specific bitstreams (DC95F9D0 / F0743756), NOT from the delivered logic-analyzer bitstream (BCAE040A).',
  'board_not_collected=three-round power-cycle test NOT done and the user declined it on 2026-09-30 (run01 only covers re-download, no real power-off; see release/evidence/board/README.md); 80MHz logic-analyzer loopback (only 50MHz has 80/80); DDR3 throughput/latency (never measured); DDR3 wired into the CPU memory path (not started); board run at the 89.25MHz N4 candidate (PDS estimate only, never board-validated)'
) | Set-Content -LiteralPath (Join-Path $releaseRoot 'build_manifest.txt') -Encoding utf8
Write-Host "RELEASE MANIFEST PASS files=$($files.Count)"
