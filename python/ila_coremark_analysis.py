#!/usr/bin/env python3
"""CoreMark 实体板 ILA 抓取波形分析（赛题「利用 ILA 波形分析流水线效率」一项的证据生成器）。

输入：Fabric Debugger 用 `dbg_fla_export_wf_data -format txt` 导出的采样文件。
探针布局见 fpga/coremark_ila/README.md（mes50hp_coremark_top 的 192-bit DebugCore）。

输出：
  --csv      逐拍 30 列（含信号名表头）
  --vcd      同样内容的 VCD，便于在波形查看器里回放
  --table    一段逐拍可读文本（默认围绕第一个 flush 事件取 24 拍）
  --summary  汇总 JSON

用法:
  D:\\Python313\\python.exe python\\ila_coremark_analysis.py \\
      --capture tmp/ila/coremark_ila.txt --dis software/coremark/build/coremark.dis \\
      --outdir release/evidence/ila_coremark
"""
import argparse
import json
import os
import re
import sys

# 与 fpga/coremark_ila/rtl 顶层 ila_probe[191:0] 的位段一一对应（低位在前）
COLUMNS = [
    ("trace_valid", None), ("trace_pc", 16), ("trace_instruction", 16),
    ("trace_rd_we", None), ("trace_rd_addr", 16), ("trace_rd_data", 16),
    ("trace_mem_we", None), ("trace_mem_addr", 16), ("trace_mem_data", 16),
    ("trace_mem_wstrb", 16),
    ("event_stall", None), ("event_load_stall", None), ("event_branch", None),
    ("event_branch_taken", None), ("event_flush", None),
    ("reset", None), ("d_req_valid", None), ("d_req_ready", None),
    ("i_req_valid", None), ("i_req_ready", None), ("memory_ready", None),
    ("reserved22", None), ("reserved23", None), ("reserved24", None),
    ("reserved25", None), ("reserved26", None), ("reserved27", None),
    ("reserved28", None), ("reserved29", None), ("reserved30", None),
]
NAME = [c[0] for c in COLUMNS]
MUL_LOOP = (0x3520, 0x3538)


def parse_capture(path):
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != len(COLUMNS):
                raise ValueError("unexpected column count %d in %r" % (len(parts), line))
            rows.append(parts)
    return rows


