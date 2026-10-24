param(
  [string]$Text = '',
  [int]$Phase = 0,
  [string]$Port = 'COM11',
  [string]$OutDir = 'tmp/trace_python'
)
$ErrorActionPreference='Stop'
# Python-side judgements for the commit-level trace feature:
#   · tests/test_trace_view.py   - record layout, decoder, parser, judgements, page, wave alignment
#   · test_trace_ui.py           - the pyUI input box + the two-page layout (skips when no Tk display)
#   · test_trace_ui_pixels.py    - 像素级冒烟：泳道高度/色块数/光标落点（挡"代码对、画面错"）
New-Item -ItemType Directory -Force $OutDir|Out-Null
Push-Location 'python'
try {
  python -m unittest tests.test_trace_view
  if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
  python -m unittest test_trace_ui
  if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
  python -m unittest test_trace_ui_pixels
  if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
} finally { Pop-Location }
Write-Host 'ALL TRACE PYTHON TEST PASS'
exit 0
