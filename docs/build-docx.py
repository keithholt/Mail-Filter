#!/usr/bin/env python3
"""Generate the project's Word docs from their markdown — stdlib only (no pandoc
/ python-docx). The `.md` files are the SOURCE OF TRUTH; the `.docx` files are
generated from them so the two never drift.

    python3 docs/build-docx.py                 # rebuild every doc in DOCS
    python3 docs/build-docx.py IN.md OUT.docx  # convert one file

A .docx is just a ZIP of XML parts (Office Open XML). We render the markdown these
docs actually use — headings, paragraphs, blockquotes, bullet/numbered lists, pipe
tables (as real Word tables with borders + header shading), fenced code blocks
(monospace single-cell table — this is how the ASCII diagrams land), horizontal
rules, and inline **bold** / *italic* / `code` (incl. bold that wraps `code`).

Adapted from Photo-Archival/docs/build-docx.py.
See docs/README.md for the Markdown and generated Word contract.
Mail-Filter adds semantic headings, links, deliberate table widths and --check.
"""
import os
import sys
import re
import zipfile
import io
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))

# (markdown source, Word output) pairs — a bare run rebuilds all of these.
DOCS = [
    (os.path.join(HERE, "app-store-deployment-plan.md"), os.path.join(HERE, "app-store-deployment-plan.docx")),
    (os.path.join(HERE, "dev", "architecture.md"), os.path.join(HERE, "dev", "architecture.docx")),
    (os.path.join(HERE, "dev", "getting-started.md"), os.path.join(HERE, "dev", "getting-started.docx")),
]

HYPERLINKS = {}

# Courier New remains monospace in both Word and the bundled LibreOffice renderer.
MONO = '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>'


