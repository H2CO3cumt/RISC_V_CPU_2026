#!/usr/bin/env python3
"""MES50HP final logic-analyzer control and validation UI.

The GUI does not program the FPGA itself. Download the final .sbit with PDS
Programmer, connect the eight adjacent J8 loopback pairs, then use this window
to configure captures over CP2102 and archive logs, JSON and VCD evidence.
"""
from __future__ import annotations

import contextlib
import os
import queue
import sys
import threading
from pathlib import Path
from typing import Callable

import tkinter as tk
from tkinter import filedialog, messagebox, ttk


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
        self.geometry("960x680")
        self.minsize(760, 500)
        self.events: queue.Queue[tuple[str, str]] = queue.Queue()
        self.running = False
        self.base_dir = Path(__file__).resolve().parent
        self.port_map: dict[str, str] = {}

        self.port_var = tk.StringVar(value="COM3")
        self.baud_var = tk.StringVar(value="115200")
        self.runs_var = tk.StringVar(value="1")
        self.timeout_var = tk.StringVar(value="70")
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
        root.rowconfigure(8, weight=1)

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
        actions.grid(row=6, column=0, columnspan=3, sticky="w", pady=(8, 8))
        self.logic_button = ttk.Button(actions, text="采集四种模式并生成 VCD", command=self._run_logic_analyzer)
        self.logic_button.pack(side="left", padx=(0, 8))
        ttk.Button(actions, text="打开输出目录", command=self._open_output).pack(side="left")

        ttk.Label(root, textvariable=self.status_var, foreground="#174a7c").grid(
            row=7, column=0, columnspan=3, sticky="w", pady=(0, 6)
        )
        self.log = tk.Text(root, wrap="word", height=20, state="disabled", background="#101820", foreground="#d7f9ff")
        self.log.grid(row=8, column=0, columnspan=3, sticky="nsew")
        scroll = ttk.Scrollbar(root, orient="vertical", command=self.log.yview)
        scroll.grid(row=8, column=3, sticky="ns")
        self.log.configure(yscrollcommand=scroll.set)

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
        state = "disabled" if running else "normal"
        self.logic_button.configure(state=state)

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

    def _run_logic_analyzer(self) -> None:
        try:
            port, baud, timeout, output = self._read_common()
            runs = int(self.runs_var.get())
            if runs <= 0:
                raise ValueError("Runs/模式 必须为正整数")
        except ValueError as exc:
            messagebox.showerror("参数错误", str(exc))
            return

        def work() -> None:
            from logic_analyzer_serial import run_captures

            for mode, value in (("static", 0xA5), ("counter", 0x00), ("uart", 0xA5), ("spi", 0x3C)):
                run_captures(port, output / "logic_analyzer" / mode, mode, value, runs, baud, timeout)

        self._start_worker("逻辑分析仪四模式", work)

    def _poll_events(self) -> None:
        try:
            while True:
                kind, text = self.events.get_nowait()
                if kind == "log":
                    self._append_log(text)
                elif kind == "done":
                    self._set_running(False)
                    self.status_var.set("完成：" + text)
                    self._append_log(text + "\n")
                elif kind == "error":
                    self._set_running(False)
                    self.status_var.set("失败：请查看日志")
                    self._append_log(text + "\n")
                    messagebox.showerror("板级验证失败", text)
        except queue.Empty:
            pass
        self.after(100, self._poll_events)


def main() -> int:
    app = ValidationUI()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
