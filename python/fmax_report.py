#!/usr/bin/env python3
"""汇总频率扫描数据为 Markdown 表（T0 / T4 / T6）。

输入：由 scripts/run_fmax_sweep_rtl.ps1 生成的 <tag>_sweep_summary.csv
     以及各频率点工程目录下的 report_timing/*.rtr 与 synthesize/run.log。

用法：
  D:\\Python313\\python.exe python\\fmax_report.py --sweep-root tmp/fmax_sweep --tag after
"""
import argparse
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pds_paths import parse  # noqa: E402


def read_csv(path):
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def rtr_of(proj_dir):
    td = os.path.join(proj_dir, "report_timing")
    if not os.path.isdir(td):
        return None
    cands = [os.path.join(td, f) for f in os.listdir(td) if f.endswith(".rtr")]
    if not cands:
        return None
    return max(cands, key=os.path.getmtime)


def resources(proj_dir):
    log = os.path.join(proj_dir, "synthesize", "run.log")
    out = {"lut": "", "ff": "", "drm": ""}
    if not os.path.exists(log):
        return out
    with open(log, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    for key, pat in (("lut", r"Total LUTs:\s*(\d+)"),
                     ("ff", r"Total Registers:\s*(\d+)"),
                     ("drm", r"Total DRM18Ks\s*=\s*([\d.]+)")):
        m = re.search(pat, text)
        if m:
            out[key] = m.group(1)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep-root", default="tmp/fmax_sweep")
    ap.add_argument("--tag", required=True)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    proj_root = os.path.join(args.sweep_root, f"{args.tag}_proj")
    if not os.path.isdir(proj_root):
        sys.exit(f"missing sweep project dir: {proj_root}")
    rtl_dir = os.path.join(args.sweep_root, f"{args.tag}_rtl")

    rows = []
    for name in sorted(os.listdir(proj_root)):
        d = os.path.join(proj_root, name)
        if not os.path.isdir(d):
            continue
        rtr = rtr_of(d)
        if not rtr:
            continue
        with open(rtr, "r", encoding="utf-8", errors="replace") as fh:
            head = fh.read(4000)
        m = re.search(r"clk_50m\s+([\d.]+) MHz\s+([\d.]+) MHz\s+([\d.]+)\s+([\d.]+)\s+(-?[\d.]+)", head)
        target = est = wns = ""
        if m:
            target, est, wns = m.group(1), m.group(2), m.group(5)
        ds = "MET" if "All Constraints Met" in head else "VIOLATED"
        entries = parse(rtr)
        setup = sorted([e for e in entries if e["path_type"].startswith("max") and e["corner"] == "slow"],
                       key=lambda e: e["slack"])
        hold = sorted([e for e in entries if e["path_type"].startswith("min") and e["corner"] == "slow"],
                      key=lambda e: e["slack"])
        whs = hold[0]["slack"] if hold else ""
        res = resources(d)
        worst = setup[0] if setup else None
        rows.append({
            "target_mhz": target, "est_mhz": est, "wns": wns, "whs": whs, "summary": ds,
            "lut": res["lut"], "ff": res["ff"], "drm": res["drm"],
            "worst_start": worst["startpoint"] if worst else "",
            "worst_end": worst["endpoint"] if worst else "",
            "worst_levels": worst["levels"] if worst else "",
            "worst_arrival": worst["arrival"] if worst else "",
            "worst_logic_pct": worst["logic_pct"] if worst else "",
            "proj": os.path.relpath(d, args.sweep_root).replace("\\", "/"),
            "rtr": os.path.relpath(rtr, os.path.dirname(args.sweep_root)).replace("\\", "/"),
        })

    def keyf(r):
        try:
            return float(r["target_mhz"])
        except ValueError:
            return 0.0

    rows.sort(key=keyf)
    lines = [f"## 频率扫描结果 tag=`{args.tag}`", ""]
    lines.append(f"RTL 快照：`{os.path.relpath(rtl_dir, '.').replace(os.sep, '/')}`")
    lines.append("")
    lines.append("| 目标 MHz | All Met | setup WNS(ns) | hold WHS(ns) | 估算 Fmax(MHz) | LUT | FF | DRM18K | 最差路径终点 | 逻辑级数 |")
    lines.append("|---:|---|---:|---:|---:|---:|---:|---:|---|---:|")
    for r in rows:
        lines.append(f"| {r['target_mhz']} | {r['summary']} | {r['wns']} | {r['whs']} | {r['est_mhz']} | "
                     f"{r['lut']} | {r['ff']} | {r['drm']} | `{r['worst_end']}` | {r['worst_levels']} |")
    lines.append("")
    for r in rows:
        lines.append(f"- **{r['target_mhz']} MHz**（`{r['proj']}`）最差路径："
                     f"`{r['worst_start']}` → `{r['worst_end']}`，"
                     f"{r['worst_levels']} 级逻辑，arrival {r['worst_arrival']} ns，"
                     f"逻辑延迟占比 {r['worst_logic_pct']}%，报告 `{r['rtr']}`")
    text = "\n".join(lines) + "\n"
    if args.out:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"FMAX REPORT {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
