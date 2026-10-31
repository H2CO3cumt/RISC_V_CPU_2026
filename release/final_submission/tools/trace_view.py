"""提交级 trace 的解析、判据与可视化（上位机一侧的唯一实现）。

这个模块是"判据与标注必须同源"的落点，所以有三条硬纪律：

1. **记录位段只定义一次**：``REC_FIELDS`` 是 132 位记录的唯一拆解表，
   解析、页面标注、自动判据全部从这里取。RTL 侧对应
   ``rtl/trace_buffer.v`` 的拼接顺序，改任一侧必须同步改另一侧并重跑
   ``scripts/run_trace_buffer_tb.ps1``。
2. **指令反汇编只有一个实现**：页面上的助记符就是判据里用的那个字符串，
   不存在"页面显示一份、判 PASS 用另一份"。
3. **pc 与镜像同源要逐条证明**：用位流里同一份 ``logic_analyzer_program.mem``
   反查 ``instr_at(pc)``，逐条断言 ``record.instr == imem[pc>>2]``。
   对不上就说明页面用的镜像和位流里的不是同一份——这种错误在页面上
   看起来"完全正常"，只有逐条对拍才抓得住。

已知边界（如实写在这里，不在页面上偷偷回避）：
* ``trace_mem_addr`` 只在 **store** 时有效（``docs/interfaces.md`` §6.1 的
  ``trace_mem_we`` 语义就是"本指令是否写存储"），所以 **load 的地址不在
  记录里**。页面能显示 load 读到什么值，地址只有在基址寄存器于窗口内被写过
  时才能推出来，推不出来就标 ``?``，不猜。
"""

from __future__ import annotations

import json
import re
from pathlib import Path

# ---------------------------------------------------------------------------
# 记录位段：与 rtl/trace_buffer.v 的拼接顺序逐位一致
# ---------------------------------------------------------------------------
REC_W = 132
TR_WORDS = 5          # 一条记录要 5 个 MMIO 字才装得下（132 > 4*32）
REC_FIELDS = (
    # name,       low, width
    ("pc",         0, 12),
    ("instr",     12, 32),
    ("rd_we",     44,  1),
    ("rd",        45,  5),
    ("rd_data",   50, 32),
    ("mem_we",    82,  1),
    ("mem_addr",  83, 12),
    ("mem_wstrb", 95,  4),
    ("mem_data",  99, 32),
    ("error",    131,  1),
)

FIELD_NAMES = tuple(name for name, _low, _w in REC_FIELDS)


def unpack_record(words):
    """5 个 32 位字 -> 一条记录的字段字典。words[0] 是最低 32 位。"""
    if len(words) != TR_WORDS:
        raise ValueError("一条记录必须正好 %d 个字，收到 %d 个" % (TR_WORDS, len(words)))
    raw = 0
    for i, w in enumerate(words):
        if not (0 <= w <= 0xFFFFFFFF):
            raise ValueError("字 %d 超出 32 位: %r" % (i, w))
        raw |= (w & 0xFFFFFFFF) << (32 * i)
    if raw >> REC_W:
        raise ValueError("记录超出 %d 位: 0x%X" % (REC_W, raw))
    rec = {}
    for name, low, width in REC_FIELDS:
        rec[name] = (raw >> low) & ((1 << width) - 1)
    rec["raw"] = raw
    return rec


def pack_record(rec):
    """字段字典 -> 132 位整数（判据与测试用的反向操作）。"""
    raw = 0
    for name, low, width in REC_FIELDS:
        v = int(rec.get(name, 0)) & ((1 << width) - 1)
        raw |= v << low
    return raw


def record_words(rec):
    raw = rec["raw"] if "raw" in rec else pack_record(rec)
    return [(raw >> (32 * i)) & 0xFFFFFFFF for i in range(TR_WORDS)]


# ---------------------------------------------------------------------------
# 程序镜像：位流里同一份 .mem，用来做"pc 与镜像同源"的逐条对拍
# ---------------------------------------------------------------------------
def parse_program_mem(text, depth=2048):
    """解析 objcopy 生成的 Verilog 镜像（@地址 + 若干十六进制字）。

    ``@`` 后面按**字序号**解释，与项目现有的
    ``scripts/generate_logic_analyzer_fpga_memory.ps1`` 完全一致：那份脚本就是
    用 ``@`` 的值直接当下标写 ``$words[index]``。两边口径不同会让"页面上的指令"
    和"位流里的指令"错位，而这正是本模块要判死的那类错误。

    ``depth`` 只是容量上界（大一点无害：镜像里没有的字按 0 处理）。默认取 2048，
    因为 tr85 那一档的固件镜像在 2026-10-24 扩到了 8 KB = 2048 字；
    交付工程（la85/la50）仍是 1024 字的镜像，用同一个上界解析同样正确。
    """
    words = [0] * depth
    index = 0
    for token in text.split():
        if token.startswith("@"):
            index = int(token[1:], 16)
            if index >= depth:
                raise ValueError("@ 地址 %d 超出容量 %d 字" % (index, depth))
            continue
        if not re.fullmatch(r"[0-9A-Fa-f]{2,8}", token):
            raise ValueError("镜像里有无法识别的词: %r" % token)
        if len(token) % 2:
            raise ValueError("镜像词长度不是字节整数倍: %r" % token)
        if index >= depth:
            raise ValueError("镜像超出 %d 字的容量（index=%d）" % (depth, index))
        words[index] = int(token, 16) & 0xFFFFFFFF
        index += 1
    return words


