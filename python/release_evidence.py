"""Extract reproducible PDS/CoreMark evidence without inventing board results."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    """读取文本，自动兼容 UTF-8 与 UTF-16。

    为什么需要兼容：本仓库的日志多数由 PowerShell 的 `Tee-Object` 落盘，
    而 Windows PowerShell 5.1 的 `Tee-Object` 默认写 UTF-16LE（每字节前带 \\x00）。
    早期实现固定按 UTF-8 读，结果是"文件明明有内容却匹配不到任何字段"，
    Task 29 证据提取在本机必然失败。这里按 UTF-8 → UTF-16 顺序尝试，
    以"能否正常解码且不含 NUL"作为判定，不依赖 BOM。
    """
    raw = (ROOT / path).read_bytes()
    for encoding in ("utf-8-sig", "utf-16", "utf-8"):
        try:
            text = raw.decode(encoding)
        except UnicodeDecodeError:
            continue
        if "\x00" not in text:
            return text
    return raw.decode("utf-8", errors="replace").replace("\x00", "")


def sha256(path: str) -> str:
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest().upper()


def timing(path: str) -> dict[str, float]:
    """从 PDS 时序报告里取 Setup/Hold 汇总。

    【2026-09-30 改】旧实现把行首写死成 ``clk_50m 50.0000 MHz ... 20.0000``，
    只认"声明时钟 50 MHz"那一种排版。交付配置切到 85 MHz PLL 版之后，
    PDS 推导出的是**生成时钟** ``clk_50m|u_pll/u_pll_85m/CLKOUT0_Inferred``，
    名字太长会**折行**：时钟名单独一行、数值在下一行。
    现在改成按"段落 + 数字序列"解析，两种排版都吃得下，也不再把 50 MHz 写死。
    """
    text = read(path).replace("\r\n", "\n").replace("\r", "\n")  # .rtr 是 CRLF，正则按 \n 写
    perf = re.search(r"Performance Summary:\s*\n\*+\n.*?\n-{10,}\n(.*?)\n=+", text, re.S)
    hold = re.search(r"Hold Summary\(Slow Corner\):\s*\n\*+\n.*?\n-{10,}\n(.*?)\n=+", text, re.S)
    if not perf or not hold:
        raise ValueError(f"cannot parse timing report {path}")
    # 只取带小数点的数字，避免把时钟名里的 "85m" / "CLKOUT0" 当数值
    nums = re.findall(r"([0-9]+\.[0-9]+)", perf.group(1))
    if len(nums) < 5:
        raise ValueError(f"unexpected Performance Summary in {path}: {nums!r}")
    # 列序：Requested Freq | Estimated Freq | Requested Period | Estimated Period | Slack
    whs = re.findall(r"([0-9]+\.[0-9]+)", hold.group(1))
    if not whs:
        raise ValueError(f"unexpected Hold Summary in {path}")
    return {"estimated_fmax_mhz": float(nums[1]), "estimated_period_ns": float(nums[3]),
            "setup_wns_ns": float(nums[4]), "hold_whs_ns": float(whs[0])}


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
    perf = re.search(r"COREMARK PERF stall=(\d+) load_stall=(\d+) branch=(\d+) taken=(\d+) flush=(\d+)", text)
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
    # 【2026-09-30 交付配置切换】交付主位流由 50 MHz 版改为 **85 MHz PLL 版**：
    # 板载 50 MHz 晶振经 PLL（STATIC_RATIOF=17 => VCO 850 MHz，ODIV0=10）得到 85.000 MHz。
    # 原因：赛题指标第 (2) 条要"最高工作频率"，交付件本身跑 85 MHz 才能自证，
    # 免得出现"报告写 85 MHz、交的位流却是 50 MHz"的观感问题。
    # 50 MHz 版工程 fpga/logic_analyzer 原样保留，作为**已验证备用位流**随包提供。
    configs = {"final": ("fpga/logic_analyzer_85m", "mes50hp_logic_analyzer_pll_top")}
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
