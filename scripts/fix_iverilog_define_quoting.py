#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""去掉 iverilog `-D...=\\"...\\"` 的引号转义——它在 PowerShell 7 下会被改坏。

## 症状（实测）

`scripts\\run_final_regression.ps1` 用 `scripts\\resolve_host.ps1` 解析子宿主，
而它**优先选 `pwsh`**（PowerShell 7）：

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { $candidates.Add($pwsh.Source) }     # 第 14-15 行

在 PowerShell 7 下，子脚本里这种写法

    $qs=[char]92+[char]34                                   # \\"
    $initDef='-DTB_PN_INIT_FILE='+$qs+'tb/data/forward.mem'+$qs
    iverilog ... $initDef ...

传给原生程序时参数被改坏，`-DTB_PN_INIT_FILE` **没生效**，于是
`tb/tb_pipeline_no_hazard.v` 里的 `` `ifdef ``/`` `else ``/`` `endif `` 全部报错：

    tb/tb_pipeline_no_hazard.v:20: error: This `ifdef lacks an `endif.
    tb/tb_pipeline_no_hazard.v:22: warning: `else not supported. Use an external preprocessor.
    ...
    -> run_pipeline_forward_tb.ps1 failed with exit code 12

**注意这不是 RTL/TB 的问题**：同一个脚本改用 Windows PowerShell 5.1 跑就完全 PASS。
也就是说 `run_final_regression.ps1` 的成败**取决于 PATH 里有没有 `pwsh`** ——
本机 PATH 里正好有一个 `pwsh.exe`，于是回归会假失败。

## 修法

这些路径**都不含空格**，引号本来就是多余的。去掉 `\\"` 包裹，
`-DTB_PN_INIT_FILE=<path>` 在 PowerShell 5.1 与 7 下都能正确传递。

## 用法

    python scripts\\fix_iverilog_define_quoting.py            # 修改
    python scripts\\fix_iverilog_define_quoting.py --check    # 只检查
"""

import argparse
import glob
import io
import os
import re
import sys

# 匹配： $initDef='-DTB_PN_INIT_FILE='+$qs+'<path>'+$qs
INITDEF = re.compile(r"\$initDef='-DTB_PN_INIT_FILE='\+\$qs\+'([^']+)'\+\$qs")
QS_LINE = re.compile(r"(?m)^([ \t]*)\$qs=\[char\]92\+\[char\]34[ \t]*\r?$")

NOTE = ("$qs=[char]92+[char]34   # 仅为兼容保留；-D 一律不再用 \\\" 包裹："
        "PS7 下会被参数传递层改坏（见 scripts\\fix_iverilog_define_quoting.py）")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sorted(glob.glob(os.path.join(root, "scripts", "*.ps1")))

    changed, problems = [], []
    for path in files:
        with io.open(path, "r", encoding="utf-8", newline="") as fh:
            text = fh.read()
        if "$initDef" not in text:
            continue
        orig = text
        text, n = INITDEF.subn(r"$initDef='-DTB_PN_INIT_FILE=\1'", text)
        if n == 0:
            problems.append("%s: no $initDef assignment matched" % os.path.basename(path))
            continue
        if "$qs" in text:
            text, m = QS_LINE.subn(NOTE, text, count=1)
            if m == 0:
                problems.append("%s: $qs line not normalised" % os.path.basename(path))
                continue
        if text != orig:
            changed.append(os.path.basename(path))
            if not args.check:
                with io.open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(text)

    for p in problems:
        print("PROBLEM " + p)
    if problems:
        print("FIX IVERILOG DEFINE QUOTING FAILED")
        return 1
    if args.check:
        # 幂等检查：不应再有任何 '+$qs+' 形式的 -D 拼接
        bad = []
        for path in files:
            with io.open(path, "r", encoding="utf-8", newline="") as fh:
                if "+$qs+" in fh.read():
                    bad.append(os.path.basename(path))
        if bad:
            print("PROBLEM still using \\\" escaping: " + ", ".join(bad))
            print("FIX IVERILOG DEFINE QUOTING FAILED")
            return 1
        print("FIX IVERILOG DEFINE QUOTING CHECK PASS (no quoted -D defines left)")
        return 0
    if changed:
        print("FIX IVERILOG DEFINE QUOTING %s: %s"
              % ("CHECKED (no write)" if args.check else "APPLIED", ", ".join(changed)))
    else:
        print("FIX IVERILOG DEFINE QUOTING CHECK PASS (already applied)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
