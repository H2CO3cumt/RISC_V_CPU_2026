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

try:                      # trace 侧唯一的实现：探针位序、对齐、判据都在 trace_view 里
    import trace_view as tv
except ImportError:       # pragma: no cover - 交付包里 trace_view.py 一定在
    tv = None

# 五种模式的默认测试字节，与 logic_analyzer_serial 的判据一致。
# `core` = 采集源切到 Core 内部观测点（双源可选）：它的默认配置来自
# logic_analyzer_serial.default_config("core", ...)——全速采样、触发 ch6 冲刷沿、
# 2048 点窗口；默认字节在这里没有意义，填 0x00 只为了让表格形状一致。
MODE_VALUES = (("static", 0xA5), ("counter", 0x00), ("uart", 0xA5),
               ("spi", 0x3C), ("mirror", 0x00), ("core", 0x00))

# [2026-10-22] 提交级数据流（trace）的两个阶段。取值与固件 0xAA 命令的 [2] 字节一致：
#   0 = 只记录**处理过程**（先把整句收进 RAM，再 Arm）
#   1 = 连**串口轮询**一起记（Arm 在接收之前）
TRACE_PHASE_LABELS = ("0 · 只记处理过程", "1 · 连串口轮询一起记")
TRACE_MAX_CHARS = 32   # 与固件 TRACE_BUF_MAX、trace_board.TRACE_MAX_CHARS 必须一致

# 0xAB 波形窗口档 → 后触发样本数（与固件 trace_and_wave 的 post 计算一致）
TRACE_WAVE_WINDOWS = (("512 拍", 1), ("1024 拍", 2), ("2048 拍", 3))


