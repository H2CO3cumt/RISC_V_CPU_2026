"""实时波形显示面板：tkinter Canvas，仅用标准库。

为什么不用 matplotlib：交付包对第三方依赖只保证 pyserial 一个；
tkinter + Canvas 是 Python 标准库自带，评委机/本机都不需要额外安装。
面板只负责"把样本画出来"，采集与协议仍在 logic_analyzer_serial.py 里。

画法：每个通道一条折线（采样点 -> x，电平 -> y），触发点画红色虚线；
窗口尺寸变化时自动重画；样本数 ≤ 256（Raw 深度上限），重画开销可忽略。
"""
from __future__ import annotations

import tkinter as tk
from typing import Iterable, List, Sequence, Tuple

PALETTE = ("#39c0ff", "#2ecc71", "#f1c40f", "#e67e22",
           "#9b59b6", "#5dade2", "#1abc9c", "#e84393")


def channel_levels(samples: Sequence[int], channel: int) -> List[int]:
    """取出某个通道的电平序列（0/1）。"""
    mask = 1 << channel
    return [1 if (s & mask) else 0 for s in samples]


def iter_segments(levels: Sequence[int]) -> Iterable[Tuple[int, int, int]]:
    """把电平序列压成 (起始下标, 结束下标, 电平) 段。

    结束下标取"变化点"，即该段覆盖 [start, end)；这样折线在段边界正好跳变，
    不会出现斜线（不压缩直接逐点连线在样本多时同样正确，但压缩后点数更少）。
    """
    if not levels:
        return
    start = 0
    cur = levels[0]
    for i in range(1, len(levels)):
        if levels[i] != cur:
            yield (start, i, cur)
            start = i
            cur = levels[i]
    yield (start, len(levels), cur)


def value_at(levels: Sequence[int], index: int) -> int:
    if not levels:
        return 0
    if index < 0:
        return levels[0]
    if index >= len(levels):
        return levels[-1]
    return levels[index]


def sample_to_x(index: float, count: int, x0: float, x1: float) -> float:
    """把采样点下标映射到画布 x 坐标；只有一个采样点时居中。"""
    if count <= 1:
        return (x0 + x1) / 2.0
    return x0 + (x1 - x0) * (index / float(count - 1))


class WaveformPanel(tk.Frame):
    """八通道波形显示：show() 换数据，clear() 清屏。"""

    def __init__(self, master, channels: int = 8, height: int = 240, **kwargs):
        super().__init__(master, **kwargs)
        self.channels = channels
        self.canvas = tk.Canvas(self, height=height, background="#0e1420",
                                highlightthickness=0, bd=0)
        self.canvas.pack(fill="both", expand=True)
        self.status = tk.Label(self, anchor="w", background="#151d2c", foreground="#93a4c4",
                               font=("Consolas", 9), padx=8, pady=3)
        self.status.pack(fill="x")
        self._samples: List[int] = []
        self._trigger: int | None = None
        self._title = ""
        self._redraw_job = None
        self.canvas.bind("<Configure>", self._on_resize)

    # ------------------------------------------------------------------ API
    def show(self, samples: Sequence[int], trigger: int | None = None, title: str = "",
             note: str = "") -> None:
        """显示一次采集结果（UI 线程调用）。"""
        self._samples = list(samples)
        self._trigger = trigger
        self._title = title
        self._note = note
        self._redraw()

    def clear(self, message: str = "等待采集…") -> None:
        self._samples = []
        self._trigger = None
        self._title = ""
        self._note = message
        self._redraw()

    # ------------------------------------------------------------- 内部实现
    def _on_resize(self, _event=None) -> None:
        # 窗口拖动时事件很密集，合并到 idle 再画一次
        if self._redraw_job is not None:
            self.after_cancel(self._redraw_job)
        self._redraw_job = self.after(60, self._redraw)

    def _redraw(self) -> None:
        self._redraw_job = None
        cv = self.canvas
        cv.delete("all")
        width = max(int(cv.winfo_width()), 200)
        height = max(int(cv.winfo_height()), 120)
        channels = self.channels
        pad_left, pad_right, pad_top, pad_bottom = 62, 14, 14, 22
        rows_h = (height - pad_top - pad_bottom) / float(channels)
        x0, x1 = pad_left, width - pad_right

        # 通道名与背景
        for ch in range(channels):
            top = pad_top + ch * rows_h
            cv.create_rectangle(0, top, width, top + rows_h,
                                fill="#131b28" if ch % 2 else "#0e1420", outline="")
            cv.create_text(10, top + rows_h / 2, anchor="w", fill="#93a4c4",
                           font=("Consolas", 9), text="ch%d" % ch)
            cv.create_text(10, top + rows_h / 2 + 12, anchor="w", fill="#5f7396",
                           font=("Consolas", 8), text="J8 %d/%d" % (ch * 4 + 3, ch * 4 + 4))

        if not self._samples:
            cv.create_text(width / 2, height / 2, fill="#5f7396",
                           font=("Microsoft YaHei", 11), text=self._note or "等待采集…")
            self.status.configure(text=self._title)
            return

        count = len(self._samples)
        # 时间刻度（采样点下标）
        step = max(1, count // 10)
        for i in range(0, count, step):
            x = sample_to_x(i, count, x0, x1)
            cv.create_line(x, pad_top, x, height - pad_bottom, fill="#1e2a3d")
            cv.create_text(x, height - pad_bottom + 10, fill="#7e91b3",
                           font=("Consolas", 8), text=str(i))

        # 波形
        for ch in range(channels):
            levels = channel_levels(self._samples, ch)
            top = pad_top + ch * rows_h
            y_hi = top + rows_h * 0.22
            y_lo = top + rows_h * 0.82
            points: List[float] = []
            for start, end, level in iter_segments(levels):
                y = y_hi if level else y_lo
                points.append(sample_to_x(start, count, x0, x1))
                points.append(y)
                # 段末尾停在"变化点"位置，再补一段水平线终点
                points.append(sample_to_x(end - 1, count, x0, x1))
                points.append(y)
                nxt = value_at(levels, end)
                if end < count and nxt != level:
                    points.append(sample_to_x(end - 1, count, x0, x1))
                    points.append(y_hi if nxt else y_lo)
            if len(points) >= 4:
                cv.create_line(*points, fill=PALETTE[ch % len(PALETTE)], width=2,
                               joinstyle="round", capstyle="round")

        # 触发点
        if self._trigger is not None and 0 <= self._trigger < count:
            tx = sample_to_x(self._trigger, count, x0, x1)
            cv.create_line(tx, pad_top, tx, height - pad_bottom,
                           fill="#ff4d6d", dash=(6, 4), width=2)
            cv.create_text(min(tx + 6, x1 - 5), pad_top + 8, anchor="w", fill="#ff8fa3",
                           font=("Consolas", 9), text="触发 @%d" % self._trigger)

        head = self._title or ""
        tail = "样本 %d 点" % count
        if self._trigger is not None:
            tail += " · 触发点 %s" % self._trigger
        if getattr(self, "_note", ""):
            tail += " · " + self._note
        self.status.configure(text=(head + "  |  " if head else "") + tail)
