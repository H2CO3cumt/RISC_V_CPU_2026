# -*- coding: utf-8 -*-
"""对比模板与生成件的页面级设置：背景、页眉页脚、页面尺寸与边距。"""
import re
import zipfile

TPL = r"D:\RISC_V_CPU_2026\docs\技术文档模板.docx"
GEN = r"D:\RISC_V_CPU_2026\docs\设计文档_RISC-V多协议逻辑分析仪.docx"


def dump(tag, path):
    z = zipfile.ZipFile(path)
    d = z.read("word/document.xml").decode("utf-8")
    print(f"--- {tag} ---")

    m = re.search(r"<w:background[^>]*/?>", d)
    print("  background:", m.group(0) if m else "(无)")

    i = d.rfind("<w:sectPr")
    sect = d[i:] if i >= 0 else ""
    refs = re.findall(r'<w:(header|footer)Reference[^>]*r:id="([^"]+)"', sect)
    print("  header/footer refs:", refs or "(无)")

    for t in ("w:pgSz", "w:pgMar", "w:cols", "w:docGrid"):
        mm = re.search(rf"<{t}[^>]*/>", sect)
        print(f"  {t}: {mm.group(0) if mm else '(无)'}")

    # 样式里 Normal 的字体字号
    st = z.read("word/styles.xml").decode("utf-8")
    mm = re.search(r'<w:style [^>]*w:styleId="1"[^>]*>(.*?)</w:style>', st, re.S)
    if mm:
        body = mm.group(1)
        fonts = re.search(r"<w:rFonts[^>]*/>", body)
        size = re.search(r'<w:sz w:val="(\d+)"', body)
        spacing = re.search(r"<w:spacing[^>]*/>", body)
        ind = re.search(r"<w:ind[^>]*/>", body)
        print("  Normal 字体:", fonts.group(0) if fonts else "(无)")
        print("  Normal 字号:", size.group(1) if size else "(无)",
              "| 行距:", spacing.group(0) if spacing else "(无)",
              "| 缩进:", ind.group(0) if ind else "(无)")

    # 生成件里我自己写的段落有没有 pStyle
    n_plain = len(re.findall(r"<w:p><w:pPr><w:ind", d))
    print("  自建段落数（无 pStyle 的）:", n_plain)
    print()


dump("模板", TPL)
dump("生成件", GEN)
