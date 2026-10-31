@echo off
rem 上位机启动入口 —— 离线演示路径（**不需要开发板**）。
rem
rem 2026-10-30 收口：单文件上位机《逻辑分析仪演示.py》自带一枪真实记录
rem （内置样例，2026-10-24 板上 tr85 的 100 条提交），所以离线演示不需要任何样本文件：
rem 本 .cmd 只是用 --trace 打开「CPU 数据流」窗口，再点一下『示例数据（不用板子）』。
rem 窗口顶部状态栏会写明"示例数据（离线，不是本机板子）"，不会与实时采集混淆。
chcp 65001 >nul
cd /d "%~dp0"

set "APP=逻辑分析仪演示.py"
if not exist "%APP%" set "APP=..\逻辑分析仪演示.py"
if not exist "%APP%" (
  echo 找不到单文件上位机『逻辑分析仪演示.py』。
  echo 它应当与本文件放在同一目录（交付包）或上一级目录（仓库的 python\）。
  pause
  exit /b 1
)

where py >nul 2>nul
if %errorlevel%==0 (
  py -3 "%APP%" --trace
) else (
  python "%APP%" --trace
)
if errorlevel 1 pause
