#!/usr/bin/env python3
"""从已有的频率扫描目录重新提取时序/资源汇总为 CSV（无需重跑 PDS）。

按小节标题（Setup Summary(Slow Corner) / Hold Summary(Slow Corner)）定位，
并只接受紧随 `WNS(ns) TNS(ns) Endpoints Endpoints` 表头之后的**数值行**，
避免把 Minimum Pulse Width 的 WPWS（8.483 之类的大数）误当成 setup WNS。

用法：
  python/fmax_summary.py --proj-root tmp/fmax_sweep/after_proj --tag after
"""
import argparse
import csv
import os
import re

RE_SECTION = re.compile(r"^(Setup|Hold) Summary\(Slow Corner\)\s*$")
RE_HEADER = re.compile(r"WNS\(ns\)|WHS\(ns\)")
# 列布局：Launch Clock | Capture Clock | WNS(ns) | TNS(ns) | TNS Failing Endpoints | TNS Total Endpoints
# 时钟名里可能含 `|`（PLL 生成时钟），因此两列都用非贪婪匹配到下一列前的空白。
RE_ROW = re.compile(
    r"^\s*(?P<launch>\S+)\s+(?P<cap>.+?)\s+(?P<v1>-?\d+\.\d+)\s+(?P<v2>-?\d+\.\d+)\s+"
    r"(?P<f1>\d+)\s+(?P<f2>\d+)\s*$"
)


def section_value(lines, which):
    """返回 (value, tns, failing_endpoints)；which 为 'Setup' 或 'Hold'。

    在报告里先从 Performance Summary 之后的第一个 `<which> Summary(Slow Corner)` 标题定位，
    再在其后的表头（含 WNS(ns) 或 WHS(ns)）之后取第一条以 `clk_50m` 开头的数据行。
    """
    target = f"{which} Summary(Slow Corner)"
    start = None
    for i, line in enumerate(lines):
        s = line.strip()
        if s == target or s == target + ":":
            start = i
            break
    if start is None:
        return None
    seen_header = False
    for j in range(start, min(start + 40, len(lines))):
        line = lines[j]
        if RE_HEADER.search(line):
            seen_header = True
            continue
        if not seen_header:
            continue
        if not line.lstrip().startswith("clk_50m"):
            continue
        m = RE_ROW.match(line)
        if m:
            return float(m.group("v1")), float(m.group("v2")), int(m.group("f1"))
    return None


def resources(proj_dir):
    out = {"lut": "", "ff": "", "drm": ""}
    log = os.path.join(proj_dir, "synthesize", "run.log")
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


def find_rtr(proj_dir):
    td = os.path.join(proj_dir, "report_timing")
    if not os.path.isdir(td):
        return None
    cands = [os.path.join(td, f) for f in os.listdir(td) if f.endswith(".rtr")]
    return max(cands, key=os.path.getmtime) if cands else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proj-root", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--sweep-root", default="tmp/fmax_sweep")
    args = ap.parse_args()

    rows = []
    for name in sorted(os.listdir(args.proj_root)):
        d = os.path.join(args.proj_root, name)
        if not os.path.isdir(d):
            continue
        rtr = find_rtr(d)
        if not rtr:
            continue
        with open(rtr, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
        head = "\n".join(lines[:60])
        m = re.search(r"clk_50m\s+([\d.]+) MHz\s+([\d.]+) MHz\s+([\d.]+)\s+([\d.]+)\s+(-?[\d.]+)", head)
        row = {"freq": name,
               "target_mhz": m.group(1) if m else "",
               "est_mhz": m.group(2) if m else "",
               "summary": "MET" if "All Constraints Met" in head else "VIOLATED"}
        setup = section_value(lines, "Setup")
        hold = section_value(lines, "Hold")
        row["wns"] = f"{setup[0]:.3f}" if setup else ""
        row["tns"] = f"{setup[1]:.3f}" if setup else ""
        row["setup_fail"] = setup[2] if setup else ""
        row["whs"] = f"{hold[0]:.3f}" if hold else ""
        row["ths"] = f"{hold[1]:.3f}" if hold else ""
        row["hold_fail"] = hold[2] if hold else ""
        row.update(resources(d))
        rows.append(row)

    def keyf(r):
        try:
            return float(r["target_mhz"])
        except ValueError:
            return 0.0

    rows.sort(key=keyf)
    out = os.path.join(args.sweep_root, f"{args.tag}_sweep_summary.csv")
    os.makedirs(args.sweep_root, exist_ok=True)
    with open(out, "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"REFRESHED {out}")
    for r in rows:
        print(f"  {r['target_mhz']:>9} MHz  {r['summary']:<9} WNS={r['wns']:>8} "
              f"fail={r['setup_fail']:>4}  WHS={r['whs']:>7}  LUT={r['lut']:>5} FF={r['ff']:>5} DRM={r['drm']}")


if __name__ == "__main__":
    main()
