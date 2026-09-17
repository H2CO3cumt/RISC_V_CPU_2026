$ErrorActionPreference='Stop'
$releaseRoot=Join-Path (Resolve-Path '.').Path 'release'
$artifactRoot=Join-Path $releaseRoot 'artifacts'
New-Item -ItemType Directory -Force $artifactRoot | Out-Null

# 最终交付只保留一套可下载配置；阶段性 bitstream 仍留在各自 FPGA
# 工程目录作为开发证据，不再混入最终 artifacts。
foreach($legacy in @('pipeline_soc.sbit','pipeline_soc_timing.rtr','coremark_stable.sbit','coremark_stable_timing.rtr','coremark_debug_ila.sbit','coremark_debug_ila_timing.rtr','logic_analyzer_p0.sbit','logic_analyzer_p0_timing.rtr','coremark_imem.mem','coremark_drom.mem','coremark_ram.mem','task30_program.mem')){
  $legacyPath=Join-Path $artifactRoot $legacy
  if(Test-Path -LiteralPath $legacyPath){Remove-Item -LiteralPath $legacyPath -Force}
}

$artifacts=@(
  @('fpga/task30_logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit','mes50hp_riscv_logic_analyzer.sbit'),
  @('fpga/task30_logic_analyzer/report_timing/mes50hp_logic_analyzer_top.rtr','mes50hp_riscv_logic_analyzer_timing.rtr'),
  @('fpga/task30_logic_analyzer/rtl/task30_program.mem','logic_analyzer_firmware.mem')
)
foreach($pair in $artifacts){
  if(-not (Test-Path -LiteralPath $pair[0])){throw "Release artifact missing: $($pair[0])"}
  Copy-Item -LiteralPath $pair[0] -Destination (Join-Path $artifactRoot $pair[1]) -Force
}

$roots=@('AGENTS.md','AGENTS.local.md','rtl','tb','scripts','python','software','docs','third_party/coremark',
         'fpga/task26_pipeline_soc','fpga/task28_coremark','fpga/task29_coremark_ila','fpga/task30_logic_analyzer',
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
  $relative=[System.IO.Path]::GetRelativePath($repoRoot,$file.FullName).Replace('\','/')
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
  'scope=Task0-30,Task32,Task33-35;Task31 RLE frozen',
  'board_results=logic analyzer J8 physical loopback 80/80 PASS in release/evidence/logic_analyzer_board_final; other board results remain evidence-gated'
) | Set-Content -LiteralPath (Join-Path $releaseRoot 'build_manifest.txt') -Encoding utf8
Write-Host "RELEASE MANIFEST PASS files=$($files.Count)"
