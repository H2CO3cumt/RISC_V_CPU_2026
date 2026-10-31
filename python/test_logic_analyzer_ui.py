"""仪器面板（pyUI）行为测试：旋钮 → 报文 的映射、禁用规则与即时校验。

跑法（与其它上位机测试同一条命令）：
    python -m unittest discover -s python -p 'test_logic_analyzer*.py'

为什么这些用例值得存在：界面上的"触发通道 ch3 / 电平 高"要换算成报文里的
掩码 1<<3 与**同位**的值（capture_engine.v 第 25 行是
`(channels & active_mask) == (trigger_value & active_mask)`，值写 1 会被 AND 成 0，
触发电平正好反掉）；镜像模式除 post 以外的旋钮在固件里被重新定义或写死。
这两条都属于"点得动但结果是错的"，只有测试能守住。

无图形环境（Tk 起不来）时整类 skip，不当成失败——交付机与回归机都有桌面，
但没必要让这条测试在无桌面环境下变成假红。
"""
import unittest


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


class SourceSelectorTests(unittest.TestCase):
    """采集源双源可选（2026-10-14）：界面能选、报文真的跟着变。

    为什么这组用例值得存在：功能最早只做在 RTL、固件与库里，命令行能跑、界面上点不出来，
    等于现场演示用不上。守住三条：
      1. 不勾面板时，默认仍是 J8 外部、报文仍是 13 字节 0xA5（历史证据不受影响）；
      2. 选 Core 之后报文必须是 16 字节 0xA8，且 [14] 字节 = 1；
      3. 镜像模式下这个控件要被禁用（0xA7 装不下源字节）。
    """

    def setUp(self):
        self.app = _build_app()
        self.addCleanup(self.app.destroy)

    def test_selector_exists_and_defaults_to_j8(self):
        app = self.app
        self.assertIn("source", app.knob_widgets, "面板上必须有采集源控件")
        # 控件存在但没布局出去 = 界面还是点不出来，等于没做（这正是本功能第一版的毛病）
        self.assertIn(app.knob_widgets["source"].winfo_manager(), ("grid", "pack", "place"),
                      "采集源控件必须真的被布局出来")
        app.live_mode_var.set("uart")
        app._on_mode_change()
        self.assertEqual(app.knob_vars["source"].get(), "J8 外部 8 路")
        self.assertNotIn("source", app._default_cfg(), "J8 源的默认配置不该带 source 键")

    def test_core_mode_defaults_to_core_source(self):
        app = self.app
        app.live_mode_var.set("core")
        app._on_mode_change()
        self.assertEqual(app.knob_vars["source"].get(), "Core 内部观测点")
        cfg = app._default_cfg()
        self.assertEqual(cfg.get("source"), 1)
        self.assertEqual(cfg["trigger_mask"], 1 << 6)
        self.assertEqual(cfg["sample_div"], 0)
        self.assertEqual(cfg["pre"] + cfg["post"] + 1, 2048)

    def test_manual_selection_reaches_the_packet(self):
        from logic_analyzer_serial import build_packet

        app = self.app
        app.live_mode_var.set("uart")
        app._on_mode_change()
        app.manual_var.set(True)
        app._on_manual_toggle()
        app.knob_vars["source"].set("Core 内部观测点")
        app._on_source_change()
        knobs = app._collect_knobs()
        self.assertEqual(knobs["source"], 1)
        cfg = app._default_cfg()
        from logic_analyzer_serial import apply_knobs

        merged = apply_knobs("uart", cfg, knobs)
        packet = build_packet(merged["mode"], merged["data"], merged["pattern_div"],
                              merged["sample_div"], merged["trigger_type"], merged["trigger_mask"],
                              merged["trigger_value"], merged["pre"], merged["post"],
                              merged["prefix"], merged["post16"], merged.get("source"))
        self.assertEqual(len(packet), 16)
        self.assertEqual(packet[0], 0xA8)
        self.assertEqual(packet[14], 1)

    def test_switch_to_core_rewrites_the_window(self):
        """从 J8 切到 Core 时，窗口要换成 Core 下合法的默认值（16 位）。"""
        app = self.app
        app.live_mode_var.set("uart")
        app._on_mode_change()
        app.manual_var.set(True)
        app._on_manual_toggle()
        app.knob_vars["source"].set("Core 内部观测点")
        app._on_source_change()
        self.assertEqual(app.knob_vars["sample_div"].get(), "0")
        self.assertGreater(int(app.knob_vars["post"].get()), 0xFF)

    def test_mirror_disables_the_selector(self):
        app = self.app
        app.live_mode_var.set("mirror")
        app._on_mode_change()
        app.manual_var.set(True)
        app._on_manual_toggle()
        self.assertEqual(str(app.knob_widgets["source"]["state"]), "disabled")

    def test_wave_title_names_the_actual_source(self):
        """采集源与模式不一致时，波形标题必须写出真正的源。

        为什么值得一条用例：uart 模式 + Core 源采到的是流水线内部信号。标题若只写
        "uart 模式"，操作员与评委看到的是"界面说的和板子做的不一样"，而这正是
        本次把采集源拆成独立控件要消灭的那类坑。
        """
        app = self.app
        samples = [0x01, 0x81, 0x01, 0x81] * 8      # ch0 取指请求 + ch7 提交脉冲
        app._show_wave(samples, 1, {"mode": "uart", "view": "core", "source": 1, "run": 0})
        self.assertIn("采集源 Core 内部观测点", app.panel.status.cget("text"))
        app._show_wave(samples, 1, {"mode": "uart", "view": "uart", "source": 0, "run": 0})
        self.assertIn("uart 模式", app.panel.status.cget("text"))
        self.assertNotIn("Core 内部观测点", app.panel.status.cget("text"))


