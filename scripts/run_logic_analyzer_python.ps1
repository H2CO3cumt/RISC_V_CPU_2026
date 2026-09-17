$ErrorActionPreference='Stop'
python -m unittest discover -s python -p 'test_logic_analyzer*.py' -v
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
New-Item -ItemType Directory -Force tmp/logic_analyzer | Out-Null
$sample="LA RAW count=00000004 trigger=00000002`r`n00 01 03 07`r`n"
[IO.File]::WriteAllText('tmp/logic_analyzer/sample.txt',$sample)
python python/logic_analyzer.py tmp/logic_analyzer/sample.txt --output-vcd tmp/logic_analyzer/sample.vcd
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
if(-not (Test-Path tmp/logic_analyzer/sample.vcd)){throw 'VCD output missing'}
Write-Output 'ALL LOGIC ANALYZER PYTHON TEST PASS'
