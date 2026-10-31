# -*- coding: utf-8 -*-
"""按文档顺序列出顶层段落，确认章节、插图与图注的相对位置正确。"""
import re
import zipfile

P = r"D:\RISC_V_CPU_2026\docs\设计文档_RISC-V多协议逻辑分析仪.docx"

with zipfile.ZipFile(P) as z:
    d = z.read("word/document.xml").decode("utf-8")

start = d.index("<w:body>") + len("<w:body>")
end = d.rindex("</w:body>")
inner = d[start:end]

elems = []
i = 0
while True:
    m = re.compile(r"<w:(p|tbl|sectPr)[ >/]").search(inner, i)
    if not m:
        break
    tag = m.group(1)
    if tag == "sectPr":
        close = inner.index("</w:sectPr>") + len("</w:sectPr>")
    elif tag == "p":
        close = inner.index("</w:p>", m.start()) + len("</w:p>")
    else:
        close = inner.index("</w:tbl>", m.start()) + len("</w:tbl>")
    elems.append((tag, inner[m.start():close]))
    i = close

print(f"顶层元素 {len(elems)} 个\n")
seq = []
for tag, raw in elems:
    if tag == "tbl":
        rows = raw.count("<w:tr>")
        seq.append(("TABLE", f"{rows} 行"))
        continue
    if tag == "sectPr":
        seq.append(("SECT", ""))
        continue
    has_img = "<w:drawing>" in raw
    text = "".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", raw, re.S)).strip()
    if has_img:
        seq.append(("IMG", text or "(无文字)"))
    elif text:
        seq.append(("TXT", text[:46]))

for n, (kind, txt) in enumerate(seq):
    mark = {"IMG": "🖼", "TABLE": "▦", "SECT": "»"}.get(kind, "  ")
    print(f"{n:>3} {mark} {kind:<5} {txt}")

# 检查每张图后面是否紧跟图注
bad = []
for n, (kind, txt) in enumerate(seq):
    if kind != "IMG":
        continue
    nxt = seq[n + 1] if n + 1 < len(seq) else ("", "")
    if not (nxt[0] == "TXT" and nxt[1].startswith("图")):
        bad.append((n, nxt))
print()
if bad:
    print("✗ 图后未紧跟图注：", bad)
else:
    print("✓ 每张图后都紧跟图注")
