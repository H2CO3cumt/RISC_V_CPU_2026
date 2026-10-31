#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""S4 收尾：修 D-Cache 的 uncacheable（MMIO/直连）通路。

## 背景：为什么必须修

`docs/interfaces.md` 规定 **MMIO 区域始终 uncacheable**，
所以 D-Cache 必须能把 MMIO 事务**原样透传**。CoreMark 第一次访问 MMIO 是在
`uart_send_char`（`pc=0x3c: lw a5,0(a4)`，a4=0x10000004），集成后死在那里。

追踪到的第一个错误点是 **D-Cache 的直连读通路**有两处缺陷：

1. **锁存位置错**：`word_q <= pend_addr[LINE_BITS-1:2]` 是"行内第几个字"。
   对可缓存访问，下游从**行首**开始连发，这个索引正好对上；
   但直连读的下游是**从请求字本身**开始发的（`m_rd_len=0`，只发一个字），
   此时 `word_q` 仍然等于 `addr[4:2]`，于是 `fill_idx == word_q` 永远对不上
   （0x10000004 的 addr[4:2]=1，而实际只会有 fill_idx=0 那一拍），
   读回的是**陈旧/错字**。→ 修：非可缓存时锁存位置一律取 0。

2. **适配器不认 `m_rd_len`**：`m_rd_len` 是"本次要取几个字 - 1"
   （可缓存 = 7，直连 = 0）。`dcache_coremark_adapter` 却无视它，
   永远取满 `LINE_WORDS`=8 个字，并按 8 拍连发。
   对 MMIO 就是**越界读 8 个字**：0x10000004 之后的地块没有设备应答，
   适配器永远等不到响应 → Cache 永远等不到 `m_beat_last` → 死锁。
   → 修：按 `m_rd_len` 决定取几个字（`lf_words = m_rd_len + 1`）。

3. 顺带加固：读命中判定必须**先看可缓存性**。
   原判据 `else if (hit)` 没有门控 `cacheable_q`，
   目前靠"可缓存地址都 ≤0xFFFF、tag 不会撞上 MMIO 的 tag"侥幸不炸，
   属于隐患。→ 修：`else if (cacheable_q && hit)`。

## 用法

    python scripts\\fix_dcache_mmio_bypass.py            # 修改
    python scripts\\fix_dcache_mmio_bypass.py --check    # 只检查，不改
"""

import argparse
import io
import sys

EDITS = [
    (
        "rtl/soc_dcache_2way.v",
        [
            # (旧, 新, 期望出现次数)
            # 【1】直连读的锁存位置：非可缓存时下游只发请求字那一拍
            (
                "word_q      <= pend_addr[LINE_BITS-1:2];",
                "word_q      <= pend_cacheable ? pend_addr[LINE_BITS-1:2] : {WORD_BITS{1'b0}};",
                1,
            ),
            # 【3】读命中必须先看可缓存性：MMIO 绝不允许命中 Cache
            (
                "else if (hit) begin",
                "else if (cacheable_q && hit) begin",
                1,
            ),
        ],
    ),
    (
        "tb/dcache_coremark_adapter.v",
        [
            # 【2a】声明本次要取的字数（-1）
            (
                "    reg [3:0]      lf_feed;",
                "    reg [3:0]      lf_feed;\n"
                "    reg [7:0]      lf_len;          // 本次请求要取几个字 - 1（= Cache 的 m_rd_len）",
                1,
            ),
            # 【2b】实际字数 = lf_len + 1
            (
                "    wire [31:0] lf_out = lf_buf[lf_feed];",
                "    wire [31:0] lf_out = lf_buf[lf_feed];\n"
                "    wire [7:0]  lf_words = lf_len + 8'd1;   // 本次要取/要喂的字数",
                1,
            ),
            # 【2c】复位
            (
                "\n            lf_feed        <= 4'd0;",
                "\n            lf_feed        <= 4'd0;\n            lf_len         <= 8'd0;",
                1,
            ),
            # 【2d】行请求被接受时锁存字数
            (
                "\n                        lf_feed        <= 4'd0;",
                "\n                        lf_feed        <= 4'd0;\n"
                "                        lf_len         <= c_rd_len;",
                1,
            ),
            # 【2e】取行结束判据
            (
                "if (lf_idx == (LINE_WORDS - 1)) begin",
                "if (lf_idx == (lf_words - 8'd1)) begin",
                1,
            ),
            # 【2f】喂完判据
            (
                "if (lf_feed == (LINE_WORDS - 1)) begin",
                "if (lf_feed == (lf_words - 8'd1)) begin",
                1,
            ),
            # 【2g】last 标志
            (
                "assign c_beat_last  = (lf_state == LF_FEED) && (lf_feed == (LINE_WORDS - 1));",
                "assign c_beat_last  = (lf_state == LF_FEED) && (lf_feed == (lf_words - 8'd1));",
                1,
            ),
        ],
    ),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只检查，不写回")
    args = ap.parse_args()

    problems = []
    changed = []
    for path, edits in EDITS:
        with io.open(path, "r", encoding="utf-8", newline="") as fh:
            text = fh.read()
        orig = text
        for old, new, want in edits:
            got_old = text.count(old)
            got_new = text.count(new)
            if args.check:
                # --check 校验的是"新文本在位"（幂等检查），不是"旧文本还在"。
                if got_new != want:
                    problems.append("%s: expected %d occurrence(s) of NEW %r, found %d"
                                    % (path, want, new[:60], got_new))
                continue
            if got_old != want:
                problems.append("%s: expected %d occurrence(s) of %r, found %d"
                                % (path, want, old[:60], got_old))
                continue
            text = text.replace(old, new, want)
        if text != orig:
            changed.append(path)
            if not args.check:
                with io.open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(text)

    for p in problems:
        print("PROBLEM " + p)
    if problems:
        print("FIX DCACHE MMIO BYPASS FAILED")
        return 1
    if changed:
        print("FIX DCACHE MMIO BYPASS %s: %s"
              % ("CHECKED (no write)" if args.check else "APPLIED", ", ".join(changed)))
    else:
        print("FIX DCACHE MMIO BYPASS CHECK PASS (already applied)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
