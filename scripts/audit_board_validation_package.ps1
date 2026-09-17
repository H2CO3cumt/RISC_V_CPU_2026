$ErrorActionPreference = 'Stop'
$packageRoot = Join-Path (Resolve-Path '.').Path 'release/board_validation'
if(-not (Test-Path -LiteralPath $packageRoot -PathType Container)){ throw 'BOARD PACKAGE AUDIT FAIL package missing' }

$required = @(
  'README.md','bitstreams.json',
  'bitstreams/pipeline_soc.sbit','bitstreams/coremark_stable.sbit',
  'bitstreams/coremark_debug_ila.sbit','bitstreams/logic_analyzer_p0.sbit',
  'pyui/pyUI.py','pyui/mes50hp_validation_ui.py','pyui/coremark_serial.py',
  'pyui/logic_analyzer_serial.py','pyui/logic_analyzer.py','pyui/pyUI_requirements.txt',
  'projects/task26_pipeline_soc/impl.pds','projects/task26_pipeline_soc/task26_generated.pds',
  'projects/task28_coremark/task28_generated.pds',
  'projects/task29_coremark_ila/task29_coremark_ila.pds',
  'projects/task30_logic_analyzer/task30_generated.pds'
)
foreach($relative in $required){
  $path=Join-Path $packageRoot $relative
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "BOARD PACKAGE AUDIT FAIL missing $relative"}
  if((Get-Item -LiteralPath $path).Length -eq 0){throw "BOARD PACKAGE AUDIT FAIL empty $relative"}
}

$expected=@{
  'bitstreams/pipeline_soc.sbit'='548AEF4B95282A4A98FCF9460CEC1B85AE3E7D2CBED1D893168BC40659159253'
  'bitstreams/coremark_stable.sbit'='3204B46D8B447BB8206A914FA4A7CFBE6560144CE15DF6DD2A9C8A96884A3581'
  'bitstreams/coremark_debug_ila.sbit'='B2F4C8A30A6207942786257AEFF9B35DF1DF1EA413F872DAC67E6BD0D5D24506'
  'bitstreams/logic_analyzer_p0.sbit'='C8123DA9699AE29D528F2FE61BFD8A3064DB678DB9AA1F0050EA490545BF779A'
}
$json = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'bitstreams.json') | ConvertFrom-Json
foreach($item in $json){
  if(-not $expected.ContainsKey($item.file)){throw "BOARD PACKAGE AUDIT FAIL unexpected bitstream $($item.file)"}
  $path=Join-Path $packageRoot $item.file
  $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  if($hash -ne $expected[$item.file] -or $item.bytes -ne (Get-Item -LiteralPath $path).Length){throw "BOARD PACKAGE AUDIT FAIL metadata $($item.file)"}
}
if($json.Count -ne 4){throw "BOARD PACKAGE AUDIT FAIL bitstream metadata count=$($json.Count)"}

$astFiles = @('pyui/pyUI.py','pyui/mes50hp_validation_ui.py','pyui/coremark_serial.py','pyui/logic_analyzer_serial.py','pyui/logic_analyzer.py') | ForEach-Object { (Join-Path $packageRoot $_).Replace('\','/') }
$astArg = $astFiles -join "','"
& python -c "import ast; [ast.parse(open(p, encoding='utf-8').read(), filename=p) for p in ['$astArg']]"
if($LASTEXITCODE -ne 0){throw 'BOARD PACKAGE AUDIT FAIL Python syntax'}

$projects = Get-ChildItem -LiteralPath (Join-Path $packageRoot 'projects') -Directory
foreach($project in $projects){
  $recipe=Join-Path $project.FullName 'pds_recipe.tcl'
  foreach($line in Get-Content -LiteralPath $recipe){
    if($line -match '^add_design\s+(.+)$'){
      $relative=$Matches[1].Trim(); $path=if($relative -like '../../rtl/*'){Join-Path $packageRoot ($relative -replace '^../../','')}else{Join-Path $project.FullName $relative}
      if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "BOARD PACKAGE AUDIT FAIL $($project.Name) missing $relative"}
    }
    if($line -match '^add_constraint\s+-fdc\s+(.+)$'){
      $relative=$Matches[1].Trim();$path=Join-Path $project.FullName $relative
      if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "BOARD PACKAGE AUDIT FAIL $($project.Name) missing $relative"}
    }
  }
}
Write-Host "BOARD PACKAGE AUDIT PASS projects=$($projects.Count) bitstreams=$($json.Count) files=$((Get-ChildItem -LiteralPath $packageRoot -File -Recurse).Count)"
