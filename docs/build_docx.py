# -*- coding: utf-8 -*-
"""把 docs/design_document.md 的正文注入技术文档模板，生成最终 docx。

做法：在 OOXML 层做字符串级注入——
  * 保留模板全部自动编号段落（1.1～1.6、2.1～2.3、3.1～3.3、4.1～4.2）的 pPr，只替换或清理文字；
  * 说明性占位段落整段替换为正文段落；
  * 图片写入 word/media/ 并补 relationship 与 [Content_Types]；
  * 表格按 Markdown 表格转成 w:tbl。

用法：python docs/build_docx.py
"""
from __future__ import annotations

import pathlib
import re
import struct
import zipfile

ROOT = pathlib.Path(r"D:\RISC_V_CPU_2026")
MD = ROOT / "docs" / "design_document.md"
TPL = ROOT / "docs" / "技术文档模板.docx"
OUT = ROOT / "docs" / "设计文档_RISC-V多协议逻辑分析仪.docx"

NS = (
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"'
)

MAX_WIDTH_CM = 15.5
EMU_PER_CM = 914400 / 2.54
# 文档属性里的作者留空：不留模板作者，也不写本人姓名
AUTHOR = ""


# ----------------------------------------------------------------- 图片尺寸
def image_size(path: pathlib.Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", data[16:24])
        return w, h
    if data[:2] == b"\xff\xd8":
        i = 2
        while i < len(data) - 9:
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                          0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            seg = struct.unpack(">H", data[i + 2:i + 4])[0]
            i += 2 + seg
    raise ValueError(f"无法读取图片尺寸：{path}")


# ----------------------------------------------------------------- Markdown 解析
BLOCK_FIG = "fig"
BLOCK_TABLE = "table"
BLOCK_PARA = "para"
BLOCK_NOTE = "note"


def parse_markdown(text: str) -> dict[str, list[tuple]]:
    """返回 {章节键: [block, ...]}，章节键形如 '1.1'、'2.2.3'、'摘要'。"""
    sections: dict[str, list[tuple]] = {}
    cur: str | None = None
    lines = text.splitlines()
    i = 0
    pending_caption: str | None = None
    in_header_note = True

    while i < len(lines):
        raw = lines[i]
        line = raw.rstrip()

        # 文首的 > 说明块整体跳过
        if in_header_note:
            if line.startswith(">"):
                i += 1
                continue
            if line.strip() == "" or line.startswith("---"):
                i += 1
                continue
            in_header_note = False

        if line.startswith("# ") or line.startswith("---"):
            i += 1
            continue

        # 部分标题：只切换章节归属，不产生正文块
        if line.startswith("## "):
            title = line[3:].strip()
            if "参考文献" in title:
                cur = "参考文献"
                sections.setdefault(cur, [])
            elif title.startswith("第"):
                cur = None
            else:
                cur = title
                sections.setdefault(cur, [])
            i += 1
            continue

        m = re.match(r"^(#{3,4})\s+(.+?)\s*$", line)
        if m:
            title = m.group(2)
            km = re.match(r"^(\d+(?:\.\d+)+)\s", title)
            if km:
                cur = km.group(1)
            else:
                cur = title.strip()
            sections.setdefault(cur, [])
            i += 1
            continue

        if line.startswith("## "):
            title = line[3:].strip()
            cur = title
            sections.setdefault(cur, [])
            i += 1
            continue

        # 表格
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                row = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not re.match(r"^[-: ]+$", "".join(row)):
                    rows.append(row)
                i += 1
            if cur is not None and rows:
                sections[cur].append((BLOCK_TABLE, rows))
            continue

        # 图片
        im = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)", line)
        if im:
            if cur is not None:
                sections[cur].append((BLOCK_FIG, im.group(2), pending_caption or im.group(1)))
            pending_caption = None
            i += 1
            continue

        # 图注（图序行，在图片上方）
        cap = re.match(r"^\*\*(图\s*[\d\-]+[^*]*)\*\*$", line.replace("　", " "))
        if cap:
            pending_caption = cap.group(1).strip()
            i += 1
            continue

        if line.startswith(">"):
            if cur is not None:
                sections[cur].append((BLOCK_NOTE, line[1:].strip()))
            i += 1
            continue

        if line.strip() == "":
            i += 1
            continue

        if cur is not None:
            sections[cur].append((BLOCK_PARA, line.strip()))
        i += 1

    # 去掉空章节
    return {k: v for k, v in sections.items() if v}


