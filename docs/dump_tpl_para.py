# -*- coding: utf-8 -*-
import re
import zipfile

z = zipfile.ZipFile(r"D:\RISC_V_CPU_2026\docs\技术文档模板.docx")
d = z.read("word/document.xml").decode("utf-8")
out, i = [], 0
while True:
    m = re.compile(r"<w:p[ >]").search(d, i)
    if not m:
        break
    c = d.index("</w:p>", m.start()) + len("</w:p>")
    out.append(d[m.start():c])
    i = c

for idx in (1, 3, 7, 28):
    p = out[idx]
    txt = "".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", p, re.S))
    print(f"--- 模板第 {idx} 段: {txt[:34]!r} ---")
    m = re.search(r"<w:pPr>.*?</w:pPr>", p, re.S)
    print("pPr:", m.group(0) if m else "(无)")
    tail = p.split("</w:pPr>")[-1]
    m2 = re.search(r"<w:rPr>.*?</w:rPr>", tail, re.S)
    print("run rPr:", m2.group(0) if m2 else "(无)")
    print()
