"""数据流输入框（pyUI「提交级数据流」那一栏）的行为测试。

守三条，都是"界面点得动但结果是错的"那一类：

1. **输入框真的存在并且真的布局出来**——控件建了但没 grid/pack，
   现场等于没有（本项目在第一版采集源开关上就踩过这个坑）。
2. **不合法的输入必须在点按钮之前就被拦住**：超 32 字符、非 ASCII、空串。
   采集一次失败要等十几秒，而错在输入框里本该立刻变红。
3. **界面上的"会得到什么"与自动判据同源**：两边都必须来自
   ``trace_view.expected_phase0``，否则界面上写着 HELLO 而判据要求别的。

无图形环境（Tk 起不来）时整类 skip，不当成失败。
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import trace_view as tv  # noqa: E402


def _build_app():
    try:
        import tkinter
    except ImportError as exc:  # pragma: no cover - 交付机的 Python 自带 tkinter
        raise unittest.SkipTest(f"没有 tkinter：{exc}")
    from mes50hp_validation_ui import ValidationUI

    try:
        app = ValidationUI()
    except tkinter.TclError as exc:  # pragma: no cover - 无桌面环境
        raise unittest.SkipTest(f"没有可用图形环境：{exc}")
    app.withdraw()
    app.update()
    return app


class ExpectedPhase0Tests(unittest.TestCase):
    """expected_phase0 是"固件对字节做了什么"的唯一实现，先把它的口径钉死。"""

    def test_uppercase_and_xor(self):
        exp = tv.expected_phase0("hello,rv")
        self.assertEqual(exp["want"], [ord(c) for c in "HELLO,RV"])
        self.assertEqual(exp["up"], 7)
        xor = 0
        for c in [ord(c) for c in "HELLO,RV"]:
            xor ^= c
        self.assertEqual(exp["xor"], xor)

    def test_non_letters_pass_through(self):
        exp = tv.expected_phase0("a1!Z")
        self.assertEqual(exp["want"], [ord("A"), ord("1"), ord("!"), ord("Z")])
        self.assertEqual(exp["up"], 1)

    def test_empty_string(self):
        exp = tv.expected_phase0("")
        self.assertEqual(exp["want"], [])
        self.assertEqual(exp["xor"], 0)
        self.assertEqual(exp["up"], 0)


class TraceInputTests(unittest.TestCase):
    def setUp(self):
        self.app = _build_app()
        self.addCleanup(self.app.destroy)

    def test_ui_is_split_into_two_pages(self):
        """用户明确要求：**一个界面两页**——① 逻辑分析仪 ② CPU 数据流热力图。

        守的是"分页真的存在且两页标题对得上"，不是"有个 Notebook 就算"。
        """
        app = self.app
        self.assertTrue(hasattr(app, "notebook"), "界面必须有分页容器")
        tabs = app.notebook.tabs()
        self.assertEqual(len(tabs), 2, "必须正好两页")
        titles = [app.notebook.tab(t, "text") for t in tabs]
        self.assertIn("逻辑分析仪", titles[0])
        self.assertIn("数据流", titles[1])

    def test_dataflow_widgets_live_on_page_two(self):
        app = self.app
        page2 = str(app.trace_page)
        for name in ("trace_entry", "trace_button", "trace_timeline",
                     "trace_list", "trace_detail", "trace_log", "trace_scrub"):
            widget = getattr(app, name, None)
            self.assertIsNotNone(widget, "第 2 页缺少控件：%s" % name)
            self.assertTrue(str(widget).startswith(page2),
                            "%s 必须住在第 2 页，而不是第 1 页" % name)
            self.assertIn(widget.winfo_manager(), ("grid", "pack", "place"),
                          "%s 必须真的被布局出来" % name)

    def test_detail_and_log_are_tabbed_not_stacked(self):
        """底部的「这条指令」与「判据日志」是标签页，不再各抢一条横条的高度。"""
        app = self.app
        for widget in (app.trace_detail, app.trace_log):
            parent = widget.master
            self.assertEqual(parent.master.winfo_class(), "TNotebook",
                             "%s 的父容器必须是标签页" % widget)

    def _fake_nodes(self, n=6):
        out = []
        for i in range(n):
            out.append({
                "i": i, "pc": 0x900 + 4 * (i % 3), "raw_pc": 0x900 + 4 * (i % 3),
                "instr": 0x00002403, "asm": "lw x8,0(x0)",
                "mnemonic": "lw" if i % 2 else "addi", "reads": [8, 12], "writes": [8],
                "rd": 8, "rd_we": 1, "rd_data": 0x40 + i,
                "mem_we": 1 if i == 2 else 0, "mem_addr": 0x100 + i,
                "mem_data": 0x48, "mem_wstrb": 1, "error": 0,
                "srcs": [{"reg": 8, "from": (i - 1) if i else None}],
                "load_addr": None, "store_addr": (0x1000 + 4 * i) if i == 2 else None,
                "marks": [],
            })
        return out

    def _draw_fake(self, n=6):
        """把假数据灌进去，并且**真的**布一次版。

        注意必须先 deiconify + 给尺寸：窗口没映射时 winfo_width() 恒为 1，
        画布会按 1×1 分配行高，测出来的行数不是真实界面里的行数。
        """
        app = self.app
        app.trace_nodes = self._fake_nodes(n)
        app.trace_marks = [{"index": 1, "value": ord("h")}]
        app.deiconify()
        app.geometry("1280x900")
        app.update()
        app.notebook.select(1)
        app.update()
        app._trace_select(min(2, n - 1))
        app.update()
        return app

    def test_timeline_is_one_canvas_with_four_lanes(self):
        """2026-10-22 第三轮：四块画布合成**一块**，四组泳道同框。

        守的是"仪表盘式"版面的三个硬条件：
          ① 只有一块画布（上一版四个各自独立的 canvas 是"乱"的根因）；
          ② 四组泳道都排出来了，且每组都有真实高度；
          ③ 只有一根光标，且它**贯穿全部泳道**——共享一条时间轴的证据。
        """
        app = self._draw_fake(6)
        lay = app._tl_layout
        self.assertIsNotNone(lay, "时间轴没有布局信息，说明根本没画")
        self.assertEqual(sorted(lay["groups"]), ["ev", "mem", "pc", "reg"])
        for name, (top, bot) in lay["groups"].items():
            self.assertGreater(bot - top, 0, "%s 泳道高度必须为正" % name)
        h = max(1, app.trace_timeline.winfo_height())
        box = app.trace_timeline.bbox("tl_cur")
        self.assertTrue(box, "没有光标层")
        self.assertLessEqual(box[1], 14, "光标必须从顶部标尺开始")
        self.assertGreaterEqual(box[3], h - 4, "光标必须贯穿到画布底部（全部泳道共享一条轴）")

    def test_all_lanes_use_the_same_x_for_the_same_record(self):
        """同一条记录在任何泳道里的 x 必须一致——这是"共享横轴"的代数定义。"""
        app = self._draw_fake(9)
        lo, hi, bw, x0, x1, n = app._tl_geom()
        lay = app._tl_layout
        self.assertAlmostEqual(lay["x0"], x0)
        self.assertAlmostEqual(lay["bw"], bw)
        self.assertEqual((lay["lo"], lay["hi"]), (lo, hi))
        c = app.trace_timeline
        # 贯穿全部泳道的那条竖线（从标尺 y=12 一直画到画布底部）就是唯一的光标
        cursors = [c.coords(i) for i in c.find_withtag("tl_cur")
                   if c.type(i) == "line" and abs(c.coords(i)[1] - 12) < 0.5]
        self.assertEqual(len(cursors), 1, "必须有且只有一条贯穿全部泳道的光标")
        self.assertAlmostEqual(cursors[0][0], x0 + (app.trace_sel - lo + 0.5) * bw, delta=1.0)

    def test_dense_window_shows_one_record_per_pixel_not_a_wall(self):
        """4096 条记录 × 1160 px 的实测教训：一列塞 3～4 条会糊成一片色带。

        所以放大规则必须是"一条记录至少 1 px"，超出的部分滚动显示。
        """
        app = self._draw_fake(1500)
        lo, hi, bw, _x0, _x1, n = app._tl_geom()
        self.assertGreaterEqual(bw, 0.99, "一条记录不得窄于 1 px：%.3f" % bw)
        self.assertGreaterEqual(bw, app._TL_PX_PER_REC - 0.01,
                                "一条记录至少要占 %.0f px，否则就是一条条形码" % app._TL_PX_PER_REC)
        self.assertLess(hi - lo, n, "1500 条不可能一次全塞进这个宽度")
        self.assertLessEqual(lo, app.trace_sel)
        self.assertGreater(hi, app.trace_sel)
        lay = app._tl_layout
        self.assertIn("放大显示", " ".join(
            app.trace_timeline.itemcget(i, "text")
            for i in app.trace_timeline.find_all()
            if app.trace_timeline.type(i) == "text"))

    def test_register_lane_shows_read_only_registers(self):
        """实测 100 条记录里有 130 次读、远多于写：只画写会整类寄存器看不见。"""
        app = self._draw_fake(3)          # reads=[8,12]，而只有 x8 被写
        stat = app._trace_reg_stat()
        self.assertEqual(stat[12][0], 0, "假数据里 x12 从没被写")
        self.assertEqual(stat[12][1], 3, "x12 被读了 3 次")
        self.assertIn(12, app._tl_layout["row_of"]["reg"],
                      "只读寄存器也必须有自己的行，否则读数又被白丢")

    def test_store_lane_only_lists_addresses_actually_written(self):
        """地址泳道只列真正写过的地址：固定 32 行会变成一堆空白。"""
        app = self._draw_fake(6)          # 只有 i==2 写存储，store_addr = 0x1008
        rows = app._tl_layout["row_of"]["mem"]
        self.assertEqual(len(rows), 1, "写存储泳道只该有一行：%r" % (rows,))
        self.assertIn(("addr", 0x1008), rows)

    def test_selected_record_outlines_its_own_registers(self):
        """选中的那条指令读了哪些寄存器，寄存器泳道里就要把它们框出来。

        这是"点一条指令 → 右边高亮它碰过的行"的兑现，不是装饰。
        """
        app = self._draw_fake(6)
        c = app.trace_timeline
        lay = app._tl_layout
        top, rh, rof = lay["top"]["reg"], lay["row_h"]["reg"], lay["row_of"]["reg"]
        ys = {round(c.coords(i)[1], 1) for i in c.find_withtag("tl_cur") if c.type(i) == "rectangle"}
        for r in app.trace_nodes[app.trace_sel]["reads"]:
            self.assertIn(round(top + rof[r] * rh, 1), ys, "寄存器 x%d 的行没被框出来" % r)

    def test_selected_line_is_marked_in_the_list(self):
        """当前那条必须整行标出来；顺便钉死"标签名不能叫 sel"这个坑。

        Tk 的 Text 把 "sel" 保留给选中区（由 -selectbackground 接管），
        外界 tag_configure 上去的背景会被静默忽略——2026-10-23 实测，
        tag_names 里有 sel、tag_cget 也读得回颜色，界面上却一点底色都没有。
        """
        app = self._draw_fake(6)
        tags = app.trace_list.tag_names("3.0")          # trace_sel == 2 → 第 3 行
        self.assertIn("cur", tags, "指令表里当前那条必须整行标出来")
        self.assertNotIn("sel", tags, "别用 Tk 保留的 sel 标签：背景会被忽略")
        self.assertEqual(app.trace_list.tag_cget("cur", "background"), "#3c5f96")
        self.assertIn(">", app.trace_list.get("3.0", "3.2"))

    def test_list_does_not_scroll_sideways(self):
        """指令表必须停在最左边。

        插入点会被顶到行尾，Tk 为了"让插入点可见"会把画面横向挪几像素，
        行首的 ">" 和高亮列就被切掉了（2026-10-24 实板界面才发现）。
        """
        app = self._draw_fake(6)
        self.assertEqual(app.trace_list.xview()[0], 0.0, "指令表被横向滚走了")
        self.assertEqual(str(app.trace_list.index("insert")), "1.0")

    def test_wave_mode_puts_a_probe_lane_above_the_records(self):
        """0xAB 的波形模式：多一组"Core 探针（每拍）"泳道，且记录按**它退休的那一拍**定位。

        这里是"同一次采集里波形与指令流共享一根横轴"的界面侧断言：
          · 五组泳道都在（wave/reg/pc/mem/ev）；
          · 横轴单位从"记录"变成"拍"（layout["units"] == "拍"）；
          · 选中指令的竖光标落在它自己那一拍上。
        """
        app = self.app
        nodes = self._fake_nodes(8)
        # 造一段 32 拍的波形：每 3 拍一个退休脉冲，dv&dr 落在第 0/2 条记录上
        samples = [0] * 32
        for k in range(8):
            samples[k * 3] |= 0x80 | 0x01 | 0x02
        samples[0] |= 0x08 | 0x10
        samples[6] |= 0x08 | 0x10
        align = {"offset": 0, "anchor": 0, "delta": 0, "tied": [0], "ambiguous": False,
                 "trace_arm": 0, "cycles": 32, "div": 0, "records": 8,
                 "retire_pulses": 8, "data_pulses": 2, "data_records": 2, "mismatch": 0,
                 "lanes": []}
        payload = {"text": "x", "phase": 0, "count": 8, "status": 4, "marks": [],
                   "nodes": nodes, "judgements": [], "pass": True,
                   "summary": {"records": 8, "chars": 0, "top4_share": 0.0}, "html": None,
                   "wave": {"count": 32, "trigger": 0, "window": 32, "div": 0,
                            "samples": samples},
                   "align": align}
        app.deiconify()
        app.geometry("1280x900")
        app.update()
        app.notebook.select(1)
        app.update()
        app._show_wave_capture(payload)
        app.update()
        lay = app._tl_layout
        self.assertEqual(sorted(lay["groups"]), ["ev", "mem", "pc", "reg", "wave"])
        self.assertEqual(lay["units"], "拍")
        self.assertEqual(app._trace_cyc[:4], [0, 3, 6, 9])
        x0, bw = lay["x0"], lay["bw"]
        c = app.trace_timeline
        cursors = [c.coords(i) for i in c.find_withtag("tl_cur")
                   if c.type(i) == "line" and abs(c.coords(i)[1] - 12) < 0.5]
        self.assertEqual(len(cursors), 1)
        self.assertAlmostEqual(cursors[0][0], x0 + (app._trace_cyc[app.trace_sel] - lay["lo"] + 0.5) * bw,
                               delta=1.5)

    def test_plain_capture_clears_a_previous_wave(self):
        """普通 0xAA 那一枪没有波形：必须把上一次的对齐一起撤掉，否则拍号会错配到新记录上。"""
        app = self.app
        self._draw_fake(6)
        app.trace_wave = {"samples": [0] * 8, "count": 8, "div": 0}
        app._trace_cyc = [0] * 6
        app._show_trace({"text": "x", "phase": 0, "count": 6,
                         "marks": [], "nodes": self._fake_nodes(6),
                         "judgements": [], "pass": True, "html": None,
                         "summary": {"records": 6, "chars": 0, "top4_share": 0.0}})
        app.update()
        self.assertIsNone(app.trace_wave)
        self.assertIsNone(app._trace_cyc)
        self.assertEqual(sorted(app._tl_layout["groups"]), ["ev", "mem", "pc", "reg"])

    def test_character_marks_are_drawn_in_the_event_lane(self):
        """打点字符是"字符串 ↔ 指令"的锚点，必须画出来。"""
        app = self._draw_fake(6)
        app.trace_marks = []
        app._tl_static_key = None
        app._draw_trace_all()
        app.update()
        base = len(app.trace_timeline.find_all())
        app.trace_marks = [{"index": 1, "value": ord("h")},
                           {"index": 3, "value": ord("i")},
                           {"index": 5, "value": ord("!")}]
        app._tl_static_key = None            # 数据变了，强制重建静态层
        app._draw_trace_all()
        app.update()
        self.assertGreater(len(app.trace_timeline.find_all()), base, "打点字符没画出来")

    def test_value_source_colouring_distinguishes_kinds(self):
        """填充色要按"值从哪来"区分，否则热力图只是"哪个寄存器被写了"。"""
        app = self.app
        kinds = {}
        for mnem, expect in (("lw", "load"), ("addi", "alu"), ("lui", "imm"), ("jal", "pc")):
            kinds[mnem] = app._value_kind({"mnemonic": mnem})
            self.assertEqual(kinds[mnem], expect, mnem)
        colors = {app._SRC_COLORS[k] for k in kinds.values()}
        self.assertEqual(len(colors), 4, "四类值的颜色必须互不相同")

    def test_page_one_keeps_the_original_instruments(self):
        """第 1 页必须还是原来那套东西（波形面板、日志、仪器旋钮），没被搬到第 2 页。"""
        app = self.app
        page2 = str(app.trace_page)
        for widget in (app.panel, app.log, app.logic_button, app.port_combo):
            self.assertFalse(str(widget).startswith(page2),
                             "第 1 页的控件被搬到第 2 页了：%s" % widget)
        self.assertIn("source", app.knob_widgets)

    def test_input_exists_and_is_laid_out(self):
        app = self.app
        self.assertIsNotNone(app.trace_entry, "界面上必须有数据流输入框")
        # 建了控件但没布局 = 界面上根本看不到，等于没做
        self.assertIn(app.trace_entry.winfo_manager(), ("grid", "pack", "place"),
                      "数据流输入框必须真的被布局出来")
        self.assertIsNotNone(app.trace_button, "必须有一个触发采集的按钮")
        self.assertIn(app.trace_button.winfo_manager(), ("grid", "pack", "place"))

    def test_default_value_is_sendable(self):
        app = self.app
        self.assertEqual(app.trace_text_var.get(), "hello,rv")
        self.assertEqual(app._trace_problem(), "")
        self.assertEqual(str(app.trace_button.cget("state")), "normal")

    def test_too_long_is_rejected_before_capture(self):
        from mes50hp_validation_ui import TRACE_MAX_CHARS

        app = self.app
        app.trace_text_var.set("x" * (TRACE_MAX_CHARS + 1))
        app.update()
        self.assertIn("最长", app._trace_problem())
        self.assertEqual(str(app.trace_button.cget("state")), "disabled")
        self.assertIn("✗", app.trace_info_var.get())

    def test_exactly_max_length_is_allowed(self):
        from mes50hp_validation_ui import TRACE_MAX_CHARS

        app = self.app
        app.trace_text_var.set("y" * TRACE_MAX_CHARS)
        app.update()
        self.assertEqual(app._trace_problem(), "")
        self.assertEqual(str(app.trace_button.cget("state")), "normal")

    def test_non_ascii_is_rejected(self):
        app = self.app
        app.trace_text_var.set("你好")
        app.update()
        self.assertIn("ASCII", app._trace_problem())
        self.assertEqual(str(app.trace_button.cget("state")), "disabled")

    def test_empty_is_rejected(self):
        app = self.app
        app.trace_text_var.set("")
        app.update()
        self.assertIn("不能为空", app._trace_problem())

    def test_preview_comes_from_the_same_implementation_as_the_judgement(self):
        app = self.app
        for text in ("hello,rv", "abcXYZ", "1234"):
            app.trace_text_var.set(text)
            app.update()
            exp = tv.expected_phase0(text)
            preview = "".join(chr(c) if 32 <= c < 127 else "." for c in exp["want"])
            info = app.trace_info_var.get()
            self.assertIn(preview, info, "预览必须与 expected_phase0 一致：%r" % info)
            self.assertIn("up=%d" % exp["up"], info)
            self.assertIn("xor=0x%08X" % exp["xor"], info)

    def test_phase_selector_maps_to_packet_byte(self):
        from mes50hp_validation_ui import TRACE_PHASE_LABELS
        import trace_board

        app = self.app
        for index, label in enumerate(TRACE_PHASE_LABELS):
            app.trace_phase_var.set(label)
            app.update()
            self.assertEqual(app._trace_phase(), index)
            packet = trace_board.build_trace_packet(len("hello,rv"), app._trace_phase())
            self.assertEqual(packet[2], index, "阶段必须原样进 0xAA 报文的 [2] 字节")

    def test_ui_limit_matches_packet_builder_limit(self):
        """界面允许的长度必须正好是上层真的能发出去的长度。"""
        from mes50hp_validation_ui import TRACE_MAX_CHARS
        import trace_board

        self.assertEqual(TRACE_MAX_CHARS, trace_board.TRACE_MAX_CHARS)
        trace_board.build_trace_packet(TRACE_MAX_CHARS, 0)
        with self.assertRaises(ValueError):
            trace_board.build_trace_packet(TRACE_MAX_CHARS + 1, 0)


def _replay_payload(replay=""):
    """按 _load_trace_log 的口径造一份 payload（同源：样本 → build_flow → judge）。"""
    sample = Path(__file__).resolve().parent / "samples" / "trace_hello_rv.log"
    mem = (Path(__file__).resolve().parent.parent
           / "fpga" / "trace85" / "rtl" / "logic_analyzer_program.mem")
    if not sample.exists():
        raise unittest.SkipTest("没有离线回放样本 python/samples/trace_hello_rv.log")
    import trace_board

    cap = tv.parse_capture(sample.read_bytes().decode("utf-8", errors="replace"))
    sent = "".join(chr(m["value"]) for m in cap["marks"])
    imem = tv.load_program_mem(mem) if mem.exists() else None
    flow = tv.build_flow(cap, imem)
    return {
        "text": sent, "phase": 0, "count": cap["count"], "status": cap["status"],
        "marks": cap["marks"], "nodes": flow["nodes"],
        "judgements": tv.judge(cap, sent, 0, imem, depth=4096),
        "summary": trace_board.summarise(cap, flow, sent),
        "html": "", "pass": True, "replay": replay,
    }


class OfflineReplaySampleTests(unittest.TestCase):
    """离线回放那份样本必须与当前 trace85 固件镜像同源（2026-10-28 修）。

    这三条守的是本轮真实的三个缺陷，任何一个复发都会红：
    ① 样本换过镜像没重录 → `pc 与位流镜像同源` 全错；
    ② 判据拿回包 `TRACE TEXT`（大写化之后）当输入 → 2 条假 FAIL；
    ③ 回放与实采的口径分叉 → 用户没法判断屏幕上是不是板子刚采的。
    """

    SAMPLE = Path(__file__).resolve().parent / "samples" / "trace_hello_rv.log"
    MEM = (Path(__file__).resolve().parent.parent
           / "fpga" / "trace85" / "rtl" / "logic_analyzer_program.mem")

    def setUp(self):
        if not self.SAMPLE.exists():
            raise unittest.SkipTest("没有离线回放样本")
        self.capture = tv.parse_capture(
            self.SAMPLE.read_bytes().decode("utf-8", errors="replace"))

    def test_sent_text_is_the_mark_values(self):
        sent = "".join(chr(m["value"]) for m in self.capture["marks"])
        self.assertEqual(sent, "hello,rv")
        self.assertEqual(len(sent), self.capture["mark_count"])

    def test_trailer_text_is_not_the_sent_text(self):
        """回包 TRACE TEXT 是大写化之后的；拿它判据会稳定出 2 条假 FAIL。"""
        trailer = "".join(chr(c) for c in self.capture["text"])
        self.assertEqual(trailer, "HELLO,RV")
        imem = tv.load_program_mem(self.MEM) if self.MEM.exists() else None
        bad = [n for n, ok, _d in tv.judge(self.capture, trailer, 0, imem, depth=4096)
               if not ok]
        self.assertIn("打点值等于发送的字符", bad)
        self.assertIn("大写字符计数", bad)

    def test_sample_is_same_image_as_current_firmware(self):
        """换过 program.mem 就必须重录样本，否则这条会红（这是本次修的根因）。"""
        if not self.MEM.exists():
            raise unittest.SkipTest("没有 trace85 固件镜像")
        imem = tv.load_program_mem(self.MEM)
        sent = "".join(chr(m["value"]) for m in self.capture["marks"])
        results = tv.judge(self.capture, sent, 0, imem, depth=4096)
        self.assertTrue(tv.judgements_pass(results),
                        "样本与当前镜像不同源，请重录或重新对齐：%r"
                        % [n for n, ok, _d in results if not ok])


class ReplayBannerTests(unittest.TestCase):
    """第 ② 页必须一眼看得出"这是回放"还是"板子刚采的"。"""

    def setUp(self):
        self.app = _build_app()

    def tearDown(self):
        self.app.destroy()

    def test_replay_shows_a_warning_banner(self):
        self.app._show_trace(_replay_payload("samples/trace_hello_rv.log"))
        self.app.update()
        self.assertIn("离线回放", self.app._trace_replay_note)
        self.assertIn("仅供参考", self.app._trace_replay_note)
        self.assertEqual(self.app.trace_replay_label.winfo_manager(), "pack",
                         "徽标建了但没 pack 出来，现场等于没有")

    def test_live_capture_clears_the_banner(self):
        self.app._show_trace(_replay_payload("samples/trace_hello_rv.log"))
        self.app.update()
        self.app._show_trace(_replay_payload(""))
        self.app.update()
        self.assertEqual(self.app._trace_replay_note, "")
        self.assertEqual(self.app.trace_replay_label.winfo_manager(), "",
                         "实采之后必须把回放徽标撤掉，否则把实时数据标成录像")

    def test_load_trace_log_marks_itself_as_replay(self):
        sample = Path(__file__).resolve().parent / "samples" / "trace_hello_rv.log"
        if not sample.exists():
            raise unittest.SkipTest("没有离线回放样本")
        self.app._load_trace_log(sample)
        kind, payload = self.app.events.get_nowait()
        self.assertEqual(kind, "trace")
        self.assertEqual(payload["text"], "hello,rv", "必须用打点值，不是大写化的回包文本")
        self.assertTrue(payload["pass"])
        self.assertIn("trace_hello_rv.log", payload["replay"],
                      "payload 必须带 replay 来源，第 ② 页据此显示「离线回放」徽标")


if __name__ == "__main__":
    unittest.main()
