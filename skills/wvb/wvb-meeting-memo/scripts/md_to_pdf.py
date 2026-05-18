#!/usr/bin/env python3
"""Convert markdown meeting memo to PDF using reportlab.

Uses CID built-in HYGothic-Medium for Korean (no external font file needed).
Fallback to fonts-noto-cjk TTF if available.

Usage:
    python md_to_pdf.py --input memo.md --output memo.pdf [--title "Meeting Memo"]
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.colors import HexColor
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    HRFlowable,
    PageBreak,
    KeepTogether,
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfbase.ttfonts import TTFont


# ---------------------------------------------------------------------------
# Font registration — Korean
# ---------------------------------------------------------------------------
KOREAN_FONT = "HYSMyeongJo-Medium"  # CID built-in, Korean serif
KOREAN_BOLD = "HYGothic-Medium"     # CID built-in, Korean sans (use for bold/heading)

# Try TTF first (better rendering), fallback to CID
NOTO_PATHS = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
]


def register_fonts() -> tuple[str, str]:
    """Register fonts and return (regular_name, bold_name)."""
    # Try Noto Sans CJK TTC first
    for noto_path in NOTO_PATHS:
        if os.path.exists(noto_path):
            try:
                # TTC is a font collection; index 0 = Regular, 1 = Bold (usually)
                pdfmetrics.registerFont(TTFont("NotoSansKR", noto_path, subfontIndex=0))
                pdfmetrics.registerFont(TTFont("NotoSansKR-Bold", noto_path, subfontIndex=1))
                return "NotoSansKR", "NotoSansKR-Bold"
            except Exception:
                continue

    # Fallback to CID built-in (no file needed, ships with reportlab)
    try:
        pdfmetrics.registerFont(UnicodeCIDFont(KOREAN_FONT))
        pdfmetrics.registerFont(UnicodeCIDFont(KOREAN_BOLD))
        return KOREAN_FONT, KOREAN_BOLD
    except Exception as e:
        print(f"Font registration failed: {e}", file=sys.stderr)
        # Last resort: Helvetica (won't render Korean correctly)
        return "Helvetica", "Helvetica-Bold"


# ---------------------------------------------------------------------------
# Colors (subdued, professional)
# ---------------------------------------------------------------------------
BLUE = HexColor("#1a56db")
DARK = HexColor("#1f2937")
GRAY = HexColor("#6b7280")
WHITE = HexColor("#ffffff")
TABLE_HEADER_BG = HexColor("#1e40af")
BORDER_COLOR = HexColor("#d1d5db")
CONFIDENTIAL_RED = HexColor("#991b1b")


def build_styles(regular: str, bold: str) -> dict:
    return {
        "title": ParagraphStyle(
            "Title", fontName=bold, fontSize=18, leading=24, textColor=DARK, spaceAfter=8
        ),
        "exec_h": ParagraphStyle(
            "ExecH", fontName=bold, fontSize=14, leading=20, textColor=BLUE, spaceBefore=12, spaceAfter=6
        ),
        "h2": ParagraphStyle(
            "H2", fontName=bold, fontSize=13, leading=18, textColor=BLUE, spaceBefore=12, spaceAfter=6
        ),
        "h3": ParagraphStyle(
            "H3", fontName=bold, fontSize=11, leading=15, textColor=DARK, spaceBefore=8, spaceAfter=4
        ),
        "h4": ParagraphStyle(
            "H4", fontName=bold, fontSize=10, leading=14, textColor=BLUE, spaceBefore=6, spaceAfter=3
        ),
        "body": ParagraphStyle(
            "Body", fontName=regular, fontSize=10, leading=15, textColor=DARK, spaceBefore=2, spaceAfter=2
        ),
        "bullet": ParagraphStyle(
            "Bullet", fontName=regular, fontSize=10, leading=15, textColor=DARK, leftIndent=14, bulletIndent=0
        ),
        "sub_bullet": ParagraphStyle(
            "SubBullet", fontName=regular, fontSize=9.5, leading=13, textColor=GRAY, leftIndent=28, bulletIndent=14
        ),
        "confidential": ParagraphStyle(
            "Confidential", fontName=regular, fontSize=8, leading=12, textColor=CONFIDENTIAL_RED, alignment=1
        ),
        "th": ParagraphStyle(
            "TH", fontName=bold, fontSize=9, leading=12, textColor=WHITE
        ),
        "td": ParagraphStyle(
            "TD", fontName=regular, fontSize=9, leading=12, textColor=DARK
        ),
    }


def escape_xml(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def md_inline(text: str) -> str:
    text = escape_xml(text)
    text = re.sub(r"\*\*\*(.+?)\*\*\*", r"<b><i>\1</i></b>", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*]+?)\*(?!\*)", r"<i>\1</i>", text)
    return text


def parse_markdown(md: str, styles: dict, usable_width: float) -> list:
    """Convert markdown text to reportlab flowables."""
    flowables: list = []
    lines = md.split("\n")
    i = 0
    in_table = False
    table_headers: list = []
    table_rows: list = []

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Horizontal rule
        if stripped in ("---", "***", "___"):
            flowables.append(Spacer(1, 4))
            flowables.append(HRFlowable(width="100%", thickness=0.5, color=BORDER_COLOR))
            flowables.append(Spacer(1, 4))
            i += 1
            continue

        # Headings
        if stripped.startswith("# "):
            flowables.append(Paragraph(md_inline(stripped[2:]), styles["title"]))
            i += 1
            continue
        if stripped.startswith("## "):
            content = stripped[3:]
            style = styles["exec_h"] if content == "Executive Summary" else styles["h2"]
            flowables.append(Paragraph(md_inline(content), style))
            i += 1
            continue
        if stripped.startswith("### "):
            flowables.append(Paragraph(md_inline(stripped[4:]), styles["h3"]))
            i += 1
            continue
        if stripped.startswith("#### "):
            flowables.append(Paragraph(md_inline(stripped[5:]), styles["h4"]))
            i += 1
            continue

        # Tables
        if "|" in line and i + 1 < len(lines) and re.match(r"^\s*\|?[\s\-:|]+\|?\s*$", lines[i + 1]):
            # Table header detected
            headers = [c.strip() for c in line.strip().strip("|").split("|")]
            i += 2  # skip separator
            rows = []
            while i < len(lines) and "|" in lines[i] and lines[i].strip():
                row = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                rows.append(row)
                i += 1

            # Build table
            data = [[Paragraph(md_inline(h), styles["th"]) for h in headers]]
            for row in rows:
                data.append([Paragraph(md_inline(c), styles["td"]) for c in row])
            n_cols = len(headers)
            col_widths = [usable_width / n_cols] * n_cols
            table = Table(data, colWidths=col_widths)
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ]))
            flowables.append(Spacer(1, 4))
            flowables.append(table)
            flowables.append(Spacer(1, 4))
            continue

        # Bullets (- / *) — handle sub-bullets by indent
        bullet_match = re.match(r"^(\s*)[-*]\s+(.*)$", line)
        if bullet_match:
            indent_str = bullet_match.group(1)
            content = bullet_match.group(2)
            indent_level = len(indent_str) // 2
            style = styles["sub_bullet"] if indent_level >= 1 else styles["bullet"]
            flowables.append(Paragraph(f"• {md_inline(content)}", style))
            i += 1
            continue

        # Numbered list
        numbered_match = re.match(r"^(\s*)(\d+)\.\s+(.*)$", line)
        if numbered_match:
            num = numbered_match.group(2)
            content = numbered_match.group(3)
            flowables.append(Paragraph(f"{num}. {md_inline(content)}", styles["bullet"]))
            i += 1
            continue

        # Italic-only line (e.g., CONFIDENTIAL line)
        italic_match = re.match(r"^\s*\*(.+)\*\s*$", line)
        if italic_match and "CONFIDENTIAL" in italic_match.group(1).upper():
            flowables.append(Spacer(1, 6))
            flowables.append(Paragraph(escape_xml(italic_match.group(1)), styles["confidential"]))
            i += 1
            continue

        # Plain paragraph
        if stripped:
            flowables.append(Paragraph(md_inline(stripped), styles["body"]))
        else:
            flowables.append(Spacer(1, 4))
        i += 1

    return flowables


def md_to_pdf(input_path: str, output_path: str, title: str = "Meeting Memo") -> None:
    md = Path(input_path).read_text(encoding="utf-8")

    regular, bold = register_fonts()
    styles = build_styles(regular, bold)

    doc = SimpleDocTemplate(
        output_path,
        pagesize=A4,
        leftMargin=20 * mm,
        rightMargin=20 * mm,
        topMargin=18 * mm,
        bottomMargin=18 * mm,
        title=title,
        author="WVB Hermes Bot",
    )
    usable_width = A4[0] - 40 * mm

    flowables = parse_markdown(md, styles, usable_width)
    doc.build(flowables)


def main() -> int:
    parser = argparse.ArgumentParser(description="Markdown → PDF (Korean-aware)")
    parser.add_argument("--input", required=True, help="Input markdown file")
    parser.add_argument("--output", required=True, help="Output PDF file")
    parser.add_argument("--title", default="Meeting Memo", help="PDF title metadata")
    args = parser.parse_args()

    try:
        md_to_pdf(args.input, args.output, args.title)
        # Output page count for skill to report
        try:
            from pypdf import PdfReader  # type: ignore
            reader = PdfReader(args.output)
            print(f"OK pages={len(reader.pages)} path={args.output}")
        except ImportError:
            print(f"OK path={args.output}")
        return 0
    except Exception as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
