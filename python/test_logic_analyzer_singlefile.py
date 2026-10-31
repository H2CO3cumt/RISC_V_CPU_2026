"""单文件演示器（`逻辑分析仪演示.py`）的界面级测试：采集源控件必须真的能用。

跑法（与其它上位机测试同一条命令）：
    python -m unittest discover -s python -p 'test_logic_analyzer*.py'

为什么这组用例值得存在：采集源"双源可选"最初只做在 RTL、固件与库里——命令行能跑，
**界面上点不出来**，现场演示等于用不上。pyUI 那份由 `test_logic_analyzer_ui.py` 守着，
自包含的这份是**独立实现**（零依赖设计，不能 import 仓库模块），所以必须单独再守一遍：
控件存在、真的被布局出来、切换后窗口参数按新源换成合法值、报文跟着变成 16 字节 0xA8。

无图形环境（Tk 起不来）时整类 skip，不当成失败。
"""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load_demo():
    spec = importlib.util.spec_from_file_location("la_demo", ROOT / "逻辑分析仪演示.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SingleFileSourceSelectorTests(unittest.TestCase):
    """走真实的 `run_gui(probe=...)` 通道：拿到的是界面自己的状态与控件。"""

    @classmethod
    def setUpClass(cls):
        try:
            import tkinter
        except ImportError as exc:  # pragma: no cover
            raise unittest.SkipTest(f"没有 tkinter：{exc}")
        cls.tk = tkinter
        cls.demo = _load_demo()

    def setUp(self):
        holder: dict = {}

        def probe(st, update_info, sync_knob_state, knob_info, run_btn, live_btn, root):
            holder.update(st=st, root=root, update_info=update_info,
                          sync_knob_state=sync_knob_state, knob_info=knob_info)
            # 只退出事件循环，**不销毁窗口**：控件要留到测试体里继续用
            # （销毁后再 event_generate 会报 application has been destroyed）。
            root.after(30, root.quit)

        try:
            self.demo.run_gui(autorun=None, probe=probe)
        except self.tk.TclError as exc:  # pragma: no cover - 无桌面环境
            raise unittest.SkipTest(f"没有可用图形环境：{exc}")
        if not holder:
            self.skipTest("单文件演示器没有回调 probe，取不到界面控件")
        self.st = holder["st"]
        self.root = holder["root"]
        self.addCleanup(self._cleanup)

    def _cleanup(self):
        try:
            # 先把挂着的 after 定时器全撤掉：窗销毁后再触发 Tk 会报
            # `invalid command name "...poll"`，那只是噪音，不该混进回归输出。
            for job in self.root.tk.call("after", "info"):
                self.root.after_cancel(job)
        except Exception:
            pass
        try:
            self.root.destroy()
        except Exception:
            pass

    def test_selector_exists_is_laid_out_and_defaults_to_j8(self):
        widget = self.st["knob_widgets"].get("source")
        self.assertIsNotNone(widget, "面板上必须有「采集源」控件")
        # 控件存在但没布局出去 = 界面还是点不出来，等于没做
        self.assertIn(widget.winfo_manager(), ("grid", "pack", "place"),
                      "采集源控件必须真的被布局出来")
        # 控件与状态必须是同一个变量：改状态，控件显示要跟着变（否则"点了没反应"）
        self.st["knob"]["source"].set(self.demo.SOURCES[1][0])
        self.root.update()
        self.assertEqual(widget.get(), self.demo.SOURCES[1][0],
                         "采集源控件没有绑到界面状态上")
        self.st["knob"]["source"].set(self.demo.SOURCES[0][0])
        self.root.update()
        self.assertEqual(tuple(widget.cget("values")),
                         tuple(label for label, _ in self.demo.SOURCES))
        self.assertEqual(self.st["knob"]["source"].get(), self.demo.SOURCES[0][0],
                         "默认必须是 J8 外部 8 路（与历史全部证据同源）")

    def test_switching_to_core_rewrites_the_window(self):
        """勾上面板后切到 Core：窗口自动换成 Core 源下的合法默认值（全速 + 2048 点）。"""
        st = self.st
        st["manual"].set(True)
        widget = st["knob_widgets"]["source"]
        st["knob"]["source"].set(self.demo.SOURCES[1][0])
        widget.event_generate("<<ComboboxSelected>>")     # 走界面真正绑定的回调
        self.root.update()
        self.assertEqual(st["knob"]["sample_div"].get(), "0")
        self.assertGreater(int(st["knob"]["post"].get()), 0xFF,
                           "Core 源的 post 应该超过 1 字节上限（0xA8 才有 16 位窗口）")

    def test_core_source_reaches_the_packet(self):
        """旋钮 -> 报文：源 = Core 时必须走 16 字节 0xA8，且 [14] = 1。"""
        knobs = {}
        for name, var in self.st["knob"].items():
            value = var.get()
            if name == "trigger_type":
                value = ("level", "rise", "fall").index(value)
            elif name == "trigger_channel":
                value = int(value[2:])
            elif name == "trigger_level":
                value = 1 if value.startswith("1") else 0
            knobs[name] = value
        # 触发通道/电平在这里不参与判据（只关心源与窗口），按掩码最低位换算即可
        knobs["trigger_mask"] = 1 << knobs.pop("trigger_channel")
        knobs["trigger_value"] = knobs.pop("trigger_level") << (knobs["trigger_mask"].bit_length() - 1)
        knobs["source"] = self.demo.SOURCE_CORE
        knobs["sample_div"] = 0
        knobs["pre"] = 64
        knobs["post"] = 1983
        cfg = self.demo.apply_knobs("uart", self.demo.mode_config("uart", "HELLO,"), knobs)
        packet = self.demo.build_packet(cfg["mode"], cfg["data"], cfg["pattern_div"],
                                        cfg["sample_div"], cfg["trig_type"], cfg["trig_mask"],
                                        cfg["trig_value"], cfg["pre"], cfg["post"],
                                        cfg["prefix"], cfg["post16"], cfg.get("source"))
        self.assertEqual(len(packet), 16)
        self.assertEqual(packet[0], 0xA8)
        self.assertEqual(packet[14], self.demo.SOURCE_CORE)
        # 切回 J8：老报文必须逐字节回到 13 字节 0xA5
        back = self.demo.apply_knobs("uart", self.demo.mode_config("uart", "HELLO,"),
                                     {"source": self.demo.SOURCE_J8})
        packet_j8 = self.demo.build_packet(back["mode"], back["data"], back["pattern_div"],
                                           back["sample_div"], back["trig_type"],
                                           back["trig_mask"], back["trig_value"],
                                           back["pre"], back["post"], back["prefix"],
                                           back["post16"], back.get("source"))
        self.assertEqual(len(packet_j8), 13)
        self.assertEqual(packet_j8[0], 0xA5)

    def test_switching_mode_while_running_stops_and_restarts(self):
        """运行中切模式：必须停掉当前那一枪、并按新模式重开（2026-10-14 实板踩到的坑）。

        为什么值得一条用例：任务在 `start()` 那一刻就把模式固定了（`jobs.put` 只读一次），
        所以运行中改单选钮**不会**改变正在跑的采集——现场表现是"点 core 没反应、
        画面还是 mirror 的波形"（用户实测截图确认）。修法：切模式即请求停止，
        连续采集在收尾后按新模自动重开；同时状态行要写明"正在采哪个模式"。
        """
        st = self.st
        # 模拟"正在连续采集 static"这个状态（不起真线程：这里只验证界面状态机）
        st["mode"].set("static")
        st["busy"] = True
        st["live"] = True
        st["running_mode"] = "static"
        st["stop"] = False
        st["restart_live"] = False
        try:
            self.choice_of("core").invoke()          # 点 core 单选钮
            self.root.update()
            self.assertTrue(st["stop"], "运行中切模式必须请求停止当前采集")
            self.assertTrue(st["restart_live"], "连续采集要在收尾后按新模重开")
            self.assertEqual(st["mode"].get(), "core")
            self.assertIn("Core 内部观测点", st["knob"]["source"].get(),
                          "切到 core 后采集源格子要跟着变成 Core 内部观测点")
            # 切回同一个模式不该触发停止
            st["stop"] = False
            st["restart_live"] = False
            st["running_mode"] = "core"
            self.choice_of("core").invoke()
            self.root.update()
            self.assertFalse(st["stop"], "模式没变就不该停")
        finally:
            st["busy"] = False
            st["live"] = False
            st["stop"] = False
            st["restart_live"] = False

    def choice_of(self, mode: str):
        """找到"模式"那一排单选钮里对应 mode 的那个控件（用于模拟点击）。"""
        for widget in self._walk(self.root):
            if widget.winfo_class() == "TRadiobutton":
                try:
                    if str(widget.cget("text")) == mode:
                        return widget
                except Exception:
                    continue
        self.fail(f"没找到模式单选钮 {mode!r}")

    @staticmethod
    def _walk(widget):
        yield widget
        for child in widget.winfo_children():
            yield from SingleFileSourceSelectorTests._walk(child)

    def test_every_mode_builds_a_packet_through_the_shared_helper(self):
        """六个模式都必须能经**同一个** `packet_for_cfg()` 打出报文（2026-10-14 修的真 bug）。

        为什么值得一条用例：界面里原来有两处拼报文——`capture()` 传了 `source`、
        而写日志的 `log_packet()` 漏传。于是 **core 模式的报文在写日志时抛 ValueError**
        （pre=64/post=1983 被当单字节），异常从 Tk 的 after 回调里窜出去，
        末尾那句 `root.after(120, poll)` 不再执行 ⇒ 整个界面看起来"点 core 没反应"。
        现在两处合成一个 `packet_for_cfg()`，这条用例就替那条路径把关。
        """
        expected_len = {"static": 13, "counter": 13, "uart": 13, "spi": 13, "mirror": 13, "core": 16}
        for mode, want in expected_len.items():
            cfg = self.demo.mode_config(mode, self.demo.DEFAULT_TEXT, 85_000_000)
            packet = self.demo.packet_for_cfg(cfg)
            self.assertEqual(len(packet), want, msg=mode)
            if mode == "core":
                self.assertEqual(packet[0], 0xA8, "core 模式必须走 0xA8")
                self.assertEqual(packet[14], self.demo.SOURCE_CORE)
                self.assertEqual(packet[12] | (packet[13] << 8), cfg["post"],
                                 "0xA8 的 post 是 16 位小端，不能被截成单字节")
            elif mode == "mirror":
                self.assertEqual(packet[0], 0xA7)
            else:
                self.assertEqual(packet[0], 0xA5)

    def test_view_follows_the_source_not_the_mode(self):
        """判据口径：源 = Core 一律按流水线观测点解释；core 预设 + J8 源是纯 8 路。"""
        self.assertEqual(self.demo.capture_view("uart", self.demo.SOURCE_CORE),
                         self.demo.VIEW_CORE)
        self.assertEqual(self.demo.capture_view("uart", self.demo.SOURCE_J8), "uart")
        self.assertEqual(self.demo.capture_view("core", self.demo.SOURCE_J8),
                         self.demo.VIEW_RAW)
        self.assertEqual(self.demo.capture_view("core", self.demo.SOURCE_CORE),
                         self.demo.VIEW_CORE)


if __name__ == "__main__":
    unittest.main()
