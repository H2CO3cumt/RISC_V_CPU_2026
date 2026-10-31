import unittest
from pathlib import Path

from logic_analyzer_serial import (CORE_PROBE_NAMES, SOURCE_CHOICES, SOURCE_CORE,
                                   SOURCE_J8, VIEW_CORE, VIEW_RAW, apply_knobs, build_packet,
                                   capture_view, default_config, mirror_required_samples,
                                   packet_for, read_until, run_captures, synchronize_ready)


def packet_for_cfg(cfg: dict) -> bytes:
    """按一份已经是最终形态的 cfg 打报文（含 source 的 0xA8 分支）。"""
    return build_packet(cfg["mode"], cfg["data"], cfg["pattern_div"], cfg["sample_div"],
                        cfg["trigger_type"], cfg["trigger_mask"], cfg["trigger_value"],
                        cfg["pre"], cfg["post"], cfg["prefix"], cfg["post16"],
                        cfg.get("source"))


class FakeSerial:
    def __init__(self, chunks): self.chunks = list(chunks)
    def read(self, _size): return self.chunks.pop(0) if self.chunks else b""


class SerialProtocolTests(unittest.TestCase):
    def test_packet_checksum_and_layout(self):
        packet, _ = packet_for("uart", 0xA5)
        self.assertEqual(len(packet), 13)
        self.assertEqual(packet[0:3], bytes((0xA5, 2, 0xA5)))
        checksum = 0
        for value in packet[:-1]:
            checksum ^= value
        self.assertEqual(packet[-1], checksum)

    def test_spi_defaults_fit_capture_depth(self):
        _, cfg = packet_for("spi", 0x3C)
        self.assertLessEqual(cfg["pre"] + cfg["post"] + 2, 256)
        # [2026-10-10 改] 触发从 SCLK 上升沿（type=1/mask=ch0）改成 CS 下降沿（type=2/mask=ch2）。
        # 原因：pattern_gen 自由运行，按 SCLK 上升沿触发会让窗口落在字节的任意一个 bit 上，
        # 落在 b6 时只剩 7 个 SCLK 脉冲、CS 提前拉高，整个字节被解码器（正确地）丢弃。
        self.assertEqual(cfg["trigger_type"], 2)
        self.assertEqual(cfg["trigger_mask"], 0x04)

    def test_mirror_window_fits_the_whole_sentence(self):
        # 镜像模式的窗口必须真的装得下一整句，否则波形页会把报文截断（这正是"展示效果差"的老问题）。
        _, cfg = packet_for("mirror", 0, clock_hz=85_000_000, baud=115200)
        self.assertEqual(cfg["pre"], 0)                      # 窗口从起始位开始
        self.assertEqual(cfg["channel"], 7)                  # ch7 = J8-31/32
        self.assertEqual(cfg["bit_samples"], 8)
        self.assertGreaterEqual(cfg["post"] + 1, 12 * 10 * cfg["bit_samples"])
        # 50 MHz 备用位流要算出自己的采样分频，不能照抄 85 MHz 的值
        _, cfg50 = packet_for("mirror", 0, clock_hz=50_000_000, baud=115200)
        self.assertNotEqual(cfg50["sample_div"], cfg["sample_div"])
        self.assertEqual(cfg50["bit_samples"], cfg["bit_samples"])

    def test_out_of_range_rejected(self):
        cfg = default_config("static", 1); cfg["post"] = 256
        with self.assertRaises(ValueError):
            build_packet(cfg["mode"], cfg["data"], cfg["pattern_div"], cfg["sample_div"],
                         cfg["trigger_type"], cfg["trigger_mask"], cfg["trigger_value"],
                         cfg["pre"], cfg["post"], cfg["prefix"], cfg["post16"])

    def test_ready_synchronization_and_response_boundary(self):
        self.assertIn(b"LA_READY", synchronize_ready(FakeSerial([b"LA_", b"READY\r\n"]), 0.2))
        response = read_until(FakeSerial([b"LA_DONE\r\n", b"LA_READY\r\n"]), b"LA_READY", 0.2)
        self.assertIn(b"LA_DONE", response)


