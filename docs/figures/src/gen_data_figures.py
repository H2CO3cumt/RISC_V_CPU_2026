# -*- coding: utf-8 -*-
"""生成设计文档的数据图（图 3-5 ~ 图 3-8）为 .drawio 文件。

为什么不用 matplotlib：本机 Python 未安装 matplotlib，为不改动用户环境，
这里只做几何计算，最终由 draw.io 渲染，与正文其它插图共用同一套字体与配色。

数据来源（全部来自 release/evidence/ 与 docs/）：
  图 3-5  automated_metrics.json → coremark_predictor_on / _off
  图 3-6  docs/coremark_cpi_analysis.md §8.1（rv32im，1 次迭代）
  图 3-7  release/evidence/claims_map.md §3.1~§3.4
  图 3-8  release/evidence/logic_analyzer_board_85m/*/summary.json

用法：python gen_data_figures.py
"""
from __future__ import annotations

import json
import pathlib

ROOT = pathlib.Path(r"D:\RISC_V_CPU_2026")
OUT = ROOT / "docs" / "figures" / "src"

TEXT = "#1F1F1F"
PAL = {
    "orange": ("#FFD9B0", "#C86F17"),
    "orange_lt": ("#FFE9D2", "#D9822B"),
    "blue": ("#CCE2F7", "#2E6FB7"),
    "green": ("#D8EEDA", "#2E7D32"),
    "purple": ("#D6C2F5", "#6335C6"),
    "purple_lt": ("#E7DBFA", "#7A4FD0"),
    "gray": ("#EDEDED", "#5F5F5F"),
    "gray_lt": ("#F5F5F5", "#ABABAB"),
    "red": ("#F8D7D3", "#C0392B"),
    "white": ("#FFFFFF", "#000000"),
}


class Fig:
    def __init__(self, name: str, w: int, h: int):
        self.name = name
        self.w = w
        self.h = h
        self.cells: list[str] = []
        self._id = 0

    def _nid(self, prefix: str = "c") -> str:
        self._id += 1
        return f"{prefix}{self._id}"

    def rect(self, x, y, w, h, fill, stroke, label="", size=13, bold=False,
             align="center", valign="middle", dashed=False, spacing_left=8):
        cid = self._nid()
        style = (
            f"rounded=0;whiteSpace=wrap;html=1;fontSize={size};"
            f"fontFamily=Microsoft YaHei;fillColor={fill};strokeColor={stroke};"
            f"strokeWidth=1.5;align={align};verticalAlign={valign};"
            f"spacingLeft={spacing_left};"
        )
        if bold:
            style += "fontStyle=1;"
        if dashed:
            style += "dashed=1;"
        val = label.replace("\n", "&#10;")
        self.cells.append(
            f'<mxCell id="{cid}" value="{val}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" /></mxCell>'
        )
        return cid

    def text(self, x, y, w, h, label, size=13, color=TEXT, bold=False, align="left"):
        cid = self._nid()
        style = (
            f"text;html=1;whiteSpace=wrap;fontSize={size};fontFamily=Microsoft YaHei;"
            f"fontColor={color};align={align};verticalAlign=middle;"
        )
        if bold:
            style += "fontStyle=1;"
        val = label.replace("\n", "&#10;")
        self.cells.append(
            f'<mxCell id="{cid}" value="{val}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" /></mxCell>'
        )
        return cid

    def line(self, x1, y1, x2, y2, color="#000000", width=1.5, dashed=False, arrow=False):
        cid = self._nid()
        style = f"html=1;strokeColor={color};strokeWidth={width};"
        if dashed:
            style += "dashed=1;"
        if arrow:
            style += "endArrow=block;endFill=1;"
        else:
            style += "endArrow=none;"
        self.cells.append(
            f'<mxCell id="{cid}" style="{style}" edge="1" parent="1">'
            f'<mxGeometry relative="1" as="geometry">'
            f'<mxPoint x="{x1}" y="{y1}" as="sourcePoint" />'
            f'<mxPoint x="{x2}" y="{y2}" as="targetPoint" /></mxGeometry></mxCell>'
        )
        return cid

    def save(self, path: pathlib.Path):
        body = "\n        ".join(self.cells)
        xml = (
            '<mxfile host="app.diagrams.net" type="device">\n'
            f'  <diagram name="{self.name}" id="d1">\n'
            f'    <mxGraphModel dx="{self.w}" dy="{self.h}" grid="0" gridSize="10" guides="1" '
            f'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
            f'pageWidth="{self.w}" pageHeight="{self.h}" math="0" shadow="0">\n'
            "      <root>\n"
            '        <mxCell id="0" />\n'
            '        <mxCell id="1" parent="0" />\n'
            f"        {body}\n"
            "      </root>\n"
            "    </mxGraphModel>\n"
            "  </diagram>\n"
            "</mxfile>\n"
        )
        path.write_text(xml, encoding="utf-8")
        print(f"  wrote {path.name}  ({len(self.cells)} cells)")