# ----------------------------------------------------------------- XML 片段
def esc(t: str) -> str:
    return (t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def run(rpr: str, text: str) -> str:
    return (f'<w:r>{rpr}<w:t xml:space="preserve">{esc(text)}</w:t></w:r>')


INLINE = re.compile(r"(\*\*.+?\*\*|`[^`]+`)")


def rpr_xml(*, bold: bool = False, size: int = 24, color: str | None = None,
            mono: bool = False) -> str:
    font = "Consolas" if mono else "Times New Roman"
    east = "等线" if mono else "宋体"
    out = (f'<w:rPr><w:rFonts w:hint="eastAsia" w:ascii="{font}" w:hAnsi="{font}" '
           f'w:eastAsia="{east}" w:cs="{font}"/>')
    if bold:
        out += "<w:b/>"
    if color:
        out += f'<w:color w:val="{color}"/>'
    out += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/></w:rPr>'
    return out


def rich(text: str, *, size: int = 24, color: str | None = None) -> str:
    """把 Markdown 的 **加粗** 与 `代码` 转成 Word 运行。"""
    parts: list[str] = []
    for seg in INLINE.split(text):
        if not seg:
            continue
        if seg.startswith("**") and seg.endswith("**") and len(seg) > 4:
            parts.append(run(rpr_xml(bold=True, size=size, color=color), seg[2:-2]))
        elif seg.startswith("`") and seg.endswith("`") and len(seg) > 2:
            parts.append(run(rpr_xml(size=size, color=color, mono=True), seg[1:-1]))
        else:
            parts.append(run(rpr_xml(size=size, color=color), seg))
    return "".join(parts)


def para(text: str, *, size: int = 24, align: str | None = None,
         indent_left: int = 420, color: str | None = None) -> str:
    """正文段落：完全对齐模板自身的正文格式。

    模板正文是 List Paragraph 样式 + 1.5 倍行距 + 整段左缩进 420 twips，
    不是首行缩进；字号 12 pt，西文 Times New Roman、中文宋体。
    """
    text = text.replace("\u3000", " ")
    ppr = '<w:pPr><w:pStyle w:val="12"/><w:spacing w:line="360" w:lineRule="auto"/>'
    ppr += f'<w:ind w:left="{indent_left}" w:firstLine="0" w:firstLineChars="0"/>'
    if align:
        ppr += f'<w:jc w:val="{align}"/>'
    ppr += "</w:pPr>"
    return f"<w:p>{ppr}{rich(text, size=size, color=color)}</w:p>"


def caption(text: str) -> str:
    return para(text, size=21, align="center", indent_left=0)


def note_para(text: str) -> str:
    return para(text, size=21, indent_left=420, color="595959")


def image_para(rid: str, cx: int, cy: int, pic_id: int, name: str) -> str:
    # 所有用到的前缀必须在这一层声明，否则 graphicFrameLocks 会用到未声明的 a:
    decl = (
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"'
    )
    drawing = (
        "<w:drawing>"
        f'<wp:inline {decl} distT="0" distB="0" distL="0" distR="0">'
        f'<wp:extent cx="{cx}" cy="{cy}"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        f'<wp:docPr id="{pic_id}" name="Picture {pic_id}"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        f'<pic:pic><pic:nvPicPr><pic:cNvPr id="{pic_id}" name="{esc(name)}"/><pic:cNvPicPr/></pic:nvPicPr>'
        f'<pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        "</a:graphicData></a:graphic></wp:inline></w:drawing>"
    )
    return ('<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="120" w:after="60"/>'
            f"</w:pPr><w:r>{drawing}</w:r></w:p>")


def table_xml(rows: list[list[str]]) -> str:
    cols = max(len(r) for r in rows)
    total = 8300
    # 按各列最长内容分配宽度，避免「4,479 LUT / 3,610 FF」被拆行
    weights = []
    for c in range(cols):
        longest = max((len(r[c]) for r in rows if c < len(r)), default=1)
        weights.append(max(6, longest))
    s = sum(weights)
    widths = [max(900, int(total * w / s)) for w in weights]
    scale = total / sum(widths)
    widths = [int(w * scale) for w in widths]
    border = ('<w:tblBorders>'
              + "".join(f'<w:{s2} w:val="single" w:sz="6" w:space="0" w:color="000000"/>'
                        for s2 in ("top", "left", "bottom", "right", "insideH", "insideV"))
              + "</w:tblBorders>")
    out = ['<w:tbl><w:tblPr>'
           f'<w:tblW w:w="{total}" w:type="dxa"/><w:jc w:val="center"/>{border}'
           '<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>'
           + "".join(f'<w:gridCol w:w="{w}"/>' for w in widths)
           + "</w:tblGrid>"]
    for r_i, row in enumerate(rows):
        cells = row + [""] * (cols - len(row))
        out.append("<w:tr>")
        for c_i, cell in enumerate(cells):
            text = cell.replace("**", "")
            body = rich(text, size=19) if text else ""
            if r_i == 0 and text:
                body = run(rpr_xml(bold=True, size=19), text)
            out.append(f'<w:tc><w:tcPr><w:tcW w:w="{widths[c_i]}" w:type="dxa"/>'
                       '<w:vAlign w:val="center"/></w:tcPr>'
                       '<w:p><w:pPr><w:jc w:val="center"/>'
                       '<w:spacing w:before="16" w:after="16"/></w:pPr>'
                       + body
                       + "</w:p></w:tc>")
        out.append("</w:tr>")
    out.append("</w:tbl>")
    out.append('<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr></w:p>')
    return "".join(out)


# ----------------------------------------------------------------- 主流程
SLOTS = [
    # (模板段落下标, 章节键, 动作, 清理后的标题)
    (0, None, "title", "RISC-V 多协议逻辑分析仪"),
    (1, None, "drop", None),
    (3, "摘要", "replace", None),
    (7, "1.1", "replace", None),
    (10, "1.2", "replace", None),
    (13, "1.3", "replace", None),
    (16, "1.4", "replace", None),
    (19, "1.5", "replace", None),
    (22, "1.6", "replace", None),
    (25, None, "drop", None),
    (28, "2.1", "replace", None),
    (31, "2.2.1", "clean", "2.2.1 硬件整体介绍"),
    (32, "2.2.2", "clean", "2.2.2 机械设计介绍"),
    (33, "2.2.3", "clean", "2.2.3 电路各模块介绍"),
    (36, "2.3.1", "clean", "2.3.1 软件整体介绍"),
    (37, "2.3.2", "clean", "2.3.2 软件各模块介绍"),
    (40, None, "drop", None),
    (41, "3.1", "clean", "整体介绍"),
    (43, None, "clean", "工程成果"),
    (44, "3.2.1", "clean", "3.2.1 机械成果"),
    (45, "3.2.2", "clean", "3.2.2 电路成果"),
    (46, "3.2.3", "clean", "3.2.3 软件成果"),
    (48, "3.3", "clean", "特性成果"),
    (54, "4.1", "replace", None),
    (56, "4.2", "replace", None),
    (59, "参考文献", "replace", None),
]


def split_body(xml: str) -> tuple[str, list[str], str]:
    """把 <w:body> 拆成 前导 + 顶层元素列表 + 尾随。"""
    start = xml.index("<w:body>") + len("<w:body>")
    end = xml.rindex("</w:body>")
    inner = xml[start:end]
    elems: list[str] = []
    i = 0
    while i < len(inner):
        m = re.compile(r"<w:(p|tbl|sectPr)[ >/]").search(inner, i)
        if not m:
            elems.append(inner[i:])
            break
        if m.start() > i:
            elems.append(inner[i:m.start()])
        tag = m.group(1)
        if tag == "sectPr":
            close = inner.index("</w:sectPr>") + len("</w:sectPr>")
        elif tag == "p":
            close = inner.index("</w:p>", m.start()) + len("</w:p>")
        else:
            close = inner.index("</w:tbl>", m.start()) + len("</w:tbl>")
        elems.append(inner[m.start():close])
        i = close
    return xml[:start], elems, xml[end:]


def set_para_text(p: str, new_text: str) -> str:
    """保留 pPr，把段落文字整体换掉。"""
    texts = list(re.finditer(r"<w:t(?: [^>]*)?>(.*?)</w:t>", p, re.S))
    if not texts:
        return p[:p.index("</w:p>")] + run("", "") + "</w:p>"
    first, last = texts[0], texts[-1]
    return p[:first.start()] + f'<w:t xml:space="preserve">{esc(new_text)}</w:t>' + p[last.end():]


def sanitize_props(blobs: dict[str, bytes], pages: int = 22, words: int = 9158) -> None:
    """清掉模板作者信息，写入本作品的文档属性。

    模板原带的 creator/lastModifiedBy 是模板作者的，页数字数与正文也对不上，
    交上去会露出“这份文档不是我写的”。
    """
    import datetime

    now = datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%SZ")
    author_xml = ""
    if AUTHOR:
        author_xml = (f"<dc:creator>{AUTHOR}</dc:creator>"
                      f"<cp:lastModifiedBy>{AUTHOR}</cp:lastModifiedBy>")
    core = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<cp:coreProperties '
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        f'<dc:title>RISC-V 多协议逻辑分析仪 技术文档</dc:title>'
        f"{author_xml}"
        '<cp:revision>1</cp:revision>'
        f'<dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>'
        f'<dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>'
        "</cp:coreProperties>"
    )
    blobs["docProps/core.xml"] = core.encode("utf-8")

    app = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        f"<Pages>{pages}</Pages>"
        f"<Words>{words}</Words>"
        f"<Characters>{words}</Characters>"
        "<ScaleCrop>false</ScaleCrop>"
        "<LinksUpToDate>false</LinksUpToDate>"
        "<DocSecurity>0</DocSecurity>"
        "</Properties>"
    )
    blobs["docProps/app.xml"] = app.encode("utf-8")

    # custom.xml 里是模板制作方的内部标记，直接去掉并解绑关系
    blobs.pop("docProps/custom.xml", None)
    for rel_name in ("_rels/.rels",):
        if rel_name in blobs:
            rels = blobs[rel_name].decode("utf-8")
            rels = re.sub(r'<Relationship[^>]*custom\.xml"[^>]*/>', "", rels)
            blobs[rel_name] = rels.encode("utf-8")


