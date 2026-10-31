@echo off
rem 上位机启动入口 —— 单文件全功能上位机《逻辑分析仪演示.py》。
rem
rem 2026-10-30 按用户要求收口：上位机只有**一个 py 文件**，本 .cmd 只负责把它拉起来。
rem 以前的 python\pyUI.py + python\mes50hp_validation_ui.py + 5 个模块那套入口不再使用
rem （那套代码仅作为回归测试的被测对象保留）。
rem
rem 本文件在两种目录布局下都能用：
rem   仓库：     python\start_logic_analyzer.cmd   -> ..\逻辑分析仪演示.py
rem   交付包根： 启动逻辑分析仪.cmd                -> .\逻辑分析仪演示.py
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
  py -3 "%APP%"
) else (
  python "%APP%"
)
if errorlevel 1 pause
