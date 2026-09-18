param([string]$Destination = 'release/board_validation')
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path '.').Path
$packageRoot = Join-Path $repoRoot $Destination
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
$packageCache = Join-Path $packageRoot 'pyui/__pycache__'
if(Test-Path -LiteralPath $packageCache -PathType Container){
  $rootPrefix=[System.IO.Path]::GetFullPath($packageRoot).TrimEnd('\') + '\'
  $cacheFull=[System.IO.Path]::GetFullPath($packageCache)
  if(-not $cacheFull.StartsWith($rootPrefix,[System.StringComparison]::OrdinalIgnoreCase)){throw "Refusing cache cleanup outside package: $cacheFull"}
  Remove-Item -LiteralPath $cacheFull -Recurse -Force
}

function Copy-RequiredFile([string]$Source, [string]$Target) {
  $sourcePath = Join-Path $repoRoot $Source
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "BOARD PACKAGE MISSING $Source" }
  $targetPath = Join-Path $packageRoot $Target
  $targetDir = Split-Path -Parent $targetPath
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
}

# Shared RTL is placed at packageRoot/rtl because every PDS project keeps the
# original ../../rtl source references and is opened from packageRoot/projects/*.
$sharedRtl = @(
  'pipeline_cpu.v','branch_predictor.v','forward_unit.v','hazard_unit.v','perf_monitor.v','perf_mmio.v',
  'regfile.v','alu.v','imm_gen.v','decoder.v','branch_unit.v','load_store_unit.v',
  'soc_data_interconnect.v','soc_fpga_memory.v','uart_tx.v','uart_rx.v',
  'uart_mmio.v','gpio_mmio.v','capture_engine.v','logic_analyzer_pattern_gen.v',
  'logic_analyzer_mmio.v','application_mmio_mux.v'
)
foreach($name in $sharedRtl){ Copy-RequiredFile "rtl/$name" "rtl/$name" }

$projects = @(
  @{ Name='pipeline_soc'; Source='fpga/pipeline_soc'; Pds=@('impl.pds','pipeline_soc_generated.pds') },
  @{ Name='coremark'; Source='fpga/coremark'; Pds=@('coremark_generated.pds') },
  @{ Name='coremark_ila'; Source='fpga/coremark_ila'; Pds=@('coremark_ila.pds') },
  @{ Name='logic_analyzer'; Source='fpga/logic_analyzer'; Pds=@('logic_analyzer_generated.pds') }
)
foreach($project in $projects){
  $sourceRoot = Join-Path $repoRoot $project.Source
  $destRoot = Join-Path $packageRoot "projects/$($project.Name)"
  New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
  foreach($pds in $project.Pds){ Copy-RequiredFile "$($project.Source)/$pds" "projects/$($project.Name)/$pds" }
  foreach($name in @('pds_recipe.tcl','impl.tcl','README.md')){
    $sourcePath = Join-Path $sourceRoot $name
    if(Test-Path -LiteralPath $sourcePath -PathType Leaf){ Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $destRoot $name) -Force }
  }
  foreach($folder in @('constraints','rtl')){
    $sourceFolder = Join-Path $sourceRoot $folder
    if(Test-Path -LiteralPath $sourceFolder -PathType Container){
      Get-ChildItem -LiteralPath $sourceFolder -File -Recurse | Where-Object {
        $_.Extension -in @('.v','.vhd','.vhdl','.mem','.fdc','.tcl','.ipc','.fic','.md')
      } | ForEach-Object {
        $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\','/')
        $target = Join-Path $destRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
      }
    }
  }
  if($project.Name -eq 'coremark_ila'){
    $ipRoot = Join-Path $sourceRoot 'ip'
    Get-ChildItem -LiteralPath $ipRoot -File -Recurse | Where-Object {
      $_.Extension -in @('.v','.vhd','.vhdl','.fdc','.tcl','.ipc')
    } | ForEach-Object {
      $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\','/')
      $target = Join-Path $destRoot $relative
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
      Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
  }
  $generated = Join-Path $sourceRoot 'generate_bitstream'
  if(Test-Path -LiteralPath $generated -PathType Container){
    New-Item -ItemType Directory -Force -Path (Join-Path $destRoot 'generate_bitstream') | Out-Null
    Get-ChildItem -LiteralPath $generated -File | Where-Object {
      $_.Extension -in @('.sbit','.smsk','.bgr','.db')
    } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destRoot "generate_bitstream/$($_.Name)") -Force }
  }
  $timing = Join-Path $sourceRoot 'report_timing'
  if(Test-Path -LiteralPath $timing -PathType Container){
    New-Item -ItemType Directory -Force -Path (Join-Path $destRoot 'report_timing') | Out-Null
    Get-ChildItem -LiteralPath $timing -File -Filter '*.rtr' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destRoot "report_timing/$($_.Name)") -Force }
  }
}

# Board-facing Python helpers and the Tkinter PyUI are kept together so the
# copied package runs without importing files from the repository root.
foreach($name in @('pyUI.py','mes50hp_validation_ui.py','coremark_serial.py','logic_analyzer_serial.py','logic_analyzer.py','pyUI_requirements.txt')){
  Copy-RequiredFile "python/$name" "pyui/$name"
}
Copy-RequiredFile 'scripts/audit_board_validation_package.ps1' 'audit_board_validation_package.ps1'

$bitstreams = @(
  @{ Source='release/artifacts/pipeline_soc.sbit'; Name='pipeline_soc.sbit'; Task='Pipeline SoC' },
  @{ Source='release/artifacts/coremark_stable.sbit'; Name='coremark_stable.sbit'; Task='CoreMark' },
  @{ Source='release/artifacts/coremark_debug_ila.sbit'; Name='coremark_debug_ila.sbit'; Task='CoreMark DebugCore' },
  @{ Source='release/artifacts/logic_analyzer_p0.sbit'; Name='logic_analyzer_p0.sbit'; Task='Logic Analyzer P0' }
)
$manifest = @()
foreach($item in $bitstreams){
  Copy-RequiredFile $item.Source "bitstreams/$($item.Name)"
  $path = Join-Path $packageRoot "bitstreams/$($item.Name)"
  $manifest += [pscustomobject]@{ task=$item.Task; file="bitstreams/$($item.Name)"; bytes=(Get-Item -LiteralPath $path).Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $packageRoot 'bitstreams.json') -Encoding utf8
Copy-RequiredFile 'docs/reproduction.md' 'docs/reproduction.md'
Copy-RequiredFile 'release/materials/field_recovery_card.md' 'docs/field_recovery_card.md'
$zipPath = Join-Path $repoRoot 'release/MES50HP_board_validation_package.zip'
Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -Force
Write-Host "BOARD VALIDATION PACKAGE PASS root=$packageRoot bitstreams=$($manifest.Count)"
