# -*- coding: utf-8 -*-
"""清空 docx 的作者类属性，并删除模板自带的 custom.xml。

用途：在 Word 里改完正文并保存后，Word 会把“最后修改者”写成 Windows 账号名。
交稿前跑一次这个脚本即可复位：

    python docs/clear_docx_author.py "docs/设计文档_RISC-V多协议逻辑分析仪.docx"
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile

KEEP_TITLE = "RISC-V 多协议逻辑分析仪 技术文档"


def clean(path: str) -> None:
    src = zipfile.ZipFile(path)
    items = {n: src.read(n) for n in src.namelist()}
    src.close()

    now = __import__("datetime").datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%SZ")
    items["docProps/core.xml"] = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<cp:coreProperties '
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        f"<dc:title>{KEEP_TITLE}</dc:title>"
        '<cp:revision>1</cp:revision>'
        f'<dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>'
        f'<dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>'
        "</cp:coreProperties>"
    ).encode("utf-8")

    items.pop("docProps/custom.xml", None)
    if "_rels/.rels" in items:
        rels = items["_rels/.rels"].decode("utf-8")
        rels = re.sub(r'<Relationship[^>]*custom\.xml"[^>]*/>', "", rels)
        items["_rels/.rels"] = rels.encode("utf-8")

    order = [n for n in items if not n.endswith("/")]
    shutil.move(path, path + ".bak")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n in order:
            z.writestr(n, items[n])
    print(f"已清理作者属性：{path}")
    print(f"原件备份：{path}.bak")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(2)
    clean(sys.argv[1])
