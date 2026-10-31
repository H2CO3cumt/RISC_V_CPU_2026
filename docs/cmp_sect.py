# -*- coding: utf-8 -*-
"""看模板首节设置与三个页眉/页脚的真实内容。"""
import re
import zipfile

TPL = r"D:\RISC_V_CPU_2026\docs\技术文档模板.docx"
GEN = r"D:\RISC_V_CPU_2026\docs\设计文档_RISC-V多协议逻辑分析仪.docx"


def sect(path, tag):
    z = zipfile.ZipFile(path)
    d = z.read("word/document.xml").decode("utf-8")
    i = d.rfind("<w:sectPr")
    j = d.find("</w:sectPr>", i)
    s = d[i:j + 11]
    print(f"===== {tag} 完整 sectPr =====")
    print(s.replace("><", ">\n<"))
    print("titlePg:", "有" if "<w:titlePg" in s else "无")
    print()
    for n in sorted(z.namelist()):
        if re.match(r"word/header\d*\.xml$", n) or re.match(r"word/footer\d*\.xml$", n):
            x = z.read(n).decode("utf-8")
            txt = "".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", x, re.S))
            img = re.findall(r'r:embed="([^"]+)"', x)
            print(f"  {n}: 文字={txt[:40]!r} 图片引用={img} 长度={len(x)}")
    print()


sect(TPL, "模板")
sect(GEN, "生成件")