class CoreSourceTests(unittest.TestCase):
    """双源可选（2026-10-13）：0xA8 命令把采集源显式写进报文。

    三条必须守住的东西：
      1. 不指定 source 时，报文与历史 13 字节逐字节相同（老证据不受影响）；
      2. 指定 source 时是 14 字节、[12]=源、[13]=XOR([0..12])；
      3. core 模式的默认配置本身自洽（全速采样 + ch6 冲刷触发 + 窗口不越界）。
    """

    def test_legacy_packet_is_byte_identical_without_source(self):
        legacy, _ = packet_for("uart", 0xA5)
        explicit, _ = packet_for("uart", 0xA5)
        self.assertEqual(legacy, explicit)
        self.assertEqual(len(legacy), 13)

    def test_source_packet_layout_and_checksum(self):
        packet = build_packet(2, 0xA5, 433, 26, 2, 0x01, 0, 64, 191,
                              source=SOURCE_CORE)
        self.assertEqual(len(packet), 16)
        self.assertEqual(packet[0], 0xA8)
        self.assertEqual(packet[14], SOURCE_CORE)
        checksum = 0
        for value in packet[:-1]:
            checksum ^= value
        self.assertEqual(packet[15], checksum)
        # [1]～[9] 必须与同参数的 0xA5 报文逐字节相同：改的只有包头、pre/post 宽度与源字节。
        ref = build_packet(2, 0xA5, 433, 26, 2, 0x01, 0, 64, 191)
        self.assertEqual(packet[1:10], ref[1:10])
        self.assertEqual(packet[10:12], bytes((64, 0)))    # pre 16 位小端
        self.assertEqual(packet[12:14], bytes((191, 0)))   # post 16 位小端

    def test_source_packet_carries_16bit_window(self):
        # core 模式要 2048 点窗口，1 字节装不下——这正是 0xA8 存在的原因。
        packet, cfg = packet_for("core", 0)
        self.assertEqual(cfg["pre"] + cfg["post"] + 1, 2048)
        self.assertEqual(packet[12] | (packet[13] << 8), cfg["post"])
        self.assertGreater(cfg["post"], 0xFF)

    def test_source_rejects_unknown_value(self):
        with self.assertRaises(ValueError):
            build_packet(2, 0, 3, 0, 0, 1, 0, 4, 4, source=2)

    def test_core_mode_defaults(self):
        packet, cfg = packet_for("core", 0, clock_hz=85_000_000)
        self.assertEqual(cfg["source"], SOURCE_CORE)
        self.assertEqual(cfg["sample_div"], 0)        # 全速采样：每拍一个样点
        self.assertEqual(cfg["trigger_mask"], 1 << 6)  # ch6 = event_flush
        self.assertEqual(cfg["trigger_type"], 1)       # 上升沿
        self.assertLessEqual(cfg["pre"] + cfg["post"] + 1, 2048)  # 窗口 = pre + 触发 + post
        self.assertEqual(packet[0], 0xA8)

    def test_core_probe_names_cover_all_eight_channels(self):
        self.assertEqual(sorted(CORE_PROBE_NAMES), [str(i) for i in range(8)])
        self.assertEqual(CORE_PROBE_NAMES["6"], "event_flush")
        self.assertEqual(CORE_PROBE_NAMES["7"], "trace_valid")


    def test_source_knob_switches_to_the_0xa8_command(self):
        """采集源作为旋钮：普通模式不动它就是 0xA5，选 Core 才变成 0xA8。"""
        base = default_config("uart", 0xA5)
        # 不碰 source：cfg 里不该多出这个键，报文与历史逐字节一致
        plain = apply_knobs("uart", base, {"sample_div": 26})
        self.assertNotIn("source", plain)
        self.assertEqual(len(packet_for_cfg(plain)), 13)
        # 选 Core：多出 source=1，报文变 16 字节 0xA8，且 pre/post 可以到 16 位
        core = apply_knobs("uart", base, {"source": SOURCE_CORE, "post": 1983})
        self.assertEqual(core["source"], SOURCE_CORE)
        packet = packet_for_cfg(core)
        self.assertEqual(len(packet), 16)
        self.assertEqual(packet[0], 0xA8)
        self.assertEqual(packet[14], SOURCE_CORE)
        self.assertEqual(packet[12] | (packet[13] << 8), 1983)
        # 显式选回 J8：source 键被清掉，又回到 13 字节
        back = apply_knobs("uart", base, {"source": SOURCE_J8})
        self.assertNotIn("source", back)

    def test_source_wide_window_only_with_core_source(self):
        """窗口上限按**将要发出的那条命令**判：0xA5 各 1 字节，0xA8 各 2 字节。"""
        base = default_config("uart", 0xA5)
        with self.assertRaises(ValueError):
            apply_knobs("uart", base, {"post": 1000})
        ok = apply_knobs("uart", base, {"source": SOURCE_CORE, "post": 1000})
        self.assertEqual(ok["post"], 1000)
        with self.assertRaises(ValueError):
            apply_knobs("uart", base, {"source": SOURCE_CORE, "post": 0x10000})

    def test_source_out_of_range_rejected(self):
        base = default_config("uart", 0xA5)
        with self.assertRaises(ValueError):
            apply_knobs("uart", base, {"source": 2})

    def test_mirror_rejects_source(self):
        """镜像模式抓的是上位机串口线，0xA7 的 13 字节报文装不下源字节。"""
        base = default_config("mirror", 0)
        with self.assertRaises(ValueError):
            apply_knobs("mirror", base, {"source": SOURCE_CORE})

    def test_source_choices_cover_both_sources(self):
        self.assertEqual(sorted(code for _, code in SOURCE_CHOICES), [SOURCE_J8, SOURCE_CORE])


