#!/usr/bin/env python3
"""A6 故障诊断判定器：把采集结果与真值自动比较，并定位注入的故障。

输入：`tmp/logic_analyzer_fault_diag/capture.log`（由 `tb/tb_logic_analyzer_fault_diag.v` 产生）
  CFG   <tag> <inj_tick> <inj_mask>
  INFO  <first_tick> <trigger_index> <capture_count> <overflow> <ticks>
  CAP   <i> <value>     ← Capture Engine 读出的 Raw 流
  CLEAN <i> <value>     ← 真值：没有注入时引擎应该看到的
  SEEN  <i> <value>     ← 引擎实际看到的（含注入）

判定三件事：
  1. **采集保真**：CAP 必须逐样本等于 SEEN——不多、不少、不重排、不改值；
  2. **定位**：CAP 与 CLEAN 的第一个不同（索引 + 通道位）必须**正好等于**注入描述；
  3. **复现**：注入点若落在采样窗口之外，CAP 必须与 CLEAN 完全一致（窗口没覆盖到的故障
     不能被"诊断"出来，这条防止判定器自欺）。

输出量化报告：`fault_report.md` + `fault_report.json`（含首个差异的索引/通道/位数、
窗口覆盖率、采集保真结论），并打印 `FAULT DIAG <TAG> PASS/FAIL`。
"""

from __future__ import annotations

import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# 场景编号与 Testbench 的 TB_FD_SCEN 一一对应，只用于报告可读性。
SCEN_NAMES = {0: "post", 1: "pre", 2: "before", 3: "none"}
DIR = REPO / "tmp" / "logic_analyzer_fault_diag"
LOG = DIR / "capture.log"


def bits(mask: int) -> list[int]:
    return [b for b in range(8) if (mask >> b) & 1]


def vcd_round_trip(tag: str, cap: dict[int, int], clean: dict[int, int], trig: int) -> dict:
    """把采集流按上位机协议导出成 VCD，再把 VCD 解析回来与真值比较。

    为什么值得单独做一遍：A6 要求的是"Raw / **VCD** / 解析结果与真值自动比较"。
    只看 Raw 相等并不能证明上位机链路可用——VCD 才是交付给用户的产物。
    这里用**同一份** `python/logic_analyzer.py`（生产用的上位机导出器）做端到端比对：
    Raw → 上位机文本协议 → VCD → 解析回样本流 → 与真值比对。
    任何一环丢样本、错位或写坏都会在这里被抓到。
    """
    sys.path.insert(0, str(REPO / "python"))
    import logic_analyzer  # 上位机导出器，与生产链路同一份实现

    order = sorted(cap)
    n = len(order)
    txt = DIR / f"raw_{tag}.txt"
    body = "\n".join(f"{cap[i]:02x}" for i in order)
    txt.write_text(f"LA RAW count={n:x} trigger={trig:x}\n{body}\n", encoding="ascii")

    samples, parsed_trigger = logic_analyzer.parse_raw(txt.read_text(encoding="ascii"))
    vcd = DIR / f"capture_{tag}.vcd"
    logic_analyzer.write_vcd(samples, vcd, channels=8, trigger=parsed_trigger)

    # 反向解析。write_vcd 的格式是固定的："#t" 之后紧跟 8 行 "<bit><ident>"，
    # ident 为 ch<i>，因此这里可以精确还原每个采样点的 8 位值。
    ch_of: dict[str, int] = {}
    stream: list[int] = []
    cur = 0
    seen_time = False
    cur = 0
    seen_time = False
    for raw_line in vcd.read_text(encoding="ascii", errors="replace").splitlines():
        s = raw_line.strip()
        if s.startswith("$var"):
            parts = s.split()
            if len(parts) >= 5 and parts[4].startswith("ch"):
                ch_of[parts[3]] = int(parts[4][2:])
        elif s.startswith("#"):
            if seen_time:
                stream.append(cur)
            seen_time = True
            cur = 0
        elif len(s) >= 2 and s[0] in "01" and s[1:] in ch_of:
            if s[0] == "1":
                cur |= 1 << ch_of[s[1:]]
    if seen_time:
        stream.append(cur)

    # 注意比较对象是**采集流 CAP**，不是真值 CLEAN：
    # VCD 链路的责任是"把采集到的数据一字不差地交给上位机"，
    # 而"采集流与真值的差异"由上面的定位检查负责（差异必须正好等于注入的那一位）。
    expected = [cap[i] for i in order]
    first = None
    for i, (a, b) in enumerate(zip(expected, stream)):
        if a != b:
            first = i
            break
    return {
        "samples_in_vcd": len(stream),
        "expected_samples": len(expected),
        "trigger_in_vcd": parsed_trigger,
        "vcd_first_difference": first,
        "vcd_matches_capture": len(stream) == len(expected) and first is None,
    }
    return {
        "samples_in_vcd": len(stream),
        "expected_samples": len(expected),
        "trigger_in_vcd": parsed_trigger,
        "vcd_first_difference": first,
        "vcd_matches_truth": len(stream) == len(expected) and first is None,
    }


