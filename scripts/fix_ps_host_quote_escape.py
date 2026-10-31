#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""让 iverilog `-D<name>="<path>"` 在 Windows PowerShell 5.1 与 PowerShell 7 下都正确传递。

## 为什么需要按宿主选转义（实测数据）

iverilog 的 `-D` 值会被当成**常量表达式**解析，所以文件路径必须写成 Verilog 字符串
（带双引号），否则 `tb/data/forward.mem` 会被解析成 `tb / data / forward.mem`：

    tb/tb_pipeline_no_hazard.v:21: error: Unable to bind parameter `data'
    tb/tb_pipeline_no_hazard.v:21: error: A hierarchical reference (`forward.mem') ...

而"把双引号送进原生命令行"这件事，两个宿主的行为**正好相反**（本机实测，用
`-DQ="abc"` + `$display("MACRO_VALUE=%s", `Q)` 判定）：

| 脚本里的写法 | PowerShell 5.1 | PowerShell 7 |
|---|---|---|
| `'-DQ="abc"'`（单引号里放裸双引号） | **FAIL**（引号被剥掉 -> 见 `abc` 未定义） | **PASS** |
| `'-DQ=\\"abc\\"'`（反斜杠转义，就是原来的 `$qs`） | **PASS** | **FAIL**（语法错） |
| `('-DQ=' + [char]34 + 'abc' + [char]34)` | **FAIL** | **PASS** |

**所以没有一种字面写法能同时过两个宿主，必须按版本选。**

## 为什么这件事会影响最终回归

`scripts\\resolve_host.ps1` 解析子宿主时**优先选 `pwsh`**（第 14-15 行）。
本机 PATH 里恰好有一个 `pwsh.exe`（来自另一个工具的运行时缓存），
于是 `run_final_regression.ps1` 会用 PowerShell 7 去跑子 Testbench，
5 个 `run_pipeline_*_tb.ps1` 的 `-D` 全部传坏，回归**假失败**：

    tb/tb_pipeline_no_hazard.v:20: error: This `ifdef lacks an `endif.
    -> run_pipeline_forward_tb.ps1 failed with exit code 12

同一脚本用 Windows PowerShell 5.1 跑则完全 PASS —— **与 RTL/TB 无关，纯粹是宿主差异**。

## 修法

把 `$qs=[char]92+[char]34` 换成按版本选择，`$initDef` 保持原来的 `$qs` 拼接写法：

    if($PSVersionTable.PSVersion.Major -ge 7){ $qs=[char]34 } else { $qs=[char]92+[char]34 }

## 用法

    python scripts\\fix_ps_host_quote_escape.py            # 修改
    python scripts\\fix_ps_host_quote_escape.py --check    # 只检查
"""

import argparse
import glob
import io
import os
import re
import sys

INITDEF_BARE = re.compile(r"\$initDef='-DTB_PN_INIT_FILE=([^']+)'")
INITDEF_QS = re.compile(r"\$initDef='-DTB_PN_INIT_FILE='\+\$qs\+'[^']+'\+\$qs")

QS_LINE = re.compile(r"(?m)^[ \t]*\$qs=\[char\]92\+\[char\]34.*$")

QS_FIX = ("if($PSVersionTable.PSVersion.Major -ge 7){ $qs=[char]34 } "
          "else { $qs=[char]92+[char]34 }   "
          "# 5.1 needs backslash-quote, 7 needs a bare quote (see "
          "scripts/fix_ps_host_quote_escape.py)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sorted(glob.glob(os.path.join(root, "scripts", "*.ps1")))

    changed, problems, ok = [], [], 0
    for path in files:
        with io.open(path, "r", encoding="utf-8", newline="") as fh:
            text = fh.read()
        if "$initDef" not in text and "$qs" not in text:
            continue
        orig = text
        # 1) 先把裸路径写回 $qs 拼接形式（有的脚本只用 $qs、没有 $initDef，要容忍）
        if "$initDef" in text:
            text, n1 = INITDEF_BARE.subn(r"$initDef='-DTB_PN_INIT_FILE='+$qs+'\1'+$qs", text)
            if n1 == 0 and not INITDEF_QS.search(text):
                problems.append("%s: cannot find the $initDef assignment" % os.path.basename(path))
                continue
        # 2) $qs 的定义改成按宿主版本选
        text, n2 = QS_LINE.subn(QS_FIX, text, count=1)
        if n2 == 0 and "PSVersionTable" not in text:
            problems.append("%s: cannot find the $qs definition line" % os.path.basename(path))
            continue
        if text != orig:
            changed.append(os.path.basename(path))
            if not args.check:
                with io.open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(text)
        ok += 1

    for p in problems:
        print("PROBLEM " + p)
    if problems:
        print("FIX PS HOST QUOTE ESCAPE FAILED")
        return 1

    if args.check:
        bad = []
        for path in files:
            with io.open(path, "r", encoding="utf-8", newline="") as fh:
                t = fh.read()
            if "$initDef" in t and "PSVersionTable.PSVersion.Major -ge 7" not in t:
                bad.append(os.path.basename(path))
        if bad:
            print("PROBLEM host-aware quoting missing in: " + ", ".join(bad))
            print("FIX PS HOST QUOTE ESCAPE FAILED")
            return 1
        print("FIX PS HOST QUOTE ESCAPE CHECK PASS (%d script(s) host-aware)" % ok)
        return 0

    if changed:
        print("FIX PS HOST QUOTE ESCAPE APPLIED: " + ", ".join(changed))
    else:
        print("FIX PS HOST QUOTE ESCAPE CHECK PASS (already applied)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
