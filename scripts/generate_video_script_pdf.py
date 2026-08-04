#!/usr/bin/env python3
"""Generate Budget Pro video tutorial script PDF and DOCX (Urdu)."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from generate_user_guides import build_docx, build_pdf, ensure_font, parse_md

SOURCE = ROOT / "docs" / "guides" / "source" / "video_tutorial_script_ur_final.md"
OUT_PDF = ROOT / "docs" / "guides" / "BudgetPro_Video_Tutorial_Script_Urdu.pdf"
OUT_DOCX = ROOT / "docs" / "guides" / "BudgetPro_Video_Tutorial_Script_Urdu.docx"


def main() -> None:
    if not SOURCE.exists():
        print(f"Missing {SOURCE}")
        sys.exit(1)
    text = SOURCE.read_text(encoding="utf-8")
    blocks = parse_md(text)
    font = ensure_font()
    OUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    print(f"Building {OUT_PDF.name}...")
    build_pdf(blocks, OUT_PDF, rtl=True, font_path=font)
    print(f"OK: {OUT_PDF}")
    print(f"Building {OUT_DOCX.name}...")
    build_docx(blocks, OUT_DOCX, rtl=True)
    print(f"OK: {OUT_DOCX}")


if __name__ == "__main__":
    main()
