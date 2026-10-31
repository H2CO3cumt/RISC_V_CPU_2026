# -*- coding: utf-8 -*-
"""列出模板 docx 的段落结构：序号、样式、自动编号、文字、是否含图片。"""
from __future__ import annotations

import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
DOCX = r"D:\RISC_V_CPU_2026\docs\技术文档模板.docx"


def text_of(p) -> str:
    out = []
    for t in p.iter(W + "t"):
        out.append(t.text or "")
    return "".join(out)


def main() -> None:
    with zipfile.ZipFile(DOCX) as z:
        print("=== zip 条目 ===")
        for n in z.namelist():
            print("  ", n)
        print()
        print("=== [Content_Types].xml ===")
        print(z.read("[Content_Types].xml").decode("utf-8"))
        print()
        print("=== _rels/document.xml.rels ===")
        print(z.read("word/_rels/document.xml.rels").decode("utf-8"))
        print()
        root = ET.fromstring(z.read("word/document.xml"))
        body = root.find(W + "body")
        print("=== body 段落 ===")
        idx = 0
        for child in body:
            tag = child.tag.replace(W, "")
            if tag == "p":
                ppr = child.find(W + "pPr")
                style = num = ""
                if ppr is not None:
                    st = ppr.find(W + "pStyle")
                    if st is not None:
                        style = st.get(W + "val") or ""
                    npr = ppr.find(W + "numPr")
                    if npr is not None:
                        ilvl = npr.find(W + "ilvl")
                        nid = npr.find(W + "numId")
                        num = f"numId={nid.get(W + 'val') if nid is not None else '?'}" \
                              f"/ilvl={ilvl.get(W + 'val') if ilvl is not None else '?'}"
                img = "IMG" if any(True for _ in child.iter(W + "drawing")) else ""
                txt = text_of(child).replace("\n", " ")
                print(f"[{idx:>3}] p  style={style:<3} {num:<20} {img:<3} {txt[:64]}")
                idx += 1
            elif tag == "tbl":
                print(f"[{idx:>3}] TABLE")
                idx += 1
            else:
                print(f"[{idx:>3}] <{tag}>")
                idx += 1


if __name__ == "__main__":
    main()
