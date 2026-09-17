#!/usr/bin/env python3
"""从 PDS 时序报告 (*.rtr) 提取最差路径（T2）。

分离 slow/fast corner，输出起点/终点/逻辑级数/逻辑与走线延迟占比/slack，
并按终点模块归类（core / perf / uart / gpio / xbar / 其它），用于判断哪些
路径属于 CPU Core、哪些只是可打拍的统计逻辑。

用法：
  D:\\Python313\\python.exe python\\pds_paths.py --report fpga/task28_coremark/report_timing/mes50hp_coremark_top.rtr --top 10
"""
import argparse
import os
import re
import sys

RE_START = re.compile(r"^\s*Startpoint\s*:\s*(.+?)\s*$")
RE_END = re.compile(r"^\s*Endpoint\s*:\s*(.+?)\s*$")
RE_TYPE = re.compile(r"^\s*Path Type\s*:\s*(.+?)\s*$")
RE_ARRIVAL = re.compile(r"Data arrival time\s+([\d.]+)\s+Logic Levels:\s*(\d+)")
RE_SPLIT = re.compile(r"Logic:\s*([\d.]+)ns\(([\d.]+)%\),\s*Route:\s*([\d.]+)ns")
RE_SLACK = re.compile(r"^\s*Slack\s*\(\w+\)\s+(-?[\d.]+)")
RE_CORNER = re.compile(r"^(Slow|Fast) Corner\s*$")


def classify(node):
    n = node
    if n.startswith("core/rf") or n.startswith("core/"):
        return "core"
    if n.startswith("perf") or "/perf" in n:
        return "perf"
    if n.startswith("uart"):
        return "uart"
    if n.startswith("gpio"):
        return "gpio"
    if n.startswith("xbar") or n.startswith("app"):
        return "soc"
    if n.startswith("u_pll") or "pll" in n:
        return "pll"
    return "other"


def parse(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    entries = []
    corner = "slow"
    i = 0
    while i < len(lines):
        m = RE_CORNER.match(lines[i])
        if m:
            corner = m.group(1).lower()
        ms = RE_START.match(lines[i])
        if not ms:
            i += 1
            continue
        rec = {"corner": corner, "startpoint": ms.group(1), "endpoint": "",
               "path_type": "", "arrival": None, "levels": None,
               "logic_ns": None, "logic_pct": None, "route_ns": None, "slack": None}
        for j in range(i, min(i + 300, len(lines))):
            line = lines[j]
            me = RE_END.match(line)
            if me:
                rec["endpoint"] = me.group(1)
            mt = RE_TYPE.match(line)
            if mt:
                rec["path_type"] = mt.group(1)
            ma = RE_ARRIVAL.search(line)
            if ma:
                rec["arrival"] = float(ma.group(1))
                rec["levels"] = int(ma.group(2))
            msp = RE_SPLIT.search(line)
            if msp:
                rec["logic_ns"] = float(msp.group(1))
                rec["logic_pct"] = float(msp.group(2))
                rec["route_ns"] = float(msp.group(3))
            msl = RE_SLACK.match(line)
            if msl:
                rec["slack"] = float(msl.group(1))
                break
        if rec["endpoint"] and rec["slack"] is not None:
            rec["start_class"] = classify(rec["startpoint"])
            rec["end_class"] = classify(rec["endpoint"])
            entries.append(rec)
        i += 1
    return entries


def fmt_paths(entries, top, title):
    out = ["", title, ""]
    out.append("| # | 起点 | 终点 | 逻辑级数 | arrival(ns) | 逻辑(ns/%) | 走线(ns) | slack(ns) | 终点归属 |")
    out.append("|---:|---|---|---:|---:|---:|---:|---:|---|")
    for k, e in enumerate(entries[:top], 1):
        lp = f"{e['logic_ns']}/{e['logic_pct']}%" if e["logic_ns"] is not None else "-"
        rt = f"{e['route_ns']}" if e["route_ns"] is not None else "-"
        out.append(f"| {k} | `{e['startpoint']}` | `{e['endpoint']}` | {e['levels']} | "
                   f"{e['arrival']} | {lp} | {rt} | {e['slack']} | {e['end_class']} |")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", required=True)
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    if not os.path.exists(args.report):
        sys.exit(f"report not found: {args.report}")
    entries = parse(args.report)
    setup_slow = sorted([e for e in entries if e["path_type"].startswith("max") and e["corner"] == "slow"],
                        key=lambda e: e["slack"])
    hold_slow = sorted([e for e in entries if e["path_type"].startswith("min") and e["corner"] == "slow"],
                       key=lambda e: e["slack"])
    lines = [f"# PDS 最差路径提取：`{args.report}`", f"", f"共解析 {len(entries)} 条带 slack 的路径。"]
    lines += fmt_paths(setup_slow, args.top, "## Slow corner 最差 setup 路径")
    lines += fmt_paths(hold_slow, 3, "## Slow corner 最差 hold 路径")
    classes = {}
    for e in setup_slow[:args.top]:
        classes[e["end_class"]] = classes.get(e["end_class"], 0) + 1
    lines += ["", "## 最差路径终点归属统计（前 %d 条）" % args.top, ""]
    for key in sorted(classes):
        lines.append(f"- {key}: {classes[key]}")
    text = "\n".join(lines) + "\n"
    if args.out:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"PATHS REPORT {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