class KnobPanelTests(unittest.TestCase):
    def setUp(self):
        self.app = _build_app()
        self.addCleanup(self.app.destroy)

    def test_defaults_are_disabled_and_follow_the_mode(self):
        # 不勾面板：旋钮全灰，界面显示的窗口/位点数来自模式默认配置，
        # 采集也走模式默认（板级 100/100 验收走的就是这条路）。
        app = self.app
        self.assertFalse(app.manual_var.get())
        app.live_mode_var.set("uart")
        app._on_mode_change()
        for name in ("sample_div", "pre", "post", "pattern_div", "data", "trigger_type"):
            self.assertEqual(str(app.knob_widgets[name]["state"]), "disabled", msg=name)
        self.assertEqual(app._default_cfg()["bit_samples"], 16)
        # [2026-10-14 改] 提示行现在以"采集源 …"开头：面板新增了双源选择，
        # 因此不再断言整行以"每比特"起头，改为断言关键片段都在。
        self.assertIn("采集源", app.knob_info_var.get(), msg=app.knob_info_var.get())
        self.assertIn("每比特 16 个采样点", app.knob_info_var.get())
        self.assertIn("窗口 256 点", app.knob_info_var.get())

    def test_trigger_channel_and_level_share_the_same_bit(self):
        app = self.app
        app.live_mode_var.set("uart")
        app._on_mode_change()
        app.manual_var.set(True)
        app._on_manual_toggle()
        app.knob_vars["trigger_channel"].set("ch3")
        app.knob_vars["trigger_level"].set("1 高")
        app.knob_vars["trigger_type"].set("rise")
        knobs = app._collect_knobs()
        self.assertEqual(knobs["trigger_type"], 1)
        self.assertEqual(knobs["trigger_mask"], 8)
        self.assertEqual(knobs["trigger_value"], 8, "触发电平值必须与掩码同位")
        app.knob_vars["trigger_level"].set("0 低")
        self.assertEqual(app._collect_knobs()["trigger_value"], 0)

    def test_mirror_disables_everything_but_post(self):
        app = self.app
        app.manual_var.set(True)
        app._on_manual_toggle()
        app.live_mode_var.set("mirror")
        app._on_mode_change()
        self.assertEqual(list(app._collect_knobs()), ["post"])
        for name in ("sample_div", "pre", "pattern_div", "data", "trigger_type",
                     "trigger_channel", "trigger_level"):
            self.assertEqual(str(app.knob_widgets[name]["state"]), "disabled", msg=name)
        self.assertEqual(str(app.knob_widgets["post"]["state"]), "normal")
        # 镜像窗口的最小值只有一个公式，界面显示的与判据用的是同一个数
        self.assertIn("整句至少要 960 点", app.knob_info_var.get())

    def test_invalid_value_is_reported_in_the_panel(self):
        app = self.app
        app.live_mode_var.set("uart")
        app._on_mode_change()
        app.manual_var.set(True)
        app._on_manual_toggle()
        app.knob_vars["post"].set("99999")
        app._update_knob_info()
        self.assertTrue(app.knob_info_var.get().startswith("✗"), msg=app.knob_info_var.get())
        self.assertEqual(str(app.knob_info_label.cget("foreground")), "#b3261e")
        app.knob_vars["post"].set("abc")
        app._update_knob_info()
        self.assertIn("不是整数", app.knob_info_var.get())
        app.knob_vars["post"].set("191")
        app._update_knob_info()
        self.assertIn("每比特", app.knob_info_var.get(), msg=app.knob_info_var.get())
        self.assertEqual(str(app.knob_info_label.cget("foreground")), "#174a7c")

    def test_live_stop_condition_only_applies_to_continuous_capture(self):
        # 停止条件只对连续采集有意义；不勾连续采集时输入框应当禁用
        app = self.app
        self.assertEqual(str(app.knob_widgets["stop_after"]["state"]), "disabled")
        app.live_var.set(True)
        app._sync_knob_state()
        self.assertEqual(str(app.knob_widgets["stop_after"]["state"]), "normal")


if __name__ == "__main__":
    unittest.main()