def write_summary() -> int:
    """把本轮所有场景的 JSON 汇总成一张量化表（fault_report.md）。"""
    rows = []
    for path in sorted(DIR.glob("fault_report_*.json")):
        rows.append(json.loads(path.read_text(encoding="utf-8")))
    if not rows:
        print("FAULT DIAG FAIL 没有找到任何场景报告")
        return 1
    lines = [
        "# A6 故障诊断量化报告（全部场景汇总）",
        "",
        "| 场景 | 采集样本 | 触发索引 | 窗口（采样点） | 注入 | 窗口内 | 首个差异（索引/通道掩码） | 采集保真 | 判定 |",
        "|---|---:|---:|---|---|:--:|---|---|:--:|",
    ]
    for r in rows:
        inj = r["injected"]
        fd = r["first_difference"]
        fd_txt = "—" if fd is None else f"{fd['capture_index']} / {fd['mask']}"
        lines.append(
            f"| `{r['tag']}` | {r['capture_count']} | {r['trigger_index']} | "
            f"{r['window_first_tick']}~{r['window_last_tick']} | "
            f"tick {inj['tick']} mask {inj['mask']} | "
            f"{'是' if r['inj_in_window'] else '否'} | {fd_txt} | "
            f"{r['capture_fidelity']} | **{r['verdict']}** |"
        )
    all_pass = all(r["verdict"] == "PASS" for r in rows)
    lines += [
        "",
        f"**总判定：{'PASS' if all_pass else 'FAIL'}**（{len(rows)} 个场景）",
        "",
        "说明：`采集保真` 指 Capture Engine 读出的 Raw 流逐样本等于它当时看到的输入流"
        "（不多、不少、不重排、不改值）；`首个差异` 是采集流与真值流的第一个不同样本，"
        "必须正好落在注入描述上；注入点落在窗口之外时要求**报不出差异**，防止判定器自欺。",
    ]
    (DIR / "fault_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"FAULT DIAG SUMMARY {'PASS' if all_pass else 'FAIL'} scenarios={len(rows)}")
    return 0 if all_pass else 1


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--summary":
        return write_summary()

    if not LOG.exists():
        print(f"FAULT DIAG FAIL 日志不存在：{LOG}")
        return 1

    inj_tick = -1
    inj_mask = 0
    first_tick = trig_index = cap_count = overflow = ticks = 0
    cap: dict[int, int] = {}
    clean: dict[int, int] = {}
    seen: dict[int, int] = {}

    for raw in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
        p = raw.split()
        if not p:
            continue
        if p[0] == "CFG":
            scen = int(p[1])
            tag = SCEN_NAMES.get(scen, f"scen{scen}")
            inj_tick = int(p[2])
            inj_mask = int(p[3], 16)
        elif p[0] == "INFO":
            first_tick, trig_index, cap_count, overflow, ticks = (int(x) for x in p[1:6])
        elif p[0] == "CAP":
            cap[int(p[1])] = int(p[2], 16)
        elif p[0] == "CLEAN":
            clean[int(p[1])] = int(p[2], 16)
        elif p[0] == "SEEN":
            seen[int(p[1])] = int(p[2], 16)

    failures: list[str] = []

    # 1) 采集保真：CAP == SEEN
    fidelity_bad = [i for i in range(cap_count) if cap.get(i) != seen.get(i)]

    # 2) 定位：CAP 与 CLEAN 的第一个不同
    diffs = [(i, clean.get(i, 0) ^ cap.get(i, 0)) for i in range(cap_count)]
    diffs = [(i, m) for i, m in diffs if m != 0]
    first_diff_index = diffs[0][0] if diffs else None
    first_diff_mask = diffs[0][1] if diffs else 0

    # 3) 注入点是否落在窗口内
    inj_in_window = inj_tick >= 0 and first_tick <= inj_tick < (first_tick + cap_count)
    expected_index = (inj_tick - first_tick) if inj_in_window else None

    if fidelity_bad:
        failures.append(
            f"capture fidelity broken at {len(fidelity_bad)} samples (first={fidelity_bad[0]})"
        )
    if inj_mask == 0:
        if diffs:
            failures.append(f"no fault was injected but {len(diffs)} differences were found")
    elif inj_in_window:
        if first_diff_index is None:
            failures.append(
                f"fault injected at tick {inj_tick} (capture index {expected_index}) was NOT detected"
            )
        else:
            if first_diff_index != expected_index:
                failures.append(
                    f"first difference at index {first_diff_index}, expected {expected_index}"
                )
            if first_diff_mask != inj_mask:
                failures.append(
                    f"first difference mask {first_diff_mask:#04x}, expected {inj_mask:#04x}"
                )
    else:
        if diffs:
            failures.append(
                f"fault at tick {inj_tick} is outside the capture window "
                f"[{first_tick},{first_tick + cap_count}) but differences were reported"
            )

    vcd = vcd_round_trip(tag, cap, clean, trig_index)
    if not vcd["vcd_matches_capture"]:
        failures.append(
            "VCD round-trip mismatch: samples={} expected={} first_diff={}".format(
                vcd["samples_in_vcd"], vcd["expected_samples"], vcd["vcd_first_difference"]
            )
        )

    report = {
        "tag": tag,
        "vcd": vcd,
        "capture_count": cap_count,
        "trigger_index": trig_index,
        "overflow": overflow,
        "window_first_tick": first_tick,
        "window_last_tick": first_tick + cap_count - 1,
        "injected": {"tick": inj_tick, "mask": f"0x{inj_mask:02x}", "channels": bits(inj_mask)},
        "inj_in_window": inj_in_window,
        "first_difference": (
            None
            if first_diff_index is None
            else {
                "capture_index": first_diff_index,
                "absolute_tick": first_tick + first_diff_index,
                "mask": f"0x{first_diff_mask:02x}",
                "channels": bits(first_diff_mask),
                "golden": f"0x{clean.get(first_diff_index, 0):02x}",
                "captured": f"0x{cap.get(first_diff_index, 0):02x}",
            }
        ),
        "capture_fidelity": "PASS" if not fidelity_bad else "FAIL",
        "verdict": "PASS" if not failures else "FAIL",
        "failures": failures,
    }

    DIR.mkdir(parents=True, exist_ok=True)
    (DIR / f"fault_report_{tag}.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    lines = [
        f"# A6 故障诊断量化报告 — 场景 `{tag}`",
        "",
        f"- 采集样本数：**{cap_count}**（触发索引 {trig_index}，溢出 {overflow}）",
        f"- 采样窗口：第 {first_tick} ~ {first_tick + cap_count - 1} 个采样点",
        f"- 注入描述：第 {inj_tick} 个采样点翻转 `0x{inj_mask:02x}`（通道 {bits(inj_mask)}）"
        + ("（窗口内）" if inj_in_window else "（**窗口外**）"),
        f"- 采集保真（CAP == SEEN）：**{'PASS' if not fidelity_bad else 'FAIL'}**",
        f"- VCD 链路保真（采集流 → 上位机文本协议 → VCD → 解析回，与 CAP 逐样本一致）：**{'PASS' if vcd['vcd_matches_capture'] else 'FAIL'}**"
        f"（VCD 内 {vcd['samples_in_vcd']} 个采样点，触发索引 {vcd['trigger_in_vcd']}）",
        "",
    ]
    if first_diff_index is None:
        lines.append("- 首个差异：**无**（采集流与真值完全一致）")
    else:
        lines += [
            f"- 首个差异：采集索引 **{first_diff_index}**"
            f"（绝对采样点 {first_tick + first_diff_index}）",
            f"  - 通道掩码 `0x{first_diff_mask:02x}` → 通道 {bits(first_diff_mask)}",
            f"  - 真值 `0x{clean.get(first_diff_index, 0):02x}` vs 采集 `0x{cap.get(first_diff_index, 0):02x}`",
        ]
    lines += ["", f"**判定：{'PASS' if not failures else 'FAIL'}**"]
    for f in failures:
        lines.append(f"- FAIL: {f}")
    (DIR / f"fault_report_{tag}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    if failures:
        print(f"FAULT DIAG {tag} FAIL cap={cap_count} diffs={len(diffs)}")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(
        f"FAULT DIAG {tag} PASS cap={cap_count} fidelity=OK "
        f"first_diff={first_diff_index} mask=0x{first_diff_mask:02x}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
