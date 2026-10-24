"""第 2 页的**像素级**冒烟检查：这些断言只在"画出来不对"时才失败。

为什么需要单独一层（2026-10-24 的两个教训）：
  · `tk.Text` 的保留标签名 `sel` 让整行高亮**静默失效**——控件在、tag 在、颜色也读得回，
    界面上就是没有底色；所有行为断言全绿。
  · 波形泳道被压成 56 px 的暗蓝条带，观感上和"没有新东西"一样——同样全绿。
两层都是"代码对、画面错"，只有量**画出来的像素/图元**才抓得住。

这里量的东西刻意选得"结构性"而不"像素级精确"（不比对逐像素快照，避免字体/DPI 一变就红）：
  · 探针泳道必须真的占够高度（≥ 80 px），且 8 条都在；
  · 每条泳道至少要有 N 个"高电平"色块（否则等于画空了）；
  · 光标必须**贯穿**全部泳道，且落点与"选中记录退休的那一拍"一致；
  · 选中指令的寄存器行必须被框出来。
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import trace_view as tv  # noqa: E402


def _build_app():
    try:
        import tkinter
    except ImportError as exc:  # pragma: no cover
        raise unittest.SkipTest(f"没有 tkinter：{exc}")
    from mes50hp_validation_ui import ValidationUI

    try:
        app = ValidationUI()
    except tkinter.TclError as exc:  # pragma: no cover
        raise unittest.SkipTest(f"没有可用图形环境：{exc}")
    app.withdraw()
    app.update()
    return app


def _fake_wave(nodes, cycles=64, every=3):
    samples = [0] * cycles
    for k in range(len(nodes)):
        u = (k * every) % cycles
        samples[u] |= tv.CH_RETIRE | tv.CH_IV | tv.CH_IR
        if nodes[k]["mem_we"] or nodes[k]["mnemonic"] in ("lw", "lb", "lh", "lbu", "lhu"):
            samples[u] |= tv.CH_DV | tv.CH_DR
    return {"count": cycles, "trigger": 0, "window": cycles, "div": 0, "samples": samples}


def _fake_nodes(n=12):
    out = []
    for i in range(n):
        out.append({
            "i": i, "pc": 0x900 + 4 * (i % 3), "raw_pc": 0x900 + 4 * (i % 3),
            "instr": 0x00002403, "asm": "lw x8,0(x0)",
            "mnemonic": "lw" if i % 2 else "addi", "reads": [8, 12], "writes": [8],
            "rd": 8, "rd_we": 1, "rd_data": 0x40 + i,
            "mem_we": 1 if i % 3 == 0 else 0, "mem_addr": 0x100 + i,
            "mem_data": 0x48, "mem_wstrb": 1, "error": 0,
            "srcs": [{"reg": 8, "from": (i - 1) if i else None}],
            "load_addr": None, "store_addr": (0x1000 + 4 * i) if i % 3 == 0 else None,
            "marks": [],
        })
    return out


class TracePixels(unittest.TestCase):
    def setUp(self):
        self.app = _build_app()
        self.addCleanup(self.app.destroy)
        self.app.deiconify()
        self.app.geometry("1500x950")
        self.app.update()
        self.app.notebook.select(1)
        self.app.update()

    def _load_wave(self, n=12):
        app = self.app
        nodes = _fake_nodes(n)
        wave = _fake_wave(nodes)
        align = {"offset": 1, "anchor": 1, "delta": 0, "tied": [0], "ambiguous": False,
                 "trace_arm": 0, "cycles": len(wave["samples"]), "div": 0,
                 "records": n, "retire_pulses": n, "data_pulses": 0,
                 "data_records": 0, "mismatch": 0, "lanes": []}
        app._show_wave_capture({
            "text": "x", "phase": 0, "count": n, "status": 4, "marks": [],
            "nodes": nodes, "judgements": [], "pass": True, "html": None,
            "summary": {"records": n, "chars": 0, "top4_share": 0.0},
            "wave": wave, "align": align})
        app.update()
        return app, wave

    def test_probe_lanes_are_tall_enough_and_not_empty(self):
        app, wave = self._load_wave()
        lay = app._tl_layout
        top, bot = lay["groups"]["wave"]
        self.assertGreaterEqual(bot - top, 80,
                                "8 条探针泳道总高只有 %d px，看起来就是一条色带" % (bot - top))
        c = app.trace_timeline
        lanes = tv.wave_lanes(wave)
        # 每条泳道里"高电平"色块的数量，必须与样本里置起的位数一致（±窗口裁剪）
        colors = app._TL_WAVE_COLORS
        for k in range(len(lanes)):
            want = sum(lanes[k]["bits"][lay["lo"]:lay["hi"]])
            got = sum(1 for item in c.find_all()
                      if c.type(item) == "rectangle"
                      and str(c.itemcget(item, "fill")).lower() == colors[k].lower()
                      and top <= c.coords(item)[1] <= bot)
            self.assertGreaterEqual(got, want * 0.8,
                                    "第 %d 条探针泳道画得太少：应有约 %d 块，实画 %d" % (k, want, got))

    def test_cursor_lands_on_the_retired_cycle(self):
        app, wave = self._load_wave()
        app._trace_select(3)
        app.update()
        lay = app._tl_layout
        c = app.trace_timeline
        cursors = [c.coords(i) for i in c.find_withtag("tl_cur")
                   if c.type(i) == "line" and abs(c.coords(i)[1] - 12) < 0.5]
        self.assertEqual(len(cursors), 1, "必须有且只有一条贯穿全部泳道的光标")
        want = lay["x0"] + (app._trace_cyc[app.trace_sel] - lay["lo"] + 0.5) * lay["bw"]
        self.assertAlmostEqual(cursors[0][0], want, delta=2.0)
        h = app.trace_timeline.winfo_height()
        self.assertLessEqual(cursors[0][1], 14)
        self.assertGreaterEqual(cursors[0][3], h - 4, "光标必须贯穿到底")

    def test_selected_record_marks_its_probe_pulses_white(self):
        """选中一条访存指令时，它自己那一拍的提交脉冲与块内的数据请求脉冲都要被标白。"""
        app, wave = self._load_wave()
        app._trace_select(3)          # i=3 是 addi，改选 0/3 里带 mem 的那条
        app.update()
        c = app.trace_timeline
        whites = [i for i in c.find_withtag("tl_cur")
                  if c.type(i) == "rectangle"
                  and str(c.itemcget(i, "fill")).lower() == "#ffffff"]
        self.assertTrue(whites, "选中指令的探针脉冲没有被标出来（对齐这件事画面上看不见）")

    def test_register_rows_of_the_selection_are_outlined(self):
        app, _wave = self._load_wave()
        app._trace_select(2)
        app.update()
        lay = app._tl_layout
        c = app.trace_timeline
        top, rh = lay["top"]["reg"], lay["row_h"]["reg"]
        ys = {round(c.coords(i)[1], 1) for i in c.find_withtag("tl_cur") if c.type(i) == "rectangle"}
        for r in app.trace_nodes[app.trace_sel]["reads"]:
            if r in lay["row_of"]["reg"]:
                self.assertIn(round(top + lay["row_of"]["reg"][r] * rh, 1), ys)


if __name__ == "__main__":
    unittest.main()