class KnobTests(unittest.TestCase):
    """仪器面板旋钮（2026-10-10）：推导、校验，以及与默认路径的等价性。

    背景：时基、触发方式/通道/电平、pre/post、激励速率与数据一直写死在
    mode_config/default_config 里，界面上没有旋钮；而固件（13 字节报文 →
    LA_DIV/LA_TR_*/LA_PRE/LA_POST）早就支持它们。这一组测试守住两件事：
    不勾面板时**逐字节不变**，勾了面板时**按固件同一个公式**重算。
    """

    def test_no_knobs_is_identical_to_defaults(self):
        # 板级 100/100 验收与历史证据走的就是这条路，一个字节都不许变。
        for mode in ("static", "counter", "uart", "spi", "mirror"):
            base_packet, base_cfg = packet_for(mode, 0xA5)
            for knobs in (None, {}):
                packet, cfg = packet_for(mode, 0xA5, knobs=knobs)
                self.assertEqual(packet, base_packet, msg=f"{mode} {knobs}")
                self.assertEqual(cfg, base_cfg, msg=f"{mode} {knobs}")

    def test_knobs_land_in_the_packet(self):
        packet, cfg = packet_for("uart", 0xA5, knobs={
            "sample_div": "52", "pattern_div": "433", "pre": "8", "post": "8",
            "trigger_type": "1", "trigger_mask": "0x04", "trigger_value": "4"})
        self.assertEqual(len(packet), 13)
        self.assertEqual(packet[5] | (packet[6] << 8), 52)   # sd_lo | sd_hi
        self.assertEqual(packet[3] | (packet[4] << 8), 433)  # pd_lo | pd_hi
        self.assertEqual(packet[7], 1)                       # 触发方式：上升沿
        self.assertEqual(packet[8], 0x04)                    # 触发掩码
        self.assertEqual(packet[9], 0x04)                    # 触发电平值（与掩码同位）
        self.assertEqual((packet[10], packet[11]), (8, 8))   # pre / post
        self.assertEqual(cfg["sample_div"], 52)

    def test_bit_samples_follow_the_firmware_formula(self):
        # 固件用整数除法自己算位点数（logic_analyzer.c 第 177 行）：
        # `(pattern_div+1)/(sample_div+1)`。上位机必须用同一个式子，
        # 否则页面标注的字节和判据用的字节不是同一个（§6.6 同源纪律）。
        for pattern_div, sample_div, expect in ((433, 26, 16), (433, 52, 8), (3, 0, 4)):
            _, cfg = packet_for("uart", 0xA5, knobs={"pattern_div": pattern_div,
                                                     "sample_div": sample_div})
            self.assertEqual(cfg["bit_samples"], expect,
                             msg=f"pd={pattern_div} sd={sample_div}")

    def test_out_of_range_and_unknown_knobs_are_rejected(self):
        # 越界一律报错，绝不静默截断成另一个配置（build_packet 的既有纪律）。
        cfg = default_config("uart", 0xA5)
        for knobs in ({"post": 256}, {"pre": 256}, {"sample_div": 0x10000},
                      {"pattern_div": 0x10000}, {"trigger_type": 3},
                      {"trigger_mask": 256}, {"trigger_value": 256}, {"data": 256},
                      {"channel_mask": 255},          # 固件写死 0xFF，报文里没有这个字节
                      {"sample_div": "abc"}, {"sample_div": ""}, {"pre": 2048}):
            with self.assertRaises(ValueError, msg=repr(knobs)):
                apply_knobs("uart", cfg, knobs)

    def test_mirror_only_accepts_post(self):
        cfg = default_config("mirror", 0)
        self.assertEqual(apply_knobs("mirror", cfg, {"post": 2047})["post"], 2047)
        for name in ("pre", "data", "sample_div", "pattern_div", "trigger_type",
                     "trigger_mask", "trigger_value"):
            with self.assertRaises(ValueError, msg=name):
                apply_knobs("mirror", cfg, {name: 1})

    def test_slow_timebase_is_rejected_for_uart(self):
        # 时基比激励速率还慢 ⇒ 每比特不足 1 个采样点，UART 解码不成立
        cfg = default_config("uart", 0xA5)
        with self.assertRaises(ValueError):
            apply_knobs("uart", cfg, {"pattern_div": 3, "sample_div": 500})

    def test_knob_number_formats(self):
        # 面板输入框是自由文本：十进制、前导零和 0x 十六进制都要认，
        # 其余一律报错（不静默取整、不悄悄换一个值）
        cfg = default_config("uart", 0xA5)
        self.assertEqual(apply_knobs("uart", cfg, {"pre": "010"})["pre"], 10)
        self.assertEqual(apply_knobs("uart", cfg, {"pre": "0x1f"})["pre"], 31)
        self.assertEqual(apply_knobs("uart", cfg, {"pre": " 8 "})["pre"], 8)
        for bad in ("9.5", "8ns", "--1", "0x"):
            with self.assertRaises(ValueError, msg=bad):
                apply_knobs("uart", cfg, {"pre": bad})

    def test_mirror_window_minimum_uses_one_formula(self):
        # 界面的事前校验与 run_captures 的事后判据必须是同一个数
        self.assertEqual(mirror_required_samples("HELLO,RISC-V", 8), 12 * 10 * 8)

    def test_caller_config_is_not_mutated(self):
        # apply_knobs 返回新字典：调用方的 cfg 必须是只读的，
        # 否则"面板改一次"会污染后续所有模式（它们共用同一份推导入口）。
        cfg = default_config("uart", 0xA5)
        before = dict(cfg)
        apply_knobs("uart", cfg, {"sample_div": "52", "pre": "8"})
        self.assertEqual(cfg, before)

    def test_mirror_window_checked_before_opening_the_port(self):
        # 窗口装不下整句要在**打开串口之前**报错：现场不该先等一轮采集再失败
        with self.assertRaises(ValueError):
            run_captures("COM_NOT_A_REAL_PORT", Path("results/_unused_by_test"), "mirror",
                         0, 1, 115200, 1.0, mirror_text="HELLO,RISC-V", knobs={"post": 10})


