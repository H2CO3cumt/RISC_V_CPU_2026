#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""上位机入口 —— 直接运行同目录的『逻辑分析仪演示.py』（**单文件全功能**上位机）。

按用户要求（2026-10-30）：上位机只保留一个 py 文件，所有功能都在
『逻辑分析仪演示.py』里。本文件退化成跳板：它自己**不实现任何功能**，
也不再引用 python/ 下的任何模块。

历史：2026-10-22 ~ 10-28 期间本文件是"多文件版上位机"
（python/mes50hp_validation_ui.py + trace_view/trace_board/logic_analyzer*）
的入口；那套代码现在只作为回归测试的被测对象保留，不再是用户入口。
"""
import runpy
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent / "逻辑分析仪演示.py"

if not APP.exists():
    print("=" * 66)
    print("找不到单文件上位机：%s" % APP)
    print("")
    print("『逻辑分析仪演示.py』必须和本文件放在同一个目录里。")
    print("如果是在『压缩文件夹预览』里直接双击的，请先把 zip 全部解压缩。")
    print("=" * 66)
    try:
        input("\n按回车键关闭…")
    except EOFError:
        pass
    raise SystemExit(1)

runpy.run_path(str(APP), run_name="__main__")
