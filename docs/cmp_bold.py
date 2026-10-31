# -*- coding: utf-8 -*-
"""检查生成件里模板原有段落的加粗是否保留，以及正文段落与模板的样式差异。"""
import re
import zipfile

TPL = r"D:\RISC_V_CPU_2026\docs\技术文档模板.docx"
GEN = r"D:\RISC_V_CPU_2026\docs\设计文档_RISC-V多协议逻辑分析仪.docx"


def paras(path):
    z = zipfile.ZipFile(path)
    d = z.read("word/document.xml").decode("utf-8")
    out, i = [], 0
    while True:
        m = re.compile(r"<w:p[ >]").search(d, i)
        if not m:
            break
        close = d.index("</w:p>", m.start()) + len("</w:p>")
        out.append(d[m.start():close])
        i = close
    return out


print("=== 模板里 '功能与特性' 那段 ===")
for p in paras(TPL):
    if "功能与特性" in p:
        print(p[:520])
        break

print()
print("=== 生成件里 '功能与特性' 那段 ===")
for p in paras(GEN):
    if "功能与特性" in p:
        print(p[:520])
        break

print()
print("=== 统计：生成件正文段落的字号分布 ===")
sizes = {}
styles = {}
for p in paras(GEN):
    m = re.search(r'<w:sz w:val="(\d+)"', p)
    sizes[m.group(1) if m else "继承"] = sizes.get(m.group(1) if m else "继承", 0) + 1
    m2 = re.search(r'<w:pStyle w:val="(\d+)"', p)
    styles[m2.group(1) if m2 else "无pStyle"] = styles.get(m2.group(1) if m2 else "无pStyle", 0) + 1
print("字号:", sizes)
print("样式:", styles)
