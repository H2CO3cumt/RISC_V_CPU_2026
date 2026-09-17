"""Extract reproducible PDS/CoreMark evidence without inventing board results."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8", errors="replace")


def sha256(path: str) -> str:
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest().upper()


def timing(path: str) -> dict[str, float]:
    text = read(path)
    row = re.search(r"clk_50m\s+50\.0000 MHz\s+([0-9.]+) MHz\s+20\.0000\s+([0-9.]+)\s+([0-9.]+)", text)
    hold = re.search(r"Hold Summary\(Slow Corner\):.*?clk_50m\s+clk_50m\s+([0-9.]+)", text, re.S)
    if not row or not hold:
        raise ValueError(f"cannot parse timing report {path}")
    return {"estimated_fmax_mhz": float(row.group(1)), "estimated_period_ns": float(row.group(2)),
            "setup_wns_ns": float(row.group(3)), "hold_whs_ns": float(hold.group(1))}


def utilization(path: str) -> dict[str, int | float]:
    """资源三元组必须来自同一阶段：综合统计的 LUT/寄存器/DRM18K。

    布局布线后的 device map 会给出略低的实现 FF（当前 3120，对应综合寄存器 3129），
    该值单独记录为 ff_implemented，不得与综合数字混在同一行里比较。
    """
    text = read(path)
    lut = re.search(r"Total LUTs:\s*(\d+)", text)
    registers = re.search(r"Total Registers:\s*(\d+)", text)
    drm = re.search(r"Total DRM18Ks\s*=\s*([0-9.]+)", text)
    if not lut or not registers or not drm:
        raise ValueError(f"cannot parse synthesis utilization from {path}")
    result: dict[str, int | float] = {"lut": int(lut.group(1)), "ff": int(registers.group(1)),
                                     "drm": float(drm.group(1))}
    implemented = re.search(r"^\| FF\s+\|\s+(\d+)", text, re.M)
    if implemented:
        result["ff_implemented"] = int(implemented.group(1))
    return result


def coremark(path: str) -> dict[str, float | int | str]:
    text = read(path)
    def decimal(label: str) -> int:
        found = re.search(rf"{re.escape(label)}\s*:\s*(\d+)", text)
        if not found:
            raise ValueError(f"missing {label} in {path}")
        return int(found.group(1))
    perf = re.search(r"PERF cycle=([0-9a-f]+) instret=([0-9a-f]+) stall=([0-9a-f]+) load=([0-9a-f]+) branch=([0-9a-f]+) taken=([0-9a-f]+) flush=([0-9a-f]+)", text, re.I)
    if not perf or "Correct operation validated." not in text:
        raise ValueError(f"invalid CoreMark evidence {path}")
    values = [int(value, 16) for value in perf.groups()]
    ticks, iterations = decimal("Total ticks"), decimal("Iterations")
    return {"source": path, "validation": "official CRC validated in RTL simulation",
            "ticks_per_iteration": ticks // iterations, "cycles": values[0], "instret": values[1],
            "stall": values[2], "load_stall": values[3], "branch": values[4],
            "branch_taken": values[5], "flush": values[6], "cpi": values[0] / values[1],
            "coremark_per_mhz": 1_000_000.0 * iterations / ticks}


def predictor(path: str) -> dict[str, int | float]:
    text = read(path)
    execution = re.search(r"COREMARK PIPELINE EXECUTION PASS cycles=(\d+) retired=(\d+)", text)
    perf = re.search(r"COREMARK PERF stall=(\d+) load=(\d+) branch=(\d+) taken=(\d+) flush=(\d+)", text)
    pred = re.search(r"COREMARK PREDICTOR enabled=(\d+) predict=(\d+) btb_hit=(\d+) mispredict=(\d+)", text)
    if not execution or not perf or not pred:
        raise ValueError(f"missing predictor metrics in {path}")
    cycles, instret = (int(value) for value in execution.groups())
    stalls, loads, branches, taken, flushes = (int(value) for value in perf.groups())
    enabled, predicts, hits, misses = (int(value) for value in pred.groups())
    return {"cycles": cycles, "instret": instret, "stall": stalls, "load_stall": loads,
            "branch": branches, "branch_taken": taken, "flush": flushes,
            "cpi": cycles / instret, "enabled": enabled, "predict": predicts,
            "btb_hit": hits, "mispredict": misses}


def main() -> int:
    out = ROOT / "release" / "evidence"
    out.mkdir(parents=True, exist_ok=True)
    configs = {"final": ("fpga/task30_logic_analyzer", "mes50hp_logic_analyzer_top")}
    result: dict[str, object] = {"board_evidence": "not claimed by this extractor"}
    for name, (folder, top) in configs.items():
        bit = f"{folder}/generate_bitstream/{top}.sbit"
        result[name] = {**timing(f"{folder}/report_timing/{top}.rtr"),
                        **utilization(f"{folder}/flow.log"), "bitstream": bit,
                        "bitstream_sha256": sha256(bit)}
    cm_on = coremark("tmp/coremark/uart-random-0-predictor-1.log")
    cm_on.update(predictor("tmp/coremark/sim-random-0-predictor-1.log"))
    cm_off = coremark("tmp/coremark/uart-random-0-predictor-0.log")
    cm_off.update(predictor("tmp/coremark/sim-random-0-predictor-0.log"))
    result["coremark_predictor_on"] = cm_on
    result["coremark_predictor_off"] = cm_off
    (out / "automated_metrics.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    lines = ["# Automated release metrics", "", "Board-measured fields are intentionally not claimed here.", "",
             "| Configuration | LUT | FF | DRM | setup WNS ns | hold WHS ns | estimated Fmax MHz |",
             "|---|---:|---:|---:|---:|---:|---:|"]
    for name in configs:
        value = result[name]
        assert isinstance(value, dict)
        lines.append(f"| {name} | {value['lut']} | {value['ff']} | {value['drm']} | {value['setup_wns_ns']:.3f} | {value['hold_whs_ns']:.3f} | {value['estimated_fmax_mhz']:.4f} |")
    for name in configs:
        value = result[name]
        assert isinstance(value, dict)
        if "ff_implemented" in value:
            lines += ["", f"`{name}` 的 FF 为综合寄存器数；布局布线后 device map 的实现 FF 为 {value['ff_implemented']}，两者阶段不同，不混用。"]
    reduction=(int(cm_off["cycles"])-int(cm_on["cycles"]))/int(cm_off["cycles"])*100.0
    lines += ["", "Official-CRC RTL simulation, same RV32I CoreMark image:", "",
              "| Predictor | cycles | retired | CPI | BTB hit | misprediction |",
              "|---|---:|---:|---:|---:|---:|",
              f"| Off | {cm_off['cycles']} | {cm_off['instret']} | {cm_off['cpi']:.4f} | {cm_off['btb_hit']} | {cm_off['mispredict']} |",
              f"| On | {cm_on['cycles']} | {cm_on['instret']} | {cm_on['cpi']:.4f} | {cm_on['btb_hit']} | {cm_on['mispredict']} |",
              "", f"Predictor On reduces cycles by {reduction:.2f}%. Final physical-board score remains subject to board measurement."]
    (out / "automated_metrics.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("RELEASE EVIDENCE EXTRACTION PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