def trace_probe_lanes(wave):
    """8 条 Core 探针泳道（位序的唯一实现在 trace_view.wave_lanes）。"""
    if tv is None or not wave:
        return []
    return tv.wave_lanes(wave)


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
        # [2026-10-10 仪器面板] 把固件早就有、却一直写死在模式默认里的旋钮接到界面上。
        # 不勾「使用面板参数」时，命令行与板级 100/100 验收走的那条路**逐字节不变**
        # （旋钮为空 → logic_analyzer_serial.apply_knobs 原样返回默认配置）。
        self.manual_var = tk.BooleanVar(value=False)
        self.stop_after_var = tk.StringVar(value="0")
        self.clock_var = tk.StringVar(value="85000000")
        # 面板控件名与报文字段名**故意不同名**：界面上是"触发通道 ch3"和"电平 高/低"，
        # 报文里是掩码 1<<3 和与之同位的值，换算集中在 _collect_knobs 一处。
        self.knob_vars: dict[str, tk.StringVar] = {
            name: tk.StringVar() for name in
            ("sample_div", "trigger_type", "trigger_channel", "trigger_level",
             "pre", "post", "pattern_div", "data", "source")}
        self.knob_widgets: dict[str, tk.Widget] = {}
        self.knob_info_var = tk.StringVar(value="")
        # 镜像模式要发送并抓取的那句话：上位机把它发到板子串口，逻辑分析仪抓的就是这根线本身。
        self.mirror_text_var = tk.StringVar(value="HELLO,RISC-V")
        # [2026-10-22] 提交级数据流的输入框：这里填什么，CPU 就收什么并处理什么。
        # 它和上面的"镜像模式字符串"是两件事：镜像只是把串口线本身抓下来给分析仪看，
        # 而这里是真的让 CPU 去读、去改、去存，然后逐条指令画出来。
        self.trace_text_var = tk.StringVar(value="hello,rv")
        self.trace_phase_var = tk.StringVar(value=TRACE_PHASE_LABELS[0])
        self.trace_autoopen_var = tk.BooleanVar(value=False)
        self.trace_live_var = tk.BooleanVar(value=False)
        self.trace_info_var = tk.StringVar(value="")
        self.trace_button: ttk.Button | None = None
        # 第 2 页的显示状态（由 _show_trace 在 UI 线程里填）
        self.trace_nodes: list[dict] = []
        self.trace_marks: list[dict] = []
        self.trace_sel = 0
        self.trace_pass = True
        # 0xAB 组合采集的产物：波形 + 对齐结果；_trace_cyc 是"每条记录落在第几拍"
        self.trace_wave = None
        self.trace_align = None
        self._trace_cyc = None
        self._trace_job = None
        self._trace_playing = False
        # 时间轴的视图状态：_tl_lo = 当前显示的那一段的起始记录号
        self._tl_lo = 0
        self._tl_layout: dict | None = None
        self._tl_static_key = None
        # ttk.Scale 的 command 在自己被 set() 时也会触发；不加这个标志就会
        # set → command → _trace_select → set → … 直接 RecursionError
        # （2026-10-22 实测：窗口一打开就崩，报 RecursionError 指在 create_text）。
        self._scrub_syncing = False
        self.output_var = tk.StringVar(value=str(self.base_dir.parent / "results"))
        self.bitstream_var = tk.StringVar(
            value=str(self.base_dir.parent / "bitstream" / "mes50hp_riscv_logic_analyzer.sbit")
        )
        self.status_var = tk.StringVar(value="就绪：下载最终 bitstream，连接 J8 八组相邻脚，再选择 CP2102 串口")
        self._build_widgets()
        # 面板初始状态：载入当前模式（uart）的默认值，并禁用所有旋钮——
        # 不勾「使用面板参数」时，采集行为与加面板之前逐字节相同。
        self._load_knob_defaults()
        self._sync_knob_state()
        # 镜像字符串一变，"整句至少要多少点"就要跟着变，接到同一处校验。
        self.mirror_text_var.trace_add("write", lambda *_args: self._update_knob_info())
        # 数据流输入的即时校验与"会得到什么"的预览，和自动判据用同一个实现。
        self.trace_text_var.trace_add("write", lambda *_args: self._update_trace_info())
        self.trace_phase_var.trace_add("write", lambda *_args: self._update_trace_info())
        self._poll_job = self.after(100, self._poll_events)
        self._refresh_ports()

    def _build_widgets(self) -> None:
        # [2026-10-22 用户要求] 一个界面分成两页：
        #   ① 逻辑分析仪      —— 原来的全部内容（下载/串口/仪器面板/波形/日志）
        #   ② CPU 数据流      —— 发字符串 + 寄存器热力图 + 逐条指令，**画在界面里**
        # 用 ttk.Notebook 分页。原来 `root` 就是整个窗口体的那一层，现在它是第 1 页，
        # 所以下面原有的 grid 代码一行都不用改（row/column 编号仍从 0 起）。
        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True)
        page1 = ttk.Frame(self.notebook, padding=12)
        page2 = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(page1, text="  ① 逻辑分析仪（八通道波形）  ")
        self.notebook.add(page2, text="  ② CPU 数据流（寄存器热力图）  ")
        self.trace_page = page2
        root = page1
        # 注意：**不要对 page1 调 pack()**。Notebook 的子页由 add() 管布局，
        # 再手工 pack 一次会把它从标签页体系里挤出去（实测第二个 add 直接不生效，
        # tabs() 只剩 1 个）。只要把 page1 内部的 grid 权重设好即可。
        root.columnconfigure(1, weight=1)
        root.rowconfigure(10, weight=3)   # 波形面板占大头
        root.rowconfigure(11, weight=1)   # 日志留在下面

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

        # 镜像模式：这句话会经 CP2102 发到 uart0_rx，板级顶层把它镜像到 J8-31/32（ch7），
        # 逻辑分析仪抓的就是这根线本身。改成任何 ASCII 句子，波形与会话都会跟着变。
        mirror_row = ttk.Frame(root)
        mirror_row.grid(row=6, column=0, columnspan=3, sticky="ew", pady=(2, 0))
        mirror_row.columnconfigure(1, weight=1)
        ttk.Label(mirror_row, text="镜像模式发送的字符串").grid(row=0, column=0, sticky="w")
        ttk.Entry(mirror_row, textvariable=self.mirror_text_var).grid(
            row=0, column=1, sticky="ew", padx=(8, 0)
        )
        ttk.Label(mirror_row, text="（只支持可打印 ASCII）", foreground="#666").grid(
            row=0, column=2, sticky="w", padx=(8, 0)
        )

        # 仪器面板：勾上「使用面板参数」后，这些值覆盖模式默认值，并直接进 13 字节报文。
        # 每改一个值就立刻用与采集**同一份** apply_knobs 校验，并显示"每比特几个采样点"——
        # 这个数就是波形页标注和判据共用的那个数（判据与标注同源，见
        # docs/application_logic_analyzer.md §6.6）。界面说"能采"时，采集路径不会再报另一个错。
        knob_frame = ttk.LabelFrame(root, text="仪器面板", padding=8)
        knob_frame.grid(row=7, column=0, columnspan=3, sticky="ew", pady=(6, 0))

        head = ttk.Frame(knob_frame)
        head.pack(fill="x")
        self.knob_widgets["manual"] = ttk.Checkbutton(
            head, text="使用面板参数（覆盖模式默认）", variable=self.manual_var,
            command=self._on_manual_toggle)
        self.knob_widgets["manual"].pack(side="left")
        self.knob_widgets["load"] = ttk.Button(head, text="载入当前模式默认值",
                                               command=self._load_knob_defaults)
        self.knob_widgets["load"].pack(side="left", padx=(8, 0))
        # 板级时钟必须与实际下载的位流一致：镜像模式的时基是按"比特时间 ÷ 每比特采样点数"
        # 反算的，时钟填错就解出乱码（la85 = 85 MHz 交付位流，la50 = 50 MHz 备用位流）。
        ttk.Label(head, text="板级时钟").pack(side="left", padx=(14, 4))
        self.knob_widgets["clock"] = ttk.Combobox(head, textvariable=self.clock_var, width=12,
                                                  state="readonly",
                                                  values=("85000000", "50000000"))
        self.knob_widgets["clock"].pack(side="left")
        # 停止条件只对连续采集有意义。固件只在"触发过"以后才置 done（capture_engine.v
        # 第 55、59 行），所以每一次成功回包都必然是一次命中，这里的 N 就是"采满 N 次"。
        ttk.Label(head, text="采满").pack(side="left", padx=(14, 4))
        self.knob_widgets["stop_after"] = ttk.Entry(head, textvariable=self.stop_after_var, width=6)
        self.knob_widgets["stop_after"].pack(side="left")
        ttk.Label(head, text="次后停（0 = 一直采）").pack(side="left", padx=(4, 0))

        knob_grid = ttk.Frame(knob_frame)
        knob_grid.pack(fill="x", pady=(6, 0))
        knob_specs = (
            ("时基 sample_div", "sample_div", 8),
            ("触发方式", "trigger_type", 8),
            ("触发通道", "trigger_channel", 6),
            ("电平", "trigger_level", 6),
            ("pre", "pre", 6),
            ("post", "post", 7),
            ("激励速率", "pattern_div", 8),
            ("激励数据", "data", 6),
            # 采集源（双源可选）：0 = J8 外部 8 路，1 = Core 内部观测点。
            # 选 Core 时命令变成 0xA8（16 位 pre/post + 源字节），
            # 此时 pre/post 的上限也是 65535 而不是 255 —— 上限由 apply_knobs 按
            # "将要发出的那条命令"判，界面只负责把选择传下去。
            ("采集源", "source", 16),
        )
        for index, (label, name, width) in enumerate(knob_specs):
            row, col = divmod(index, 4)
            ttk.Label(knob_grid, text=label).grid(row=row, column=col * 2, sticky="e",
                                                  padx=(0 if col == 0 else 12, 4), pady=2)
            widget: tk.Widget
            if name == "trigger_type":
                widget = ttk.Combobox(knob_grid, textvariable=self.knob_vars[name], width=width,
                                      state="readonly", values=("level", "rise", "fall"))
                widget.bind("<<ComboboxSelected>>", lambda _e: self._update_knob_info())
            elif name == "trigger_level":
                widget = ttk.Combobox(knob_grid, textvariable=self.knob_vars[name], width=width,
                                      state="readonly", values=("1 高", "0 低"))
                widget.bind("<<ComboboxSelected>>", lambda _e: self._update_knob_info())
            elif name == "trigger_channel":
                widget = ttk.Combobox(knob_grid, textvariable=self.knob_vars[name], width=width,
                                      state="readonly",
                                      values=tuple("ch%d" % ch for ch in range(8)))
                widget.bind("<<ComboboxSelected>>", lambda _e: self._update_knob_info())
            elif name == "source":
                # 显示名与数值的对应只在 logic_analyzer_serial.SOURCE_CHOICES 里定义一次，
                # 界面与命令行不会各说各话。
                widget = ttk.Combobox(knob_grid, textvariable=self.knob_vars[name], width=width,
                                      state="readonly", values=self._source_labels())
                widget.bind("<<ComboboxSelected>>", lambda _e: self._on_source_change())
            else:
                widget = ttk.Entry(knob_grid, textvariable=self.knob_vars[name], width=width)
                widget.bind("<KeyRelease>", lambda _e: self._update_knob_info())
            self.knob_widgets[name] = widget
            widget.grid(row=row, column=col * 2 + 1, sticky="w", pady=2)

        self.knob_info_label = ttk.Label(knob_frame, textvariable=self.knob_info_var,
                                         foreground="#174a7c")
        self.knob_info_label.pack(anchor="w", pady=(6, 0))

        # 数据流那一栏在**第 2 页**（见 _build_trace_page）。这一页保持原样：
        # 它是已经过 G11 验收的逻辑分析仪界面，不往里塞别的东西。

        actions = ttk.Frame(root)
        actions.grid(row=8, column=0, columnspan=3, sticky="w", pady=(6, 4))
        self.logic_button = ttk.Button(actions, text="采集全部模式并生成 VCD", command=self._run_logic_analyzer)
        self.logic_button.pack(side="left", padx=(0, 8))
        ttk.Button(actions, text="打开输出目录", command=self._open_output).pack(side="left", padx=(0, 14))
        self.live_check = ttk.Checkbutton(actions, text="实时连续采集", variable=self.live_var,
                                          command=self._sync_knob_state)
        self.live_check.pack(side="left", padx=(0, 4))
        ttk.Label(actions, text="实时模式").pack(side="left")
        self.live_combo = ttk.Combobox(actions, textvariable=self.live_mode_var, width=9,
                                       state="readonly", values=[m for m, _ in MODE_VALUES])
        self.live_combo.pack(side="left", padx=(6, 0))
        # 换了模式，面板要跟着换：不同模式的默认触发/时基完全不同，留着上一模式的数字
        # 等于"用 UART 的触发去打 SPI"（大概率永远等不到触发，现场表现为超时）。
        self.live_combo.bind("<<ComboboxSelected>>", lambda _e: self._on_mode_change())

        ttk.Label(root, textvariable=self.status_var, foreground="#174a7c").grid(
            row=9, column=0, columnspan=3, sticky="w", pady=(0, 4)
        )
        # 实时波形面板：采集到的每一轮都在这里立刻画出来。
        # height=150 只是"最小请求高度"——它会在 grid 里随窗口一起变高（weight=3）；
        # 这里刻意压小，是因为 Windows 高 DPI 缩放下 Tk 的逻辑高度比实际小很多，
        # 请求太高会把下面的日志区挤出屏幕（2026-10-03 实测 150% 缩放踩到过）。
        self.panel = WaveformPanel(root, height=150)
        self.panel.grid(row=10, column=0, columnspan=4, sticky="nsew", pady=(0, 4))

        # [2026-10-22] 试过把日志区从 5 行加到 8 行（想让 15 条判据一屏读完），
        # **实测不可行**：窗口本来就贴着屏幕底边，加高 3 行直接把日志顶出可视区
        # （截图里只剩最上面一条深色边）。这就是下面 panel 注释里说的那个高 DPI 老坑。
        # 所以保持 5 行 + 滚动条：判据多了就滚，别为了少滚几下把日志弄丢。
        self.log = tk.Text(root, wrap="word", height=5, state="disabled", background="#101820", foreground="#d7f9ff")
        self.log.grid(row=11, column=0, columnspan=3, sticky="nsew")
        scroll = ttk.Scrollbar(root, orient="vertical", command=self.log.yview)
        scroll.grid(row=11, column=3, sticky="ns")
        self.log.configure(yscrollcommand=scroll.set)
        self.panel.clear("等待采集：下载最终 bitstream、接好 J8，然后点『采集全部模式并生成 VCD』")

        self._build_trace_page(page2)

    # ---- 第 2 页：CPU 数据流（发字符串 → 逐条指令 + 寄存器热力图）---------------
    def _build_trace_page(self, page: ttk.Frame) -> None:
        """第 2 页的版面（2026-10-24 第三轮：按成熟工具的范式重排）。

        借鉴的三处（都指向同一个范式，不是拍脑袋）：
          · **Perfetto / Chrome tracing** 的时间轴：多条 lane 共享**同一条时间轴**，
            一条竖光标贯穿全部 lane，选中项的详情另开一栏——
            https://deepwiki.com/google/perfetto/6.3-timeline-viewer-and-styling
          · **GTKWave / Surfer** 的波形：左侧信号名栏 + 右侧波形，单一时间光标；
          · **Ripes**（RISC-V 模拟器）把"架构状态"单独成视图、与流水线图分离，
            靠步进/拖动同步——https://ieeexplore.ieee.org/ielx8/6287639/11323511/11359194.pdf
        上一版是**四块独立画布**，各用一套 x 刻度、各套一套小标签，所以看着乱。
        现在合成**一块画布**：左边留 82 px 放泳道名，右边是一条共享时间轴，
        从上到下依次是 寄存器 / PC / 写存储地址 / 事件 四组泳道。
        指令表挪到左侧与光标同步（点行选中、选中行整行高亮），
        详情与判据收进底部标签页——不再和主视图抢高度。
        """
        page.columnconfigure(0, weight=1)
        page.rowconfigure(4, weight=5)   # 主体：左表 + 右泳道图
        page.rowconfigure(6, weight=1)   # 底部：详情 / 判据

        ttk.Label(page, text="CPU 数据流 · 逐条指令与寄存器热力图",
                  font=("Segoe UI", 15, "bold")).grid(row=0, column=0, sticky="w", pady=(0, 2))
        ttk.Label(page, text="发一个字符串给 CPU —— 它真的逐字节读、改、存；下面按退休顺序把每条指令与寄存器变化摊开。",
                  foreground="#174a7c").grid(row=1, column=0, sticky="w", pady=(0, 6))

        row_input = ttk.Frame(page)
        row_input.grid(row=2, column=0, sticky="ew")
        ttk.Label(row_input, text="发送给 CPU 的字符串").pack(side="left")
        self.trace_entry = ttk.Entry(row_input, textvariable=self.trace_text_var, width=28)
        self.trace_entry.pack(side="left", padx=(6, 10))
        ttk.Label(row_input, text="阶段").pack(side="left")
        self.trace_phase_combo = ttk.Combobox(row_input, textvariable=self.trace_phase_var,
                                              width=20, state="readonly",
                                              values=list(TRACE_PHASE_LABELS))
        self.trace_phase_combo.pack(side="left", padx=(6, 10))
        self.trace_button = ttk.Button(row_input, text="采集", command=self._run_trace)
        self.trace_button.pack(side="left", padx=(0, 8))
        self.trace_wave_var = tk.StringVar(value=TRACE_WAVE_WINDOWS[0][0])
        self.trace_wave_combo = ttk.Combobox(row_input, textvariable=self.trace_wave_var,
                                             width=9, state="readonly",
                                             values=[label for label, _v in TRACE_WAVE_WINDOWS])
        self.trace_wave_combo.pack(side="left")
        # 这条按钮走的是 0xAB：同一次运行里既采 Core 探针波形、又采逐条指令
        self.trace_wave_button = ttk.Button(row_input, text="波形+指令",
                                           command=self._run_wave)
        self.trace_wave_button.pack(side="left", padx=(4, 8))
        self.trace_live_check = ttk.Checkbutton(row_input, text="连续采集",
                                               variable=self.trace_live_var, command=self._on_trace_live)
        self.trace_live_check.pack(side="left", padx=(0, 8))
        ttk.Checkbutton(row_input, text="同时导出网页",
                        variable=self.trace_autoopen_var).pack(side="left")

        self.trace_info_label = ttk.Label(page, textvariable=self.trace_info_var, foreground="#174a7c")
        self.trace_info_label.grid(row=3, column=0, sticky="w", pady=(4, 4))

        # ---- 主体：左侧指令流（选中项 = 右侧光标位置）--------------------------
        body = ttk.Frame(page)
        body.grid(row=4, column=0, sticky="nsew")
        body.columnconfigure(0, weight=0, minsize=430)
        body.columnconfigure(1, weight=1)
        body.rowconfigure(0, weight=1)
        self.trace_list = tk.Text(body, wrap="none", width=52, height=10, state="disabled",
                                  font=("Consolas", 9), background="#0d1622", foreground="#dbe8ff",
                                  insertwidth=0, highlightthickness=0)
        self.trace_list.grid(row=0, column=0, sticky="nsew")
        self.trace_list.bind("<Button-1>", self._on_trace_list_click)
        list_scroll = ttk.Scrollbar(body, orient="vertical", command=self.trace_list.yview)
        list_scroll.grid(row=0, column=0, sticky="nse")
        self.trace_list.configure(yscrollcommand=list_scroll.set)

        # 右侧：**一块**画布，四组泳道共享一条时间轴
        self.trace_timeline = tk.Canvas(body, background="#0b111d", highlightthickness=0,
                                        height=330)
        self.trace_timeline.grid(row=0, column=1, sticky="nsew", padx=(8, 0))
        self.trace_timeline.bind("<Configure>", lambda _e: self._draw_trace_timeline())
        self.trace_timeline.bind("<Button-1>", self._on_trace_canvas_click)
        self.trace_timeline.bind("<Motion>", self._on_trace_hover)
        self.trace_timeline.bind("<Leave>", lambda _e: self._clear_hover())

        # ---- 播放条 ---------------------------------------------------------
        row_play = ttk.Frame(page)
        row_play.grid(row=5, column=0, sticky="ew", pady=(4, 0))
        self.trace_play_button = ttk.Button(row_play, text="▶ 播放", width=9, command=self._toggle_trace_play)
        self.trace_play_button.pack(side="left")
        ttk.Button(row_play, text="◀", width=3,
                   command=lambda: self._trace_select(self.trace_sel - 1)).pack(side="left", padx=(6, 0))
        ttk.Button(row_play, text="▶", width=3,
                   command=lambda: self._trace_select(self.trace_sel + 1)).pack(side="left", padx=(2, 6))
        self.trace_scrub = ttk.Scale(row_play, from_=0, to=0, orient="horizontal", length=300,
                                     command=self._on_scrub)
        self.trace_scrub.pack(side="left")
        self.trace_pos_var = tk.StringVar(value="尚未采集")
        ttk.Label(row_play, textvariable=self.trace_pos_var, foreground="#174a7c").pack(side="left", padx=(8, 0))

        # ---- 底部：详情 / 判据 两个标签页（不再挤占主视图）--------------------
        bottom_nb = ttk.Notebook(page)
        bottom_nb.grid(row=6, column=0, sticky="nsew", pady=(6, 0))
        tab_detail = ttk.Frame(bottom_nb, padding=4)
        tab_log = ttk.Frame(bottom_nb, padding=4)
        bottom_nb.add(tab_detail, text="  这条指令  ")
        bottom_nb.add(tab_log, text="  判据日志  ")
        self.trace_detail = tk.Text(tab_detail, wrap="word", height=6, state="disabled",
                                    font=("Consolas", 9), background="#0d1622", foreground="#cfe0ff",
                                    highlightthickness=0)
        self.trace_detail.pack(fill="both", expand=True)
        self.trace_log = tk.Text(tab_log, wrap="word", height=6, state="disabled",
                                 background="#101820", foreground="#d7f9ff", highlightthickness=0)
        self.trace_log.pack(fill="both", expand=True)

        self._append_trace_log("尚未采集。填字符串 → 点「采集」。\n")
        self._draw_trace_all()

    def _append_trace_log(self, text: str) -> None:
        self.trace_log.configure(state="normal")
        self.trace_log.insert("end", text)
        self.trace_log.see("end")
        self.trace_log.configure(state="disabled")

    def _on_trace_live(self) -> None:
        if self.trace_live_var.get() and not self.running:
            self._run_trace()
        elif not self.trace_live_var.get():
            self._cancel_trace_refresh()

    def _cancel_trace_refresh(self) -> None:
        job = getattr(self, "_trace_job", None)
        if job is not None:
            try:
                self.after_cancel(job)
            except tk.TclError:
                pass
            self._trace_job = None

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

    # ------------------------------------------------------------ 仪器面板
    @staticmethod
    def _source_labels() -> tuple[str, ...]:
        from logic_analyzer_serial import SOURCE_CHOICES

        return tuple(label for label, _ in SOURCE_CHOICES)

    @staticmethod
    def _source_to_label(value: int) -> str:
        from logic_analyzer_serial import SOURCE_CHOICES

        for label, code in SOURCE_CHOICES:
            if code == value:
                return label
        return SOURCE_CHOICES[0][0]

    @staticmethod
    def _label_to_source(label: str) -> int:
        from logic_analyzer_serial import SOURCE_CHOICES

        for name, code in SOURCE_CHOICES:
            if name == label:
                return code
        raise ValueError(f"未知采集源 {label!r}；可用：{'、'.join(n for n, _ in SOURCE_CHOICES)}")

    def _on_source_change(self) -> None:
        """切换采集源后立刻把窗口换成新源下的合法默认值，并重算面板提示。

        为什么必须跟着换：`0xA8`（Core 源）的 pre/post 各 2 字节、`0xA5`（J8 源）只有
        1 字节。从 Core 切回 J8 时，`post=1983` 会超出 1 字节上限，采集时被 `apply_knobs`
        拦下——那是正确的拦截，但现场看到报错会以为功能坏了；反过来从 J8 切到 Core 时，
        用户要的多半也是 2048 点全速窗口。
        """
        from logic_analyzer_serial import SOURCE_CORE, default_config

        if self.manual_var.get():
            try:
                if self._label_to_source(self.knob_vars["source"].get()) == SOURCE_CORE:
                    # 切到 Core：窗口取 **core 模式**的默认值（全速采样 + 2048 点），
                    # 而不是当前模式（例如 uart 的 64/191）——后者虽然在 0xA8 里合法，
                    # 但用户点"Core 内部观测点"想要的就是看流水线的那一窗。
                    cfg = default_config("core", 0, self._clock_hz())
                    self.knob_vars["sample_div"].set("0")
                    self.knob_vars["pre"].set(str(cfg["pre"]))
                    self.knob_vars["post"].set(str(cfg["post"]))
                else:
                    # 切回 J8：命令回到 0xA5（pre/post 各 1 字节），窗口必须压回 255 以内，
                    # 否则采集时会被 apply_knobs 正确地拦下，现场却会以为功能坏了。
                    cfg = self._default_cfg()
                    self.knob_vars["pre"].set(str(min(int(cfg["pre"]), 0xFF)))
                    self.knob_vars["post"].set(str(min(int(cfg["post"]), 0xFF)))
            except (ValueError, KeyError):
                pass
        self._update_knob_info()

    def _clock_hz(self) -> int:
        try:
            return int(self.clock_var.get())
        except ValueError:
            return 85_000_000

    def _current_mode(self) -> str:
        return self.live_mode_var.get()

    def _mode_value(self, mode: str) -> int:
        return dict(MODE_VALUES).get(mode, 0xA5)

    def _default_cfg(self) -> dict:
        """当前模式的默认参数（与命令行、板级验收用的是同一个 default_config）。"""
        from logic_analyzer_serial import default_config

        try:
            baud = int(self.baud_var.get())
        except ValueError:
            baud = 115200
        return default_config(self._current_mode(), self._mode_value(self._current_mode()),
                              self._clock_hz(), baud)

    @staticmethod
    def _mask_to_channel(mask: int) -> int:
        """单选通道掩码 → 通道号；多通道掩码取最低那一位。"""
        for channel in range(8):
            if mask & (1 << channel):
                return channel
        return 0

    def _load_knob_defaults(self) -> None:
        """把当前模式的默认参数填进面板。

        空着的输入框发出去等于把参数改成 0（例如 post=0 → 窗口只有触发那一点），
        所以勾选面板时第一件事就是载入默认值，操作员只改他要改的那一个。
        """
        cfg = self._default_cfg()
        self.knob_vars["sample_div"].set(str(cfg["sample_div"]))
        self.knob_vars["trigger_type"].set(("level", "rise", "fall")[cfg["trigger_type"]])
        self.knob_vars["trigger_channel"].set("ch%d" % self._mask_to_channel(cfg["trigger_mask"]))
        self.knob_vars["trigger_level"].set(
            "1 高" if (cfg["trigger_value"] & cfg["trigger_mask"]) else "0 低")
        self.knob_vars["pre"].set(str(cfg["pre"]))
        self.knob_vars["post"].set(str(cfg["post"]))
        self.knob_vars["pattern_div"].set(str(cfg["pattern_div"]))
        self.knob_vars["data"].set(str(cfg["data"]))
        # 采集源：从模式默认配置读（`core` 模式默认为 1 = Core 内部观测点）
        self.knob_vars["source"].set(self._source_to_label(int(cfg.get("source", 0))))
        self._update_knob_info()

    def _collect_knobs(self) -> dict:
        """把面板控件收成 logic_analyzer_serial 认的字段名（返回原始字符串）。

        两处换算集中在这里：
        1. 界面上选"触发通道 ch3"，报文里要的是掩码 `1<<3`；
        2. 电平触发的目标值必须**与掩码同位**——capture_engine.v 第 25 行是
           `(channels & active_mask) == (trigger_value & active_mask)`，
           所以 ch3 选"高"时值要写 0x08，写 1 会被 AND 成 0，触发电平就反了。
        """
        knobs = {name: self.knob_vars[name].get() for name in
                 ("sample_div", "pre", "post", "pattern_div", "data")}
        # 采集源：界面显示名 → 报文数值（0xA8 的 [14] 字节 / 是否走 0xA8）
        knobs["source"] = self._label_to_source(self.knob_vars["source"].get())
        channel_text = self.knob_vars["trigger_channel"].get().strip().lstrip("ch")
        try:
            channel = int(channel_text)
        except ValueError:
            raise ValueError(
                f"触发通道 {self.knob_vars['trigger_channel'].get()!r} 不是 ch0…ch7") from None
        if not 0 <= channel <= 7:
            raise ValueError(f"触发通道 {channel} 越界：本板只有 ch0…ch7")
        knobs["trigger_type"] = {"level": 0, "rise": 1, "fall": 2}.get(
            self.knob_vars["trigger_type"].get(), 0)
        knobs["trigger_mask"] = 1 << channel
        knobs["trigger_value"] = (1 << channel) if self.knob_vars["trigger_level"].get().startswith("1") else 0
        if self._current_mode() == "mirror":
            # 镜像模式只接受 post：其余字段在固件里被重新定义或写死
            # （见 logic_analyzer_serial.MIRROR_REJECT），控件也已禁用，这里再兜一次。
            knobs = {"post": knobs["post"]}
        return knobs

    def _update_knob_info(self) -> None:
        """面板的即时校验：这组参数能不能采、采出来每比特几个采样点、窗口多少点。"""
        from logic_analyzer_serial import apply_knobs, mirror_required_samples

        try:
            cfg = apply_knobs(self._current_mode(), self._default_cfg(),
                              self._collect_knobs() if self.manual_var.get() else None)
        except (ValueError, KeyError) as exc:
            self.knob_info_var.set("✗ " + str(exc))
            self.knob_info_label.configure(foreground="#b3261e")
            return
        window = cfg["pre"] + 1 + cfg["post"]
        source_name = self._source_to_label(int(cfg.get("source", 0)))
        text = ("采集源 %s · 每比特 %d 个采样点 · 窗口 %d 点（pre %d + 触发 1 + post %d）"
                % (source_name, cfg["bit_samples"], window, cfg["pre"], cfg["post"]))
        if self._current_mode() == "mirror":
            need = mirror_required_samples(self.mirror_text_var.get() or "HELLO,RISC-V",
                                           cfg["bit_samples"])
            text += " · 整句至少要 %d 点" % need
            if window < need:
                self.knob_info_var.set("✗ 镜像窗口 %d 点装不下整句（需要 %d 点）" % (window, need))
                self.knob_info_label.configure(foreground="#b3261e")
                return
        if not self.manual_var.get():
            text += " ·（当前用模式默认值，勾选左侧才生效）"
        self.knob_info_var.set(text)
        self.knob_info_label.configure(foreground="#174a7c")

    def _sync_knob_state(self) -> None:
        """按"是否勾选面板 + 当前模式 + 是否在跑"决定每个控件能不能动。"""
        manual = bool(self.manual_var.get())
        mirror = self._current_mode() == "mirror"
        for name, widget in self.knob_widgets.items():
            if name == "manual":
                enabled = not self.running
            elif name == "load":
                enabled = not self.running
            elif name == "stop_after":
                # 停止条件只对连续采集有意义
                enabled = not self.running and bool(self.live_var.get())
            elif name == "clock":
                enabled = not self.running
            elif name == "post":
                enabled = manual and not self.running
            else:
                # 镜像模式下除 post 以外的旋钮全部禁用：固件里它们被重新定义或写死
                enabled = manual and not mirror and not self.running
            if isinstance(widget, ttk.Combobox):
                widget.configure(state="readonly" if enabled else "disabled")
            else:
                widget.configure(state="normal" if enabled else "disabled")

    def _on_manual_toggle(self) -> None:
        if self.manual_var.get():
            # 先载入默认值，避免空框被当成 0 发出去
            self._load_knob_defaults()
        self.logic_button.configure(
            text="停止采集" if self.running else
            ("按面板参数采集当前模式" if self.manual_var.get() else "采集全部模式并生成 VCD"))
        self._sync_knob_state()
        self._update_knob_info()

    def _on_mode_change(self) -> None:
        if self.manual_var.get():
            self._load_knob_defaults()
        else:
            # 不勾面板时旋钮是灰的，但"采集源"这一格必须显示**真正会用的**那个值：
            # core 模式默认就走 Core 内部观测点，格子还写 J8 会与实际采集不符
            #（那正是"界面说的和板子做的不一样"这一类坑）。
            self.knob_vars["source"].set(
                self._source_to_label(int(self._default_cfg().get("source", 0))))
        self._sync_knob_state()
        self._update_knob_info()

    def _set_running(self, running: bool) -> None:
        self.running = running
        # 运行中按钮变成「停止采集」且保持可点（实时模式下必须能停下来）
        if running:
            self.logic_button.configure(text="停止采集")
        else:
            self.logic_button.configure(
                text="按面板参数采集当前模式" if self.manual_var.get() else "采集全部模式并生成 VCD")
        state = "disabled" if running else "normal"
        for widget in (self.live_check, self.live_combo):
            widget.configure(state=state)
        self._sync_knob_state()
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

    # ---- 提交级数据流（trace）：输入框 + 采集 ---------------------------------
    def _trace_phase(self) -> int:
        try:
            return TRACE_PHASE_LABELS.index(self.trace_phase_var.get())
        except ValueError:
            return 0

    def _trace_problem(self) -> str:
        """输入不合法时返回原因，合法返回空串。

        **界面禁用与采集前的拒绝都用这一个判定**：两处各写一遍迟早会分叉
        （控件变成可点、点下去又失败，现场最容易踩）。
        """
        text = self.trace_text_var.get()
        if not text:
            return "字符串不能为空"
        if len(text) > TRACE_MAX_CHARS:
            return "最长 %d 个字符，当前 %d 个" % (TRACE_MAX_CHARS, len(text))
        try:
            text.encode("ascii")
        except UnicodeEncodeError:
            return "只支持 ASCII 字符（中文或全角符号请换掉）"
        return ""

    def _update_trace_info(self) -> None:
        """输入一变就给出"能不能发 / 发出去会得到什么"。

        预计算复用 ``trace_view.expected_phase0``——那同时也是自动判据用的实现，
        所以界面上写着"会得到 HELLO,RV"，判据要求的也一定是同一个结果。
        """
        problem = self._trace_problem()
        if problem:
            self.trace_info_var.set("✗ " + problem)
            foreground = "#b3261e"
            if self.trace_button is not None:
                self.trace_button.configure(state="disabled")
        else:
            text = self.trace_text_var.get()
            phase = self._trace_phase()
            try:
                import trace_view

                if phase == 0:
                    exp = trace_view.expected_phase0(text)
                    preview = "".join(chr(c) if 32 <= c < 127 else "." for c in exp["want"])
                    detail = "会得到 %r · up=%d · xor=0x%08X" % (preview, exp["up"], exp["xor"])
                else:
                    detail = "窗口里会包含串口轮询（115200 下一个字符约 4400 条提交）"
            except ImportError as exc:  # 缺 trace_view.py 时界面其余部分照常可用
                detail = "缺少 trace_view.py：%s" % exc
            self.trace_info_var.set("%d 个字符 · 阶段 %d · %s" % (len(text), phase, detail))
            foreground = "#174a7c"
            if self.trace_button is not None and not self.running:
                self.trace_button.configure(state="normal")
        try:
            self.trace_info_label.configure(foreground=foreground)
        except tk.TclError:  # 控件已销毁（关窗过程中）
            pass

    def _run_trace(self) -> None:
        if self.running:
            return
        self._cancel_trace_refresh()
        problem = self._trace_problem()
        if problem:
            messagebox.showerror("数据流采集", problem)
            return
        port, baud, timeout, output = self._read_common()
        text = self.trace_text_var.get()
        phase = self._trace_phase()
        autoopen = bool(self.trace_autoopen_var.get())
        mem = self.base_dir.parent / "fpga" / "trace85" / "rtl" / "logic_analyzer_program.mem"

        def work() -> None:
            import trace_board
            import trace_view

            raw, capture = trace_board.run_trace(port, baud, text, phase, timeout)
            out = trace_board.capture_and_page(output / "trace", text, phase, capture, str(mem))
            out["log"].write_bytes(raw)
            # 数据流视图要的是"每条记录 + 依赖边"，那一步在后台线程算好（纯 python），
            # 再整包丢给 UI 线程去画——绝不在后台线程碰 Tk 控件。
            imem = None
            if Path(mem).exists():
                imem = trace_view.load_program_mem(mem)
            flow = trace_view.build_flow(capture, imem)
            self.events.put(("trace", {
                "text": text,
                "phase": phase,
                "count": capture["count"],
                "status": capture["status"],
                "marks": capture["marks"],
                "nodes": flow["nodes"],
                "judgements": out["judgements"],
                "summary": out["summary"],
                "html": str(out["html"]),
                "pass": out["pass"],
            }))
            if autoopen:
                try:
                    os.startfile(str(out["html"]))  # noqa: S606 - Windows 下用默认浏览器打开
                except OSError:
                    print("自动打开失败，请手动打开：%s" % out["html"])

        self._start_worker("CPU 数据流采集", work)

    def _run_wave(self) -> None:
        """0xAB 组合采集：**一次运行**同时拿 Core 探针波形和逐条指令，并按拍对齐。"""
        self._cancel_trace_refresh()
        problem = self._trace_problem()
        if problem:
            messagebox.showerror("波形 + 指令流采集", problem)
            return
        port, baud, timeout, output = self._read_common()
        text = self.trace_text_var.get()
        window = dict((label, value) for label, value in TRACE_WAVE_WINDOWS)[
            self.trace_wave_var.get()]
        mem = self.base_dir.parent / "fpga" / "trace85" / "rtl" / "logic_analyzer_program.mem"

        def work() -> None:
            import trace_board
            import trace_view

            raw, res = trace_board.run_wave(port, baud, text, window, timeout)
            out = trace_board.capture_wave(output / "trace", text, window, res, str(mem),
                                          raw)
            imem = None
            if Path(mem).exists():
                imem = trace_view.load_program_mem(mem)
            flow = trace_view.build_flow(res["capture"], imem)
            align = trace_view.align_wave(res["capture"], res["wave"], flow["nodes"])
            self.events.put(("wavetrace", {
                "text": text,
                "phase": 0,
                "count": res["capture"]["count"],
                "status": res["capture"]["status"],
                "marks": res["capture"]["marks"],
                "nodes": flow["nodes"],
                "judgements": out["judgements"],
                "summary": out["summary"],
                "html": str(out["html"]),
                "pass": out["pass"],
                "wave": res["wave"],
                "align": align,
            }))

        self._start_worker("Core 探针波形 + 指令流采集", work)

    # ---- 第 2 页的绘制（全部在 UI 线程）---------------------------------------
    def _show_wave_capture(self, payload: dict) -> None:
        """把 0xAB 的波形 + 指令流装进第 2 页：波形泳道按拍、记录按退休的那一拍定位。"""
        wave = payload.get("wave")
        align = payload.get("align")
        self.trace_wave = wave
        self.trace_align = align
        cyc = None
        if wave and align:
            cyc = [None] * len(payload["nodes"])
            k = 0
            for c, v in enumerate(wave["samples"]):
                if v & 0x80:                      # bit7 = 退休脉冲（与 trace_view 一致）
                    idx = align["offset"] + k
                    if 0 <= idx < len(cyc) and cyc[idx] is None:
                        cyc[idx] = c
                    k += 1
        self._trace_cyc = cyc
        self._tl_lo = 0
        self._tl_static_key = None
        self._show_trace(payload)
        if align:
            # 默认落在**波形窗口里的第一条记录**上（而不是 #0）：用户打开就该看到
            # "这条指令 ↔ 它那一拍的探针脉冲"这几根标记，而不是"不在波形窗口内"。
            first = int(align.get("offset") or 0)
            self._trace_select(first)
            self._append_trace_log(
                "\n波形对齐：%d 拍 · %d 个退休脉冲 · 覆盖记录 #%d..#%d · "
                "数据访问脉冲 %d / 区间访存 %d（差 %d）\n"
                % (align["cycles"], align["retire_pulses"], align["offset"],
                   align["offset"] + align["retire_pulses"] - 1, align["data_pulses"],
                   align["data_records"], align["mismatch"]))

    def _show_trace(self, payload: dict) -> None:
        self.trace_nodes = payload["nodes"]
        self.trace_marks = payload["marks"]
        self.trace_pass = bool(payload["pass"])
        # 普通 0xAA 那一枪没有波形：把上一次 0xAB 的波形与对齐一起撤掉，
        # 否则界面会拿旧的拍号去定位新的记录（"图说的和板子做的不一样"）。
        if not payload.get("wave"):
            self.trace_wave = None
            self.trace_align = None
            self._trace_cyc = None
        self.trace_sel = 0
        self.trace_scrub.configure(to=max(0, len(self.trace_nodes) - 1))
        self._set_scrub(0)
        self._append_trace_log("\n===== 这一枪：%r（阶段 %d）=====\n"
                               % (payload["text"], payload["phase"]))
        for name, ok, detail in payload["judgements"]:
            self._append_trace_log("%s %s — %s\n" % ("PASS" if ok else "FAIL", name, detail))
        summary = payload["summary"]
        self._append_trace_log("记录 %d 条 · 打点 %d 个 · 热点前四占 %.2f%%\n"
                              % (summary["records"], summary["chars"], 100.0 * summary["top4_share"]))
        if payload["html"]:
            self._append_trace_log("浏览器页：%s\n" % payload["html"])
        self.status_var.set("CPU 数据流：%s（%d 条记录）" % ("PASS" if payload["pass"] else "FAIL",
                                                        payload["count"]))
        self._trace_select(0)
        # 「连续采集（实时刷新）」：上一枪跑完立刻再来一枪，热力图就一直跟着板子动。
        if self.trace_live_var.get() and payload["pass"]:
            self._trace_job = self.after(400, self._run_trace)

    def _on_scrub(self, value) -> None:
        """滑杆回调：程序自己 set() 的时候必须忽略，否则会无限递归。"""
        if self._scrub_syncing:
            return
        try:
            self._trace_select(int(float(value)))
        except (TypeError, ValueError):
            return

    def _set_scrub(self, value: int) -> None:
        self._scrub_syncing = True
        try:
            self.trace_scrub.set(value)
        except tk.TclError:
            pass
        finally:
            self._scrub_syncing = False

    def _trace_select(self, index: int) -> None:
        if not self.trace_nodes:
            self.trace_pos_var.set("尚未采集")
            return
        self.trace_sel = max(0, min(len(self.trace_nodes) - 1, int(index)))
        self._set_scrub(self.trace_sel)
        pos = "#%d / %d" % (self.trace_sel, len(self.trace_nodes) - 1)
        cyc = getattr(self, "_trace_cyc", None)
        if cyc and self.trace_sel < len(cyc):
            sp = self._record_span_cycles(self.trace_sel)
            if sp is not None:
                pos += " · 第 %d–%d 拍（%d 拍后退休）" % (sp[0], sp[1], sp[1] - sp[0] + 1)
            else:
                pos += " · 不在波形窗口内"
        self.trace_pos_var.set(pos)
        self._draw_trace_all()
        self._draw_trace_list()
        self._draw_trace_detail()

    def _draw_trace_all(self) -> None:
        """重画时间轴。静态图层（数据块）有缓存，选中变化时只重画光标层。"""
        self._draw_trace_timeline()

    def _on_trace_hover(self, event) -> None:
        """鼠标悬停：直接把那一列的指令与动作显示在游标行上，不用先点。"""
        nodes = self.trace_nodes
        if not nodes:
            return
        lo, hi, bw, x0 = self._tl_geom()[:4]
        u = max(lo, min(hi - 1, lo + int((event.x - x0) / bw)))
        i = self._record_at_unit(u)
        nd = nodes[i]
        eff = ""
        if nd["rd_we"]:
            eff = "x%d=0x%08X" % (nd["rd"], nd["rd_data"])
        if nd["mem_we"]:
            eff += ("  " if eff else "") + "[0x%03X]<-0x%02X" % (nd["mem_addr"], nd["mem_data"] & 0xFF)
        self.trace_pos_var.set("#%d / %d   %s   %s" % (i, len(nodes) - 1, nd["asm"], eff))

    def _clear_hover(self) -> None:
        if self.trace_nodes:
            self.trace_pos_var.set("#%d / %d" % (self.trace_sel, len(self.trace_nodes) - 1))

    _REG_COLORS = ("#3ad2a0", "#39c0ff", "#e6a8ff", "#ffd479", "#ff8fb0",
                   "#8ff0c0", "#7fd6ff", "#c48bff")

    def _reg_color(self, reg: int) -> str:
        return self._REG_COLORS[reg % len(self._REG_COLORS)]

    # 值来源类别 → 颜色。这是"数据流"的关键一维：
    #   青 = 从存储器读进来的（load 的 rd_data 就是内存的值）
    #   绿 = ALU 算出来的
    #   紫 = 指令自带的立即数（lui/auipc）
    #   黄 = PC 系（jal/jalr 写回的返回地址）
    _LOAD_MN = ("lb", "lh", "lw", "lbu", "lhu")
    _SRC_COLORS = {"load": "#39c0ff", "alu": "#3ad2a0", "imm": "#e6a8ff", "pc": "#ffd479"}
    # 8 条探针泳道的颜色**按语义成对**：提交/冲刷/停顿各一色，
    # 数据通道（请求+就绪）同一蓝家族、取指通道（请求+就绪+响应）同一紫家族。
    # 上一版 8 条全用同一个暗蓝，用户 2026-10-24 当场说"感觉没啥变化"。
    _TL_WAVE_ON = "#5ef0c0"
    _TL_WAVE_COLORS = ("#5ef0c0",   # 提交
                       "#ffb347",   # 冲刷
                       "#ff7f9e",   # 停顿
                       "#7fe0ff",   # 数据就绪（蓝家族浅）
                       "#39c0ff",   # 数据请求（蓝家族深）
                       "#d18bff",   # 取指响应（紫家族深）
                       "#b9a6ff",   # 取指就绪（紫家族浅）
                       "#8f7fff")   # 取指请求
    _TL_WAVE_ROW_H = 11.5     # 探针泳道的行高：不再和其它泳道同一个行距
    _TL_LANE_RETIRE = 0       # 提交脉冲在第 0 条
    _TL_LANE_DR = 3           # 数据就绪
    _TL_LANE_DV = 4           # 数据请求

    def _value_kind(self, node) -> str:
        mn = node["mnemonic"]
        if mn in self._LOAD_MN:
            return "load"
        if mn in ("lui", "auipc"):
            return "imm"
        if mn in ("jal", "jalr"):
            return "pc"
        return "alu"

    # ---- 时间轴：一块画布、一条共享横轴、一条贯穿全部泳道的光标 -------------
    # 这个版面不是随手排的，是照着成熟工具的共同范式来的：
    #   · Perfetto / Chrome tracing：多条 track 共享一根时间轴，一个光标，详情另开一栏；
    #   · GTKWave / Surfer：左侧信号名栏 + 右侧波形，单光标；
    #   · Ripes：架构状态（寄存器/存储）与流水线分开看，靠光标/步进同步。
    # 上一版失败的原因正是这三点全反着来：四块画布、四套刻度、四套标签。
    _TL_GUTTER = 82      # 左侧泳道名栏宽度
    _TL_RIGHT = 26
    _TL_HDR = 10         # 每个泳道组的组名条高度
    _TL_ROW_MIN = 7.0    # 行高下限：7 pt 的字再挤就糊了，放不下就少画几行
    _TL_PX_PER_REC = 3.0  # 一条记录最少占几像素：1 px 会糊成"条形码"，3 px 还看得出单条指令

    def _tl_geom(self):
        """返回 (lo, hi, bw, x0, x1, n)：当前显示的那一段**单位**与它的几何。

        单位（unit）在两种模式下含义不同，但下游代码只用这一套：
          · 没有波形时：单位 = 「第几条记录」；
          · 载入了 0xAB 的波形时：单位 = 「第几拍」（cycle），记录按它退休的那一拍定位。
        这样"波形"和"指令流"能用**同一根横轴**——这正是 §6.11.10 里说的那种范式，
        也是 0xAB 组合命令存在的全部意义。

        **为什么要分段显示**：阶段 1 一枪有 4096 条记录，而画布只有 ~1160 px 宽。
        若硬把 4096 条压进 1160 列，一个像素列里就叠了 3～4 条记录，
        颜色只能"谁最后写谁说了算"，整块面板必然糊成一片色带——
        2026-10-22 实测就是这样。所以这里保证**一个单位至少占 3 px**，
        超出的部分取当前光标附近的一段，并在标尺上标出真实的拍号/记录号，
        另配一条全览条显示"现在看的是整窗的哪一段"。
        """
        c = self.trace_timeline
        w = max(1, c.winfo_width())
        unit, n = self._trace_unit_list()
        x0 = self._TL_GUTTER
        x1 = max(x0 + 24, w - self._TL_RIGHT)
        span = max(1, x1 - x0)
        vis = max(1, min(n, int(span // self._TL_PX_PER_REC)))
        if n <= vis:
            lo = 0
        else:
            sel = max(0, min(n - 1, self.trace_sel))
            sel_unit = unit[sel] if unit[sel] is not None else 0
            lo = max(0, min(n - vis, getattr(self, "_tl_lo", 0)))
            if sel_unit < lo:                  # 光标跑到左边看不到的地方 → 往前翻一页
                lo = max(0, sel_unit - vis // 8)
            elif sel_unit >= lo + vis:         # 跑到右边 → 往后翻一页（留一点重叠）
                lo = min(max(0, n - vis), sel_unit - vis + vis // 8)
            self._tl_lo = lo
        hi = min(n, lo + vis)
        return lo, hi, (x1 - x0) / max(1, hi - lo), x0, x1, n

    def _trace_unit_list(self):
        """每条记录对应哪个单位（有波形时是拍号，否则是记录号），以及单位总数。"""
        nodes = self.trace_nodes
        cyc = getattr(self, "_trace_cyc", None)
        if cyc and len(cyc) >= len(nodes):
            return cyc, max(1, len(self.trace_wave["samples"]))
        return list(range(len(nodes))), max(1, len(nodes))

    def _record_at_unit(self, u: int) -> int:
        """把"第几拍/第几条"换算回记录下标（波形模式下拍号是单调的，可以二分）。"""
        unit = getattr(self, "_trace_cyc", None)
        n = len(self.trace_nodes)
        if not unit or len(unit) < n:
            return max(0, min(n - 1, int(u)))
        best = None
        for i in range(n):
            if unit[i] is None:
                continue
            if unit[i] <= u:
                best = i
            else:
                break
        return best if best is not None else 0

    def _cell_span(self, unit, i, lo, hi, bw):
        """第 i 条记录在画布上占哪一段像素。

        **块的右边界 = 它退休的那一拍**，左边界 = 上一条记录退休的下一拍。
        这样"块"读起来就是"这条指令从上次退休之后跑到自己退休"的那段时间——
        访存指令的数据访问脉冲也正好落在自己的块里（MEM 在自己的 WB 之前），
        所以能一眼看出"这块里有且只有一个数据访问脉冲"。
        """
        u = unit[i] if i < len(unit) else None
        if u is None or u < lo:
            return None
        prev = None
        for j in range(i - 1, -1, -1):
            if unit[j] is not None:
                prev = unit[j]
                break
        start = lo if prev is None else max(lo, prev + 1)
        if start > u:
            start = u
        px = self._TL_GUTTER + (start - lo) * bw
        return px, max(1.0, (u - start + 1) * bw - 0.25)

    def _record_span_cycles(self, i):
        """(这条指令占的起拍, 退休拍)；不在波形窗口内时返回 None。"""
        cyc = getattr(self, "_trace_cyc", None)
        if not cyc or i >= len(cyc) or cyc[i] is None:
            return None
        prev = None
        for j in range(i - 1, -1, -1):
            if cyc[j] is not None:
                prev = cyc[j]
                break
        start = 0 if prev is None else prev + 1
        return start, cyc[i]

    @staticmethod
    def _lighten(color: str, k: float = 0.45) -> str:
        """把颜色往白色方向提一点，用来画阶跃沿（比主色亮一档，看得出是"沿"）。"""
        try:
            r = int(color[1:3], 16)
            g = int(color[3:5], 16)
            b = int(color[5:7], 16)
        except (ValueError, IndexError):
            return color
        r = int(r + (255 - r) * k)
        g = int(g + (255 - g) * k)
        b = int(b + (255 - b) * k)
        return "#%02x%02x%02x" % (r, g, b)

    def _trace_reg_stat(self) -> dict:
        """本窗口里每个寄存器被写几次、被读几次（只列真正用到的寄存器）。"""
        stat: dict = {}
        for nd in self.trace_nodes:
            for r in nd["reads"]:
                stat.setdefault(r, [0, 0])[1] += 1
            if nd["rd_we"] and nd["rd"]:
                stat.setdefault(nd["rd"], [0, 0])[0] += 1
        return stat

    @staticmethod
    def _store_key(nd):
        """写存储的行键：能还原出完整地址就按地址分行，否则退回低 12 位的字索引。"""
        full = nd.get("store_addr")
        if full is not None:
            return ("addr", full)
        return ("low", (nd["mem_addr"] >> 2) & 0x1F)

    @staticmethod
    def _store_label(key, sample) -> str:
        """行标签：MMIO 打印完整地址（0x1000_222C 这种必须看全），内存打印低 16 位。"""
        if key[0] != "addr":
            return "?%03X" % sample["mem_addr"]
        addr = key[1]
        return ("%08X" % addr) if addr >= 0x10000000 else ("%04X" % (addr & 0xFFFF))

    def _tl_fit(self, height: float, keys: list) -> tuple:
        """行高不够就砍行：宁可少画几行，也不要画成每行 3 px 的虚线。"""
        if not keys:
            return [], max(1.0, height)
        if len(keys) * self._TL_ROW_MIN > height:
            keys = keys[:max(1, int(height // self._TL_ROW_MIN))]
        return keys, max(1.0, height / len(keys))

    def _draw_trace_timeline(self) -> None:
        """重画整条时间轴。数据块只在"数据、尺寸或视窗段变了"时重建。"""
        c = self.trace_timeline
        n = len(self.trace_nodes)
        # 视窗段 lo 也进 key：光标走到一段外面时整块要跟着平移
        key = (id(self.trace_nodes), n, c.winfo_width(), c.winfo_height(),
               self._tl_geom()[0])
        if getattr(self, "_tl_static_key", None) != key:
            self._draw_trace_lanes()
            self._tl_static_key = key
        self._draw_trace_cursor()

    def _draw_trace_lanes(self) -> None:
        """静态图层：标尺 + 四组泳道 + 数据块 + 图例。

        四组泳道自上而下：寄存器 / PC / 写存储地址 / 事件。
        它们**共用**顶部的记录号横轴和同一条竖光标——这正是上一版最缺的东西。
        """
        c = self.trace_timeline
        c.delete("all")
        w = max(1, c.winfo_width())
        h = max(1, c.winfo_height())
        nodes = self.trace_nodes
        self._tl_layout = None
        if not nodes:
            c.create_text(w // 2, max(24, h // 2), fill="#6d80a0", font=("Segoe UI", 10),
                          text="还没有数据 —— 填字符串，然后点「采集」")
            return
        lo, hi, bw, x0, x1, n = self._tl_geom()
        unit, n_units = self._trace_unit_list()
        wave = getattr(self, "trace_wave", None)
        seg = [(i, nd) for i, nd in enumerate(nodes)
               if unit[i] is not None and lo <= unit[i] < hi]
        c.create_rectangle(0, 0, x0 - 1, h, fill="#0e1626", outline="")
        c.create_line(x0 - 1, 0, x0 - 1, h, fill="#1d2a40")

        def cell(px: float, y: float, hh: float, color: str, wd: float = 0.0) -> None:
            c.create_rectangle(px, y, px + (wd if wd > 0 else max(1.0, bw - 0.25)),
                               y + max(1.0, hh - 0.5), fill=color, outline="")

        # ---- 顶部：标尺（唯一的一条横轴）+ 放大时的全览条 ----
        ruler_h = 15
        unit_name = "拍号" if wave else "记录号"
        c.create_line(x0, ruler_h, x1, ruler_h, fill="#22304a")
        c.create_text(3, 2, anchor="nw", fill="#61759c", font=("Segoe UI", 7), text=unit_name)
        for frac, anchor in ((0.0, "w"), (0.5, "center"), (1.0, "e")):
            i = lo + int(round(frac * (hi - lo - 1)))
            xx = x0 if anchor == "w" else (x1 if anchor == "e" else x0 + (i - lo + 0.5) * bw)
            c.create_line(xx, ruler_h - 3, xx, ruler_h, fill="#22304a")
            dx = 2 if anchor == "w" else (-2 if anchor == "e" else 0)
            c.create_text(xx + dx, 2, anchor=anchor, fill="#61759c",
                          font=("Consolas", 7), text="#%d" % i)
        top = ruler_h + 2
        if hi - lo < n:
            # 全览条：整窗的密度 + 一个黄框表示"你现在看的是哪一段"（Perfetto 的 overview）
            ov_h = 9
            bins = [0] * max(1, int(x1 - x0))
            for i in range(n):
                b = int(i * len(bins) / n)
                bins[min(len(bins) - 1, b)] += 1
            peak = max(bins) or 1
            for b, cnt in enumerate(bins):
                if cnt:
                    v = int(70 + 180 * (cnt / peak) ** 0.35)
                    c.create_line(x0 + b, top, x0 + b, top + ov_h,
                                  fill="#%02x%02x%02x" % (v // 3, v // 2, v))
            vx0 = x0 + (lo / n) * (x1 - x0)
            vx1 = x0 + (hi / n) * (x1 - x0)
            c.create_rectangle(vx0, top - 1, max(vx0 + 3, vx1), top + ov_h,
                               outline="#ffd479")
            c.create_text(x1 - 2, top + ov_h + 1, anchor="ne", fill="#ffd479",
                          font=("Consolas", 7),
                          text="放大显示 %s#%d–#%d / 共 %d"
                               % ("拍" if wave else "", lo, hi - 1, n))
            top += ov_h + 12

        # ---- 纵向分配：所有泳道共用同一个行距，看起来才是一张表而不是三张图 ----
        legend_h = 13 if h >= 210 else 0
        ev_h = 30 if h >= 200 else 15
        avail = max(60, h - top - legend_h - 8)
        hdr = self._TL_HDR
        wave_rows = len(trace_probe_lanes(wave)) if wave else 0
        n_groups = 5 if wave else 4
        body = max(24, avail - n_groups * hdr - ev_h)

        stat = self._trace_reg_stat()
        freq: dict = {}
        for nd in nodes:
            freq[nd["pc"]] = freq.get(nd["pc"], 0) + 1
        store_groups: dict = {}
        for nd in nodes:
            if nd["mem_we"]:
                store_groups.setdefault(self._store_key(nd), []).append(nd)
        # 行数上限：不是画不下，而是画到每行只剩 3 px 就成了一串虚线点（上一版的毛病）
        counts = {"reg": min(len(stat), 14), "pc": min(len(freq), 10),
                  "mem": min(len(store_groups), 8)}
        # 波形模式下探针泳道**自己占固定高度**（8 行 × 11.5 px），不从"统一行距"里挤；
        # 剩下的高度才均分给寄存器/PC/存储三组。
        wave_h_total = wave_rows * self._TL_WAVE_ROW_H if wave else 0.0
        body_rows = max(24.0, body - wave_h_total)
        while sum(counts.values()) * self._TL_ROW_MIN > body_rows and sum(counts.values()) > 3:
            biggest = max(counts, key=lambda k: counts[k])
            counts[biggest] = max(1, counts[biggest] - 1)
        # 行距封顶 20 px：一行再高只会显得稀疏，多出来的高度宁可留白
        pitch = min(20.0, max(self._TL_ROW_MIN, body_rows / max(1, sum(counts.values()))))
        heights = {name: max(pitch, pitch * counts[name]) for name in counts}
        heights["ev"] = ev_h
        if wave:
            counts["wave"] = wave_rows
            heights["wave"] = wave_rows * self._TL_WAVE_ROW_H
        titles = {"wave": "Core 探针（每拍）", "reg": "寄存器", "pc": "PC",
                  "mem": "写存储地址", "ev": "事件"}
        layout = {"x0": x0, "x1": x1, "bw": bw, "n": n, "lo": lo, "hi": hi,
                  "units": "拍" if wave else "记录", "unit": n_units,
                  "groups": {}, "row_of": {}, "row_h": {}, "top": {}}
        y = top
        for name in (("wave", "reg", "pc", "mem", "ev") if wave
                     else ("reg", "pc", "mem", "ev")):
            layout["groups"][name] = (y + hdr, y + hdr + heights[name])
            c.create_text(3, y, anchor="nw", fill="#8ea3c7",
                          font=("Segoe UI", 7, "bold"), text=titles[name])
            c.create_line(x0, y + hdr - 1, x1, y + hdr - 1, fill="#1b2740")
            y += hdr + heights[name] + 2
            if name == "wave":
                # 探针组下面压一条 3 px 的过渡带：它只是把"波形"和"指令块"隔开一点点，
                # 又不像分隔线那样把两块切断。
                tick_top = y - 3
                layout["tick_top"] = tick_top
                layout["tick_bot"] = tick_top + 3
                y = tick_top + 4

        # ---------- ⓪ Core 探针泳道：每拍一行一位，像真波形那样画高电平 + 阶跃沿 ----------
        if wave:
            wtop = layout["groups"]["wave"][0]
            wave_h = heights["wave"] / max(1, wave_rows)
            lanes = trace_probe_lanes(wave)
            col = {k: self._TL_WAVE_COLORS[k % len(self._TL_WAVE_COLORS)]
                   for k in range(len(lanes))}
            lit = {k: self._lighten(col[k]) for k in range(len(lanes))}

            def edge(u, k, ly):
                """在电平跳变处补一根竖线——真波形是阶跃线，不是一根根色块。"""
                ex = x0 + (u - lo) * bw
                c.create_line(ex, ly + 1.5, ex, ly + wave_h - 1.5,
                              fill=lit[k], width=1)

            for k, lane in enumerate(lanes):
                ly = wtop + k * wave_h
                bits = lane["bits"]
                c.create_line(x0, ly + wave_h - 1, x1, ly + wave_h - 1, fill="#16233a")
                c.create_text(x0 - 6, ly + wave_h * 0.55, anchor="e",
                              fill=col[k] if k == 0 else "#9fb6dd",
                              font=("Consolas", 7), text=lane["name"])
                prev = bits[lo - 1] if lo > 0 else 0
                for u in range(lo, hi):
                    if bits[u]:
                        cell(x0 + (u - lo) * bw, ly + 2.0, wave_h - 4.0, col[k])
                        if not prev:
                            edge(u, k, ly)          # 上升沿
                    elif prev:
                        edge(u, k, ly)              # 下降沿
                    prev = bits[u]
            # 每 32 拍一条很淡的竖网格，方便数拍
            step = 32
            u = ((lo + step - 1) // step) * step
            while u < hi:
                gx = x0 + (u - lo) * bw
                c.create_line(gx, wtop, gx, layout["tick_bot"], fill="#1a2740")
                u += step
            layout["top"]["wave"] = wtop
            layout["row_h"]["wave"] = wave_h

        # ---------- ① 寄存器泳道：行 = 本窗口用到的寄存器，色 = 值从哪来 ----------
        keys = sorted(stat)
        if len(keys) > counts["reg"]:
            keys = sorted(sorted(keys, key=lambda r: -(stat[r][0] + stat[r][1]))[:counts["reg"]])
        reg_keys, reg_h = self._tl_fit(heights["reg"], keys)
        top = layout["groups"]["reg"][0]
        reg_of = {r: i for i, r in enumerate(reg_keys)}
        layout["row_of"]["reg"] = reg_of
        layout["row_h"]["reg"] = reg_h
        layout["top"]["reg"] = top
        for i, r in enumerate(reg_keys):
            ry = top + i * reg_h
            if i % 2:
                c.create_rectangle(x0, ry, x1, ry + reg_h, fill="#0f1828", outline="")
            c.create_text(x0 - 6, ry + reg_h * 0.5, anchor="e", fill=self._reg_color(r),
                          font=("Consolas", 7), text="x%d" % r)
        # 一条记录 = 一段。没有波形时一段就是 1 列；有波形时一条记录占它退休到
        # 下一条退休之间的那几拍（所以多拍指令自然变宽——这是**真实的时间宽度**）。
        show_reads = bw >= 1.0
        reads_px, writes_px = {}, {}
        for i, nd in seg:
            sp = self._cell_span(unit, i, lo, hi, bw)
            if sp is None:
                continue
            px, wd = sp
            if show_reads:
                for r in nd["reads"]:
                    if r in reg_of:
                        reads_px.setdefault((reg_of[r], int(px)), wd)
            if nd["rd_we"] and nd["rd"] in reg_of:
                writes_px[(reg_of[nd["rd"]], int(px))] = (
                    self._SRC_COLORS[self._value_kind(nd)], wd)
        tick_h = min(4.0, reg_h * 0.42)
        for (row, px), wd in reads_px.items():
            cell(px, top + row * reg_h + reg_h - tick_h - 0.5, tick_h, "#4b628c", wd)
        for (row, px), (color, wd) in writes_px.items():
            cell(px, top + row * reg_h + 0.6, reg_h - 1.0, color, wd)

        # ---------- ② PC 泳道：行 = 出现最多的那些 PC，循环就是整齐的条纹 ----------
        pc_keys, pc_h = self._tl_fit(heights["pc"],
                                     sorted(freq, key=lambda p: (-freq[p], p))[:counts["pc"]])
        top = layout["groups"]["pc"][0]
        pc_of = {p: i for i, p in enumerate(pc_keys)}
        layout["row_of"]["pc"] = pc_of
        layout["row_h"]["pc"] = pc_h
        layout["top"]["pc"] = top
        for i, pc in enumerate(pc_keys):
            ry = top + i * pc_h
            if i % 2:
                c.create_rectangle(x0, ry, x1, ry + pc_h, fill="#0f1828", outline="")
            c.create_text(x0 - 6, ry + pc_h * 0.5, anchor="e", fill="#8fa2c0",
                          font=("Consolas", 7), text="%03X" % pc)
        pc_px = {}
        for i, nd in seg:
            row = pc_of.get(nd["pc"])
            if row is None:
                continue
            sp = self._cell_span(unit, i, lo, hi, bw)
            if sp is None:
                continue
            px, wd = sp
            color = "#e6a8ff" if nd["mem_we"] else ("#3ad2a0" if nd["rd_we"] else "#46597a")
            pc_px[(row, int(px))] = (color, wd)
        for (row, px), (color, wd) in pc_px.items():
            cell(px, top + row * pc_h + 0.5, pc_h - 1.0, color, wd)

        # ---------- ③ 写存储地址泳道：行 = 真正被写过的地址 ----------
        groups = store_groups
        top = layout["groups"]["mem"][0]
        mem_keys, mem_h = self._tl_fit(
            heights["mem"],
            sorted(groups, key=lambda k: (-len(groups[k]), str(k)))[:counts["mem"]])
        mem_of = {k: i for i, k in enumerate(mem_keys)}
        layout["row_of"]["mem"] = mem_of
        layout["row_h"]["mem"] = mem_h
        layout["top"]["mem"] = top
        if not mem_keys:
            c.create_text(x0 + 6, top + heights["mem"] * 0.5, anchor="w", fill="#5d719a",
                          font=("Segoe UI", 8), text="本窗口没有任何写存储")
        for i, k in enumerate(mem_keys):
            ry = top + i * mem_h
            if i % 2:
                c.create_rectangle(x0, ry, x1, ry + mem_h, fill="#0f1828", outline="")
            c.create_text(x0 - 6, ry + mem_h * 0.5, anchor="e", fill="#8fa2c0",
                          font=("Consolas", 7), text=self._store_label(k, groups[k][0]))
        mem_px = {}
        for i, nd in seg:
            if not nd["mem_we"]:
                continue
            row = mem_of.get(self._store_key(nd))
            if row is None:
                continue
            sp = self._cell_span(unit, i, lo, hi, bw)
            if sp is None:
                continue
            px, wd = sp
            full = nd.get("store_addr")
            if full is None:
                color = "#40506b"
            elif full == 0x1000222C:
                color = "#ff8fb0"       # 打点写入：字符锚点
            elif 0x10000000 <= full < 0x10004000:
                color = "#39c0ff"       # MMIO（UART/GPIO/性能计数）
            else:
                color = "#3ad2a0"       # 普通数据存储
            mem_px[(row, int(px))] = (color, wd)
        for (row, px), (color, wd) in mem_px.items():
            cell(px, top + row * mem_h + 0.5, mem_h - 1.0, color, wd)

        # ---------- ④ 事件泳道：上=字符打点，下=写存储/MMIO ----------
        ev_top, ev_bot = layout["groups"]["ev"]
        ev_mid = ev_top + heights["ev"] * 0.5
        marks = self.trace_marks
        wide_enough = bw >= 8 or len(marks) <= 12
        for mk in marks:
            mi = mk["index"]
            if mi >= len(unit) or unit[mi] is None or not lo <= unit[mi] < hi:
                continue
            mx = x0 + (unit[mi] - lo + 0.5) * bw
            c.create_line(mx, ev_top + 11, mx, ev_mid - 1, fill="#39c0ff")
            if wide_enough and heights["ev"] >= 24:
                ch = chr(mk["value"]) if 32 <= mk["value"] < 127 else "."
                c.create_text(mx, ev_top, anchor="n", fill="#9fe4ff",
                              font=("Consolas", 7), text=ch)
        for i, nd in seg:
            if not nd["mem_we"]:
                continue
            sp = self._cell_span(unit, i, lo, hi, bw)
            if sp is None:
                continue
            px, wd = sp
            full = nd.get("store_addr")
            if full is None:
                color = "#40506b"
            elif full == 0x1000222C:
                color = "#ff8fb0"
            elif 0x10000000 <= full < 0x10004000:
                color = "#39c0ff"
            else:
                color = "#3ad2a0"
            hh = 1.0 + 4.0 * bin(nd["mem_wstrb"]).count("1")   # 条高 = 写了几个字节
            cell(px, ev_bot - hh, hh, color, wd)

        # ---------- 图例（底部一行）----------
        if legend_h:
            ly = h - legend_h + 1
            lx = x0
            legend = [("写自存储", self._SRC_COLORS["load"]),
                      ("写自ALU", self._SRC_COLORS["alu"]),
                      ("写自立即数", self._SRC_COLORS["imm"]),
                      ("写自PC", self._SRC_COLORS["pc"]),
                      ("读", "#4b628c"),
                      ("数据存储", "#3ad2a0"),
                      ("MMIO", "#39c0ff"),
                      ("打点", "#ff8fb0")]
            if wave:
                legend.insert(0, ("提交脉冲", self._TL_WAVE_ON))
            for name, color in legend:
                if lx > w - 58:
                    break
                c.create_rectangle(lx, ly + 2, lx + 7, ly + 9, fill=color, outline="")
                c.create_text(lx + 10, ly + 5, anchor="w", fill="#7c90b5",
                              font=("Consolas", 7), text=name)
                lx += 12 + 9 * len(name) + 10
        self._tl_layout = layout

    def _draw_trace_cursor(self) -> None:
        """动态图层：贯穿全部泳道的竖光标 + 选中指令在各泳道里的行高亮 + 依赖边。

        高亮用**空心框**而不是填色块：填色会盖住那一行真正真正的数据块。
        """
        c = self.trace_timeline
        c.delete("tl_cur")
        lay = getattr(self, "_tl_layout", None)
        nodes = self.trace_nodes
        if not lay or not nodes:
            return
        x0, x1, bw, n = lay["x0"], lay["x1"], lay["bw"], lay["n"]
        lo = lay.get("lo", 0)
        sel = max(0, min(n - 1, self.trace_sel))
        nd = nodes[sel]
        unit, _nu = self._trace_unit_list()
        sel_unit = unit[sel] if sel < len(unit) and unit[sel] is not None else lo
        h = max(1, c.winfo_height())
        cx = x0 + (sel_unit - lo + 0.5) * bw
        c.create_line(cx, 12, cx, h - 2, fill="#ffd479", dash=(3, 3), tags="tl_cur")
        c.create_text(cx, 0, anchor="n", fill="#ffd479", font=("Consolas", 7),
                      text="▼", tags="tl_cur")
        # 拍号气泡：光标旁边直接写"第几拍"，不用去底部状态行找
        sel_in_wave = sel < len(unit) and unit[sel] is not None
        if lay.get("units") == "拍" and sel_in_wave:
            c.create_text(cx + 4, 1, anchor="nw", fill="#ffd479",
                          font=("Consolas", 7), text="拍%d" % sel_unit, tags="tl_cur")
        # ---- 有波形时，把"这条指令 ↔ 它那一拍的探针脉冲"直接画出来 ----
        # 这是本页最该被看见的一条线：用户不用相信判据日志，眼睛就能对上。
        if lay.get("units") == "拍" and sel_in_wave and "wave" in lay["groups"]:
            sp = self._cell_span(unit, sel, lo, lay.get("hi", n), bw)
            if sp is not None:
                wt, wb = lay["groups"]["wave"]
                c.create_rectangle(sp[0], wt, sp[0] + sp[1], wb,
                                   outline="#ffd479", tags="tl_cur")
            rh = lay["row_h"].get("wave") or 1.0
            wtop = lay["top"].get("wave") or 0
            wave = getattr(self, "trace_wave", None)
            picks = [self._TL_LANE_RETIRE]
            if nd["mem_we"] or nd["mnemonic"] in ("lb", "lh", "lw", "lbu", "lhu"):
                picks += [self._TL_LANE_DR, self._TL_LANE_DV]
            span = self._record_span_cycles(sel) or (sel_unit, sel_unit)
            for lane_k in picks:
                if not wave:
                    continue
                mask = (0x80, 0x10, 0x08)[picks.index(lane_k)]
                # 提交脉冲就在退休那一拍；数据请求/就绪在**这条指令自己的块里**
                # （MEM 在自己的 WB 之前），所以按区间找，不是只看退休那一拍。
                if lane_k == self._TL_LANE_RETIRE:
                    hit = sel_unit if (wave["samples"][sel_unit] & mask) else None
                else:
                    hit = next((u for u in range(span[0], span[1] + 1)
                                if u < len(wave["samples"])
                                and (wave["samples"][u] & mask)), None)
                if hit is None:
                    continue
                hx = x0 + (hit - lo + 0.5) * bw
                ly = wtop + lane_k * rh
                c.create_rectangle(hx - 1.5, ly + 0.5, hx + 1.5, ly + rh - 0.5,
                                   fill="#ffffff", outline="#ffd479", tags="tl_cur")
        reg_of = lay["row_of"].get("reg") or {}
        reg_h = lay["row_h"].get("reg") or 1.0
        reg_top = lay["top"].get("reg") or 0
        hot = set(nd["reads"])
        if nd["rd_we"] and nd["rd"]:
            hot.add(nd["rd"])
        for r in sorted(hot & set(reg_of)):
            ry = reg_top + reg_of[r] * reg_h
            c.create_rectangle(x0, ry, x1, ry + reg_h - 0.5, outline="#ffd479", tags="tl_cur")
        # 依赖边：这条指令读的每个寄存器，从"写下它的那条记录"拉一条横线过来
        for s in nd["srcs"]:
            if s["from"] is None or s["reg"] not in reg_of:
                continue
            src_u = unit[s["from"]] if s["from"] < len(unit) else None
            if src_u is None or not lo <= src_u < lay.get("hi", n):
                continue                     # 写者在当前这一段之外，连线会画到画面外
            ry = reg_top + reg_of[s["reg"]] * reg_h + reg_h * 0.5
            sx = x0 + (src_u - lo + 0.5) * bw
            c.create_line(sx, ry, cx, ry, fill="#ffd479", tags="tl_cur")
            c.create_line(sx, ry - reg_h * 0.35, sx, ry + reg_h * 0.35,
                          fill="#ffd479", tags="tl_cur")
        # PC / 存储泳道：把选中这条指令落到它自己那一行上
        for name, key in (("pc", nd["pc"]),
                          ("mem", self._store_key(nd) if nd["mem_we"] else None)):
            rof = lay["row_of"].get(name) or {}
            if key is None or key not in rof:
                continue
            rh = lay["row_h"].get(name) or 1.0
            tp = lay["top"].get(name) or 0
            ry = tp + rof[key] * rh
            c.create_rectangle(x0, ry, x1, ry + rh - 0.5, outline="#ffd479", tags="tl_cur")

    def _draw_trace_list(self) -> None:
        nodes = self.trace_nodes
        if not nodes:
            return
        half = 60
        lo = max(0, self.trace_sel - half)
        hi = min(len(nodes), self.trace_sel + half + 1)
        self._trace_list_base = lo
        srcs = {s["from"] for s in nodes[self.trace_sel]["srcs"] if s["from"] is not None}
        lines = []
        for i in range(lo, hi):
            nd = nodes[i]
            mark = ">" if i == self.trace_sel else ("+" if i in srcs else " ")
            eff = ""
            if nd["rd_we"]:
                eff = "x%d=0x%08X" % (nd["rd"], nd["rd_data"])
            if nd["mem_we"]:
                addr = nd.get("store_addr")
                where = "0x%08X" % addr if addr is not None else "low12=0x%03X" % nd["mem_addr"]
                eff += ("  " if eff else "") + "[%s]<-0x%02X" % (where, nd["mem_data"] & 0xFF)
            lines.append("%s%4d %03X  %-26s %s" % (mark, i, nd["pc"], nd["asm"], eff))
        self.trace_list.configure(state="normal")
        self.trace_list.delete("1.0", "end")
        self.trace_list.insert("1.0", "\n".join(lines))
        # 当前这条必须一眼看出来：选了哪条 → 右边光标就在哪。
        # 只靠行首一个符号不够，整行铺底色。
        # 标签名**不能叫 "sel"**：Tk 的 Text 把 "sel" 留给"选中区"，由
        # -selectbackground 接管，外面 tag_configure 上去的背景会被静默忽略
        # （2026-10-23 实测：tag_names 里明明有 sel、tag_cget 也读得回 #3c5f96，
        #  放大截图一看整行还是底色——白折腾一轮，才想到是保留名）。
        self.trace_list.tag_configure("cur", background="#3c5f96", foreground="#fff3c4")
        self.trace_list.tag_configure("src", foreground="#ffd479")
        line = self.trace_sel - lo + 1
        self.trace_list.tag_add("cur", "%d.0" % line, "%d.end" % line)
        for i in sorted(srcs):
            if lo <= i < hi:
                self.trace_list.tag_add("src", "%d.0" % (i - lo + 1), "%d.end" % (i - lo + 1))
        self.trace_list.configure(state="disabled")
        # 插入点在 insert 之后会跑到该行行尾（Tk 的规矩：恰好插入在插入点处，
        # 插入点被顶到插入内容之后），接着 Tk 为了"让插入点可见"会把画面**横向**
        # 顶走一小段——表现是行首的 ">" 和高亮列被切掉（2026-10-24 实板界面才发现，
        # 离线截图恰好没触发）。这里手动把插入点收回行首，并强制横向归零。
        self.trace_list.mark_set("insert", "1.0")
        self.trace_list.see("%d.0" % max(1, line - 5))
        self.trace_list.xview_moveto(0)

    def _draw_trace_detail(self) -> None:
        nodes = self.trace_nodes
        if not nodes:
            return
        nd = nodes[self.trace_sel]
        out = []
        out.append("记录 #%d\n" % self.trace_sel)
        out.append("PC   0x%03X\n" % nd["pc"])
        cyc = getattr(self, "_trace_cyc", None)
        sp = self._record_span_cycles(self.trace_sel) if cyc else None
        if sp is not None:
            out.append("波形  第 %d–%d 拍，在第 %d 拍退休（与 8 通道探针同一次采集）\n"
                       % (sp[0], sp[1], sp[1]))
        out.append("指令 %s\n" % nd["asm"])
        out.append("指令字 0x%08X\n" % nd["instr"])
        if nd["rd_we"]:
            out.append("写回 x%d = 0x%08X\n" % (nd["rd"], nd["rd_data"]))
        if nd["mem_we"]:
            addr = nd.get("store_addr")
            where = ("0x%08X" % addr) if addr is not None else ("0x%03X(低12位)" % nd["mem_addr"])
            out.append("写存储 [%s] <- 0x%08X (strb %X)\n" % (where, nd["mem_data"], nd["mem_wstrb"]))
        if nd.get("load_addr") is not None:
            out.append("load 地址 0x%08X（按基址寄存器还原）\n" % nd["load_addr"])
        if nd["marks"]:
            out.append("字符锚点 %s\n" % " ".join(nd["marks"]))
        out.append("\n数据从哪来：\n")
        if not nd["srcs"]:
            out.append("  （不读寄存器）\n")
        for s in nd["srcs"]:
            if s["from"] is None:
                out.append("  x%d ← 窗口之前就已写好\n" % s["reg"])
            else:
                p = nodes[s["from"]]
                out.append("  x%d ← #%d %s (=0x%08X)\n" % (s["reg"], s["from"], p["asm"], p["rd_data"]))
        consumers = [i for i in range(self.trace_sel + 1, len(nodes))
                     if any(s["from"] == self.trace_sel for s in nodes[i]["srcs"])]
        out.append("\n数据去了哪：\n")
        if not consumers:
            out.append("  （窗口内没有读者）\n")
        for i in consumers[:6]:
            regs = [s["reg"] for s in nodes[i]["srcs"] if s["from"] == self.trace_sel]
            out.append("  #%d %s（读 x%s）\n" % (i, nodes[i]["asm"], ",".join(str(r) for r in regs)))
        self.trace_detail.configure(state="normal")
        self.trace_detail.delete("1.0", "end")
        self.trace_detail.insert("1.0", "".join(out))
        self.trace_detail.configure(state="disabled")

    def _on_trace_canvas_click(self, event) -> None:
        nodes = self.trace_nodes
        if not nodes:
            return
        lo, hi, bw, x0 = self._tl_geom()[:4]
        u = max(lo, min(hi - 1, lo + int((event.x - x0) / bw)))
        self._trace_select(self._record_at_unit(u))

    def _on_trace_list_click(self, event) -> None:
        if not self.trace_nodes:
            return
        line = int(self.trace_list.index("@%d,%d" % (event.x, event.y)).split(".")[0])
        self._trace_select(getattr(self, "_trace_list_base", 0) + line - 1)

    def _toggle_trace_play(self) -> None:
        if not self.trace_nodes:
            return
        self._trace_playing = not self._trace_playing
        self.trace_play_button.configure(text="❚❚ 暂停" if self._trace_playing else "▶ 播放")
        if self._trace_playing:
            self._trace_tick()

    def _trace_tick(self) -> None:
        if not self._trace_playing:
            return
        if self.trace_sel >= len(self.trace_nodes) - 1:
            self._trace_playing = False
            self.trace_play_button.configure(text="▶ 播放")
            return
        self._trace_select(self.trace_sel + 1)
        self.after(80, self._trace_tick)

    def _show_wave(self, samples, trigger, info) -> None:
        """把一轮采集结果显示到面板上（UI 线程）。"""
        self.capture_count += 1
        elapsed = max(1e-6, time.monotonic() - self.capture_started)
        mode = str(info.get("mode", ""))
        # 采集源会改变这 8 根线是什么：源与模式不一致时必须写在标题里，
        # 否则面板会拿 uart 模式的名义展示一窗流水线信号（"界面说的和板子做的不一样"）。
        view = str(info.get("view", mode))
        source = int(info.get("source", 0))
        if view == "core" and mode != "core":
            suffix = " · 采集源 Core 内部观测点（不做 %s 协议解码）" % mode
        elif view == "raw":
            suffix = " · 采集源 J8 外部 8 路（core 只提供窗口/触发预设）"
        else:
            suffix = " · 采集源 J8 外部 8 路" if source == 0 and mode == "core" else ""
        if self._live_active:
            # 实时模式每轮都是"第 1 次"（runs 固定为 1），用累计次数才有信息量
            title = "%s 模式 · 第 %d 次采集%s" % (mode, self.capture_count, suffix)
        else:
            title = "%s 模式 · 第 %d 次采集%s" % (mode, int(info.get("run", 0)) + 1, suffix)
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
            stop_after = int(self.stop_after_var.get() or 0)
            if stop_after < 0:
                raise ValueError("「采满 N 次后停」不能为负数（0 = 一直采）")
        except ValueError as exc:
            messagebox.showerror("参数错误", str(exc))
            return

        # 镜像模式要把这句话原样发到板子串口，所以必须是可打印 ASCII：
        # 中文/控制字符发出去以后，波形上标出来的字符和输入框里的对不上。
        mirror_text = self.mirror_text_var.get() or "HELLO,RISC-V"
        try:
            mirror_text.encode("ascii")
        except UnicodeEncodeError:
            messagebox.showerror("参数错误", "镜像模式只支持可打印 ASCII 字符串（例如 HELLO,RISC-V）")
            return

        live = bool(self.live_var.get())
        manual = bool(self.manual_var.get())
        clock_hz = self._clock_hz()
        live_mode = self.live_mode_var.get()
        live_value = dict(MODE_VALUES).get(live_mode, 0xA5)
        knobs = self._collect_knobs() if manual else None
        if manual:
            # 面板参数在主线程先过一次校验。用的是与采集路径**同一个** apply_knobs，
            # 所以不会出现"界面放行、采集时又报另一个错"；错在输入框里就当场弹窗，不发报文。
            from logic_analyzer_serial import apply_knobs

            try:
                apply_knobs(live_mode, self._default_cfg(), knobs)
            except (ValueError, KeyError) as exc:
                messagebox.showerror("面板参数错误", str(exc))
                return
        self._live_active = live
        self.capture_count = 0
        self.capture_started = time.monotonic()

        def work() -> None:
            from logic_analyzer import write_waveform_page
            from logic_analyzer_serial import packet_for, run_captures

            latest: dict[str, dict] = {}

            def on_run(samples, trigger, info) -> None:
                # 采集线程 -> UI 线程只传数据，画图统一在 _poll_events 里做
                self.events.put(("wave", (samples, trigger, info)))
                mode = str(info.get("mode", ""))
                view = str(info.get("view", mode))
                note = "%s 模式 samples=%d trigger=%d%s" % (
                    mode, len(samples), trigger, "" if view == mode else " · 采集源 %s" % view)
                if mode == "mirror":
                    note = ("上位机发送 %s（%d 字符）· ch7 = J8-31/32 回环 · 触发 = 起始位下降沿"
                            % (mirror_text, len(mirror_text)))
                elif view == "core" and mode != "core":
                    note = ("采集源 = Core 内部观测点 · ch0 i_req_valid / ch1 i_req_ready / "
                            "ch2 i_rsp_valid / ch3 d_req_valid / ch4 d_req_ready / "
                            "ch5 event_stall / ch6 event_flush / ch7 trace_valid")
                latest[mode] = {"name": "%s 模式" % mode, "samples": list(samples), "trigger": trigger,
                                "note": note}

            def capture(mode: str, value: int, rounds: int) -> None:
                # 报文本身打进日志：现场那一次到底用了哪组参数，事后能逐字节复现
                packet, cfg = packet_for(mode, value, clock_hz, baud, knobs=knobs)
                print("[%s] 报文 %s · 采集源=%s 时基 sample_div=%d 速率 pattern_div=%d 触发 %s "
                      "mask=0x%02X value=0x%02X pre=%d post=%d 每比特 %d 点"
                      % (mode, packet.hex(),
                         "Core 内部观测点" if cfg.get("source") else "J8 外部 8 路",
                         cfg["sample_div"], cfg["pattern_div"],
                         ("level", "rise", "fall")[cfg["trigger_type"]], cfg["trigger_mask"],
                         cfg["trigger_value"], cfg["pre"], cfg["post"], cfg["bit_samples"]))
                run_captures(port, output / "logic_analyzer" / mode, mode, value, rounds,
                             baud, timeout, on_run=on_run, mirror_text=mirror_text,
                             clock_hz=clock_hz, knobs=knobs)

            if live:
                # 连续采集：同一模式反复采，每轮刷新面板；填了"采满 N 次"就采够即停。
                limit = ("「采满 %d 次」" % stop_after) if stop_after else "点「停止采集」"
                print(f"[连续] 采集 {live_mode} 模式，{limit} 结束")
                rounds = 0
                while not self.stop_requested:
                    capture(live_mode, live_value, 1)
                    rounds += 1
                    if stop_after and rounds >= stop_after:
                        break
            elif manual:
                # 面板参数是"每个模式一套"的，所以只采当前选中的那个模式：
                # 拿 UART 的触发去打 SPI 只会永远等不到触发，现场表现为等满超时。
                capture(live_mode, live_value, runs)
            else:
                for mode, value in MODE_VALUES:
                    capture(mode, value, runs)
                # 五个模式跑完再写一张总览页：采完就能双击用浏览器看
                if latest:
                    order = [m for m, _ in MODE_VALUES if m in latest]
                    preview = output / "logic_analyzer" / "波形预览.html"
                    if write_waveform_page([latest[m] for m in order], preview):
                        print(f"全部模式的浏览器波形页已生成：{preview}")
                    else:
                        print("提示：缺少 waveform_viewer.html 模板，跳过总览页")

        self._start_worker("连续采集" if live else
                           ("按面板参数采集" if manual else "逻辑分析仪全部模式"), work)

    def _poll_events(self) -> None:
        last_wave = None
        last_trace = None
        last_combo = None
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "log":
                    self._append_log(payload)
                elif kind == "wave":
                    # 一轮可能积压多帧，只画最新的一帧，保证界面跟得上
                    last_wave = payload
                elif kind == "trace":
                    # 数据流结果由后台线程算好，**在 UI 线程里**才碰 Tk 控件
                    last_trace = payload
                elif kind == "wavetrace":
                    # 0xAB：波形 + 指令流一次采集（自带对齐结果）
                    last_combo = payload
                elif kind == "tracelog":
                    self._append_trace_log(payload)
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
        if last_combo is not None:
            self._show_wave_capture(last_combo)
        if last_trace is not None:
            self._show_trace(last_trace)
        self._poll_job = self.after(50, self._poll_events)

    def destroy(self) -> None:
        """关窗时先把排队中的轮询回调撤掉。

        否则 Tk 会在窗口销毁后继续执行已排队的 `after`，打印
        `invalid command name "..._poll_events"` ——窗口都没了，回调还在跑。
        """
        job = getattr(self, "_poll_job", None)
        if job is not None:
            try:
                self.after_cancel(job)
            except tk.TclError:
                pass
            self._poll_job = None
        super().destroy()


def main(argv=None) -> int:
    # [2026-10-22] 加两个启动参数，纯粹为了"打开就能看到第 2 页有东西"：
    #   --page 2                启动时直接停在 CPU 数据流那一页
    #   --capture-text "abc"    启动后自动在第 2 页采一枪（板子要已经在跑 tr85）
    # 不带参数时行为与以前完全一样（停在①页、不采集）。
    import argparse

    ap = argparse.ArgumentParser(description="MES50HP 逻辑分析仪 / CPU 数据流")
    ap.add_argument("--page", type=int, default=1, choices=(1, 2), help="启动时停在第几页")
    ap.add_argument("--phase", type=int, default=0, choices=(0, 1),
                    help="启动时第 2 页选的阶段（0=处理过程 1=含轮询）")
    ap.add_argument("--capture-text", default="", help="启动后自动在第 2 页采集这个字符串")
    ap.add_argument("--wave-text", default="",
                    help="启动后自动在第 2 页跑一次 0xAB（波形 + 指令流按拍对齐）")
    args, _unknown = ap.parse_known_args(argv)
    app = ValidationUI()
    if args.page == 2:
        app.notebook.select(1)
    if args.phase:
        app.trace_phase_var.set(TRACE_PHASE_LABELS[min(args.phase, len(TRACE_PHASE_LABELS) - 1)])
    if args.capture_text:
        app.trace_text_var.set(args.capture_text)
        app.after(700, app._run_trace)
    if args.wave_text:
        app.trace_text_var.set(args.wave_text)
        app.after(700, app._run_wave)
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
