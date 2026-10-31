@echo off
rem ---------------------------------------------------------------------------
rem MES50HP logic analyzer: capture the four modes with NOTHING installed.
rem
rem ASCII-ONLY ON PURPOSE: cmd.exe mis-parses non-ASCII bytes in a .bat/.cmd even
rem after "chcp 65001" (verified 2026-10-03: Chinese echo lines were split into
rem bogus commands like "'0HP' is not recognized"). All Chinese messages are
rem printed by ..\scripts\logic_analyzer_capture.ps1 instead, which handles UTF-8
rem correctly (BOM + [Console]::OutputEncoding).
rem ---------------------------------------------------------------------------
chcp 65001 >nul
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

echo ============================================================
echo   MES50HP logic analyzer - capture static/counter/uart/spi
echo   Uses Windows built-in PowerShell + .NET serial port.
echo   No Python, no GTKWave, no extra software needed.
echo ============================================================
echo.

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "..\scripts\logic_analyzer_capture.ps1" -Output "results" -Runs 1
if errorlevel 1 goto failed

echo.
echo [OK] capture finished - opening the output folder.
echo Double-click the .html file there to view the waveforms in your browser.
echo (No waveform software required. The Chinese page name is printed above.)
start "" "%~dp0results\logic_analyzer"
pause
exit /b 0

:failed
echo.
echo [FAIL] capture failed. Read the red lines above, then check:
echo   1. bitstream = fpga\logic_analyzer_85m\generate_bitstream\mes50hp_logic_analyzer_pll_top.sbit
echo   2. J8 loopback pairs 3-4, 7-8, 11-12, 15-16, 19-20, 23-24, 27-28, 31-32
echo   3. serial port not used by another program
pause
exit /b 1
