"""python/trace_view.py 的自动判据测试。

这些用例的目的是把"上位机这一侧的口径"钉死：
  · 位段与 RTL 一致（同一条记录的期望值在 tb/tb_trace_buffer.v 里也有一份，两处必须相等）；
  · 反汇编器的助记符就是页面显示的助记符，不存在第二份实现；
  · 回包少一条、多一条、count 对不上时必须**报错**而不是照画；
  · 依赖图的边指向"最近一次写它的那条记录"，不是"任意一次"。
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import trace_view as tv  # noqa: E402


def rec(**kw):
    base = dict(pc=0, instr=0, rd_we=0, rd=0, rd_data=0,
                mem_we=0, mem_addr=0, mem_wstrb=0, mem_data=0, error=0)
    base.update(kw)
    return base


def make_log(records, marks, text_bytes, phase=0, status=4, xor=0, up=0, count=None):
    """按固件的真实回包格式拼一份日志（字段宽度也照抄，不放宽）。"""
    lines = []
    lines.append("LA_READY\r")
    lines.append("TRACE_ARMED\r")
    n = len(records) if count is None else count
    lines.append("TRACE RAW count=%08X marks=%08X status=%08X\r" % (n, len(marks), status))
    for r in records:
        words = tv.record_words(dict(r, raw=tv.pack_record(r)))
        lines.append(" ".join("%08X" % w for w in words))
    lines.append("TRACE MARK n=%08X" % len(marks))
    if marks:
        lines.append(" ".join("%06X" % ((m["index"] << 8) | m["value"]) for m in marks))
    lines.append("TRACE TEXT hex=" + "".join("%08X" % b for b in text_bytes)
                 + " ascii=" + "".join(chr(b) if 32 <= b < 127 else "." for b in text_bytes)
                 + " xor=%08X up=%08X chars=%08X" % (xor, up, len(text_bytes)))
    lines.append("TRACE_DONE\r")
    return "\n".join(lines)


class RecordLayout(unittest.TestCase):
    def test_field_positions_match_rtl(self):
        """这条向量与 tb/tb_trace_buffer.v 的 T3[2] 用例逐位相同。"""
        raw = tv.pack_record(rec(pc=0x008, instr=0x00A5A023, mem_we=1,
                                 mem_addr=0x100, mem_wstrb=0xF, mem_data=0x0A))
        got = tv.unpack_record(tv.record_words({"raw": raw}))
        self.assertEqual(got["pc"], 0x008)
        self.assertEqual(got["instr"], 0x00A5A023)
        self.assertEqual(got["rd_we"], 0)
        self.assertEqual(got["rd"], 0)
        self.assertEqual(got["rd_data"], 0)
        self.assertEqual(got["mem_we"], 1)
        self.assertEqual(got["mem_addr"], 0x100)
        self.assertEqual(got["mem_wstrb"], 0xF)
        self.assertEqual(got["mem_data"], 0x0A)
        self.assertEqual(got["error"], 0)

    def test_roundtrip(self):
        r = rec(pc=0x7FC, instr=0xFFFFFFFF, rd_we=1, rd=31, rd_data=0xDEADBEEF,
                mem_we=1, mem_addr=0xFFF, mem_wstrb=0xA, mem_data=0x01234567, error=1)
        back = tv.unpack_record(tv.record_words(dict(r, raw=tv.pack_record(r))))
        for k in tv.FIELD_NAMES:
            self.assertEqual(back[k], r[k], k)

    def test_rejects_wrong_word_count(self):
        with self.assertRaises(ValueError):
            tv.unpack_record([0, 0, 0, 0])

    def test_rejects_overflow_bits(self):
        with self.assertRaises(ValueError):
            tv.unpack_record([0, 0, 0, 0, 0x10])   # 第 132 位超出记录宽度


class Decoder(unittest.TestCase):
    def test_common_instructions(self):
        # reads/writes 里**不含 x0**：x0 恒为 0，没有依赖边可画
        cases = {
            0x00A00513: ("addi", [], [10]),       # addi x10,x0,10
            0x00B00593: ("addi", [], [11]),       # addi x11,x0,11
            0x00A5A023: ("sw", [11, 10], []),     # sw x10,0(x11)
            0x0005A503: ("lw", [11], [10]),       # lw x10,0(x11)
            0x00058463: ("beq", [11], []),        # beq x11,x0,8
            0x00100073: ("ebreak", [], []),
            0x00A00533: ("add", [10], [10]),      # add x10,x0,x10（只有 x10 是源）
        }
        for word, (mnem, reads, writes) in cases.items():
            d = tv.decode_rv32i(word)
            self.assertEqual(d["mnemonic"], mnem, hex(word))
            self.assertEqual(d["reads"], reads, hex(word))
            self.assertEqual(d["writes"], writes, hex(word))

    def test_mul_div_are_decoded(self):
        self.assertEqual(tv.decode_rv32i(0x02A50533)["mnemonic"], "mul")   # mul x10,x10,x10
        self.assertEqual(tv.decode_rv32i(0x02A54533)["mnemonic"], "div")   # div x10,x10,x10

    def test_unknown_word_is_flagged_not_guessed(self):
        d = tv.decode_rv32i(0xFFFFFFFF)
        self.assertEqual(d["mnemonic"], "illegal")
        self.assertEqual(d["reads"], [])
        self.assertEqual(d["writes"], [])

    def test_x0_never_appears_in_reads_or_writes(self):
        for word in (0x00000513, 0x00000033, 0x00500033):
            d = tv.decode_rv32i(word)
            self.assertNotIn(0, d["reads"])
            self.assertNotIn(0, d["writes"])


class ProgramMem(unittest.TestCase):
    def test_parse_hex_image(self):
        # @ 后面按**字序号**解释（与 generate_logic_analyzer_fpga_memory.ps1 同口径）
        words = tv.parse_program_mem("@00000000\n00001137 6D0000EF\n@00000002\n0000006F\n", depth=4)
        self.assertEqual(words[0], 0x00001137)
        self.assertEqual(words[1], 0x6D0000EF)
        self.assertEqual(words[2], 0x0000006F)

    def test_rejects_garbage(self):
        with self.assertRaises(ValueError):
            tv.parse_program_mem("@0\nZZZZ\n", depth=2)

    def test_rejects_address_beyond_depth(self):
        with self.assertRaises(ValueError):
            tv.parse_program_mem("@00001000\n00000013\n", depth=1024)


class Parsing(unittest.TestCase):
    def _records(self):
        return [
            rec(pc=0x100, instr=0x00A00513, rd_we=1, rd=10, rd_data=10),
            rec(pc=0x104, instr=0x00B00593, rd_we=1, rd=11, rd_data=11),
            rec(pc=0x108, instr=0x00A5A023, mem_we=1, mem_addr=0x100, mem_wstrb=0xF, mem_data=10),
        ]

    def test_parse_ok(self):
        log = make_log(self._records(), [{"index": 0, "value": ord("h")}], [0x48], xor=0x48, up=1)
        cap = tv.parse_capture(log)
        self.assertEqual(cap["count"], 3)
        self.assertEqual(len(cap["records"]), 3)
        self.assertEqual(cap["marks"], [{"index": 0, "value": ord("h")}])
        self.assertEqual(cap["text"], [0x48])

    def test_missing_record_must_raise(self):
        log = make_log(self._records(), [], [], count=5)
        with self.assertRaises(ValueError):
            tv.parse_capture(log)

    def test_mark_header_mismatch_must_raise(self):
        log = make_log(self._records(), [{"index": 0, "value": 0x41}], [0x41])
        broken = log.replace("marks=00000001", "marks=00000002")
        with self.assertRaises(ValueError):
            tv.parse_capture(broken)

    def test_no_trace_section_must_raise(self):
        with self.assertRaises(ValueError):
            tv.parse_capture("LA_READY\r\nLA_DONE\r\n")

    def test_iter_captures_handles_two_shots(self):
        r = self._records()
        log = make_log(r, [], [0x41]) + "\n" + make_log(r, [], [0x42])
        caps = tv.iter_captures(log)
        self.assertEqual(len(caps), 2)
        self.assertEqual(caps[1]["text"], [0x42])


class Judgement(unittest.TestCase):
    def _good_phase0(self):
        sent = "hi"
        want = [ord("H"), ord("I")]
        records = [
            rec(pc=0x200, instr=0x00002403, rd_we=1, rd=8, rd_data=ord("h")),   # lw x8 (示意)
            rec(pc=0x204, instr=0x00A40413, rd_we=1, rd=8, rd_data=ord("H")),   # addi x8,x8,-32
            # sw x8,0(x0) -> 有效地址就是 0，因此 mem_addr 必须写 0：
            # 地址字段与指令自洽也是判据的一部分（见 "store 有效地址与记录低 12 位一致"）
            rec(pc=0x208, instr=0x00802023, mem_we=1, mem_addr=0x0, mem_wstrb=0x1, mem_data=ord("h")),
        ]
        log = make_log(records, [{"index": 0, "value": ord("h")}, {"index": 2, "value": ord("i")}],
                       want, phase=0, xor=ord("H") ^ ord("I"), up=2)
        imem = [0] * 1024
        for r in records:
            imem[r["pc"] >> 2] = r["instr"]
        return tv.parse_capture(log), sent, imem

    def test_good_capture_passes(self):
        cap, sent, imem = self._good_phase0()
        results = tv.judge(cap, sent, 0, imem)
        failed = [n for n, ok, _d in results if not ok]
        self.assertEqual(failed, [])
        self.assertTrue(tv.judgements_pass(results))

    def test_wrong_uppercase_must_fail(self):
        cap, sent, imem = self._good_phase0()
        cap["text"] = [ord("h"), ord("i")]
        results = tv.judge(cap, sent, 0, imem)
        self.assertFalse(tv.judgements_pass(results))
        self.assertIn("大写化结果", [n for n, ok, _d in results if not ok])

    def test_mark_value_mismatch_must_fail(self):
        cap, sent, imem = self._good_phase0()
        cap["marks"][0]["value"] = ord("X")
        results = tv.judge(cap, sent, 0, imem)
        self.assertIn("打点值等于发送的字符", [n for n, ok, _d in results if not ok])

    def test_imem_mismatch_must_fail(self):
        """位流里的镜像和页面用的镜像不是同一份时，必须当场报出来。"""
        cap, sent, imem = self._good_phase0()
        imem[cap["records"][0]["pc"] >> 2] ^= 1
        results = tv.judge(cap, sent, 0, imem)
        self.assertIn("pc 与位流镜像同源", [n for n, ok, _d in results if not ok])

    def test_store_address_mismatch_must_fail(self):
        """记录里的 12 位地址必须与按指令还原出的有效地址低 12 位一致。

        这一条是"地址字段"和"寄存器跟踪"互相钉住：随便改一边都会露出来。
        """
        cap, sent, imem = self._good_phase0()
        cap["records"][2]["mem_addr"] = 0x300     # sw x8,0(x0) 的有效地址是 0
        results = tv.judge(cap, sent, 0, imem)
        self.assertIn("store 有效地址与记录低 12 位一致", [n for n, ok, _d in results if not ok])

    def test_bogus_overflow_must_fail(self):
        """status=0x0C 是 2026-10-21 实测到的假溢出：软件正常 stop 之后
        CPU 还会继续退休指令，旧逻辑把那些指令记成了 overflow。
        窗口容量远大于 count 时，overflow 位必须是 0。"""
        cap, sent, imem = self._good_phase0()
        cap["status"] = 0x0C
        results = tv.judge(cap, sent, 0, imem, depth=8192)
        self.assertIn("未溢出", [n for n, ok, _d in results if not ok])
        self.assertFalse(tv.judgements_pass(results))

    def test_overflow_allowed_when_buffer_really_full(self):
        cap, sent, imem = self._good_phase0()
        cap["status"] = 0x0C
        # 只有当 count 真的等于窗口容量时，overflow 才是可信的
        ok = [v for n, v, _d in tv.judge(cap, sent, 0, imem, depth=cap["count"]) if n == "未溢出"]
        self.assertEqual(ok, [True])

    def test_phase1_expects_verbatim_text(self):
        records = [rec(pc=0x300, instr=0x00000013)]
        log = make_log(records, [{"index": 0, "value": ord("A")}],
                       [ord("A")], phase=1, xor=ord("A"), up=0)
        cap = tv.parse_capture(log)
        self.assertTrue(tv.judgements_pass(tv.judge(cap, "A", 1, None)))
        self.assertFalse(tv.judgements_pass(tv.judge(cap, "B", 1, None)))


class Flow(unittest.TestCase):
    def test_dependency_edges_point_to_nearest_writer(self):
        records = [
            rec(pc=0x400, instr=0x00A00513, rd_we=1, rd=10, rd_data=5),    # addi x10,x0,5
            rec(pc=0x404, instr=0x00150513, rd_we=1, rd=10, rd_data=6),    # addi x10,x10,1
            rec(pc=0x408, instr=0x00A50533, rd_we=1, rd=10, rd_data=12),   # add x10,x10,x10
        ]
        log = make_log(records, [], [])
        cap = tv.parse_capture(log)
        flow = tv.build_flow(cap)
        nodes = flow["nodes"]
        self.assertEqual(nodes[1]["srcs"], [{"reg": 10, "from": 0}])
        self.assertEqual(nodes[2]["srcs"], [{"reg": 10, "from": 1}])

    def test_window_external_source_is_marked_unknown(self):
        records = [
            rec(pc=0x500, instr=0x00002023, mem_we=1, mem_addr=0x40, mem_wstrb=0xF, mem_data=1),
        ]
        cap = tv.parse_capture(make_log(records, [], []))
        flow = tv.build_flow(cap)
        # sw 读 rs1(x0 不记) 与 rs2=0 -> 不产生源；换成 add x5,x6,x7 才有"窗口外"的源
        recs = [rec(pc=0x500, instr=0x007302B3, rd_we=1, rd=5, rd_data=9)]   # add x5,x6,x7
        cap = tv.parse_capture(make_log(recs, [], []))
        flow = tv.build_flow(cap)
        self.assertEqual([s["from"] for s in flow["nodes"][0]["srcs"]], [None, None])

    def test_marks_anchor_to_next_record(self):
        records = [rec(pc=0x600, instr=0x00000013), rec(pc=0x604, instr=0x00000013)]
        cap = tv.parse_capture(make_log(records, [{"index": 1, "value": ord("Z")}], []))
        flow = tv.build_flow(cap)
        self.assertEqual(flow["nodes"][0]["marks"], [])
        self.assertEqual(flow["nodes"][1]["marks"], ["Z"])


class Page(unittest.TestCase):
    def test_page_contains_payload_and_no_placeholder(self):
        import tempfile
        records = [rec(pc=0x700, instr=0x00A00513, rd_we=1, rd=10, rd_data=10)]
        cap = tv.parse_capture(make_log(records, [], [0x41], xor=0x41, up=0))
        flow = tv.build_flow(cap)
        payload = tv.page_payload(cap, flow, "A", 0, {"log": "x.log", "mem": "y.mem"})
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "page.html"
            tv.write_trace_page(out, payload)
            html = out.read_text(encoding="utf-8")
        self.assertNotIn("__TRACE_DATA__", html)
        self.assertIn("addi x10,x0,10", html)        # 助记符来自同一份实现
        blob = html.split("const D = ", 1)[1].split(";\nconst N", 1)[0]
        data = json.loads(blob)
        self.assertEqual(data["nodes"][0]["rd_data"], 10)
        self.assertEqual(data["sent"], "A")

    def test_generated_page_javascript_parses(self):
        """页面里的 JS 必须能被真正的解析器吃下去。

        为什么值得单独测：页面的语法错误**不会**在任何 python 断言里出现，
        只会在打开浏览器时白屏。这里用 ``node --check`` 把这类失败前移到
        CI 里（本机没有 node 时退化为 skip，不假装通过）。
        """
        import shutil
        import subprocess
        import tempfile

        node = shutil.which("node")
        if not node:
            self.skipTest("node unavailable; skipping page JS parse check")

        records = [
            rec(pc=0x100, instr=0x00002403, rd_we=1, rd=8, rd_data=0x68),
            rec(pc=0x104, instr=0x00A40413, rd_we=1, rd=8, rd_data=0x48),
            rec(pc=0x108, instr=0x00802023, mem_we=1, mem_addr=0x300, mem_wstrb=0x1, mem_data=0x48),
        ]
        cap = tv.parse_capture(make_log(records, [{"index": 0, "value": ord("h")}],
                                        [0x48], xor=0x48, up=1))
        flow = tv.build_flow(cap)
        payload = tv.page_payload(cap, flow, "h", 0, {"log": "x", "mem": "y"})
        with tempfile.TemporaryDirectory() as td:
            page = Path(td) / "p.html"
            tv.write_trace_page(page, payload)
            html = page.read_text(encoding="utf-8")
            js = html.split("<script>", 1)[1].rsplit("</script>", 1)[0]
            jspath = Path(td) / "p.js"
            jspath.write_text(js, encoding="utf-8")
            proc = subprocess.run([node, "--check", str(jspath)],
                                  capture_output=True, text=True, timeout=60)
        self.assertEqual(proc.returncode, 0, proc.stderr[:800])

    def test_every_element_id_used_by_js_exists_in_html(self):
        """JS 里 getElementById 用到的每个 id，HTML 里都必须真的有这个元素。

        为什么单独测：拼错一个 id 时页面**不会报任何 python 侧错误**，
        只会在打开时 `Cannot set properties of null`，然后整块面板空白。
        """
        import re
        import tempfile

        records = [rec(pc=0x100, instr=0x00002403, rd_we=1, rd=8, rd_data=0x68)]
        cap = tv.parse_capture(make_log(records, [{"index": 0, "value": ord("h")}],
                                        [0x68], xor=0x68, up=1))
        payload = tv.page_payload(cap, tv.build_flow(cap), "h", 0, {"log": "x", "mem": "y"})
        with tempfile.TemporaryDirectory() as td:
            page = Path(td) / "p.html"
            tv.write_trace_page(page, payload)
            html = page.read_text(encoding="utf-8")
        js = html.split("<script>", 1)[1].rsplit("</script>", 1)[0]
        used = set(re.findall(r"getElementById\(\s*['\"]([A-Za-z0-9_\-]+)['\"]\s*\)", js))
        declared = set(re.findall(r"id=\"([A-Za-z0-9_\-]+)\"", html))
        self.assertTrue(used, "页面里应当有 getElementById 调用")
        missing = sorted(used - declared)
        self.assertEqual(missing, [], "JS 引用了 HTML 里不存在的 id: %r" % missing)


class WaveAlignment(unittest.TestCase):
    """0xAB 组合采集：波形第 k 拍 ↔ trace 第几条记录。

    这里用**人造的** capture+wave 验证"对齐算法本身"，真数据由板级/TB 两份证据兜底：
      · 正例：按某个偏移造出波形，算法必须把同一个偏移找回来，且交叉校验差值为 0；
      · 反例：把波形挪一条，交叉校验必须报出非 0 差值（否则这条判据等于没判）。
    """

    # lui x14,0x10002 / sw x15,0x100(x14)  —— 后者就是"LA 的 arm 写"
    ARM_LUI = 0x10002737
    ARM_SW = 0x10F72023
    ACCESS = [0x00002403, 0x00802023, 0x00A00513, 0x00002483, 0x00150513]
    #        lw x8,0(x0)   sw x8,0(x0)  addi x10,x0,10  lw x9,0(x0)  addi x10,x10,1

    def _capture(self, n_tail=24):
        records = [rec(pc=0x400, instr=self.ARM_LUI, rd_we=1, rd=14, rd_data=0x10002000),
                   rec(pc=0x404, instr=self.ARM_SW, mem_we=1, mem_addr=0x100,
                       mem_wstrb=0xF, mem_data=1)]
        for i in range(n_tail):
            records.append(rec(pc=0x408 + 4 * i, instr=self.ACCESS[i % len(self.ACCESS)],
                               mem_we=1 if i % len(self.ACCESS) in (1, 3) else 0,
                               mem_addr=0x200 + 4 * i, mem_wstrb=0xF, mem_data=i & 0xFF,
                               rd_we=1 if i % len(self.ACCESS) in (0, 2, 4) else 0,
                               rd=8 + (i % 3), rd_data=i))
        return tv.parse_capture(make_log(records, [], []))

    def _wave(self, cap, offset, cycles=40):
        """按 offset 造一段波形：退休脉冲落在记录所在的那一拍，数据访问脉冲落在访存记录那一拍。"""
        nodes = tv.build_flow(cap)["nodes"]
        samples = [0] * cycles
        for k in range(min(cycles, len(nodes) - offset)):
            nd = nodes[offset + k]
            samples[k] = tv.CH_RETIRE | tv.CH_IV | tv.CH_IR     # 每拍都在取指，且这一拍退休一条
            if nd["mem_we"] or nd["mnemonic"] in ("lw", "lb", "lh", "lbu", "lhu"):
                samples[k] |= tv.CH_DV | tv.CH_DR
        # 窗口末尾几拍留空：模拟"负载结束、LA 还在采"
        return {"count": cycles, "trigger": 0, "window": cycles, "div": 0,
                "samples": samples}

    def test_alignment_recovers_the_la_arm_offset(self):
        """物理事实：arm 写在 MEM 生效、它的退休脉冲在 WB —— 波形第 0 个样本就是它自己那条记录。"""
        cap = self._capture()
        wave = self._wave(cap, offset=1)          # = arm 写那条记录
        al = tv.align_wave(cap, wave)
        self.assertEqual(al["anchor"], 1, "arm 写应当在第 1 条记录")
        self.assertEqual(al["offset"], 1)
        self.assertEqual(al["delta"], 0)
        self.assertEqual(al["retire_pulses"], len(tv.build_flow(cap)["nodes"]) - 1)
        self.assertEqual(al["mismatch"], 0, al)
        res = dict((n, ok) for n, ok, _d in tv.judge_wave(cap, wave))
        self.assertTrue(all(res.values()), res)

    def test_tied_candidates_are_reported_as_pm_one(self):
        """周期性的负载会让相邻偏移同样吻合——这时要**说出来**，不能装作唯一。

        真实固件处理循环就是周期性的，所以这条是对齐功能的诚实性判据。
        """
        cap = self._capture()
        wave = self._wave(cap, offset=2)
        al = tv.align_wave(cap, wave)
        self.assertTrue(al["ambiguous"], "周期性负载下相邻偏移必然同样吻合：%r" % (al["tied"],))
        detail = [d for n, _ok, d in tv.judge_wave(cap, wave) if "arm 写" in n][0]
        self.assertIn("±1", detail)

    def test_coverage_judgement_flags_a_tiny_window(self):
        """覆盖率判据：窗口只覆盖一小截时必须 FAIL（否则"对齐"等于只对了开头几拍）。"""
        cap = self._capture()
        wave = self._wave(cap, offset=1)
        res = dict((n, ok) for n, ok, _d in tv.judge_wave(cap, wave))
        self.assertTrue(res["波形覆盖 trace 的绝大部分（≥95%）"])
        # 把波形截成只覆盖 3 条记录：覆盖率判据必须挂
        tiny = {"count": 3, "trigger": 0, "window": 3, "div": 0,
                "samples": wave["samples"][:3]}
        res = dict((n, ok) for n, ok, _d in tv.judge_wave(cap, tiny))
        self.assertFalse(res["波形覆盖 trace 的绝大部分（≥95%）"])

    def test_mismatch_is_reported_not_hidden(self):
        """少一个数据访问脉冲时必须报错——不然"对齐"就成了摆设。"""
        cap = self._capture()
        wave = self._wave(cap, offset=1)
        for i, v in enumerate(wave["samples"]):
            if v & tv.CH_DV:
                wave["samples"][i] = v & ~tv.CH_DR
                break
        res = dict((n, ok) for n, ok, _d in tv.judge_wave(cap, wave))
        self.assertFalse(res["数据访问脉冲数 = 区间内访存指令数"], res)

    def test_wave_lanes_follow_the_probe_bit_order(self):
        cap = self._capture()
        wave = self._wave(cap, offset=1)
        lanes = tv.wave_lanes(wave)
        self.assertEqual([l["name"] for l in lanes[:3]], ["提交", "冲刷", "停顿"])
        # 退休泳道里的 1 必须正好是"窗口内那条记录"的个数
        self.assertEqual(sum(lanes[0]["bits"]), len(tv.build_flow(cap)["nodes"]) - 1)
        self.assertTrue(all(b in (0, 1) for b in lanes[3]["bits"]))


if __name__ == "__main__":
    unittest.main()
