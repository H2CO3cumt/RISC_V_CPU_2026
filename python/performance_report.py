"""Create a reproducible CPI/performance table from Task 24 evidence."""
from pathlib import Path
import re

def parse(path: Path):
    values = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            try: values[k.strip()] = int(v.strip())
            except ValueError: pass
    return values

def report(directory="tmp/task24", output="tmp/performance_report.md"):
    rows = []
    paths = sorted(Path(directory).glob("*-*.perf"))
    if not paths and (Path(directory) / "perf.actual").exists(): paths = [Path(directory) / "perf.actual"]
    for path in paths:
        d = parse(path)
        rows.append((path.stem, d.get("cycles", 0), d.get("retired_instructions", 0), d.get("cpi_x1000", 0), d.get("perf_stall_count", 0), d.get("perf_load_stall_count", 0), d.get("perf_flush_count", 0)))
    out = ["# Pipeline 性能证据（Task 24）", "", "| 配置 | cycles | instret | CPI×1000 | stall | load-stall | flush |", "|---|---:|---:|---:|---:|---:|---:|"]
    out += [f"| {name} | {cyc} | {ins} | {cpi} | {st} | {ls} | {fl} |" for name,cyc,ins,cpi,st,ls,fl in rows]
    out += ["", "CoreMark/MHz、Fmax、LUT/FF/BRAM 和 CoreMark/LUT 只有在官方 CoreMark 源码、授权 PDS 运行和实体板证据齐全后才能填写；不得用本表替代 CoreMark。"]
    Path(output).parent.mkdir(parents=True, exist_ok=True); Path(output).write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"PERFORMANCE REPORT PASS rows={len(rows)} output={output}")

if __name__ == "__main__": report()