def load_program_mem(path):
    return parse_program_mem(Path(path).read_text(encoding="utf-8", errors="replace"))


# ---------------------------------------------------------------------------
# RV32I(+M) 反汇编：只为"读懂这一条指令在读哪些寄存器、写了什么"服务
# ---------------------------------------------------------------------------
_XLEN = 32


def _sext(value, bits):
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (sign if value & sign else 0)


def _imm_i(w):
    return _sext(w >> 20, 12)


def _imm_s(w):
    return _sext(((w >> 25) << 5) | ((w >> 7) & 0x1F), 12)


def _imm_b(w):
    v = (((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1)
    return _sext(v, 13)


def _imm_u(w):
    return w & 0xFFFFF000


def _imm_j(w):
    v = (((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1)
    return _sext(v, 21)


_BRANCH = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
_LOAD = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
_STORE = {0: "sb", 1: "sh", 2: "sw"}
_OPIMM = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}
_OP = {0: "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor", 5: "srl", 6: "or", 7: "and"}
_MULDIV = {0: "mul", 1: "mulh", 2: "mulhsu", 3: "mulhu", 4: "div", 5: "divu", 6: "rem", 7: "remu"}
_CSR = {1: "csrrw", 2: "csrrs", 3: "csrrc", 5: "csrrwi", 6: "csrrsi", 7: "csrrci"}


def decode_rv32i(word):
    """把一条 32 位指令拆成 {mnemonic, text, rd, rs1, rs2, imm, reads, writes}。

    ``reads``/``writes`` 是寄存器号列表，依赖图与寄存器热力图全靠它，
    和页面显示用的 ``text`` 出自同一份判断——不另写第二份实现。
    """
    word &= 0xFFFFFFFF
    opcode = word & 0x7F
    rd = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1 = (word >> 15) & 0x1F
    rs2 = (word >> 20) & 0x1F
    funct7 = (word >> 25) & 0x7F
    info = {"word": word, "rd": rd, "rs1": rs1, "rs2": rs2,
            "reads": [], "writes": [], "imm": 0}

    def done(mnem, text, reads=(), writes=()):
        info["mnemonic"] = mnem
        info["text"] = text
        info["reads"] = [r for r in reads if r]
        info["writes"] = [w for w in writes if w]
        return info

    if opcode == 0x37:
        info["imm"] = _imm_u(word)
        return done("lui", "lui x%d,0x%x" % (rd, word >> 12), (), (rd,))
    if opcode == 0x17:
        info["imm"] = _imm_u(word)
        return done("auipc", "auipc x%d,0x%x" % (rd, word >> 12), (), (rd,))
    if opcode == 0x6F:
        info["imm"] = _imm_j(word)
        return done("jal", "jal x%d,%d" % (rd, info["imm"]), (), (rd,))
    if opcode == 0x67:
        if funct3 != 0:
            return done("illegal", ".word 0x%08x" % word)
        info["imm"] = _imm_i(word)
        return done("jalr", "jalr x%d,%d(x%d)" % (rd, info["imm"], rs1), (rs1,), (rd,))
    if opcode == 0x63:
        m = _BRANCH.get(funct3)
        if m is None:
            return done("illegal", ".word 0x%08x" % word)
        info["imm"] = _imm_b(word)
        return done(m, "%s x%d,x%d,%d" % (m, rs1, rs2, info["imm"]), (rs1, rs2), ())
    if opcode == 0x03:
        m = _LOAD.get(funct3)
        if m is None:
            return done("illegal", ".word 0x%08x" % word)
        info["imm"] = _imm_i(word)
        return done(m, "%s x%d,%d(x%d)" % (m, rd, info["imm"], rs1), (rs1,), (rd,))
    if opcode == 0x23:
        m = _STORE.get(funct3)
        if m is None:
            return done("illegal", ".word 0x%08x" % word)
        info["imm"] = _imm_s(word)
        return done(m, "%s x%d,%d(x%d)" % (m, rs2, info["imm"], rs1), (rs1, rs2), ())
    if opcode == 0x13:
        if funct3 == 1:
            imm = (word >> 20) & 0x1F
            info["imm"] = imm
            return done("slli", "slli x%d,x%d,%d" % (rd, rs1, imm), (rs1,), (rd,))
        if funct3 == 5:
            imm = (word >> 20) & 0x1F
            info["imm"] = imm
            m = "srai" if funct7 == 0x20 else "srli"
            return done(m, "%s x%d,x%d,%d" % (m, rd, rs1, imm), (rs1,), (rd,))
        m = _OPIMM.get(funct3)
        if m is None:
            return done("illegal", ".word 0x%08x" % word)
        info["imm"] = _imm_i(word)
        return done(m, "%s x%d,x%d,%d" % (m, rd, rs1, info["imm"]), (rs1,), (rd,))
    if opcode == 0x33:
        if funct7 == 0x01:
            m = _MULDIV.get(funct3)
            if m is None:
                return done("illegal", ".word 0x%08x" % word)
            return done(m, "%s x%d,x%d,x%d" % (m, rd, rs1, rs2), (rs1, rs2), (rd,))
        if funct7 == 0x20 and funct3 in (0, 5):
            m = "sub" if funct3 == 0 else "sra"
            return done(m, "%s x%d,x%d,x%d" % (m, rd, rs1, rs2), (rs1, rs2), (rd,))
        if funct7 == 0x00:
            m = _OP.get(funct3)
            if m is None:
                return done("illegal", ".word 0x%08x" % word)
            return done(m, "%s x%d,x%d,x%d" % (m, rd, rs1, rs2), (rs1, rs2), (rd,))
        return done("illegal", ".word 0x%08x" % word)
    if opcode == 0x0F:
        return done("fence", "fence")
    if opcode == 0x73:
        if word == 0x00000073:
            return done("ecall", "ecall")
        if word == 0x00100073:
            return done("ebreak", "ebreak")
        if word == 0x30200073:
            return done("mret", "mret")
        if word == 0x10500073:
            return done("wfi", "wfi")
        m = _CSR.get(funct3)
        if m is not None:
            csr = word >> 20
            if funct3 >= 5:
                return done(m, "%s x%d,0x%03x,%d" % (m, rd, csr, rs1), (), (rd,))
            return done(m, "%s x%d,0x%03x,x%d" % (m, rd, csr, rs1), (rs1,), (rd,))
        return done("illegal", ".word 0x%08x" % word)
    return done("illegal", ".word 0x%08x" % word)


# ---------------------------------------------------------------------------
# 回包日志解析
# ---------------------------------------------------------------------------
_RAW_RE = re.compile(r"TRACE RAW count=([0-9A-Fa-f]{1,8}) marks=([0-9A-Fa-f]{1,8}) status=([0-9A-Fa-f]{1,8})")
_MARK_RE = re.compile(r"TRACE MARK n=([0-9A-Fa-f]{1,8})")
_TEXT_RE = re.compile(
    r"TRACE TEXT hex=([0-9A-Fa-f]*) ascii=(.*?) xor=([0-9A-Fa-f]{1,8}) up=([0-9A-Fa-f]{1,8}) chars=([0-9A-Fa-f]{1,8})"
)
_TRACE_START = "TRACE RAW count="


def parse_capture(text):
    """从 UART 回包里解析**一次** trace 抓取（脚本/界面共用的唯一入口）。"""
    start = text.find(_TRACE_START)
    if start < 0:
        raise ValueError("回包里没有 TRACE RAW 头：%r" % text[:120])
    body = text[start:]
    head = _RAW_RE.search(body)
    if not head:
        raise ValueError("TRACE RAW 头格式不对：%r" % body.splitlines()[0][:120])
    count = int(head.group(1), 16)
    mark_count = int(head.group(2), 16)
    status = int(head.group(3), 16)

    lines = body.splitlines()
    records = []
    pos = 1
    while len(records) < count:
        if pos >= len(lines):
            raise ValueError("导出的记录不足：头部说 %d 条，实际只有 %d 条" % (count, len(records)))
        line = lines[pos].strip()
        pos += 1
        if not line:
            continue
        words = line.split()
        if len(words) != TR_WORDS:
            raise ValueError("记录第 %d 行不是 %d 个字：%r" % (len(records), TR_WORDS, line))
        records.append(unpack_record([int(w, 16) for w in words]))

    marks = []
    mark_head = None
    for i in range(pos, len(lines)):
        m = _MARK_RE.search(lines[i])
        if m:
            mark_head = int(m.group(1), 16)
            pos = i + 1
            break
    if mark_head is None:
        raise ValueError("找不到 TRACE MARK 头")
    if mark_head != mark_count:
        raise ValueError("MARK 头 %d 与 RAW 头的 marks=%d 不一致" % (mark_head, mark_count))
    if mark_count:
        if pos >= len(lines):
            raise ValueError("找不到打点数据行")
        for token in lines[pos].split():
            v = int(token, 16)
            marks.append({"index": (v >> 8) & 0xFFFF, "value": v & 0xFF})

    text_head = _TEXT_RE.search(body)
    if not text_head:
        raise ValueError("找不到 TRACE TEXT 行")
    hex_blob = text_head.group(1)
    text_bytes = [int(hex_blob[i:i + 8], 16) & 0xFF for i in range(0, len(hex_blob), 8)]
    m = re.search(r"ascii=(.*)$", text_head.group(0))
    ascii_field = m.group(1) if m else ""

    return {
        "count": count,
        "mark_count": mark_count,
        "status": status,
        "records": records,
        "marks": marks,
        "text": text_bytes,
        "ascii": ascii_field,
        "xor": int(text_head.group(3), 16),
        "up": int(text_head.group(4), 16),
        "chars": int(text_head.group(5), 16),
    }


def iter_captures(text):
    """一份日志里可能有多枪（多个场景），按出现顺序全部解析出来。"""
    out = []
    cursor = 0
    while True:
        idx = text.find(_TRACE_START, cursor)
        if idx < 0:
            return out
        try:
            cap = parse_capture(text[idx:])
        except ValueError:
            cursor = idx + len(_TRACE_START)
            continue
        out.append(cap)
        # 跳到这一枪结束之后，避免同一枪被解析两次
        done = text.find("TRACE_DONE", idx)
        cursor = done + len("TRACE_DONE") if done > 0 else idx + len(_TRACE_START)


# ---------------------------------------------------------------------------
# 数据流：寄存器依赖边 + 部分寄存器值重建
# ---------------------------------------------------------------------------
def build_flow(capture, imem=None):
    """给每条记录补上：反汇编文本、源寄存器来自哪条记录、以及窗口内的寄存器值。

    "数据流向"就是这里算出来的：读者 ← 最近一次写者。窗口外写过的寄存器
    标成 ``None``（页面显示为"窗口之前"），不猜它从哪来。
    """
    records = capture["records"]
    last_writer = {}
    regs = {}
    nodes = []
    for idx, rec in enumerate(records):
        dec = decode_rv32i(rec["instr"])
        node = {
            "i": idx,
            "pc": rec["pc"] & ~3,          # pc 在记录里只存 [11:0]，低两位按 RV32I 对齐为 0
            "raw_pc": rec["pc"],
            "instr": rec["instr"],
            "asm": dec["text"],
            "mnemonic": dec["mnemonic"],
            "reads": list(dec["reads"]),
            "writes": list(dec["writes"]),
            "rd": rec["rd"],
            "rd_we": rec["rd_we"],
            "rd_data": rec["rd_data"],
            "mem_we": rec["mem_we"],
            "mem_addr": rec["mem_addr"],
            "mem_data": rec["mem_data"],
            "mem_wstrb": rec["mem_wstrb"],
            "error": rec["error"],
            "srcs": [],
            "load_addr": None,
            # 记录里只有 mem_addr[11:0]（IMEM/DMEM 各 4 KB），所以**光看记录分不出
            # RAM 和 MMIO**。能用窗口内已知的基址寄存器还原出 32 位有效地址时填这里，
            # 还原不出来就留 None（页面显示 12 位原值，不猜）。
            "store_addr": None,
        }
        # 依赖边：源寄存器 ← 最近一次写它的记录
        for r in dec["reads"]:
            if r == 0:
                continue
            edge = {"reg": r, "from": last_writer.get(r)}
            # rs1 与 rs2 是同一个寄存器（如 add x10,x10,x10）时只保留一条边，
            # 否则页面上会画出两条完全重合的箭头。
            if edge not in node["srcs"]:
                node["srcs"].append(edge)
        # load / store 的 32 位有效地址：基址寄存器在窗口内被写过才算得出来
        if dec["mnemonic"] in _LOAD.values():
            base = regs.get(dec["rs1"]) if dec["rs1"] else 0
            if base is not None:
                node["load_addr"] = (base + dec["imm"]) & 0xFFFFFFFF
        if dec["mnemonic"] in _STORE.values():
            base = regs.get(dec["rs1"]) if dec["rs1"] else 0
            if base is not None:
                node["store_addr"] = (base + dec["imm"]) & 0xFFFFFFFF
        # 更新"最近写者"与寄存器影子值（只有 rd_we 且 rd != 0 才算写）
        if rec["rd_we"] and rec["rd"]:
            last_writer[rec["rd"]] = idx
            regs[rec["rd"]] = rec["rd_data"]
        nodes.append(node)

    # 打点锚点：mark 的 index 是"打点时已记录的条数"，即它锚定的**下一条**记录
    by_index = {}
    for mk in capture["marks"]:
        by_index.setdefault(mk["index"], []).append(chr(mk["value"]) if 32 <= mk["value"] < 127 else ".")
    for node in nodes:
        node["marks"] = by_index.get(node["i"], [])

    # 镜像同源对拍（有镜像才做）
    if imem is not None:
        for node in nodes:
            wi = node["raw_pc"] >> 2
            node["imem_instr"] = imem[wi] if wi < len(imem) else None

    return {"nodes": nodes, "regs_final": {str(k): v for k, v in sorted(regs.items())}}


# ---------------------------------------------------------------------------
# 自动判据
# ---------------------------------------------------------------------------
def expected_phase0(text):
    """阶段 0 固件对字节做的处理：小写字母转大写 + 逐字节 XOR + 小写个数。

    这是这份处理逻辑的**唯一**实现：界面上的实时预览、自动判据、页面标注
    全部调它，不允许存在第二份口径（否则"界面显示会得到 X"与"判据要求 X"
    可能悄悄分叉）。固件对应 `software/logic_analyzer/logic_analyzer.c`
    第 296~299 行的处理循环。
    """
    raw = [ord(ch) & 0xFF for ch in text]
    want = [c - 0x20 if 0x61 <= c <= 0x7A else c for c in raw]
    xor = 0
    for c in want:
        xor ^= c
    up = sum(1 for c in raw if 0x61 <= c <= 0x7A)
    return {"raw": raw, "want": want, "xor": xor & 0xFFFFFFFF, "up": up}



def judge(capture, sent_text, phase, imem=None, depth=8192):
    """返回 [(判据名, 是否通过, 说明)]。任何一条 FAIL 就等于这一枪不可信。

    ``depth`` 必须与位流里的 TRACE_DEPTH 一致：overflow 位只有"记录条数已经等于
    窗口容量"时才允许置起。少了这个前提，正常收尾也被当成溢出（2026-10-21 实测
    过一次，status=0x0C，overflow 位是假的）。
    """
    out = []
    recs = capture["records"]

    out.append(("记录条数自洽", capture["count"] == len(recs),
                "头部 count=%d，实际导出 %d 条" % (capture["count"], len(recs))))

    sent = [ord(ch) for ch in sent_text]
    want_marks = len(sent)
    out.append(("打点数等于字符数", capture["mark_count"] == want_marks,
                "marks=%d，发送字符数=%d" % (capture["mark_count"], want_marks)))
    mark_vals = [m["value"] for m in capture["marks"]]
    out.append(("打点值等于发送的字符", mark_vals == sent,
                "打点=%r 发送=%r" % (bytes(mark_vals), bytes(sent))))

    idxs = [m["index"] for m in capture["marks"]]
    out.append(("打点索引单调且不越界",
                idxs == sorted(idxs) and all(0 <= i <= capture["count"] for i in idxs),
                "索引=%r，count=%d" % (idxs, capture["count"])))

    if phase == 0:
        exp = expected_phase0(sent_text)
        want, want_xor, want_up = exp["want"], exp["xor"], exp["up"]
        out.append(("大写化结果", capture["text"] == want,
                    "得到 %r，期望 %r" % (bytes(capture["text"]), bytes(want))))
        out.append(("大写字符计数", capture["up"] == want_up,
                    "up=%d，期望 %d" % (capture["up"], want_up)))
        out.append(("XOR 校验", capture["xor"] == want_xor,
                    "xor=0x%08X，期望 0x%08X" % (capture["xor"], want_xor)))

    else:
        out.append(("原样回读", capture["text"] == sent,
                    "得到 %r，期望 %r" % (bytes(capture["text"]), bytes(sent))))
        out.append(("大写字符计数应为 0", capture["up"] == 0, "up=%d" % capture["up"]))

    # 注意这里要的是**实际发给 CPU 的字符数**，不是上面按阶段换算出来的打点期望值：
    # 排序阶段打点是"每趟一个"（n-1 个），而 chars 字段始终是收到的字符数。
    out.append(("字符数字段", capture["chars"] == len(sent),
                "chars=%d，期望 %d" % (capture["chars"], len(sent))))

    # 收尾状态：done=1、armed/recording=0；overflow 只有"写满"才允许置起
    armed = capture["status"] & 1
    recording = (capture["status"] >> 1) & 1
    done = (capture["status"] >> 2) & 1
    overflow = (capture["status"] >> 3) & 1
    out.append(("收尾状态位", armed == 0 and recording == 0 and done == 1,
                "status=0x%X（armed=%d recording=%d done=%d overflow=%d）"
                % (capture["status"], armed, recording, done, overflow)))
    out.append(("未溢出", (overflow == 0) or (capture["count"] >= depth),
                "overflow=%d，count=%d，窗口容量=%d" % (overflow, capture["count"], depth)))

    # 记录内部一致性
    bad_rd = [r["pc"] for r in recs if r["rd_we"] and r["rd"] == 0]
    out.append(("rd_we 不得指向 x0", not bad_rd, "越界样本 %d 条" % len(bad_rd)))
    bad_st = [r["pc"] for r in recs if r["mem_we"] and r["mem_wstrb"] == 0]
    out.append(("store 必须有字节使能", not bad_st, "越界样本 %d 条" % len(bad_st)))
    bad_pc = [r["pc"] for r in recs if r["pc"] & 3]
    out.append(("记录 pc 必须 4 字节对齐", not bad_pc, "越界样本 %d 条" % len(bad_pc)))

    if imem is not None:
        mismatch = []
        for i, r in enumerate(recs):
            wi = r["pc"] >> 2
            if wi >= len(imem) or imem[wi] != r["instr"]:
                mismatch.append(i)
        out.append(("pc 与位流镜像同源", not mismatch,
                    "不一致记录 %d 条%s" % (len(mismatch),
                                       "" if not mismatch else "，首个 %d" % mismatch[0])))

    # store 的有效地址还原出来之后，低 12 位必须与记录里的 mem_addr 相等——
    # 这一条把"基址寄存器跟踪"和"记录里的地址字段"互相钉住，任一错都会露出来。
    bad_addr = []
    for i, r in enumerate(recs):
        if not r["mem_we"]:
            continue
        full = _full_store_addr(recs, i)
        if full is not None and (full & 0xFFF) != (r["mem_addr"] & 0xFFF):
            bad_addr.append(i)
    out.append(("store 有效地址与记录低 12 位一致", not bad_addr,
                "不一致 %d 条%s" % (len(bad_addr), "" if not bad_addr else "，首个 %d" % bad_addr[0])))

    return out


def _full_store_addr(recs, idx):
    """窗口内重放到 idx，若 store 的基址寄存器已知就返回 32 位有效地址。

    与 ``build_flow`` 的口径相同：只有**窗口内写过**的寄存器才有值，其余返回 None，
    绝不拿 12 位的记录值去猜高 20 位。
    """
    regs = {}
    for i in range(idx + 1):
        r = recs[i]
        dec = decode_rv32i(r["instr"])
        if i == idx and r["mem_we"] and dec["mnemonic"] in _STORE.values():
            base = regs.get(dec["rs1"]) if dec["rs1"] else 0
            return None if base is None else (base + dec["imm"]) & 0xFFFFFFFF
        if r["rd_we"] and r["rd"]:
            regs[r["rd"]] = r["rd_data"]
    return None


def judgements_pass(results):
    return all(ok for _name, ok, _detail in results)


# ---------------------------------------------------------------------------
# 波形 ↔ 指令流 的"按拍对齐"（0xAB 组合命令，2026-10-24）
# ---------------------------------------------------------------------------
# Core 探针 8 位的位序与 fpga/trace85/rtl/mes50hp_trace_top.v 里
#   core_probe_q <= {perf_retire,perf_flush,perf_stall,dr,dv,rv,ir,iv}
# 逐位一致：bit7 最高位 = 退休脉冲。
WAVE_LANES = (("提交", 0x80), ("冲刷", 0x40), ("停顿", 0x20), ("数据就绪", 0x10),
              ("数据请求", 0x08), ("取指响应", 0x04), ("取指就绪", 0x02), ("取指请求", 0x01))
CH_RETIRE, CH_FLUSH, CH_STALL, CH_DR, CH_DV, CH_RV, CH_IR, CH_IV = (m for _n, m in WAVE_LANES)
LA_CTRL_ADDR = 0x10002100        # LA 的 CONTROL：写 bit0 = arm，波形从下一条退休指令开始
TR_CTRL_ADDR = 0x10002200        # trace 的 CTRL：写 bit0 = arm（本命令里比 LA 先写）

_LOADS = ("lb", "lh", "lw", "lbu", "lhu")


def wave_lanes(wave):
    """把 8 位样本拆成 8 条 0/1 泳道，界面可以直接逐拍画。"""
    samples = wave["samples"]
    return [{"name": name, "mask": mask,
             "bits": [1 if v & mask else 0 for v in samples]}
            for name, mask in WAVE_LANES]


def _store_value_to(capture, addr):
    """找出"写这个 MMIO 地址、且 bit0 置起"的那条记录下标（arm 动作）。

    优先用 32 位还原地址；还原不出来（基址寄存器在窗口之前写过）就退回 12 位比较，
    并同时要求指令是 store——两条都满足才算命中，绝不猜。
    """
    hits = []
    for i, rec in enumerate(capture["records"]):
        if not rec["mem_we"]:
            continue
        dec = decode_rv32i(rec["instr"])
        if dec["mnemonic"] not in _STORE.values():
            continue
        full = _full_store_addr(capture["records"], i)
        if full is not None:
            if full != addr:
                continue
        elif (addr & 0xFFF) != (rec["mem_addr"] & 0xFFF):
            continue
        if rec["mem_data"] & 0x1:
            hits.append(i)
    return hits


def align_wave(capture, wave, nodes=None):
    """算"波形第 k 拍 ↔ trace 第几条记录"，并给出可复核的交叉校验。

    方法（全部可复核，不做任何推断）：
      1. 在 trace 里找 ``LA CONTROL = 1`` 那条 store —— 它就是"波形开始采样"的锚点；
         波形第 0 个样本是紧随其后的第一条退休指令，所以对齐点只可能是它或它的下一条。
      2. 波形里"退休脉冲"（bit7）的个数 C 就是这段波形窗口里退休了多少条指令，
         于是窗口覆盖的记录区间是 ``[offset, offset+C)``。
      3. **交叉校验**：波形里"数据请求有效 & 数据就绪"（bit3&bit4）的拍数，
         必须等于上面区间里"访存指令（load/store）"的条数。
         两条来源完全独立——一条来自 Core 的握手线，一条来自提交记录。
         候选偏移有多个时按这个校验挑；挑完仍不相等就如实报出差值。

    返回 dict：``offset``（窗口第一条记录的全局下标）、``cycles``（窗口拍数）、
    ``retire_pulses``、``data_pulses``、``data_records``、``mismatch``、``anchors``、``lanes``。
    """
    if nodes is None:
        nodes = build_flow(capture)["nodes"]
    recs = capture["records"]
    n = len(recs)
    samples = wave["samples"]
    pulses = sum(1 for v in samples if v & CH_RETIRE)
    data_pulses = sum(1 for v in samples if (v & CH_DV) and (v & CH_DR))

    def accesses(lo, hi):
        c = 0
        for nd in nodes[lo:hi]:
            if nd["mem_we"] or nd["mnemonic"] in _LOADS:
                c += 1
        return c

    anchors = _store_value_to(capture, LA_CTRL_ADDR)
    trace_arm = _store_value_to(capture, TR_CTRL_ADDR)
    cands = []
    for base in anchors or [0]:
        for delta in (0, 1, 2):
            off = base + delta
            if off < 0 or off + pulses > n:
                continue
            got = accesses(off, off + pulses)
            cands.append({"offset": off, "anchor": base, "delta": delta,
                          "data_records": got, "mismatch": abs(got - data_pulses)})
    if not cands:
        got = accesses(0, min(n, pulses))
        cands = [{"offset": 0, "anchor": (anchors or [None])[0], "delta": None,
                  "data_records": got, "mismatch": abs(got - data_pulses)}]
    # 物理上"LA 的 arm 写自己退休那一拍"就是第 0 个样本（arm 在 MEM 生效、退休脉冲在 WB），
    # 所以优先 delta=0；只有当数据（交叉校验）明确说别的偏移更吻合时才让步。
    # 多个偏移同样吻合时**如实记下来**，不装作唯一。
    zero_ok = [c for c in cands if c["mismatch"] == 0]
    if zero_ok:
        best = min(zero_ok, key=lambda c: (c["delta"] if c["delta"] is not None else 99,
                                           c["offset"]))
    else:
        best = min(cands, key=lambda c: (c["mismatch"],
                                         c["delta"] if c["delta"] is not None else 99))
    tied = sorted({c["delta"] for c in cands if c["mismatch"] == best["mismatch"]})
    return {
        "offset": best["offset"],
        "anchor": best["anchor"],
        "delta": best["delta"],
        "tied": tied,
        "ambiguous": len(tied) > 1,
        "trace_arm": trace_arm[0] if trace_arm else None,
        "cycles": len(samples),
        "div": wave.get("div", 1),
        "records": n,
        "retire_pulses": pulses,
        "data_pulses": data_pulses,
        "data_records": best["data_records"],
        "mismatch": best["mismatch"],
        "lanes": wave_lanes(wave),
    }


def judge_wave(capture, wave, nodes=None):
    """0xAB 组合采集的判据：两块自洽 + 按拍对齐能被独立信号证实。"""
    al = align_wave(capture, wave, nodes)
    out = []
    out.append(("波形样本数等于头部声明",
                wave["count"] == len(wave["samples"]),
                "count=%d，实际 %d 个" % (wave["count"], len(wave["samples"]))))
    out.append(("波形每拍一个样本（div=0）", al["div"] == 0,
                "div=%d（capture_engine 的 div=0 才是每拍采一次，否则拍号与指令对不上）"
                % al["div"]))
    out.append(("波形里确有退休脉冲", al["retire_pulses"] > 0,
                "窗口 %d 拍里数到 %d 个退休脉冲" % (al["cycles"], al["retire_pulses"])))
    n = al["records"]
    cover = al["offset"] + al["retire_pulses"] <= n
    out.append(("波形窗口整段落在 trace 里", cover,
                "窗口覆盖记录 #%d..#%d，trace 共 %d 条"
                % (al["offset"], al["offset"] + al["retire_pulses"] - 1, n)))
    # 覆盖率：波形窗口能有 512/1024/2048 拍，窗口越大覆盖的记录越多。
    # 实测 512 拍覆盖 316/323（97.8%）、2048 拍覆盖 1237/1247（99.2%），
    # 差的那几条是"LA 采满之后、trace 停之前"还在退休的指令——如实计数，不抹平。
    ratio = (al["retire_pulses"] / n) if n else 0.0
    out.append(("波形覆盖 trace 的绝大部分（≥95%）", ratio >= 0.95,
                "覆盖 %d/%d 条（%.1f%%）；窗口 %d 拍"
                % (al["retire_pulses"], n, 100.0 * ratio, al["cycles"])))
    out.append(("对齐锚点是 LA 的 arm 写",
                al["anchor"] is not None,
                "arm 写在第 %s 条（trace arm 在第 %s 条），取偏移 +%s%s"
                % (al["anchor"], al["trace_arm"], al["delta"],
                   "；候选 %r 同样吻合，故本枪对齐精度 ±1 条" % (al["tied"],)
                   if al["ambiguous"] else "")))
    out.append(("数据访问脉冲数 = 区间内访存指令数",
                al["mismatch"] == 0,
                "波形 %d 个 dv&dr 脉冲，记录 #%d..#%d 里 %d 条访存指令（差 %d）"
                % (al["data_pulses"], al["offset"],
                   al["offset"] + al["retire_pulses"] - 1, al["data_records"], al["mismatch"])))
    return out


def judge_text(results):
    lines = []
    for name, ok, detail in results:
        lines.append("%s %s — %s" % ("PASS" if ok else "FAIL", name, detail))
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 单页可视化
# ---------------------------------------------------------------------------
def page_payload(capture, flow, sent_text, phase, meta=None):
    """准备写进页面的 JSON。所有展示用字符串都由 Python 侧算好，页面不重复实现。"""
    nodes = flow["nodes"]
    payload = {
        "meta": dict(meta or {}),
        "phase": phase,
        "count": capture["count"],
        "status": capture["status"],
        "sent": sent_text,
        "text": "".join(chr(c) if 32 <= c < 127 else "." for c in capture["text"]),
        "xor": capture["xor"],
        "up": capture["up"],
        "nodes": nodes,
        "marks": capture["marks"],
        "regs_final": flow["regs_final"],
    }
    return payload


def write_trace_page(out_path, payload, template_path=None):
    tpl_path = Path(template_path) if template_path else Path(__file__).with_name("trace_viewer.html")
    tpl = tpl_path.read_text(encoding="utf-8")
    blob = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    if "__TRACE_DATA__" not in tpl:
        raise ValueError("模板里没有 __TRACE_DATA__ 占位符：%s" % tpl_path)
    html = tpl.replace("__TRACE_DATA__", blob)
    Path(out_path).write_text(html, encoding="utf-8")
    return Path(out_path)


# ---------------------------------------------------------------------------
# 命令行
# ---------------------------------------------------------------------------
def main(argv=None):
    import argparse

    ap = argparse.ArgumentParser(description="把提交级 trace 的回包日志变成单页可视化")
    ap.add_argument("--log", required=True, help="UART 回包日志（含 TRACE RAW 段）")
    ap.add_argument("--mem", default="fpga/trace85/rtl/logic_analyzer_program.mem",
                    help="位流里同一份程序镜像，用于 pc 与镜像同源对拍")
    ap.add_argument("--sent", default="hello,rv", help="这一枪发送的字符串")
    ap.add_argument("--phase", type=int, default=0, help="0=只记处理过程，1=连轮询一起记")
    ap.add_argument("--which", type=int, default=0, help="日志里有多枪时选第几枪（从 0 起）")
    ap.add_argument("--depth", type=int, default=4096,
                    help="窗口容量，必须与位流的 TRACE_DEPTH 一致（默认 4096）")
    ap.add_argument("--html", default="", help="输出 HTML 路径")
    args = ap.parse_args(argv)

    text = Path(args.log).read_text(encoding="utf-8", errors="replace")
    caps = iter_captures(text)
    if not caps:
        raise SystemExit("日志里没有可解析的 TRACE 段：%s" % args.log)
    cap = caps[min(args.which, len(caps) - 1)]
    imem = load_program_mem(args.mem) if Path(args.mem).exists() else None
    results = judge(cap, args.sent, args.phase, imem, depth=args.depth)
    print(judge_text(results))
    flow = build_flow(cap, imem)
    if args.html:
        payload = page_payload(cap, flow, args.sent, args.phase,
                               {"log": str(args.log), "mem": str(args.mem)})
        out = write_trace_page(args.html, payload)
        print("TRACE PAGE %s" % out)
    print("ALL TRACE VIEW JUDGEMENT PASS" if judgements_pass(results) else "TRACE VIEW JUDGEMENT FAIL")
    return 0 if judgements_pass(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
