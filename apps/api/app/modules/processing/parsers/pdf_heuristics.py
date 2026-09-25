"""Deterministic block classification for PDF text.

PDFs carry no semantics — only glyphs at coordinates. These heuristics infer
structure from font size, font family, style flags, indentation and page
position. They are intentionally conservative: when a block is ambiguous it
stays a paragraph, because preserving reading flow matters more than guessing a
heading. No AI, no model, no randomness — identical input, identical output.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum

from app.modules.processing.parsers.pdf_blocks import TextBlock

_BULLET = re.compile(r"^\s*([\u2022\u25cf\u25aa\u2043\u2013\u2014*\-\u00b7])\s+\S")
_ENUMERATED = re.compile(r"^\s*(\d{1,3}|[a-zA-Z]|[ivxlIVXL]{1,5})[.)]\s+\S")
_CAPTION = re.compile(
    r"^\s*(figure|fig\.?|table|tbl\.?|image|photo|chart|diagram|listing|exhibit)"
    "\\s*[-\u2013\u2014.:]?\\s*\\d+",
    re.IGNORECASE,
)
_CHAPTER_LABEL = re.compile(
    "^\\s*(chapter|part|section|appendix|unit|module|lesson)"
    "\\b[\\s:.\\-\u2013\u2014]*\\d*",
    re.IGNORECASE,
)
_NUMBERED_HEADING = re.compile(r"^\s*\d+(\.\d+)*\.?\s+\S")
_FOLIO = re.compile(
    "^[\\s|\\-\u2013\u2014]*(\\d{1,4}|[ivxlcdm]{1,7})[\\s|\\-\u2013\u2014]*$",
    re.IGNORECASE,
)
_FOOTNOTE_MARKER = re.compile(r"^\s*(\[?(\d{1,3})\]?|[\u2020\u2021*])[\s.)]+\S")
_MATH_CHARS = frozenset(
    "=\u2248\u2260\u2264\u2265\u00b1\u00d7\u00f7"
    "\u2211\u220f\u222b\u221a\u221e\u2202\u2207\u22c5"
    "\u2192\u2190\u2194"
    "\u03b1\u03b2\u03b3\u03b4\u03b8\u03bb\u03bc\u03c0\u03c3\u03c6\u03c9\u03a9"
    "^_{}"
)
_SENTENCE_END = (".", "!", "?", ":", ";", ",")
_QUOTE_OPENERS = ("\u201c", '"', "\u2018", "\u00ab", "\u201e")

_HEADING_MAX_CHARS = 140
_HEADING_MAX_LINES = 3
_CHAPTER_SIZE_RATIO = 1.45
_SECTION_SIZE_RATIO = 1.12
_QUOTE_INDENT = 24.0
_FOOTNOTE_PAGE_RATIO = 0.82
_FOOTNOTE_SIZE_RATIO = 0.92
_CODE_MONOSPACE_RATIO = 0.6
_LIST_LINE_RATIO = 0.6
_MARGIN_TOP = 0.10
_MARGIN_BOTTOM = 0.88


class BlockKind(StrEnum):
    """What a text block is treated as when building the Document Model."""

    CHAPTER_HEADING = "chapter_heading"
    SECTION_HEADING = "section_heading"
    PARAGRAPH = "paragraph"
    CODE = "code"
    QUOTE = "quote"
    LIST = "list"
    FOOTNOTE = "footnote"
    FORMULA = "formula"
    CAPTION = "caption"


@dataclass(frozen=True, slots=True)
class BlockStyle:
    """Measured, style-only facts about a text block."""

    max_size: float
    body_size: float
    monospace_ratio: float
    italic_ratio: float
    bold_ratio: float
    line_count: int
    char_count: int
    indent: float
    vertical_position: float

    @property
    def size_ratio(self) -> float:
        return self.max_size / self.body_size if self.body_size > 0 else 1.0


def measure(block: TextBlock, *, body_size: float, page_left: float) -> BlockStyle:
    """Measure a block without interpreting it."""
    lines = block.lines
    chars = sum(len(line.text) for line in lines) or 1
    monospace = sum(len(line.text) for line in lines if line.is_monospace)
    italic = sum(len(line.text) for line in lines if line.is_italic)
    bold = sum(len(line.text) for line in lines if line.is_bold)
    height = block.page_height or 1.0
    return BlockStyle(
        max_size=max((line.size for line in lines), default=0.0),
        body_size=body_size,
        monospace_ratio=monospace / chars,
        italic_ratio=italic / chars,
        bold_ratio=bold / chars,
        line_count=len(lines),
        char_count=chars,
        indent=block.bbox[0] - page_left,
        vertical_position=block.bbox[1] / height,
    )


def _is_list(block: TextBlock) -> bool:
    lines = [line.text for line in block.lines if line.text]
    if not lines:
        return False
    marked = sum(
        1
        for line in lines
        if _BULLET.match(line) is not None or _ENUMERATED.match(line) is not None
    )
    return marked / len(lines) >= _LIST_LINE_RATIO


def _is_formula(text: str, style: BlockStyle) -> bool:
    if style.char_count > 200 or style.line_count > 3:
        return False
    stripped = text.strip()
    if not stripped or stripped.endswith(_SENTENCE_END):
        return False
    math_chars = sum(1 for char in stripped if char in _MATH_CHARS)
    letters = sum(1 for char in stripped if char.isalpha())
    if math_chars == 0:
        return False
    # Symbol-dense and word-sparse: a displayed formula rather than prose.
    return math_chars / len(stripped) >= 0.08 and letters / len(stripped) <= 0.6


def _is_heading(text: str, style: BlockStyle) -> bool:
    if style.char_count > _HEADING_MAX_CHARS or style.line_count > _HEADING_MAX_LINES:
        return False
    stripped = text.strip()
    if not stripped or stripped.endswith((".", ",", ";")):
        return False
    if style.size_ratio >= _SECTION_SIZE_RATIO:
        return True
    # A "Chapter N" label only counts when the line is also set apart. Without
    # this, table-of-contents and index entries become headings.
    if (
        _CHAPTER_LABEL.match(stripped) is not None
        and style.char_count <= 60
        and (style.size_ratio >= 1.05 or style.bold_ratio >= 0.6)
    ):
        return True
    # Same-size but clearly set apart: a short, fully bold line.
    return style.bold_ratio >= 0.9 and style.char_count <= 90


def _is_chapter(
    text: str,
    style: BlockStyle,
    chapter_size: float | None,
) -> bool:
    if _CHAPTER_LABEL.match(text.strip()) is not None:
        return True
    if chapter_size is not None:
        # Document-relative: only the largest heading tier is a chapter, so a
        # book with three heading sizes does not produce thousands of chapters.
        return (
            style.max_size >= chapter_size - 0.25
            and style.size_ratio >= _SECTION_SIZE_RATIO
        )
    # No heading tiers measured: fall back to a clearly dominant size.
    return style.size_ratio >= _CHAPTER_SIZE_RATIO


def is_caption(text: str) -> bool:
    """Whether a block reads like a figure or table caption."""
    return _CAPTION.match(text.strip()) is not None


def footnote_reference(text: str) -> str | None:
    """The leading footnote marker, when present."""
    match = _FOOTNOTE_MARKER.match(text.strip())
    if match is None:
        return None
    return match.group(2) or match.group(1).strip()


def is_heading(text: str, style: BlockStyle) -> bool:
    """Whether a block reads like a heading, ignoring its tier."""
    return _is_heading(text, style)


def classify(
    block: TextBlock,
    style: BlockStyle,
    text: str,
    *,
    chapter_size: float | None = None,
) -> BlockKind:
    """Classify a text block. Order matters: strong signals win."""
    if style.monospace_ratio >= _CODE_MONOSPACE_RATIO:
        return BlockKind.CODE
    if _is_list(block):
        return BlockKind.LIST
    if is_caption(text):
        return BlockKind.CAPTION
    if _is_formula(text, style):
        return BlockKind.FORMULA
    if (
        style.vertical_position >= _FOOTNOTE_PAGE_RATIO
        and style.size_ratio <= _FOOTNOTE_SIZE_RATIO
        and footnote_reference(text) is not None
    ):
        return BlockKind.FOOTNOTE
    if _is_heading(text, style):
        return (
            BlockKind.CHAPTER_HEADING
            if _is_chapter(text, style, chapter_size)
            else BlockKind.SECTION_HEADING
        )
    if style.indent >= _QUOTE_INDENT and (
        style.italic_ratio >= 0.5 or text.strip().startswith(_QUOTE_OPENERS)
    ):
        return BlockKind.QUOTE
    return BlockKind.PARAGRAPH


def list_items(block: TextBlock) -> list[str]:
    """Split a list block into item texts, joining wrapped continuation lines."""
    items: list[str] = []
    for line in block.lines:
        text = line.text.strip()
        if not text:
            continue
        starts_item = (
            _BULLET.match(text) is not None or _ENUMERATED.match(text) is not None
        )
        if starts_item or not items:
            items.append(text)
        else:
            items[-1] = f"{items[-1]} {text}"
    return items


def repetition_key(text: str) -> str:
    """A key for detecting repeated running text.

    Digits are kept deliberately: real chapter headings often differ only by
    their number ("Chapter 4" / "Chapter 5"), so normalising numbers away would
    collapse genuine headings into one repeated line. Page numbers are handled
    separately by :func:`is_page_folio`.
    """
    return " ".join(text.split()).lower().strip(" .-\u2013\u2014|")


def is_page_folio(text: str) -> bool:
    """Whether a line is just a page number (arabic or roman)."""
    return _FOLIO.match(text) is not None


def in_page_margin(style: BlockStyle) -> bool:
    """Whether a block sits in the running header or footer band.

    The band is generous because page geometry varies (A4 vs US Letter moves the
    same footer between roughly 0.90 and 0.92 of the page height).
    """
    return style.vertical_position <= _MARGIN_TOP or style.vertical_position >= (
        _MARGIN_BOTTOM
    )


def flow_text(block: TextBlock) -> str:
    """Join wrapped lines into reading text, repairing hyphenated breaks."""
    parts: list[str] = []
    for line in block.lines:
        text = line.text.strip()
        if not text:
            continue
        if (
            parts
            and parts[-1].endswith("-")
            and len(parts[-1]) > 1
            and text[:1].islower()
        ):
            parts[-1] = parts[-1][:-1] + text
            continue
        parts.append(text)
    return " ".join(parts)