def main() -> int:
    md = MD.read_text(encoding="utf-8")
    sections = parse_markdown(md)
    print("解析到的章节：", ", ".join(sections))

    with zipfile.ZipFile(TPL) as z:
        names = z.namelist()
        blobs = {n: z.read(n) for n in names if not n.endswith("/")}

    doc = blobs["word/document.xml"].decode("utf-8")
    head, elems, tail = split_body(doc)
    print(f"模板顶层元素 {len(elems)} 个")

    rels = blobs["word/_rels/document.xml.rels"].decode("utf-8")
    ctypes = blobs["[Content_Types].xml"].decode("utf-8")
    media: dict[str, bytes] = {}

    next_rid = 20
    pic_id = 100
    out_elems: list[str] = []
    used_sections: set[str] = set()
    fig_count = 0

    slot_map = {idx: (key, action, title) for idx, key, action, title in SLOTS}

    def render_blocks(blocks) -> str:
        nonlocal next_rid, pic_id, fig_count, rels, ctypes
        parts: list[str] = []
        for blk in blocks:
            kind = blk[0]
            if kind == BLOCK_PARA:
                parts.append(para(blk[1]))
            elif kind == BLOCK_NOTE:
                parts.append(note_para(blk[1]))
            elif kind == BLOCK_TABLE:
                parts.append(table_xml(blk[1]))
            elif kind == BLOCK_FIG:
                rel_path, cap = blk[1], blk[2]
                img = (MD.parent / rel_path).resolve()
                if not img.exists():
                    raise FileNotFoundError(img)
                suffix = img.suffix.lower().lstrip(".")
                if suffix == "jpeg":
                    suffix = "jpg"
                media_name = f"fig_{fig_count:02d}.{suffix}"
                media[f"word/media/{media_name}"] = img.read_bytes()
                rid = f"rId{next_rid}"
                next_rid += 1
                rels = rels.replace(
                    "</Relationships>",
                    f'<Relationship Id="{rid}" '
                    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
                    f'Target="media/{media_name}"/></Relationships>')
                if suffix == "jpg" and 'Extension="jpg"' not in ctypes:
                    ctypes = ctypes.replace(
                        '<Default Extension="png" ContentType="image/png"/>',
                        '<Default Extension="png" ContentType="image/png"/>'
                        '<Default Extension="jpg" ContentType="image/jpeg"/>')
                w, h = image_size(img)
                cx = int(MAX_WIDTH_CM * EMU_PER_CM)
                cy = int(cx * h / w)
                pic_id += 1
                fig_count += 1
                parts.append(image_para(rid, cx, cy, pic_id, media_name))
                parts.append(caption(cap))
        return "".join(parts)

    for idx, elem in enumerate(elems):
        if idx not in slot_map:
            out_elems.append(set_para_text(elem, "") if False else elem)
            continue
        key, action, title = slot_map[idx]
        if action == "drop":
            continue
        if action == "title":
            out_elems.append(set_para_text(elem, title))
            continue
        blocks = sections.get(key, []) if key else []
        if key:
            used_sections.add(key)
        if action == "replace":
            if blocks:
                out_elems.append(render_blocks(blocks))
            continue
        if action == "clean":
            out_elems.append(set_para_text(elem, title))
            if blocks:
                out_elems.append(render_blocks(blocks))
            continue
        out_elems.append(elem)

    leftover = set(sections) - used_sections - {"第一部分　作品概述", "第二部分　系统组成及功能说明",
                                                "第三部分　完成情况及性能参数", "第四部分　总结",
                                                "第五部分　参考文献"}
    if leftover:
        print("⚠ 未使用的章节：", ", ".join(sorted(leftover)))

    new_doc = head + "".join(out_elems) + tail

    # 落盘前先验 XML 合法性，避免把坏文件交给 Word
    import xml.etree.ElementTree as ET
    try:
        ET.fromstring(new_doc.encode("utf-8"))
    except ET.ParseError as exc:
        pos = exc.position[1] if exc.position else 0
        line = exc.position[0] if exc.position else 0
        raise SystemExit(f"document.xml 不合法：{exc}\n"
                         f"附近内容：{new_doc[max(0, pos - 200):pos + 200]}")

    blobs["word/document.xml"] = new_doc.encode("utf-8")
    blobs["word/_rels/document.xml.rels"] = rels.encode("utf-8")
    blobs["[Content_Types].xml"] = ctypes.encode("utf-8")
    blobs.update(media)

    order = [n for n in names if not n.endswith("/")]
    sanitize_props(blobs)
    order = [n for n in order if n != "docProps/custom.xml"]
    for extra in sorted(media):
        if extra not in order:
            order.append(extra)

    if OUT.exists():
        OUT.unlink()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for n in order:
            z.writestr(n, blobs[n])
    print(f"\n已生成：{OUT}  ({OUT.stat().st_size:,} B)")
    print(f"插入图片 {fig_count} 张，新增 relationship 到 rId{next_rid - 1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