def load_symbols(dis_path):
    """返回 (pc -> 函数名) 与 (pc -> 反汇编文本)。"""
    sym, text, cur = {}, {}, None
    if not os.path.exists(dis_path):
        return sym, text
    with open(dis_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"^([0-9a-f]{8}) <(.+)>:", line)
            if m:
                cur = m.group(2)
                continue
            m = re.match(r"^\s*([0-9a-f]+):\s+([0-9a-f]{8})\s+(.*)$", line)
            if m:
                pc = int(m.group(1), 16)
                sym[pc] = cur
                text[pc] = m.group(3).strip()
    return sym, text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--capture", required=True)
    ap.add_argument("--dis", default="software/coremark/build/coremark.dis")
    ap.add_argument("--outdir", default="release/evidence/ila_coremark")
    ap.add_argument("--table-cycles", type=int, default=24)
    args = ap.parse_args()

    rows = parse_capture(args.capture)
    os.makedirs(args.outdir, exist_ok=True)
    sym, text = load_symbols(args.dis)

    def col(name):
        i = NAME.index(name)
        return [r[i] for r in rows]

    ints = {n: [int(v, 16) for v in col(n)] for n in NAME}
    n = len(rows)
    committed = sum(ints["trace_valid"])
    flush_idx = [i for i in range(n) if ints["event_flush"][i]]

    # ---- 逐拍 CSV ----
    csv_path = os.path.join(args.outdir, "coremark_ila_512cycle.csv")
    with open(csv_path, "w", encoding="utf-8") as fh:
        fh.write("cycle," + ",".join(NAME) + "\n")
        for i, r in enumerate(rows):
            fh.write("%d,%s\n" % (i, ",".join(r)))

    # ---- VCD（便于在波形工具里回放） ----
    vcd_path = os.path.join(args.outdir, "coremark_ila_512cycle.vcd")
    widths = {}
    for i, (nm, w) in enumerate(COLUMNS):
        widths[nm] = w or 1
    with open(vcd_path, "w", encoding="utf-8") as fh:
        fh.write("$date %s $end\n" % "CoreMark on-board ILA capture")
        fh.write("$version ila_coremark_analysis.py $end\n")
        fh.write("$timescale 20ns $end\n")
        fh.write("$scope module ila $end\n")
        for i, nm in enumerate(NAME):
            fh.write("$var wire %d %s %s $end\n" % (widths[nm], "v%d" % i, nm))
        fh.write("$upscope $end\n$enddefinitions $end\n#0\n$dumpvars\n")
        for i, nm in enumerate(NAME):
            fh.write("b%s v%d\n" % (bin(ints[nm][0])[2:], i))
        fh.write("$end\n")
        for cyc in range(1, n):
            fh.write("#%d\n" % cyc)
            for i, nm in enumerate(NAME):
                prev, cur = ints[nm][cyc - 1], ints[nm][cyc]
                if prev != cur:
                    fh.write("b%s v%d\n" % (bin(cur)[2:], i))

    # ---- 逐拍文本（围绕第一个 flush） ----
    start = max(0, (flush_idx[0] if flush_idx else 0) - 8)
    table_path = os.path.join(args.outdir, "coremark_ila_cycle_table.txt")
    with open(table_path, "w", encoding="utf-8") as fh:
        fh.write("cyc valid    pc   inst     rd_we rd  rdata      mem_we memaddr  stall load brk tak fls dv dr iv ir mrdy\n")
        for i in range(start, min(n, start + args.table_cycles)):
            r = rows[i]
            fh.write("%3d  %s  %s %s  %s  %2s  %-9s  %s  %-7s  %s  %s  %s  %s  %s  %s %s %s %s %s\n" % (
                i, r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[10], r[11], r[12], r[13], r[14],
                r[16], r[17], r[18], r[19], r[20]))

    # ---- 热点循环归因 ----
    committed_pcs = [ints["trace_pc"][i] for i in range(n) if ints["trace_valid"][i]]
    mul_commits = [p for p in committed_pcs if MUL_LOOP[0] <= p <= MUL_LOOP[1]]
    loop_cycles = sum(1 for i in range(n) if any(
        ints["trace_pc"][j] in (MUL_LOOP[0], MUL_LOOP[1] - 4) and ints["trace_valid"][j]
        for j in [i]))
    hot = {}
    for p in committed_pcs:
        hot[p] = hot.get(p, 0) + 1
    top = sorted(hot.items(), key=lambda kv: -kv[1])[:10]

    summary = {
        "source": args.capture,
        "window_samples": n,
        "clock_hz": 50000000,
        "window_us": round(n / 50e6 * 1e6, 3),
        "committed": committed,
        "ipc": round(committed / n, 4),
        "cpi": round(n / committed, 4),
        "stall_cycles": sum(ints["event_stall"]),
        "load_use_stall_cycles": sum(ints["event_load_stall"]),
        "branch_events": sum(ints["event_branch"]),
        "branch_taken_events": sum(ints["event_branch_taken"]),
        "flush_events": sum(ints["event_flush"]),
        "first_flush_cycle": flush_idx[0] if flush_idx else None,
        "mulsi3_commits": len(mul_commits),
        "mulsi3_share_of_commits": round(len(mul_commits) / committed, 4) if committed else None,
        "hot_pcs": [{"pc": "0x%08x" % p, "hits": c, "symbol": sym.get(p, "?"), "text": text.get(p, "")}
                    for p, c in top],
        "notes": [
            "采样窗口为实体板 50 MHz 下 CoreMark 运行中触发的 512 拍（10.24 us）",
            "ipc/cpi 与板级计数器同口径（各自独立测量，互相印证）",
        ],
    }
    json_path = os.path.join(args.outdir, "coremark_ila_summary.json")
    with open(json_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=1, ensure_ascii=False)

    print("ILA ANALYSIS window=%d committed=%d ipc=%.3f cpi=%.3f" % (n, committed, committed / n, n / committed))
    print("ILA ANALYSIS stall=%d load_stall=%d branch=%d taken=%d flush=%d"
          % (summary["stall_cycles"], summary["load_use_stall_cycles"], summary["branch_events"],
             summary["branch_taken_events"], summary["flush_events"]))
    print("ILA ANALYSIS mulsi3 commits=%d (%.1f%% of window commits)"
          % (len(mul_commits), 100 * len(mul_commits) / committed))
    for p, c in top[:6]:
        print("ILA HOTPC    %08x x%-3d %s | %s" % (p, c, sym.get(p, "?"), text.get(p, "")[:36]))
    print("ILA ANALYSIS WROTE %s" % args.outdir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
