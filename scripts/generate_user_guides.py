#!/usr/bin/env python3
"""Generate Budget Pro user guides: English & Urdu as DOCX and PDF."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import requests
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches, Pt
from fpdf import FPDF

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "guides" / "source"
OUT = ROOT / "docs" / "guides"
FONT_DIR = OUT / "fonts"
FONT_URL = (
    "https://github.com/google/fonts/raw/main/ofl/notosansarabic/"
    "NotoSansArabic%5Bwdth%2Cwght%5D.ttf"
)
# Static Regular if variable fails
FONT_URL_FALLBACK = (
    "https://github.com/google/fonts/raw/main/ofl/notosans/"
    "NotoSansArabic-Regular.ttf"
)


def ensure_font() -> Path:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    path = FONT_DIR / "NotoSansArabic.ttf"
    if path.exists() and path.stat().st_size > 10000:
        return path
    for url in (FONT_URL_FALLBACK, FONT_URL):
        try:
            r = requests.get(url, timeout=60)
            if r.status_code == 200 and len(r.content) > 10000:
                path.write_bytes(r.content)
                return path
        except Exception:
            continue
    raise RuntimeError("Could not download Urdu font for PDF")


def parse_md(text: str) -> list[tuple[str, str]]:
    """Return list of (kind, content): h1, h2, h3, p, li, table_row."""
    blocks: list[tuple[str, str]] = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip() == "---":
            i += 1
            continue
        if line.startswith("# "):
            blocks.append(("h1", line[2:].strip()))
            i += 1
            continue
        if line.startswith("## "):
            blocks.append(("h2", line[3:].strip()))
            i += 1
            continue
        if line.startswith("### "):
            blocks.append(("h3", line[4:].strip()))
            i += 1
            continue
        if line.startswith("|") and "|" in line[1:]:
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                row = lines[i]
                if not re.match(r"^\|[\s\-:|]+\|$", row.strip()):
                    cells = [c.strip() for c in row.strip("|").split("|")]
                    rows.append("  |  ".join(cells))
                i += 1
            if rows:
                blocks.append(("p", "\n".join(rows)))
            continue
        if line.startswith("- ") or line.startswith("* "):
            blocks.append(("li", line[2:].strip()))
            i += 1
            continue
        if re.match(r"^\d+\.\s", line):
            blocks.append(("li", line.strip()))
            i += 1
            continue
        if line.strip() == "":
            i += 1
            continue
        para = [line.strip()]
        i += 1
        while i < len(lines) and lines[i].strip() and not lines[i].startswith("#"):
            if lines[i].startswith("|") or lines[i].startswith("- "):
                break
            if re.match(r"^\d+\.\s", lines[i]):
                break
            para.append(lines[i].strip())
            i += 1
        blocks.append(("p", " ".join(para)))
    return blocks


def strip_md_inline(s: str) -> str:
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    s = re.sub(r"`(.+?)`", r"\1", s)
    return s


def build_docx(blocks: list[tuple[str, str]], out_path: Path, rtl: bool) -> None:
    doc = Document()
    section = doc.sections[0]
    section.top_margin = Inches(0.8)
    section.bottom_margin = Inches(0.8)

    for kind, raw in blocks:
        text = strip_md_inline(raw)
        if kind == "h1":
            p = doc.add_heading(text, level=0)
            if rtl:
                p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        elif kind == "h2":
            p = doc.add_heading(text, level=1)
            if rtl:
                p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        elif kind == "h3":
            p = doc.add_heading(text, level=2)
            if rtl:
                p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        elif kind == "li":
            p = doc.add_paragraph(text, style="List Bullet")
            if rtl:
                p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        else:
            p = doc.add_paragraph(text)
            if rtl:
                p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
            p.paragraph_format.space_after = Pt(6)

    doc.save(out_path)


class GuidePDF(FPDF):
    def __init__(self, rtl: bool, font_path: Path | None):
        super().__init__()
        self.rtl = rtl
        self._font_path = font_path
        self.set_auto_page_break(auto=True, margin=15)

    def header(self):
        pass

    def footer(self):
        self.set_y(-12)
        self.set_font("Guide", size=8)
        self.cell(0, 8, f"Page {self.page_no()}", align="C")


def build_pdf(
    blocks: list[tuple[str, str]], out_path: Path, rtl: bool, font_path: Path
) -> None:
    pdf = GuidePDF(rtl=rtl, font_path=font_path)
    pdf.add_font("Guide", "", str(font_path))
    pdf.set_font("Guide", size=11)
    pdf.add_page()

    for kind, raw in blocks:
        text = strip_md_inline(raw)
        if not text:
            continue
        if kind == "h1":
            pdf.set_font("Guide", size=18)
            pdf.ln(4)
        elif kind == "h2":
            pdf.set_font("Guide", size=14)
            pdf.ln(3)
        elif kind == "h3":
            pdf.set_font("Guide", size=12)
            pdf.ln(2)
        else:
            pdf.set_font("Guide", size=10)

        align = "R" if rtl else "L"
        w = pdf.epw
        if kind in ("h1", "h2", "h3"):
            pdf.multi_cell(w, 8, text, align=align)
        elif kind == "li":
            pdf.multi_cell(w, 6, f"  •  {text}", align=align)
        else:
            pdf.multi_cell(w, 6, text, align=align)
        pdf.ln(2)

    pdf.output(str(out_path))


def process(lang: str, md_name: str, rtl: bool) -> None:
    md_path = SOURCE / md_name
    if not md_path.exists():
        print(f"Missing {md_path}")
        sys.exit(1)
    text = md_path.read_text(encoding="utf-8")
    blocks = parse_md(text)

    OUT.mkdir(parents=True, exist_ok=True)
    base = f"BudgetPro_User_Guide_{lang}"
    docx_path = OUT / f"{base}.docx"
    pdf_path = OUT / f"{base}.pdf"

    print(f"Building {docx_path.name}...")
    build_docx(blocks, docx_path, rtl=rtl)

    font_path = ensure_font() if rtl else None
    if not rtl:
        # English PDF with same font (Latin + numbers)
        font_path = ensure_font()
    print(f"Building {pdf_path.name}...")
    build_pdf(blocks, pdf_path, rtl=rtl, font_path=font_path)
    print(f"  OK: {docx_path}")
    print(f"  OK: {pdf_path}")


def main() -> None:
    print("Budget Pro — User Guide Generator\n")
    process("English", "user_guide_en.md", rtl=False)
    process("Urdu", "user_guide_ur.md", rtl=True)
    print("\nAll guides written to:", OUT)


if __name__ == "__main__":
    main()
