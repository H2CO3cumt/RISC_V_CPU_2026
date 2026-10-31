# -*- coding: utf-8 -*-
"""设计文档自检：字数、图片路径、去 AI 腔清单、标点纪律。

用法：python check_design_doc.py
"""
from __future__ import annotations

import pathlib
import re

DOC = pathlib.Path(r"D:\RISC_V_CPU_2026\docs\design_document.md")
FIG = pathlib.Path(r"D:\RISC_V_CPU_2026\docs\figures")

CJK = re.compile(r"[\u4e00-\u9fff]")
LATIN_WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/%×+-]*")

# 模板字数上限（None = 无限制）
LIMITS = {
    "摘要": 800,
    "1.1 功能与特性": 400,
    "1.2 应用领域": 400,
    "1.3 主要技术特点": 400,
    "1.4 主要性能指标": 200,
    "1.5 主要创新点": 200,
    "1.6 设计流程": 200,
    "2.1 整体介绍": None,
    "2.2.1 硬件整体介绍": None,
    "2.2.2 机械设计介绍": None,
    "2.2.3 电路各模块介绍": None,
    "2.3.1 软件整体介绍": None,
    "2.3.2 软件各模块介绍": None,
    "3.1 整体介绍": None,
    "3.2.1 机械成果": None,
    "3.2.2 电路成果": None,
    "3.2.3 软件成果": None,
    "3.3 特性成果": None,
    "4.1 可扩展之处": 300,
    "4.2 心得体会": 1000,
}

# writing_style.md §9.2 清单：正面命中的固定套话
SLOP_WORDS = [
    "随着", "在当今", "值得注意的是", "综上所述", "总而言之", "通过本次设计",
    "深刻认识到", "希望对大家", "未来可期", "关键在哪里", "答案很简单",
    "原因其实很直接", "强大", "灵活", "无缝", "全面", "极致", "优雅", "一站式",
    "赋能", "抓手", "底座", "颗粒度", "起到了", "在某种程度上", "在一定情况下",
    "这一节我们", "接下来进入正题", "先把这件事", "作为一个", "通过……的方式",
]

# 清单里的“句式”类禁令，用正则表达，避免把技术性的否定句误判
SLOP_PATTERNS = [
    (r"与其说[^。]{0,40}不如说", "与其说 A，不如说 B"),
    (r"不是[^。]{0,30}，?而是", "不是 A，而是 B"),
    (r"不仅[^。]{0,24}更", "不仅……更……"),
    (r"不仅[^。]{0,24}而且", "不仅……而且……"),
    (r"综上所述|总而言之", "结尾套话"),
    (r"这一节我们来看|接下来进入正题", "主持腔过场句"),
    (r"进行了[^。]{0,10}(修改|优化|测试|设计)", "翻译腔「进行 + 动词」"),
]


def strip_markup(text: str) -> str:
    """去掉图片、行内代码、围栏代码块与表格，只留正文。"""
    body = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)
    body = re.sub(r"```.*?```", "", body, flags=re.S)
    body = re.sub(r"`[^`]*`", "", body)
    return body


def extract_sections(text: str) -> dict[str, str]:
    """按标题切分，键为标题文字。"""
    sections: dict[str, list[str]] = {}
    cur = "_front"
    sections[cur] = []
    for line in text.splitlines():
        m = re.match(r"^(#{2,4})\s+(.+?)\s*$", line)
        if m:
            cur = m.group(2).strip()
            sections.setdefault(cur, [])
            continue
        sections[cur].append(line)
    return {k: "\n".join(v) for k, v in sections.items()}


def count(text: str) -> int:
    """中文按字计，英文与数字按词计。"""
    body = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)   # 去图片
    body = re.sub(r"^\s*\|.*$", "", body, flags=re.M)  # 去表格
    body = re.sub(r"^>.*$", "", body, flags=re.M)      # 去引用注
    return len(CJK.findall(body)) + len(LATIN_WORD.findall(body))


def main() -> int:
    text = DOC.read_text(encoding="utf-8")
    sections = extract_sections(text)
    problems: list[str] = []

    print("=== 字数核对（模板上限 vs 实际）===")
    key_map = {}
    for title in sections:
        for name in LIMITS:
            if title.startswith(name):
                key_map[title] = name
    for title, content in sections.items():
        name = key_map.get(title)
        if name is None:
            continue
        n = count(content)
        lim = LIMITS[name]
        flag = ""
        if lim is not None and n > lim:
            flag = "  ✗ 超限"
            problems.append(f"{name} 超限：{n} > {lim}")
        elif lim is not None:
            flag = f"  ✓（余 {lim - n}）"
        print(f"{name:<22} {n:>5} 字" + (f"  上限 {lim}" if lim else "  无上限") + flag)

    total = sum(count(v) for k, v in sections.items()
                if k in key_map and key_map[k] not in ("摘要",)
                and not k.startswith("第五部分"))
    print(f"{'正文合计（不含摘要与文献）':<22} {total:>5} 字")

    print("\n=== 图片路径核对 ===")
    imgs = re.findall(r"!\[([^\]]*)\]\(([^)]+)\)", text)
    for alt, path in imgs:
        target = (DOC.parent / path).resolve()
        ok = target.exists()
        print(f"{'✓' if ok else '✗'} {alt:<34} {path}")
        if not ok:
            problems.append(f"图片缺失：{path}")
    print(f"共 {len(imgs)} 张插图")

    print("\n=== 去 AI 腔清单核对 ===")
    body = strip_markup(text)
    found_any = False
    for word in SLOP_WORDS:
        cnt = body.count(word)
        if cnt:
            found_any = True
            print(f"命中套话：{word} × {cnt}")
            problems.append(f"去 AI 腔命中：{word} × {cnt}")
    for pat, label in SLOP_PATTERNS:
        hits = re.findall(pat, body)
        if hits:
            found_any = True
            print(f"命中句式：{label} × {len(hits)}")
            problems.append(f"去 AI 腔命中句式：{label} × {len(hits)}")
    if not found_any:
        print("未命中禁用写法")

    print("\n=== 标点与体例核对 ===")
    checks = [
        ("英文省略号 ...", r"\.\.\."),
        ("半角感叹号 !", r"(?<![\[\w])!(?!=)"),
        ("中文后紧跟半角括号", r"[\u4e00-\u9fff]\("),
        ("半角括号包裹中文", r"\([\u4e00-\u9fff]"),
        ("中英之间缺空格", r"[\u4e00-\u9fff][A-Za-z]"),
        ("重复空格", r"  +"),
    ]
    no_fence = re.sub(r"```.*?```", "", text, flags=re.S)
    for name, pat in checks:
        # 空白检查看原文（去掉围栏代码块），其它检查看去掉标记后的正文
        source = no_fence if name == "重复空格" else body
        found = re.findall(pat, source)
        if found:
            print(f"注意：{name} × {len(found)}")
            problems.append(f"{name} × {len(found)}")
        else:
            print(f"✓ 无{name}")

    print("\n=== 结论 ===")
    if problems:
        print(f"发现 {len(problems)} 项待处理：")
        for p in problems:
            print("  -", p)
        return 1
    print("全部检查通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
