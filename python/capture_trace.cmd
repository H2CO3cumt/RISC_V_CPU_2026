@echo off
chcp 65001 >nul
rem ============================================================================
rem  One-click commit-level trace capture (2026-10-22: now takes any string).
rem
rem  Requires, in this order:
rem    1) the trace85 bitstream already downloaded:
rem          scripts\program_board.ps1 -Config tr85      (PROGRAM PASS)
rem    2) the board's USB-UART (CP2102) on COM11
rem
rem  You type any ASCII string (up to 32 chars); the CPU really reads it,
rem  upper-cases it, XOR-checksums it and writes it back, and the page shows
rem  every retired instruction around that work.
rem
rem  For a GUI with the same input box use:  python\start_logic_analyzer.cmd
rem  (pyUI -> "commit-level dataflow" row).
rem ============================================================================
setlocal
cd /d "%~dp0.."
set PY=python
where py >nul 2>nul && set PY=py -3

set TEXT=%~1
if "%TEXT%"=="" (
  echo.
  echo Type the string to send to the CPU, then press Enter.
  echo   - ASCII only, up to 32 characters.
  echo   - It is NOT decoded or guessed: the CPU really processes it.
  echo   - Default: hello,rv
  echo.
  set /p TEXT=String: 
)
if "%TEXT%"=="" set TEXT=hello,rv

echo.
echo [1/2] phase 0 : "%TEXT%"  - only the processing loop is recorded
%PY% python\trace_board.py --port COM11 --phase 0 --text "%TEXT%" --outdir results\trace85_board
if errorlevel 1 goto fail

echo.
choice /c YN /n /m "Also record the UART polling phase (phase 1)? [Y/N] "
if errorlevel 2 goto openpages
echo [2/2] phase 1 : "%TEXT%"  - includes the polling loop (window fills up)
%PY% python\trace_board.py --port COM11 --phase 1 --text "%TEXT%" --outdir results\trace85_board --timeout 180
if errorlevel 1 goto fail

:openpages
echo.
echo Opening the page(s)...
start "" "results\trace85_board\trace_phase0.html"
if exist "results\trace85_board\trace_phase1.html" start "" "results\trace85_board\trace_phase1.html"
echo.
echo DONE. Pages: results\trace85_board\
pause
exit /b 0

:fail
echo.
echo FAILED. Check:
echo   - bitstream downloaded?   scripts\program_board.ps1 -Config tr85
echo   - CP2102 on COM11?        scripts\demo_preflight.ps1 -Port COM11
echo   - raw log is under results\trace85_board
pause
exit /b 1
