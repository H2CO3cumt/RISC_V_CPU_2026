import tempfile
import unittest
from pathlib import Path
from logic_analyzer import decode_spi, decode_uart, parse_raw, write_vcd

class LogicAnalyzerTests(unittest.TestCase):
    def test_parse_and_vcd(self):
        samples, trigger = parse_raw(b"LA RAW count=00000004 trigger=00000002\r\n00 01 03 07\n")
        self.assertEqual(samples, [0, 1, 3, 7]); self.assertEqual(trigger, 2)
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.vcd"; write_vcd(samples, p, 3, trigger)
            text = p.read_text(); self.assertIn("ch0", text); self.assertIn("trigger_index=2", text)

    def test_uart(self):
        bits = [1] * 3 + [0] + [1, 0, 0, 0, 0, 0, 1, 0] + [1] + [1] * 3
        samples = []
        for bit in bits: samples.extend([bit] * 2)
        value, errors = decode_uart(samples, 0, 2)
        self.assertEqual(value, b"A"); self.assertEqual(errors, 0)

    def test_uart_samples_at_bit_centres_with_phase_offset(self):
        # 0xA5 with 16 samples/bit and a non-aligned leading idle interval.
        # Boundary sampling would mistake the final data bit for the stop bit.
        bits = [0] + [1, 0, 1, 0, 0, 1, 0, 1] + [1]
        samples = [1] * 7
        for bit in bits: samples.extend([bit] * 16)
        samples.extend([1] * 16)
        value, errors = decode_uart(samples, 0, 16)
        self.assertEqual(value, b"\xA5"); self.assertEqual(errors, 0)

    def test_spi(self):
        samples = [4]  # CS high
        value = 0xA5
        for bit in range(7, -1, -1):
            samples.extend([0 | (0 if bit == 7 else 0), 1 | ((value >> bit) & 1) * 2, 0])
        self.assertEqual(decode_spi(samples, 0, 1, 2), b"\xA5")

if __name__ == "__main__": unittest.main()
