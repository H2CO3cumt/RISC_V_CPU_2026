"""write_waveform_page 的单元测试（不需要串口、不需要浏览器）。

要点：注入后的页面必须能被 JSON.parse（否则查看器白屏），
且模板缺失时只能返回 False、不能把采集流程带崩。
"""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from logic_analyzer import write_waveform_page  # noqa: E402


class WriteWaveformPageTest(unittest.TestCase):
    def test_injects_parseable_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "uart_00.html"
            ok = write_waveform_page(
                [{"name": "uart 模式 第1次", "samples": [0xFF, 0xFE, 0x00], "trigger": 1,
                  "note": "mode=uart samples=3 trigger=1"}],
                out,
            )
            self.assertTrue(ok)
            text = out.read_text(encoding="utf-8")
            match = re.search(r"window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);", text)
            self.assertIsNotNone(match, "页面里没有注入数据")
            data = json.loads(match.group(1))
            self.assertEqual(data[0]["samples"], [255, 254, 0])
            self.assertEqual(data[0]["trigger"], 1)
            self.assertIn("function parseVcd", text)      # 模板本体（解析器）还在
            self.assertNotIn("__WAVEFORMS_JSON__", text)  # 占位行已被替换掉

    def test_multiple_datasets(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "波形预览.html"
            datasets = [{"name": m, "samples": [0, 1], "trigger": 0} for m in
                        ("static", "counter", "uart", "spi")]
            self.assertTrue(write_waveform_page(datasets, out))
            text = out.read_text(encoding="utf-8")
            data = json.loads(re.search(r"window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);", text).group(1))
            self.assertEqual([d["name"] for d in data], ["static", "counter", "uart", "spi"])

    def test_samples_are_masked_to_one_byte(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "x.html"
            write_waveform_page([{"name": "x", "samples": [0x1FF, -1], "trigger": 0}], out)
            data = json.loads(re.search(r"window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);",
                                        out.read_text(encoding="utf-8")).group(1))
            self.assertEqual(data[0]["samples"], [0xFF, 0xFF])

    def test_timebase_fields_are_injected(self):
        """时基要能让页面把横轴标成真实时间；不传时**不能凭空多出这两个字段**。"""
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "uart_tb.html"
            ok = write_waveform_page(
                [{"name": "uart", "samples": [0xFF, 0x00], "trigger": 0,
                  "sample_ns": 27 * 1e9 / 85e6, "sample_hz": 85e6 / 27}], out)
            self.assertTrue(ok)
            data = json.loads(re.search(r"window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);",
                                        out.read_text(encoding="utf-8")).group(1))
            self.assertAlmostEqual(data[0]["sample_ns"], 317.6470588235294, places=6)
            self.assertAlmostEqual(data[0]["sample_hz"], 3148148.148148148, places=3)

            out2 = Path(tmp) / "no_tb.html"
            write_waveform_page([{"samples": [1, 0], "trigger": None}], out2)
            data2 = json.loads(re.search(r"window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);",
                                         out2.read_text(encoding="utf-8")).group(1))
            self.assertNotIn("sample_ns", data2[0])
            self.assertNotIn("sample_hz", data2[0])

    def test_decode_spec_and_tag_names_are_injected(self):
        """标注说明要原样透传；不带 decode 的数据集不许凭空多出标注（会画出假帧）。"""
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "uart_dec.html"
            ok = write_waveform_page(
                [{"name": "uart", "samples": [0xFF, 0x00], "trigger": 0,
                  "decode": {"protocol": "uart", "channel": 0, "bit_samples": 16, "which": 1},
                  "tag_names": {"0": "UART_TX"}}], out)
            self.assertTrue(ok)
            data = json.loads(re.search(r"window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);",
                                        out.read_text(encoding="utf-8")).group(1))
            self.assertEqual(data[0]["decode"]["protocol"], "uart")
            self.assertEqual(data[0]["decode"]["which"], 1)
            self.assertEqual(data[0]["tag_names"]["0"], "UART_TX")

            out2 = Path(tmp) / "plain.html"
            write_waveform_page([{"samples": [1, 0], "trigger": None}], out2)
            data2 = json.loads(re.search(r"window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);",
                                         out2.read_text(encoding="utf-8")).group(1))
            self.assertNotIn("decode", data2[0])
            self.assertNotIn("tag_names", data2[0])

    def test_missing_template_returns_false_instead_of_raising(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "x.html"
            self.assertFalse(write_waveform_page([{"samples": [1]}], out,
                                                template=Path(tmp) / "missing.html"))
            self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