class CaptureViewTests(unittest.TestCase):
    """采集源 -> 这一窗数据该怎么解释（2026-10-14）。

    为什么这组用例值得存在：8 根线的物理含义由**采集源**决定，而不是由"上次选的模式"
    决定。板级实测（tmp/ui_board_check.py）暴露过两个组合的真问题：
      - uart 模式 + Core 源：波形是流水线内部信号，主机却按 UART 帧解码并报 FAIL；
      - core 预设 + J8 源：页面上仍挂着 ch7 = trace_valid，把一根普通外部线说成 CPU 提交。
    这两种都是"采集是对的、解释是错的"的假失败，只有把 view 从 mode 里拆出来才修得掉。
    """

    def test_source_decides_the_view(self):
        # 源 = Core 时，无论模式叫什么，这一窗都是流水线观测点
        for mode in ("static", "counter", "uart", "spi", "core"):
            self.assertEqual(capture_view(mode, SOURCE_CORE), VIEW_CORE, msg=mode)

    def test_j8_keeps_the_protocol_view(self):
        for mode in ("static", "counter", "uart", "spi"):
            self.assertEqual(capture_view(mode, SOURCE_J8), mode, msg=mode)

    def test_core_preset_with_j8_source_is_a_plain_capture(self):
        # core 只是一个"全速 + 2048 点 + ch6 上升沿"的预设，没有 CPU trace 可判
        self.assertEqual(capture_view("core", SOURCE_J8), VIEW_RAW)
        self.assertEqual(capture_view("core", SOURCE_CORE), VIEW_CORE)

    def test_view_matches_the_default_configs(self):
        # 每个模式默认走哪个源、于是解释成什么：这条把"默认路径不回归"钉住
        expect = {"static": "static", "counter": "counter", "uart": "uart",
                  "spi": "spi", "core": VIEW_CORE}
        for mode, view in expect.items():
            cfg = default_config(mode, 0)
            self.assertEqual(capture_view(mode, cfg.get("source", SOURCE_J8)), view, msg=mode)

    def test_mirror_cannot_be_switched_to_the_core_source(self):
        # 镜像抓的是上位机自己发的串口线（J8-31/32），0xA7 也装不下源字节
        with self.assertRaises(ValueError):
            apply_knobs("mirror", default_config("mirror", 0), {"source": SOURCE_CORE})


if __name__ == "__main__":
    unittest.main()
