#!/usr/bin/env python3
"""T1 归因辅助：把 tb_cpi_attribution 导出的逐 PC 直方图排序，并关联反汇编给出指令文本。

用法:
  D:\\Python313\\python.exe python\\cpi_attribution_report.py --pc-hist tmp/cpi/pc_hist-handoff0-predictor1.csv
"""
import argparse
import csv
import os
import re
import sys

DIS = os.path.join("software", "coremark", "build", "coremark.dis")


def load_disassembly(path):
    """返回 {pc:int -> 'hex: instruction text'}。"""
    table = {}
    if not os.path.exists(path):
        return table
    line_re = re.compile(r"^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]{8})\s+(.*)$")
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = line_re.match(line)
            if m:
                pc = int(m.group(1), 16)
                table[pc] = "%s: %s" % (m.group(2), m.group(3).strip())
    return table


def top(rows, key, n=10):
    return sorted(rows, key=lambda r: r[key], reverse=True)[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pc-hist", required=True)
    ap.add_argument("--log", default=None)
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--dis", default=DIS)
    args = ap.parse_args()

    if not os.path.exists(args.pc_hist):
        print("missing %s" % args.pc_hist, file=sys.stderr)
        return 1

    rows = []
    with open(args.pc_hist, "r", encoding="utf-8") as fh:
        for rec in csv.DictReader(fh):
            rows.append({
                "pc": int(rec["pc"], 16),
                "block": int(rec["block_cycles"]),
                "loads": int(rec["loads"]),
                "stores": int(rec["stores"]),
            })

    dis = load_disassembly(args.dis)
    total_block = sum(r["block"] for r in rows)
    total_loads = sum(r["loads"] for r in rows)
    total_stores = sum(r["stores"] for r in rows)
    total_acc = total_loads + total_stores

    print("=== PC 直方图汇总 ===")
    print("distinct PCs                : %d" % len(rows))
    print("data accesses (load/store)  : %d (%d/%d)" % (total_acc, total_loads, total_stores))
    print("mem_block cycles (attributed): %d" % total_block)
    if total_acc:
        print("board cycles per data access: %.3f" % (total_block / total_acc))

    for label, key in (("阻塞拍最多", "block"), ("load 最多", "loads"), ("store 最多", "stores")):
        print("\n=== 前 %d 个 %s 的 PC ===" % (args.top, label))
        print("%-10s %10s %8s %8s  %s" % ("pc", "block", "loads", "stores", "instruction"))
        for r in top(rows, key, args.top):
            if r[key] == 0:
                continue
            txt = dis.get(r["pc"], "<not in .text>")
            print("%08x %10d %8d %8d  %s" % (r["pc"], r["block"], r["loads"], r["stores"], txt))
    return 0


if __name__ == "__main__":
    sys.exit(main())
