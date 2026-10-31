#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""S4 收尾（第二处）：不可缓存读**绝不能写数据阵列**。

## 症状（集成 CoreMark，`CACHE_EN_D=1`）

影子内存逐笔比对报出的前三笔错读，全部集中在 **set 0 / word 0**，且**返回值都是 0x00000002**：

    WRONG DATA READ #1 cycles=1308187 addr=00008401 expected=66637263 got=00000002
      CACHE st=4 cacheable=1 aq=00008401 set=0 word=0 tag=00008400 hit=1 hit0=1
    WRONG DATA READ #2 cycles=1315420 addr=0000c000 expected=00132fa8 got=00000002
      CACHE st=4 cacheable=1 aq=0000c000 set=0 word=0 tag=0000c000 hit=1 hit1=1
    WRONG DATA READ #3 cycles=1316130 addr=00008002 expected=65726f43 got=00000002
      CACHE st=4 cacheable=1 aq=00008002 set=0 word=0 tag=00008000 hit=1 hit1=1

`0x00000002` 正是 **UART 状态寄存器**的值（CoreMark 的 `uart_send_char` 一直在轮询
`lw 0x10000004`）。而 `0x10000004` 算出来的 `set_q = addr[9:5] = 0`、`word_q = 0`
（第七轮为修直连把 `word_q` 在不可缓存时置 0）——**正好落在 set 0 / word 0**。

## 根因

`soc_dcache_2way.v` 的 `S_RFIL` 里，**数据阵列的写入没有用 `cacheable_q` 门控**：

    if (state == S_RFIL && m_beat_valid && m_beat_ready) begin
        if (victim == 32'd0) data0[set_q][fill_idx] <= m_beat_data;   // <-- 没有门控
        else                 data1[set_q][fill_idx] <= m_beat_data;
        ...
        if (m_beat_last) begin
            if (!m_beat_error && cacheable_q) begin                    // <-- 这里**有**门控
                ...tag/valid <= ...

于是对**不可缓存（MMIO 直连）读**：

- `tag/valid` 因为 `cacheable_q` 门控而**没有**被改（正确）；
- 但数据阵列**被写了**——把外设寄存器的值（UART 状态 `0x2`）写进了 `data[0][0]`。

结果 set 0 里那条**合法的**行 tag 依然命中，**数据却已经被外设寄存器的值悄悄改掉了**。
这就是"集成 CoreMark 输出被改坏、而模块级 TB 19 项全过"的原因：
模块级 TB 的存储模型只有 2048 字（0x0~0x1FFF），**根本寻址不到 0x8000~0xFFFF**，
也从来没有"MMIO 读把可缓存行改坏"这种交叉场景。

## 修法

把数据阵列的写入也用 `cacheable_q` 门控：不可缓存读只锁存 `rsp_rdata` 返回给 Core，
**不碰阵列**。

## 用法

    python scripts\\fix_dcache_bypass_data_array.py            # 修改
    python scripts\\fix_dcache_bypass_data_array.py --check    # 只检查
"""

import argparse
import io
import re
import sys

PATH = "rtl/soc_dcache_2way.v"

# 容错匹配：允许 `else` 与 `data1` 之间的空白数不同（不必逐格数空格）；
# 行尾必须用 `\r?\n`——本仓库的源文件是 CRLF，只写 `\n` 会匹配不到（踩过）。
PAT = re.compile(
    r"(?m)^([ \t]*)if \(victim == 32'd0\) data0\[set_q\]\[fill_idx\] <= m_beat_data;\r?\n"
    r"[ \t]*else[ \t]+data1\[set_q\]\[fill_idx\] <= m_beat_data;"
)

OLD_MARK = "if (victim == 32'd0) data0[set_q][fill_idx] <= m_beat_data;"
NEW_MARK = "if (cacheable_q) begin"

REPL = (
    "if (cacheable_q) begin\r\n"
    r"\1    if (victim == 32'd0) data0[set_q][fill_idx] <= m_beat_data;\r\n"
    r"\1    else                 data1[set_q][fill_idx] <= m_beat_data;\r\n"
    r"\1end"
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    with io.open(PATH, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()

    if args.check:
        # 幂等检查：门控已在数据阵列写入处出现，且裸写不再存在
        n_new = text.count(NEW_MARK)
        if n_new != 1:
            print("PROBLEM %s: expected 1 guarded data-array write, found %d" % (PATH, n_new))
            print("FIX DCACHE BYPASS DATA ARRAY FAILED")
            return 1
        print("FIX DCACHE BYPASS DATA ARRAY CHECK PASS (already applied)")
        return 0

    if text.count(NEW_MARK) == 1:
        print("FIX DCACHE BYPASS DATA ARRAY CHECK PASS (already applied)")
        return 0

    new_text, n = PAT.subn(REPL, text)
    if n != 1:
        print("PROBLEM %s: expected 1 match of the data-array write pair, found %d" % (PATH, n))
        print("FIX DCACHE BYPASS DATA ARRAY FAILED")
        return 1

    with io.open(PATH, "w", encoding="utf-8", newline="") as fh:
        fh.write(new_text)
    print("FIX DCACHE BYPASS DATA ARRAY APPLIED: " + PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
