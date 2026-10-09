#!/usr/bin/env python3
"""MES50HP final logic-analyzer control and validation UI.

The GUI does not program the FPGA itself. Download the final .sbit with PDS
Programmer, connect the eight adjacent J8 loopback pairs, then use this window
to configure captures over CP2102 and archive logs, JSON and VCD evidence.

[2026-10-03] 窗口里内嵌了实时波形面板（waveform_panel.WaveformPanel）：
每采到一轮就立刻把 8 个通道画出来，勾上「实时连续采集」就是不断采集+刷新，
不再需要把 .vcd 拿出去用别的软件打开。
"""
from __future__ import annotations

import contextlib
import os
import queue
import sys
import threading
import time
from pathlib import Path
from typing import Callable

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from waveform_panel import WaveformPanel

# 四种模式的默认测试字节，与 logic_analyzer_serial 的判据一致
MODE_VALUES = (("static", 0xA5), ("counter", 0x00), ("uart", 0xA5), ("spi", 0x3C))


class _QueueWriter:
    def __init__(self, events: queue.Queue[tuple[str, str]]) -> None:
        self.events = events

    def write(self, text: str) -> int:
        if text:
            self.events.put(("log", text))
        return len(text)

    def flush(self) -> None:
        return None


class ValidationUI(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MES50HP RISC-V 逻辑分析仪")
        # [2026-10-03] 波形面板让窗口变高，而 Windows 的 DPI 缩放会把 Tk 的逻辑尺寸再放大
        # （实测 150% 缩放下 1060x880 会被拉成约 1590x1320，底部日志区直接被挤到屏幕外）。
        # 所以 Windows 下直接最大化，任何缩放比例都不会超出屏幕；其余平台给一个保守尺寸。
        self.geometry("980x700")
        self.minsize(820, 520)
        if sys.platform == "win32":
            try:
                self.state("zoomed")
            except tk.TclError:
                pass
        self.events: queue.Queue[tuple[str, str]] = queue.Queue()
        self.running = False
        self.stop_requested = False
        self.capture_count = 0
        self.capture_started = time.monotonic()
        self._live_active = False
        self.base_dir = Path(__file__).resolve().parent
        self.port_map: dict[str, str] = {}

        self.port_var = tk.StringVar(value="COM3")
        self.baud_var = tk.StringVar(value="115200")
        self.runs_var = tk.StringVar(value="1")
        self.timeout_var = tk.StringVar(value="70")
        self.live_var = tk.BooleanVar(value=False)
        self.live_mode_var = tk.StringVar(value="uart")
        self.output_var = tk.StringVar(value=str(self.base_dir.parent / "results"))
        self.bitstream_var = tk.StringVar(
            value=str(self.base_dir.parent / "bitstream" / "mes50hp_riscv_logic_analyzer.sbit")
        )
        self.status_var = tk.StringVar(value="就绪：下载最终 bitstream，连接 J8 八组相邻脚，再选择 CP2102 串口")
        self._build_widgets()
        self.after(100, self._poll_events)
        self._refresh_ports()

    def _build_widgets(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill="both", expand=True)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(8, weight=3)   # 波形面板占大头
        root.rowconfigure(9, weight=1)   # 日志留在下面

        ttk.Label(root, text="MES50HP 八通道逻辑分析仪", font=("Segoe UI", 16, "bold")).grid(
            row=0, column=0, columnspan=3, sticky="w", pady=(0, 10)
        )
        ttk.Label(
            root,
            text="使用顺序：① PDS Programmer 下载下方文件  ② J8 接 3↔4、7↔8、…、31↔32  "
                 "③ 选择 Silicon Labs CP210x 串口  ④ 点击采集",
            foreground="#174a7c",
        ).grid(row=1, column=0, columnspan=3, sticky="w", pady=(0, 8))
        ttk.Label(root, text="唯一最终 Bitstream").grid(row=2, column=0, sticky="w", pady=3)
        ttk.Entry(root, textvariable=self.bitstream_var, state="readonly").grid(
            row=2, column=1, columnspan=2, sticky="ew", padx=(8, 0), pady=3
        )
        ttk.Label(root, text="板载 CP2102 串口").grid(row=3, column=0, sticky="w", pady=3)
        self.port_combo = ttk.Combobox(root, textvariable=self.port_var, width=54)
        self.port_combo.grid(row=3, column=1, sticky="ew", padx=(8, 0), pady=3)
        ttk.Button(root, text="刷新串口", command=self._refresh_ports).grid(row=3, column=2, sticky="w", pady=3)

        settings = ttk.Frame(root)
        settings.grid(row=4, column=0, columnspan=3, sticky="ew", pady=(4, 8))
        for col in range(8):
            settings.columnconfigure(col, weight=1 if col in (1, 3, 5, 7) else 0)
        for col, (label, var, width) in enumerate(
            (("Baud", self.baud_var, 9), ("Runs/模式", self.runs_var, 9), ("Timeout/s", self.timeout_var, 9))
        ):
            base = col * 2
            ttk.Label(settings, text=label).grid(row=0, column=base, sticky="w")
            ttk.Entry(settings, textvariable=var, width=width).grid(row=0, column=base + 1, sticky="w", padx=(6, 18))

        ttk.Label(root, text="输出目录").grid(row=5, column=0, sticky="w", pady=3)
        ttk.Entry(root, textvariable=self.output_var).grid(row=5, column=1, sticky="ew", padx=(8, 0), pady=3)
        ttk.Button(root, text="选择目录", command=self._choose_output).grid(row=5, column=2, sticky="w", padx=(8, 0), pady=3)

        actions = ttk.Frame(root)
        actions.grid(row=6, column=0, columnspan=3, sticky="w", pady=(6, 4))
        self.logic_button = ttk.Button(actions, text="采集四种模式并生成 VCD", command=self._run_logic_analyzer)
        self.logic_button.pack(side="left", padx=(0, 8))
        ttk.Button(actions, text="打开输出目录", command=self._open_output).pack(side="left", padx=(0, 14))
        self.live_check = ttk.Checkbutton(actions, text="实时连续采集", variable=self.live_var)
        self.live_check.pack(side="left", padx=(0, 4))
        ttk.Label(actions, text="实时模式").pack(side="left")
        self.live_combo = ttk.Combobox(actions, textvariable=self.live_mode_var, width=9,
                                       state="readonly", values=[m for m, _ in MODE_VALUES])
        self.live_combo.pack(side="left", padx=(6, 0))

        ttk.Label(root, textvariable=self.status_var, foreground="#174a7c").grid(
            row=7, column=0, columnspan=3, sticky="w", pady=(0, 4)
        )
        # 实时波形面板：采集到的每一轮都在这里立刻画出来。
        # height=150 只是"最小请求高度"——它会在 grid 里随窗口一起变高（weight=3）；
        # 这里刻意压小，是因为 Windows 高 DPI 缩放下 Tk 的逻辑高度比实际小很多，
        # 请求太高会把下面的日志区挤出屏幕（2026-10-03 实测 150% 缩放踩到过）。
        self.panel = WaveformPanel(root, height=150)
        self.panel.grid(row=8, column=0, columnspan=4, sticky="nsew", pady=(0, 4))

        self.log = tk.Text(root, wrap="word", height=5, state="disabled", background="#101820", foreground="#d7f9ff")
        self.log.grid(row=9, column=0, columnspan=3, sticky="nsew")
        scroll = ttk.Scrollbar(root, orient="vertical", command=self.log.yview)
        scroll.grid(row=9, column=3, sticky="ns")
        self.log.configure(yscrollcommand=scroll.set)
        self.panel.clear("等待采集：下载最终 bitstream、接好 J8，然后点『采集四种模式并生成 VCD』")

    def _append_log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text)
        self.log.see("end")
        self.log.configure(state="disabled")

    def _refresh_ports(self) -> None:
        try:
            from serial.tools import list_ports

            devices = list(list_ports.comports())
            self.port_map = {
                f"{port.device} — {port.description or '未知设备'}": port.device
                for port in devices
            }
            ports = list(self.port_map)
        except ImportError:
            ports = []
            self.port_map = {}
        self.port_combo["values"] = ports
        if ports:
            cp210x = next((item for item in ports if "CP210" in item.upper() or "SILICON LABS" in item.upper()), ports[0])
            if self.port_var.get() not in ports:
                self.port_var.set(cp210x)
        self._append_log("串口列表：" + (", ".join(ports) if ports else "未检测到，仍可手动输入 COM 号") + "\n")

    def _choose_output(self) -> None:
        chosen = filedialog.askdirectory(title="选择板级证据输出目录")
        if chosen:
            self.output_var.set(chosen)

    def _open_output(self) -> None:
        path = Path(self.output_var.get()).expanduser().resolve()
        path.mkdir(parents=True, exist_ok=True)
        if hasattr(os, "startfile"):
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            messagebox.showinfo("输出目录", str(path))

    def _set_running(self, running: bool) -> None:
        self.running = running
        # 运行中按钮变成「停止采集」且保持可点（实时模式下必须能停下来）
        self.logic_button.configure(text="停止采集" if running else "采集四种模式并生成 VCD")
        state = "disabled" if running else "normal"
        for widget in (self.live_check, self.live_combo):
            widget.configure(state=state)
        if running:
            self.stop_requested = False

    def _start_worker(self, name: str, work: Callable[[], None]) -> None:
        if self.running:
            return
        self._set_running(True)
        self.status_var.set(f"运行中：{name}")

        def worker() -> None:
            try:
                with contextlib.redirect_stdout(_QueueWriter(self.events)):
                    work()
                self.events.put(("done", f"{name} PASS"))
            except:  # noqa: E722 - the UI must surface every worker failure
                failure = sys.exc_info()[1]
                self.events.put(("error", f"{name} FAIL: {failure}"))

        threading.Thread(target=worker, name="mes50hp-validation", daemon=True).start()

    def _read_common(self) -> tuple[str, int, float, Path]:
        selected = self.port_var.get().strip()
        port = self.port_map.get(selected, selected.split(" — ", 1)[0])
        baud = int(self.baud_var.get())
        timeout = float(self.timeout_var.get())
        output = Path(self.output_var.get()).expanduser().resolve()
        if not port:
            raise ValueError("请填写 CP2102 串口，例如 COM3")
        return port, baud, timeout, output

    def _show_wave(self, samples, trigger, info) -> None:
        """把一轮采集结果显示到面板上（UI 线程）。"""
        self.capture_count += 1
        elapsed = max(1e-6, time.monotonic() - self.capture_started)
        mode = str(info.get("mode", ""))
        if self._live_active:
            # 实时模式每轮都是"第 1 次"（runs 固定为 1），用累计次数才有信息量
            title = "%s 模式 · 第 %d 次采集" % (mode, self.capture_count)
        else:
            title = "%s 模式 · 第 %d 次采集" % (mode, int(info.get("run", 0)) + 1)
        note = "累计 %d 次 · %.1f 次/秒" % (self.capture_count, self.capture_count / elapsed)
        self.panel.show(samples, trigger, title, note)

    def _run_logic_analyzer(self) -> None:
        if self.running:
            # 再点一次 = 请求停止（当前这一轮采集结束就停）
            self.stop_requested = True
            self.status_var.set("正在停止…（等当前这一轮采集收尾）")
            return
        try:
            port, baud, timeout, output = self._read_common()
            runs = int(self.runs_var.get())
            if runs <= 0:
                raise ValueError("Runs/模式 必须为正整数")
        except ValueError as exc:
            messagebox.showerror("参数错误", str(exc))
            return

        live = bool(self.live_var.get())
        live_mode = self.live_mode_var.get()
        live_value = dict(MODE_VALUES).get(live_mode, 0xA5)
        self._live_active = live
        self.capture_count = 0
        self.capture_started = time.monotonic()

        def work() -> None:
            from logic_analyzer import write_waveform_page
            from logic_analyzer_serial import run_captures

            latest: dict[str, dict] = {}

            def on_run(samples, trigger, info) -> None:
                # 采集线程 -> UI 线程只传数据，画图统一在 _poll_events 里做
                self.events.put(("wave", (samples, trigger, info)))
                mode = str(info.get("mode", ""))
                latest[mode] = {"name": "%s 模式" % mode, "samples": list(samples), "trigger": trigger,
                                "note": "%s 模式 samples=%d trigger=%d" % (mode, len(samples), trigger)}

            if live:
                # 实时模式：同一模式反复采集，每轮都刷新面板，直到点「停止采集」
                print(f"[实时] 连续采集 {live_mode} 模式，点「停止采集」结束")
                while not self.stop_requested:
                    run_captures(port, output / "logic_analyzer" / live_mode, live_mode,
                                 live_value, 1, baud, timeout, on_run=on_run)
            else:
                for mode, value in MODE_VALUES:
                    run_captures(port, output / "logic_analyzer" / mode, mode,
                                 value, runs, baud, timeout, on_run=on_run)
                # 四模式跑完再写一张总览页：采完就能双击用浏览器看四个模式
                if latest:
                    order = [m for m, _ in MODE_VALUES if m in latest]
                    preview = output / "logic_analyzer" / "波形预览.html"
                    if write_waveform_page([latest[m] for m in order], preview):
                        print(f"四个模式的浏览器波形页已生成：{preview}")
                    else:
                        print("提示：缺少 waveform_viewer.html 模板，跳过总览页")

        self._start_worker("实时波形" if live else "逻辑分析仪四模式", work)

    def _poll_events(self) -> None:
        last_wave = None
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "log":
                    self._append_log(payload)
                elif kind == "wave":
                    # 一轮可能积压多帧，只画最新的一帧，保证界面跟得上
                    last_wave = payload
                elif kind == "done":
                    self._set_running(False)
                    self.status_var.set("完成：" + payload)
                    self._append_log(payload + "\n")
                elif kind == "error":
                    self._set_running(False)
                    self.status_var.set("失败：请查看日志")
                    self._append_log(payload + "\n")
                    messagebox.showerror("板级验证失败", payload)
        except queue.Empty:
            pass
        if last_wave is not None:
            self._show_wave(*last_wave)
        self.after(50, self._poll_events)


def main() -> int:
    app = ValidationUI()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
