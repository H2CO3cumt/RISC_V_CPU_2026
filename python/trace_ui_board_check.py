"""走**真实界面路径**的板级检查：输入框 → 按钮 → 采集 → 页面。

为什么需要这个文件（而不是只跑单测）：
  `test_trace_ui.py` 只证明"控件在、校验对"。但现场真正会翻车的是**接线**——
  按钮回调没接到 `_run_trace`、输入框的值没被读出来、后台线程的 stdout 没进日志区、
  采集到的页面没落盘。这些只有真的点一次才会暴露。

做法：真的构造 `ValidationUI`，真的设 `trace_text_var`，真的调 `_run_trace()`，
然后泵 Tk 事件循环等它跑完（和用户点按钮走的是同一条代码路径，不是重写的脚本）。

用法（板子已下载 tr85、CP2102 在 COM11）：
    python python\\trace_ui_board_check.py --port COM11
    python python\\trace_ui_board_check.py --port COM11 --text "Hello,World" --phase 1
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

DEFAULT_TEXTS = ("hello,rv",)   # 与阶段 0 的期望结果一一对应（判据会按实际字符串重算）


def drive_ui(port: str, texts, phase: int, outdir: Path, timeout: float = 240.0,
             wave: bool = False) -> int:
    import tkinter

    import mes50hp_validation_ui as ui_mod
    from mes50hp_validation_ui import TRACE_PHASE_LABELS, ValidationUI

    # 无人值守：把界面弹窗换成"记账"，不让它真的弹出来。
    # 2026-10-23 实测过这个坑：板子没烧 tr85 时采集失败，_poll_events 里
    # `messagebox.showerror` 弹出模态框，`app.update()` 于是永不返回，
    # 整个检查挂死十几分钟、一个字都不打印（stdout 还被缓冲着）。
    dialogs = []

    class _QuietMessageBox:
        def __getattr__(self, name):
            def _record(title="", message="", *args, **kwargs):
                dialogs.append((title, message))
                return "ok"
            return _record

    ui_mod.messagebox = _QuietMessageBox()

    try:
        app = ValidationUI()
    except tkinter.TclError as exc:
        print("TRACE UI CHECK FAIL: 没有可用图形环境：%s" % exc)
        return 2
    failures = 0
    try:
        app.withdraw()
        app.update()
        app.notebook.select(1)      # 停在第 2 页（CPU 数据流），和用户看到的一致
        app.port_var.set(port)
        app.output_var.set(str(outdir))
        app.trace_autoopen_var.set(False)   # 检查脚本不要真去开浏览器
        app.trace_phase_var.set(TRACE_PHASE_LABELS[phase])
        for text in texts:
            before = Path(outdir) / "trace" / ("trace_phase%d.html" % phase)
            if before.exists():
                before.unlink()             # 免得把上一枪的产物当成这一枪的结果
            app.trace_text_var.set(text)
            app.update()
            problem = app._trace_problem()
            if problem:
                print("TRACE UI CHECK FAIL: 输入 %r 被界面判为非法：%s" % (text, problem))
                failures += 1
                continue
            started = time.monotonic()
            app._run_trace()
            # 泵事件循环：_poll_events 在 UI 线程里把后台线程的结果搬进日志区
            while app.running and time.monotonic() - started < timeout:
                app.update()
                time.sleep(0.05)
            app.update()
            log = app.trace_log.get("1.0", "end")
            if dialogs:
                print("TRACE UI CHECK FAIL: %r 采集报错（界面弹窗：%s）"
                      % (text, dialogs[-1][1]))
                failures += 1
                continue
            if app.running:
                print("TRACE UI CHECK FAIL: %r 超时（%.0f s）" % (text, timeout))
                failures += 1
                continue
            # 界面里必须真的画出东西：时间轴（四组泳道同框）与指令表都由 _show_trace 画
            if not app.trace_nodes:
                print("TRACE UI CHECK FAIL: %r 采集回来了但界面没拿到记录" % text)
                failures += 1
                continue
            # 采集期间窗口是 withdraw 的（画布只有 1×1，画出来的行数不算数），
            # 这里按真实尺寸重新布一次版再量——量的是用户真看到的那一版。
            app.deiconify()
            app.geometry("1500x950")
            app.update()
            app._draw_trace_all()
            app.update()
            items = len(app.trace_timeline.find_all())
            lay = getattr(app, "_tl_layout", None) or {}
            lanes = sorted(lay.get("groups", {}))
            vis = lay.get("hi", 0) - lay.get("lo", 0)
            if items <= 0 or len(lanes) != 4:
                print("TRACE UI CHECK FAIL: %r 时间轴是空的（items=%d lanes=%s）"
                      % (text, items, lanes))
                failures += 1
                continue
            if vis < 20 or not lay.get("row_of", {}).get("reg"):
                print("TRACE UI CHECK FAIL: %r 时间轴这一屏画得太少（可见 %d 条，寄存器行 %d 行）"
                      % (text, vis, len(lay.get("row_of", {}).get("reg") or {})))
                failures += 1
                continue
            if "FAIL" in log:
                print("TRACE UI CHECK FAIL: %r 的判据里有 FAIL，日志尾部：" % text)
                print("\n".join(log.strip().splitlines()[-6:]))
                failures += 1
                continue
            size = before.stat().st_size if before.exists() else 0
            rows = {k: len(v) for k, v in lay.get("row_of", {}).items()}
            print("TRACE UI OK   text=%r phase=%d nodes=%d 可见=%d 条 items=%d rows=%s page=%d bytes"
                  % (text, phase, len(app.trace_nodes), vis, items, rows, size))
            app.withdraw()
            app.update()

        # ---- 0xAB：同一枪里波形 + 指令流，且在界面里按拍对齐 ----
        if wave:
            text = texts[0]
            app.trace_text_var.set(text)
            app.update()
            started = time.monotonic()
            app._run_wave()
            while app.running and time.monotonic() - started < timeout:
                app.update()
                time.sleep(0.05)
            app.update()
            logw = app.trace_log.get("1.0", "end")
            if dialogs:
                print("TRACE UI CHECK FAIL: 波形采集报错（界面弹窗：%s）" % (dialogs[-1][1],))
                failures += 1
            elif not app.trace_wave or not app.trace_align:
                print("TRACE UI CHECK FAIL: 波形采集回来了但界面没拿到波形/对齐")
                failures += 1
            else:
                app.deiconify()
                app.geometry("1500x950")
                app.update()
                app._draw_trace_all()
                app.update()
                lay = getattr(app, "_tl_layout", None) or {}
                lanes = sorted(lay.get("groups", {}))
                al = app.trace_align
                ok = (lanes == ["ev", "mem", "pc", "reg", "wave"]
                      and lay.get("units") == "拍" and al["mismatch"] == 0
                      and al["retire_pulses"] > 0 and app._trace_cyc)
                print("TRACE UI WAVE  %s cycles=%d retire=%d dv=%d rec=%d mismatch=%d tied=%r"
                      % ("OK  " if ok else "FAIL", al["cycles"], al["retire_pulses"],
                         al["data_pulses"], al["data_records"], al["mismatch"], al["tied"]))
                if "FAIL" in logw:
                    print("TRACE UI CHECK FAIL: 波形那一枪的判据里有 FAIL")
                    failures += 1
                if not ok:
                    print("TRACE UI CHECK FAIL: 波形模式版面/对齐不对（lanes=%s units=%s）"
                          % (lanes, lay.get("units")))
                    failures += 1
                app.withdraw()
                app.update()
    finally:
        try:
            app.destroy()
        except tkinter.TclError:
            pass
    if failures:
        print("TRACE UI BOARD CHECK FAIL count=%d" % failures)
        return 1
    print("TRACE UI BOARD CHECK PASS")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="走真实界面路径的数据流板级检查")
    ap.add_argument("--port", default="COM11")
    ap.add_argument("--text", action="append", default=[],
                    help="要发给 CPU 的字符串，可重复；默认跑 hello,rv")
    ap.add_argument("--phase", type=int, default=0, choices=[0, 1],
                    help="0=只记处理过程 1=连串口轮询一起记")
    ap.add_argument("--outdir", default="results/trace85_ui_board")
    ap.add_argument("--timeout", type=float, default=240.0)
    ap.add_argument("--wave", action="store_true",
                    help="另外跑一次 0xAB 组合采集，检查波形泳道与按拍对齐")
    args = ap.parse_args(argv)
    texts = tuple(args.text) if args.text else DEFAULT_TEXTS
    return drive_ui(args.port, texts, args.phase, Path(args.outdir).resolve(), args.timeout,
                    args.wave)


if __name__ == "__main__":
    raise SystemExit(main())
