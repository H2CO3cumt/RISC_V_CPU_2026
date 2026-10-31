# -*- coding: utf-8 -*-
"""校验生成的 docx：残留标记、富文本、图片与编号。"""
import re
import zipfile

P = r"D:\RISC_V_CPU_2026\docs\设计文档_RISC-V多协议逻辑分析仪.docx"

with zipfile.ZipFile(P) as z:
    d = z.read("word/document.xml").decode("utf-8")
    media = [n for n in z.namelist() if n.startswith("word/media/")]
    rels = z.read("word/_rels/document.xml.rels").decode("utf-8")
    ctypes = z.read("[Content_Types].xml").decode("utf-8")

text = "".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", d, re.S))
print(f"正文提取字符数: {len(text)}")

checks = {
    "加粗标记 **": "**",
    "行内代码反引号": "`",
    "图片语法 ![": "![",
    "链接语法 ](": "](",
    "全角空格残留": "\u3000",
}
for name, token in checks.items():
    n = text.count(token)
    print(f"{'✓' if n == 0 else '✗'} {name}: {n}")

print(f"\n媒体文件: {len(media)} 个")
print(f"关系条目: {rels.count('<Relationship ')} 条")
print(f"图片关系: {rels.count('relationships/image')} 条")
print(f"jpg 内容类型已注册: {'Extension=\"jpg\"' in ctypes}")

bold_runs = d.count("<w:b/>")
print(f"加粗运行: {bold_runs} 处")

i = text.find("关键词")
print("\n关键词上下文:", text[max(0, i - 24):i + 50])
j = text.find("CoreMark 与分支预测收益")
print("3.3 小标题上下文:", text[max(0, j - 20):j + 30])

# 检查图片是否都有 caption 跟随
figs = re.findall(r'name="(fig_\d+\.\w+)"', d)
print(f"\n内嵌图片引用: {len(figs)} 次")
caps = re.findall(r"图\s*[123]-\d+", text)
print(f"图注编号出现: {len(caps)} 次 -> {sorted(set(caps))}")
