"""waveform_panel 纯逻辑的单元测试（不需要串口、不需要显卡）。

要测的是"画得对不对"里可以脱离屏幕判定的那部分：
  - 通道位取值（bit0..bit7 -> ch0..ch7）
  - 采样流压缩成段（(start, end, level)）的边界
  - 采样点 -> x 坐标的映射与单点/空数据退化
真正的绘制由 run_logic_analyzer_python.ps1 之外的实机 UI 测试覆盖。
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from waveform_panel import channel_levels, iter_segments, sample_to_x, value_at  # noqa: E402


class ChannelLevelsTest(unittest.TestCase):
    def test_each_channel_reads_its_own_bit(self):
        samples = [0b00000001, 0b00000010, 0b10000000, 0b11111111]
        self.assertEqual(channel_levels(samples, 0), [1, 0, 0, 1])
        self.assertEqual(channel_levels(samples, 1), [0, 1, 0, 1])
        self.assertEqual(channel_levels(samples, 7), [0, 0, 1, 1])

    def test_static_capture_is_flat(self):
        self.assertEqual(channel_levels([0xA5] * 5, 0), [1, 1, 1, 1, 1])
        self.assertEqual(channel_levels([0xA5] * 5, 1), [0, 0, 0, 0, 0])


class IterSegmentsTest(unittest.TestCase):
    def test_flat_level_is_one_segment(self):
        self.assertEqual(list(iter_segments([1, 1, 1])), [(0, 3, 1)])

    def test_uart_like_frame_boundaries(self):
        # 空闲高 -> 起始位低 -> 两位数据 -> 空闲高
        levels = [1, 1, 0, 0, 1, 0, 1, 1, 1]
        segs = list(iter_segments(levels))
        self.assertEqual(segs, [(0, 2, 1), (2, 4, 0), (4, 5, 1), (5, 6, 0), (6, 9, 1)])
        # 段的覆盖必须连续且完整，不允许丢点或重叠
        self.assertEqual(segs[0][0], 0)
        self.assertEqual(segs[-1][1], len(levels))
        for a, b in zip(segs, segs[1:]):
            self.assertEqual(a[1], b[0])

    def test_single_sample_and_empty(self):
        self.assertEqual(list(iter_segments([0])), [(0, 1, 0)])
        self.assertEqual(list(iter_segments([])), [])

    def test_counter_waveform_alternates(self):
        samples = [0x00, 0x01, 0x01, 0x01, 0x01]
        self.assertEqual(list(iter_segments(channel_levels(samples, 0))),
                         [(0, 1, 0), (1, 5, 1)])


class ValueAtTest(unittest.TestCase):
    def test_clamps_out_of_range(self):
        self.assertEqual(value_at([0, 1, 0], -5), 0)
        self.assertEqual(value_at([0, 1, 0], 99), 0)
        self.assertEqual(value_at([], 3), 0)


class SampleToXTest(unittest.TestCase):
    def test_endpoints_and_middle(self):
        self.assertAlmostEqual(sample_to_x(0, 5, 10.0, 110.0), 10.0)
        self.assertAlmostEqual(sample_to_x(4, 5, 10.0, 110.0), 110.0)
        self.assertAlmostEqual(sample_to_x(2, 5, 10.0, 110.0), 60.0)

    def test_single_sample_centres(self):
        self.assertAlmostEqual(sample_to_x(0, 1, 10.0, 110.0), 60.0)

    def test_x_is_monotonic(self):
        xs = [sample_to_x(i, 240, 62.0, 1000.0) for i in range(240)]
        self.assertEqual(xs, sorted(xs))
        self.assertTrue(all(0 < b - a for a, b in zip(xs, xs[1:])))


if __name__ == "__main__":
    unittest.main(verbosity=2)
