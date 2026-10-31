#!/usr/bin/env python3
"""完整上位机入口（双击即用）。

不带参数时直接停在第 2 页「CPU 数据流（寄存器热力图）」，并离线回放
``samples/trace_hello_rv.log`` 里那一枪真实记录——没有开发板也能看到热力图。
带参数时按命令行处理，例如 ``python pyUI.py --page 1``。
"""
from pathlib import Path
import sys

from mes50hp_validation_ui import main

SAMPLE = Path(__file__).resolve().parent / "samples" / "trace_hello_rv.log"


def _default_argv() -> list:
    argv = sys.argv[1:]
    if argv:
        return argv
    out = ["--page", "2"]
    if SAMPLE.exists():
        out += ["--trace-log", str(SAMPLE)]
    return out


if __name__ == "__main__":
    raise SystemExit(main(_default_argv()))