# --------------------------------------------------------------------------- #
# inline formatting  ->  runs
# --------------------------------------------------------------------------- #
def parse_inline(text):
    """Return run dicts {'text','bold'?,'italic'?,'code'?}.

    Code spans are masked out FIRST (so a `*` inside `code` isn't seen as
    emphasis), emphasis is parsed on the masked text (so **bold** may wrap a
    code span), then placeholders are expanded back to code runs that inherit
    the surrounding bold/italic.
    """
    codes = []

    def stash(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    links = []

    def stash_link(m):
        links.append((m.group(1), m.group(2)))
        return f"\x01{len(links) - 1}\x01"

    masked = re.sub(r"\[([^\]]+)\]\(([^\s)]+)\)", stash_link, text)
    masked = re.sub(r"`([^`]+)`", stash, masked)
    runs = []
    for seg in _emphasis(masked):
        for k, piece in enumerate(re.split(r"\x00(\d+)\x00", seg["text"])):
            if k % 2 == 1:                                  # a code placeholder
                runs.append({"text": codes[int(piece)], "code": True,
                             "bold": seg.get("bold"), "italic": seg.get("italic")})
            elif piece:
                for li, part in enumerate(re.split(r"\x01(\d+)\x01", piece)):
                    if li % 2 == 1:
                        label, target = links[int(part)]
                        runs.append({"text": label, "href": target,
                                     "bold": seg.get("bold"), "italic": seg.get("italic")})
                    elif part:
                        runs.append({"text": part, "bold": seg.get("bold"),
                                     "italic": seg.get("italic")})
    return runs


def _emphasis(text):
    out, pos = [], 0
    for m in re.finditer(r"\*\*(.+?)\*\*|\*(.+?)\*", text):
        if m.start() > pos:
            out.append({"text": text[pos:m.start()]})
        if m.group(1) is not None:
            out.append({"text": m.group(1), "bold": True})
        else:
            out.append({"text": m.group(2), "italic": True})
        pos = m.end()
    if pos < len(text):
        out.append({"text": text[pos:]})
    return out


def run_xml(r, force_bold=False):
    rpr = []
    if r.get("bold") or force_bold:
        rpr.append("<w:b/>")
    if r.get("italic"):
        rpr.append("<w:i/>")
    if r.get("code"):
        rpr.append(MONO)
        rpr.append('<w:sz w:val="19"/>')
        rpr.append('<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>')
    rpr_xml = f"<w:rPr>{''.join(rpr)}</w:rPr>" if rpr else ""
    run = f'<w:r>{rpr_xml}<w:t xml:space="preserve">{escape(r["text"])}</w:t></w:r>'
    if r.get("href"):
        target = r["href"]
        identifier = HYPERLINKS.setdefault(target, f"rId{len(HYPERLINKS) + 2}")
        return f'<w:hyperlink r:id="{identifier}">{run}</w:hyperlink>'
    return run


def runs_xml(text, force_bold=False):
    return "".join(run_xml(r, force_bold) for r in parse_inline(text))


# --------------------------------------------------------------------------- #
# block builders  ->  OOXML
# --------------------------------------------------------------------------- #
def heading(level, text):
    sz = {1: 40, 2: 32, 3: 26, 4: 24}.get(level, 24)      # half-points
    color = "000000"
    parts = []
    for r in parse_inline(text):
        rpr = ["<w:b/>", f'<w:sz w:val="{sz}"/>', f'<w:color w:val="{color}"/>']
        if r.get("italic"):
            rpr.append("<w:i/>")
        if r.get("code"):
            rpr.append(MONO)
        parts.append(
            f'<w:r><w:rPr>{"".join(rpr)}</w:rPr>'
            f'<w:t xml:space="preserve">{escape(r["text"])}</w:t></w:r>'
        )
    style = "Title" if level == 1 else f"Heading{min(level - 1, 3)}"
    ppr = f'<w:pPr><w:pStyle w:val="{style}"/><w:keepNext/><w:spacing w:before="240" w:after="80"/></w:pPr>'
    return f'<w:p>{ppr}{"".join(parts)}</w:p>'


def paragraph(text, keep_next=False):
    keep = '<w:keepNext/>' if keep_next else ''
    ppr = f'<w:pPr>{keep}<w:spacing w:after="120"/></w:pPr>'
    return f"<w:p>{ppr}{runs_xml(text)}</w:p>"


def list_item(text, level, ordered):
    prefix = f"{ordered}.  " if ordered else "•  "
    left = 360 + level * 360
    ppr = (f'<w:pPr><w:spacing w:after="40"/>'
           f'<w:ind w:left="{left}" w:hanging="360"/></w:pPr>')
    pre = f'<w:r><w:t xml:space="preserve">{escape(prefix)}</w:t></w:r>'
    return f"<w:p>{ppr}{pre}{runs_xml(text)}</w:p>"


def blockquote(text):
    ppr = ('<w:pPr>'
           '<w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="8EAADB"/></w:pBdr>'
           '<w:shd w:val="clear" w:color="auto" w:fill="EAF1FB"/>'
           '<w:ind w:left="360"/><w:spacing w:before="120" w:after="120"/></w:pPr>')
    return f"<w:p>{ppr}{runs_xml(text)}</w:p>"


def code_block(lines):
    # A single-cell table: one paragraph per line → real, reliable line breaks
    # (this is how the ASCII precedence/flow diagram renders in Word).
    paras = []
    for ln in lines:
        run = (f'<w:r><w:rPr>{MONO}<w:sz w:val="18"/></w:rPr>'
               f'<w:t xml:space="preserve">{escape(ln)}</w:t></w:r>')
        paras.append(f'<w:p><w:pPr><w:spacing w:after="0" w:line="240"'
                     f' w:lineRule="auto"/></w:pPr>{run}</w:p>')
    if not paras:
        paras.append("<w:p/>")
    borders = "".join(
        f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="D0D0D0"/>'
        for s in ("top", "left", "bottom", "right")
    )
    tbl_pr = (f'<w:tblPr><w:tblW w:w="0" w:type="auto"/>'
              f"<w:tblBorders>{borders}</w:tblBorders></w:tblPr>")
    shd = '<w:shd w:val="clear" w:color="auto" w:fill="F5F5F5"/>'
    return (f"<w:tbl>{tbl_pr}<w:tr><w:trPr><w:cantSplit/></w:trPr><w:tc><w:tcPr>{shd}</w:tcPr>"
            f'{"".join(paras)}</w:tc></w:tr></w:tbl><w:p/>')


def hr():
    return ('<w:p><w:pPr><w:pBdr>'
            '<w:bottom w:val="single" w:sz="6" w:space="1" w:color="AAAAAA"/>'
            '</w:pBdr><w:spacing w:before="60" w:after="120"/></w:pPr></w:p>')


def empty_para():
    return '<w:p/>'


def table(rows):
    borders = "".join(
        f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>'
        for s in ("top", "left", "bottom", "right", "insideH", "insideV")
    )
    count = len(rows[0])
    ratios = {2: [0.38, 0.62], 3: [0.28, 0.25, 0.47]}.get(count, [1 / count] * count)
    widths = [round(9360 * ratio) for ratio in ratios]
    widths[-1] += 9360 - sum(widths)
    tbl_pr = ('<w:tblPr><w:tblW w:w="9360" w:type="dxa"/>'
              '<w:tblLayout w:type="fixed"/>'
              '<w:tblCellMar><w:top w:w="90" w:type="dxa"/><w:bottom w:w="90" w:type="dxa"/>'
              '<w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tblCellMar>'
              f"<w:tblBorders>{borders}</w:tblBorders>"
              '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0"'
              ' w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr>')
    grid = '<w:tblGrid>' + ''.join(f'<w:gridCol w:w="{width}"/>' for width in widths) + '</w:tblGrid>'
    out = [f"<w:tbl>{tbl_pr}{grid}"]
    for ri, row in enumerate(rows):
        header = '<w:tblHeader/>' if ri == 0 else ''
        out.append(f"<w:tr><w:trPr><w:cantSplit/>{header}</w:trPr>")
        for ci, cell in enumerate(row):
            shd = ('<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>'
                   if ri == 0 else "")
            body = runs_xml(cell, force_bold=(ri == 0))
            para = f'<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>{body}</w:p>'
            width = widths[min(ci, count - 1)]
            out.append(f'<w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/><w:vAlign w:val="center"/>{shd}</w:tcPr>{para}</w:tc>')
        out.append("</w:tr>")
    out.append("</w:tbl>")
    return "".join(out)


def split_row(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


# --------------------------------------------------------------------------- #
# markdown  ->  list of block XML
# --------------------------------------------------------------------------- #
def is_table_sep(line):
    return "---" in line and re.match(r"^\s*\|?[\s:|-]+$", line) is not None


def md_to_blocks(text):
    lines = text.split("\n")
    body, i, n = [], 0, len(lines)
    while i < n:
        line = lines[i]
        s = line.strip()
        if not s:
            i += 1
            continue
        if s.startswith("```"):
            code, i = [], i + 1
            while i < n and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            body.append(code_block(code))
            i += 1
            continue
        m = re.match(r"(#{1,6})\s+(.*)", s)
        if m:
            body.append(heading(len(m.group(1)), m.group(2)))
            i += 1
            continue
        if re.match(r"^-{3,}$", s):
            body.append(hr())
            i += 1
            continue
        if "|" in line and i + 1 < n and is_table_sep(lines[i + 1]):
            rows = [split_row(line)]
            i += 2
            while i < n and "|" in lines[i] and lines[i].strip():
                rows.append(split_row(lines[i]))
                i += 1
            body.append(table(rows))
            body.append(empty_para())          # a table must be followed by a para
            continue
        if s.startswith(">"):
            quote = []
            while i < n and lines[i].strip().startswith(">"):
                quote.append(re.sub(r"^\s*>\s?", "", lines[i]).strip())
                i += 1
            body.append(blockquote(" ".join(x for x in quote if x)))
            continue
        if re.match(r"^(\s*)([-*]|\d+\.)\s+", line):
            items = []                                     # (level, ordered, text)
            while i < n:
                lm = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", lines[i])
                if lm:
                    indent = len(lm.group(1))
                    level = 0 if indent < 2 else (1 if indent < 4 else 2)
                    marker = lm.group(2)
                    ordered = None if marker in ("-", "*") else marker.rstrip(".")
                    items.append([level, ordered, lm.group(3).rstrip()])
                    i += 1
                elif lines[i].strip() == "":
                    break
                elif re.match(r"^\s+\S", lines[i]) and items:   # wrapped continuation
                    items[-1][2] += " " + lines[i].strip()
                    i += 1
                else:
                    break
            for level, ordered, txt in items:
                body.append(list_item(txt, level, ordered))
            continue
        # paragraph: gather soft-wrapped lines
        para_lines, i = [s], i + 1
        while i < n:
            t = lines[i].strip()
            nxt_is_table = ("|" in lines[i] and i + 1 < n and is_table_sep(lines[i + 1]))
            if (not t or t.startswith("#") or t.startswith("```") or t.startswith(">")
                    or re.match(r"^-{3,}$", t)
                    or re.match(r"^(\s*)([-*]|\d+\.)\s+", lines[i]) or nxt_is_table):
                break
            para_lines.append(t)
            i += 1
        before_table = i + 1 < n and "|" in lines[i] and is_table_sep(lines[i + 1])
        body.append(paragraph(" ".join(para_lines), keep_next=before_table))
    return "".join(body)


# --------------------------------------------------------------------------- #
# package the .docx
# --------------------------------------------------------------------------- #
CONTENT_TYPES = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                 '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                 '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                 '<Default Extension="xml" ContentType="application/xml"/>'
                 '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
                 '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
                 '</Types>')

RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>')

DOC_RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
            '</Relationships>')

