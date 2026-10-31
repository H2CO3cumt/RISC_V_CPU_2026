# -*- coding: utf-8 -*-
import re
import zipfile

GEN = r"D:\RISC_V_CPU_2026\docs\设计文档_RISC-V多协议逻辑分析仪.docx"
MD = r"D:\RISC_V_CPU_2026\docs\design_document.md"

d = zipfile.ZipFile(GEN).read("word/document.xml").decode("utf-8")
print("=== docx 中 CoreMark/MHz 附近的运行 ===")
for m in re.finditer(r"CoreMark/MHz", d):
    seg = d[max(0, m.start() - 120):m.start() + 260]
    print(repr(seg))
    print("-" * 60)

print()
print("=== markdown 源里的那一句 ===")
md = open(MD, encoding="utf-8").read()
i = md.find("CoreMark/MHz 0.936")
print(repr(md[i - 60:i + 80]) if i > 0 else "未找到")

print()
print("=== 检查是否有连续两个空格被折叠 ===")
i2 = md.find("CoreMark/MHz")
print(repr(md[i2:i2 + 40]))
