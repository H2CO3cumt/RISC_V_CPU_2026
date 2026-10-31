# -*- coding: utf-8 -*-
"""对比模板正文段落与生成件正文段落的 pPr / rPr。"""
import re
import zipfile

TPL = r"D:\RISC_V_CPU_2026\docs\技术文档模板.docx"
GEN = r"D:\RISC_V_CPU_2026\docs\设计文档_RISC-V多协议逻辑分析仪.docx"


def paras(path):
    z = zipfile.ZipFile(path)
    d = z.read("word/document.xml").decode("utf-8")
    out = []
    i = 0
    while True:
        m = re.compile(r"<w:p[ >]").search(d, i)
        if not m:
            break
        close = d.index("</w:p>", m.start()) + len("</w:p>")
        out.append(d[m.start():close])
        i = close
    return out


tpl = paras(TPL)
gen = paras(GEN)

print("=== 模板：'400字内（可加重要图）；' 这段（正文样例）===")
for p in tpl:
    if "400" in p and "字内" in p:
        print(p[:700])
        break

print()
print("=== 生成件：1.1 的第一段正文 ===")
for p in gen:
    if "处理器执行完整 RV32I 基础整数指令集" in p:
        print(p[:700])
        break

print()
print("=== 模板：Normal / 列表段落 样式定义 ===")
z = zipfile.ZipFile(TPL)
st = z.read("word/styles.xml").decode("utf-8")
for sid in ("1", "12"):
    m = re.search(rf'<w:style [^>]*w:styleId="{sid}"[^>]*>(.*?)</w:style>', st, re.S)
    if m:
        print(f"--- styleId={sid} ---")
        print(m.group(0)[:600])
        print()