def fmt(n: float) -> str:
    return f"{n:,.0f}" if abs(n) >= 1000 else f"{n:g}"


# ---------------------------------------------------------------- 图 3-5
def fig_3_5():
    m = json.loads((ROOT / "release/evidence/automated_metrics.json").read_text(encoding="utf-8"))
    on, off = m["coremark_predictor_on"], m["coremark_predictor_off"]
    panels = [
        ("(a) 执行周期 cycles", "cycles", fmt),
        ("(b) CPI（周期 / 退休指令）", "cpi", lambda v: f"{v:.4f}"),
        ("(c) 分支冲刷 flush", "flush", fmt),
        ("(d) BTB 命中次数", "btb_hit", fmt),
    ]
    fig = Fig("图3-5 CoreMark 分支预测前后对比", 1440, 860)
    for idx, (title, key, formatter) in enumerate(panels):
        px = 60 + (idx % 2) * 700
        py = 60 + (idx // 2) * 380
        off_v, on_v = off[key], on[key]
        peak = max(off_v, on_v) or 1
        fig.text(px, py, 560, 40, title, size=16, bold=True)
        bar_x, bar_w = px + 150, 380
        for j, (name, val, pal) in enumerate((("预测关闭", off_v, "gray"), ("预测开启", on_v, "blue"))):
            by = py + 70 + j * 110
            fig.text(px, by, 140, 56, name, size=14, align="left")
            width = max(2, bar_w * val / peak)
            fill, stroke = PAL[pal]
            fig.rect(bar_x, by, width, 56, fill, stroke)
            fig.text(bar_x + width + 12, by, 220, 56, formatter(val), size=14, bold=True)
        delta = (on_v - off_v) / off_v * 100 if off_v else 0
        fig.text(px, py + 290, 620, 36,
                 f"变化 {delta:+.2f}%".replace("+-", "-") if off_v else "基线为 0", size=14)
    fig.text(60, 800, 1320, 40,
             "数据源：release/evidence/automated_metrics.json（Predictor On / Off，官方 CRC 在 RTL 仿真中通过）",
             size=12, color="#5F5F5F")
    fig.save(OUT / "fig3_5_coremark_predictor.drawio")


# ---------------------------------------------------------------- 图 3-6
def fig_3_6():
    # docs/coremark_cpi_analysis.md §8.1（rv32im，1 次迭代，-O2）
    parts = [
        ("理想执行", 1000.0, "orange"),
        ("load-use 气泡", 110.4, "blue"),
        ("访存与乘除阻塞", 308.5, "purple"),
        ("分支冲刷", 32.1, "red"),
        ("前端重填等", 96.3, "gray"),
    ]
    total = sum(p[1] for p in parts)
    fig = Fig("图3-6 CPI 分解", 1440, 640)
    fig.text(60, 50, 1320, 40, "(a) 每 1000 条退休指令的周期构成", size=16, bold=True)
    bar_x, bar_y, bar_w, bar_h = 60, 130, 1320, 110
    cursor = bar_x
    for name, val, pal in parts:
        seg = bar_w * val / total
        fill, stroke = PAL[pal]
        fig.rect(cursor, bar_y, seg, bar_h, fill, stroke)
        if seg > 90:
            fig.text(cursor, bar_y + bar_h // 2 - 20, seg, 40, f"{val:.1f}", size=13, align="center")
        cursor += seg
    fig.text(bar_x, bar_y + bar_h + 10, bar_w, 34,
             f"合计 {total:.1f} 拍 / 1000 指令，即 CPI ≈ {total / 1000:.4f}", size=14, align="center")

    fig.text(60, 320, 1320, 34, "(b) 各来源占比", size=16, bold=True)
    for i, (name, val, pal) in enumerate(parts):
        col = i % 2
        row = i // 2
        lx = 60 + col * 680
        ly = 370 + row * 80
        fill, stroke = PAL[pal]
        fig.rect(lx, ly, 46, 40, fill, stroke)
        fig.text(lx + 60, ly, 460, 40,
                 f"{name}：{val:.1f} 拍（{val / total * 100:.2f}%）", size=14)
    fig.text(60, 590, 1320, 40,
             "数据源：docs/coremark_cpi_analysis.md §8.1（rv32im，1 次迭代，-O2；口径为事件当拍占用）",
             size=12, color="#5F5F5F")
    fig.save(OUT / "fig3_6_cpi_breakdown.drawio")


# ---------------------------------------------------------------- 图 3-7
def fig_3_7():
    # claims_map §3.1~§3.4：rv32i 计分点的频率与分数
    score_pts = [(50, 46.816), (80, 74.905), (85, 79.587), (90, 84.269)]
    # PDS 时序：目标频率 → slack（LA = 逻辑分析仪应用，CM = CoreMark 计分配置）
    slack = [
        ("LA 80 MHz", 0.789, "green"),
        ("LA 85 MHz", 0.663, "green"),
        ("LA 90 MHz", 0.191, "orange_lt"),
        ("CM 85 MHz", 0.435, "green"),
        ("CM 90 MHz", 0.072, "orange_lt"),
        ("CM 95 MHz", -0.391, "red"),
    ]
    fig = Fig("图3-7 频率与分数、时序余量", 1440, 760)

    fig.text(60, 40, 660, 40, "(a) 工作频率与 CoreMark 分数", size=16, bold=True)
    ox, oy, pw, ph = 140, 110, 520, 420
    fx0, fx1 = 45.0, 95.0
    fy0, fy1 = 40.0, 90.0

    def sx(f):
        return ox + pw * (f - fx0) / (fx1 - fx0)

    def sy(s):
        return oy + ph * (1 - (s - fy0) / (fy1 - fy0))

    for f in (50, 60, 70, 80, 90):
        fig.line(sx(f), oy, sx(f), oy + ph, "#DDDDDD", 1)
        fig.text(sx(f) - 30, oy + ph + 6, 60, 28, str(f), size=13, align="center")
    for s in (40, 50, 60, 70, 80, 90):
        fig.line(ox, sy(s), ox + pw, sy(s), "#DDDDDD", 1)
        fig.text(ox - 62, sy(s) - 14, 54, 28, str(s), size=13, align="right")
    fig.line(ox, oy + ph, ox + pw, oy + ph, "#5F5F5F", 2)
    fig.line(ox, oy, ox, oy + ph, "#5F5F5F", 2)
    fig.text(ox, oy + ph + 40, pw, 28, "工作频率 / MHz", size=13, align="center")
    fig.text(ox - 96, oy - 34, 200, 28, "分数 Score", size=13, align="left")

    # CoreMark/MHz 恒为 0.936，实测点严格落在 Score = 0.936 × f 上
    fig.text(430, 340, 215, 92,
             "实测点严格落在\n0.936 × f 上\nCoreMark/MHz 恒为 0.936",
             size=12, color="#5B31A8")

    fig.line(*[sx(score_pts[0][0]), sy(score_pts[0][1])], *[sx(score_pts[-1][0]), sy(score_pts[-1][1])],
             "#2E6FB7", 2)
    for f, s in score_pts:
        fig.rect(sx(f) - 11, sy(s) - 11, 22, 22, PAL["blue"][0], PAL["blue"][1])
        fig.text(sx(f) - 70, sy(s) - 48, 140, 28, f"{s:.3f}", size=13, bold=True, align="center")

    fig.text(740, 40, 660, 40, "(b) PDS 时序余量与上板结果", size=16, bold=True)
    bx, by, bw, rowh = 900, 110, 420, 88
    fig.line(bx, by - 10, bx, by + rowh * len(slack), "#5F5F5F", 2)
    for i, (name, val, pal) in enumerate(slack):
        y = by + i * rowh
        fig.text(740, y, 150, 60, name, size=14, align="left")
        length = abs(val) / 0.9 * bw
        fill, stroke = PAL[pal]
        if val >= 0:
            fig.rect(bx, y, max(4, length), 60, fill, stroke)
            fig.text(bx + max(4, length) + 12, y, 130, 60, f"{val:+.3f} ns", size=14, bold=True)
        else:
            fig.rect(bx - max(4, length), y, max(4, length), 60, fill, stroke)
            fig.text(bx + 12, y, 200, 60, f"{val:+.3f} ns　时序违例、未上板", size=14, bold=True,
                     color=PAL["red"][1])
    fig.line(bx, by - 18, bx, by + rowh * len(slack), "#5F5F5F", 2)
    fig.text(740, by + rowh * len(slack) + 10, 660, 40,
             "零线右侧为正余量；CM 95 MHz 为时序违例配置，未上板、不作结果引用", size=12, color="#5F5F5F")
    fig.text(60, 700, 1320, 40,
             "数据源：release/evidence/claims_map.md §3.1～§3.4（分数为板级实测，余量为 PDS 时序分析）",
             size=12, color="#5F5F5F")
    fig.save(OUT / "fig3_7_freq_score.drawio")


# ---------------------------------------------------------------- 图 3-8
def fig_3_8():
    base = ROOT / "release/evidence/logic_analyzer_board_85m"
    modes = ["static", "counter", "uart", "spi", "mirror"]
    stats = {}
    for mode in modes:
        samples = []
        for f in sorted((base / mode).glob("*.json")):
            data = json.loads(f.read_text(encoding="utf-8"))
            if isinstance(data, list):
                for rec in data:
                    if "samples" in rec:
                        samples.append((rec["samples"], rec.get("trigger", 0)))
        if samples:
            stats[mode] = (
                min(s for s, _ in samples),
                max(s for s, _ in samples),
                len(samples),
            )
    fig = Fig("图3-8 五模式板级采集结果", 1440, 700)
    fig.text(60, 40, 1320, 40, "(a) 各模式有效样本数与验收次数", size=16, bold=True)
    bx, bw = 300, 720
    peak = max(v[1] for v in stats.values()) or 1
    order = ["static", "counter", "uart", "spi", "mirror"]
    for i, mode in enumerate(order):
        lo, hi, runs = stats[mode]
        y = 110 + i * 86
        fig.text(70, y, 220, 60, mode, size=15, align="left")
        width = max(4, bw * hi / peak)
        fig.rect(bx, y, width, 60, PAL["purple"][0], PAL["purple"][1])
        label = f"{hi}" if lo == hi else f"{lo}～{hi}"
        fig.text(bx + width + 14, y, 300, 60,
                 f"{label} 样本　/　{runs} 次验收全 PASS", size=14, bold=True)
    fig.text(60, 570, 1320, 34,
             "五模式各 20 次，合计 100 次板级采集全部通过（85 MHz 交付位流）", size=14, bold=True)
    fig.text(60, 620, 1320, 40,
             "数据源：release/evidence/logic_analyzer_board_85m/<模式>/summary.json（样本数取该模式全部运行的区间）",
             size=12, color="#5F5F5F")
    fig.save(OUT / "fig3_8_mode_capture.drawio")
    for mode in order:
        print(f"    {mode}: {stats[mode]}")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    print("generating data figures ->", OUT)
    fig_3_5()
    fig_3_6()
    fig_3_7()
    fig_3_8()
    print("done")


