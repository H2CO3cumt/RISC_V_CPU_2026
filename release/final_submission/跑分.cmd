@echo off
rem ---------------------------------------------------------------------------
rem MES50HP CoreMark scoring - NOTHING to install (no Python, no pyserial).
rem
rem ASCII-ONLY ON PURPOSE: cmd.exe mis-parses non-ASCII bytes in a .cmd even
rem after "chcp 65001" (verified 2026-10-03). All Chinese messages come from
rem tools\coremark_score.ps1 (UTF-8 BOM + [Console]::OutputEncoding).
rem ---------------------------------------------------------------------------
chcp 65001 >nul
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

echo ============================================================
echo   MES50HP CoreMark scoring  (expect Score 79.587 @ 85 MHz)
echo   Uses Windows built-in PowerShell + .NET serial port.
echo   No Python, no extra software needed.
echo ============================================================
echo.
echo Reminder: the board must already run the CoreMark bitstream
echo   bitstream\mes50hp_coremark_85m.sbit   (AUTOSTART=0: this tool sends "R")
echo.

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "tools\coremark_score.ps1" -ClockHz 85000000 -OutDir "results\coremark"
if errorlevel 1 goto failed

echo.
echo [OK] CoreMark score recorded. Opening the result folder ...
start "" "%~dp0results\coremark"
pause
exit /b 0

:failed
echo.
echo [FAIL] scoring failed. Read the red lines above, then check:
echo   1. bitstream = bitstream\mes50hp_coremark_85m.sbit (not the logic analyzer one)
echo   2. do NOT press reset after download; this tool sends "R" every second
echo   3. serial port not opened by PDS terminal / other tools
pause
exit /b 1
