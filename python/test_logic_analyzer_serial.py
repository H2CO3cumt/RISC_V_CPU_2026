import unittest
from logic_analyzer_serial import build_packet, default_config, read_until, synchronize_ready


class FakeSerial:
    def __init__(self, chunks): self.chunks = list(chunks)
    def read(self, _size): return self.chunks.pop(0) if self.chunks else b""


class SerialProtocolTests(unittest.TestCase):
    def test_packet_checksum_and_layout(self):
        packet = build_packet(**default_config("uart", 0xA5))
        self.assertEqual(len(packet), 13)
        self.assertEqual(packet[0:3], bytes((0xA5, 2, 0xA5)))
        checksum = 0
        for value in packet[:-1]:
            checksum ^= value
        self.assertEqual(packet[-1], checksum)

    def test_spi_defaults_fit_capture_depth(self):
        cfg = default_config("spi", 0x3C)
        self.assertLessEqual(cfg["pre"] + cfg["post"] + 2, 256)
        self.assertEqual(cfg["trigger_type"], 1)

    def test_out_of_range_rejected(self):
        cfg = default_config("static", 1); cfg["post"] = 256
        with self.assertRaises(ValueError): build_packet(**cfg)

    def test_ready_synchronization_and_response_boundary(self):
        self.assertIn(b"LA_READY", synchronize_ready(FakeSerial([b"LA_", b"READY\r\n"]), 0.2))
        response = read_until(FakeSerial([b"LA_DONE\r\n", b"LA_READY\r\n"]), b"LA_READY", 0.2)
        self.assertIn(b"LA_DONE", response)


if __name__ == "__main__":
    unittest.main()