STYLES = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:docDefaults><w:rPrDefault><w:rPr>'
          '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>'
          '<w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
          '<w:name w:val="Normal"/><w:pPr><w:widowControl/><w:spacing w:line="264" w:lineRule="auto"/></w:pPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/>'
          '<w:rPr><w:b/><w:color w:val="000000"/><w:sz w:val="40"/></w:rPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
          '<w:pPr><w:keepNext/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="000000"/></w:rPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
          '<w:pPr><w:keepNext/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:color w:val="000000"/></w:rPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>'
          '<w:pPr><w:keepNext/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:color w:val="000000"/></w:rPr></w:style>'
          '</w:styles>')

SECT_PR = ('<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
           '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"'
           ' w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>')


def _zinfo(name):
    # Fixed timestamp → byte-DETERMINISTIC output. writestr() with a plain string
    # arcname stamps the current wall-clock time into each zip entry, which would
    # change the .docx bytes on every build and churn a git diff each time.
    zi = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    zi.compress_type = zipfile.ZIP_DEFLATED
    zi.external_attr = 0o644 << 16
    return zi


def docx_bytes(md_path):
    HYPERLINKS.clear()
    with open(md_path, encoding="utf-8") as f:
        blocks = md_to_blocks(f.read())
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                f"<w:body>{blocks}{SECT_PR}</w:body></w:document>")
    links = ''.join(
        f'<Relationship Id="{identifier}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="{escape(target, {chr(34): "&quot;"})}" TargetMode="External"/>'
        for target, identifier in HYPERLINKS.items()
    )
    relationships = DOC_RELS.replace('</Relationships>', links + '</Relationships>')
    parts = [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS),
        ("word/_rels/document.xml.rels", relationships),
        ("word/styles.xml", STYLES),
        ("word/document.xml", document),
    ]
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as z:
        for name, data in parts:
            z.writestr(_zinfo(name), data)
    return buffer.getvalue()


def build(md_path, docx_path):
    data = docx_bytes(md_path)
    with open(docx_path, "wb") as output:
        output.write(data)
    print(f"wrote {docx_path} ({len(data)} bytes)")


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        stale = []
        for md_path, docx_path in DOCS:
            expected = docx_bytes(md_path)
            if not os.path.exists(docx_path):
                stale.append(docx_path)
            else:
                with open(docx_path, "rb") as output:
                    if output.read() != expected:
                        stale.append(docx_path)
        if stale:
            sys.exit("Missing or stale Word outputs; regenerate with python3 docs/build-docx.py:\n" + "\n".join(stale))
        print("All registered Word documents match their Markdown sources.")
    elif len(sys.argv) == 3:
        build(sys.argv[1], sys.argv[2])
    elif len(sys.argv) == 1:
        for md_path, docx_path in DOCS:
            build(md_path, docx_path)
    else:
        sys.exit("usage: build-docx.py [INPUT.md OUTPUT.docx | --check]   (no args = rebuild all)")
