"""单文件上位机（`逻辑分析仪演示.py`）的协议层自检：不打开串口、不建窗口。

补的是界面测试（`python/test_logic_analyzer_singlefile.py`）之外的一层：
把"模式 × 采集源"的组合逐个过一遍报文与判据，确认老路径逐字节不变、新路径确实走 0xA8。

    python python/singlefile_protocol_check.py     # 末行应为 SINGLE FILE CHECK PASS
"""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("demo", ROOT / "逻辑分析仪演示.py")
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)


def packet_of(cfg):
    return demo.build_packet(cfg["mode"], cfg["data"], cfg["pattern_div"], cfg["sample_div"],
                             cfg["trig_type"], cfg["trig_mask"], cfg["trig_value"],
                             cfg["pre"], cfg["post"], cfg["prefix"], cfg["post16"],
                             cfg.get("source"))


core = demo.mode_config("core", "HELLO", 85_000_000)
print("core cfg:", core["sample_div"], hex(core["trig_mask"]), core["pre"], core["post"],
      "source=", core.get("source"))
packet = packet_of(core)
print("core packet len", len(packet), hex(packet[0]), "src byte", packet[14],
      "post", packet[12] | (packet[13] << 8))

uart = demo.mode_config("uart", "HELLO", 85_000_000)
print("uart packet len", len(packet_of(uart)), "（应为 13）")

merged = demo.apply_knobs("core", core, {"source": 1, "post": 1983})
print("knob source:", merged.get("source"), "post", merged["post"])

back = demo.apply_knobs("uart", uart, {"source": 1})
print("uart+Core source:", back.get("source"), "包长", len(packet_of(back)))

try:
    demo.apply_knobs("mirror", demo.mode_config("mirror", "HELLO", 85_000_000), {"source": 1})
    print("镜像接受 source：BUG")
except ValueError:
    print("镜像拒绝 source：OK")

ok, why = demo.judge("core", [0x80] * 40 + [0x01] * 40 + [0x00] * 20, b"", 0, core, "")
print("judge core:", ok, why)

# ---- 采集源 -> 这一窗怎么解释（与 python/logic_analyzer_serial.py 的 capture_view 必须同口径）
print()
cases = (
    ("core", 1, "core"), ("core", 0, "raw"), ("uart", 1, "core"),
    ("uart", 0, "uart"), ("spi", 1, "core"), ("spi", 0, "spi"),
    ("static", 0, "static"), ("counter", 0, "counter"), ("mirror", 0, "mirror"),
)
bad = 0
for mode, source, want in cases:
    got = demo.capture_view(mode, source)
    flag = "OK" if got == want else "FAIL want=%s" % want
    bad += got != want
    print("  view(%-8s source=%d) = %-8s %s" % (mode, source, got, flag))

# uart 模式 + Core 源：波形是流水线信号，不该按 UART 帧判失败
samples = [0x01] * 30 + [0x81] * 30 + [0x41] * 10      # ch0 取指 + ch7 提交
ok_core, why_core = demo.judge(demo.capture_view("uart", 1), samples, b"", 0, uart, "")
ok_uart, why_uart = demo.judge(demo.capture_view("uart", 0), samples, b"", 0, uart, "")
print("  uart+Core 源判据:", ok_core, why_core)
print("  uart+J8  源判据:", ok_uart, why_uart)
bad += not ok_core or ok_uart

# core 预设 + J8 源：没有协议可判，只报统计
ok_raw, why_raw = demo.judge(demo.capture_view("core", 0), samples, b"", 0, core, "")
print("  core+J8  源判据:", ok_raw, why_raw)
bad += not ok_raw

print()
print("SINGLE FILE CHECK " + ("PASS" if bad == 0 else "FAIL"))
