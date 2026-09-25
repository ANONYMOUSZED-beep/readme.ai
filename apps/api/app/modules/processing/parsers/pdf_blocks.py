"""PyMuPDF isolation layer.

The only module in the codebase that imports PyMuPDF. It converts a PDF into
plain, immutable value objects — text blocks with font/geometry facts, image
descriptors, tables, and links — in reading order. It makes no structural
decisions and knows nothing about the Document Model.

Every PyMuPDF exception is translated into :class:`ParserError` here, so no
library-specific exception can escape the parser layer.
"""

from __future__ import annotations

import hashlib
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field

import pymupdf

from app.modules.processing.parsers.base import (
    ParserError,
    ParserErrorCode,
    ParserIssue,
)

_PARSER_NAME = "pymupdf"
#: Wall-clock budget for table detection across one document.
DEFAULT_TABLE_BUDGET_SECONDS = 15.0
# Ignore hairline rules, spacers and 1-px shims that carry no reading value.
_MIN_IMAGE_AREA = 2500.0
_MIN_IMAGE_EDGE = 16.0
# Monospaced font families, used to detect code blocks downstream.
_MONOSPACE_HINTS = ("mono", "courier", "consol", "menlo", "inconsolata")
_ITALIC_FLAG = 1 << 1
_BOLD_FLAG = 1 << 4

Rect = tuple[float, float, float, float]

_PageProgress = Callable[[int, int], None]


@dataclass(frozen=True, slots=True)
class TextLine:
    """One visual line with the font facts needed by the heuristics."""

    text: str
    bbox: Rect
    size: float
    font: str
    flags: int

    @property
    def is_monospace(self) -> bool:
        lowered = self.font.lower()
        return any(hint in lowered for hint in _MONOSPACE_HINTS)

    @property
    def is_italic(self) -> bool:
        return bool(self.flags & _ITALIC_FLAG) or "italic" in self.font.lower()

    @property
    def is_bold(self) -> bool:
        return bool(self.flags & _BOLD_FLAG) or "bold" in self.font.lower()


@dataclass(frozen=True, slots=True)
class TextBlock:
    """A contiguous run of lines PyMuPDF grouped together."""

    page_number: int
    bbox: Rect
    page_height: float
    lines: tuple[TextLine, ...]

    @property
    def raw_text(self) -> str:
        return "\n".join(line.text for line in self.lines)


@dataclass(frozen=True, slots=True)
class ImageBlock:
    """An embedded image, described but never decoded or analysed."""

    page_number: int
    bbox: Rect
    identifier: str
    width: int
    height: int
    media_type: str | None
    byte_size: int
    reference: str


@dataclass(frozen=True, slots=True)
class TableBlock:
    """A table as PyMuPDF detected it; cell text is taken verbatim."""

    page_number: int
    bbox: Rect
    rows: tuple[tuple[str, ...], ...]


@dataclass(frozen=True, slots=True)
class LinkBlock:
    """An external hyperlink annotation and the text it covers."""

    page_number: int
    bbox: Rect
    uri: str
    text: str


PdfBlock = TextBlock | ImageBlock | TableBlock


@dataclass(frozen=True, slots=True)
class PdfMetadata:
    """Document-level metadata as reported by the PDF itself."""

    title: str | None
    author: str | None
    language: str | None
    page_count: int


@dataclass(frozen=True, slots=True)
class PdfContent:
    """Everything extracted from a PDF, already in reading order."""

    metadata: PdfMetadata
    blocks: tuple[PdfBlock, ...]
    links: tuple[LinkBlock, ...]
    body_font_size: float
    issues: tuple[ParserIssue, ...] = field(default=())


def _rect(values: Sequence[float]) -> Rect:
    return (float(values[0]), float(values[1]), float(values[2]), float(values[3]))


def _clean(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    return stripped or None


def _open(data: bytes) -> pymupdf.Document:
    """Open the PDF, mapping every failure onto a structured parser error."""
    if not data:
        raise ParserError(
            ParserErrorCode.EMPTY_DOCUMENT,
            "The file is empty.",
            parser_name=_PARSER_NAME,
        )
    try:
        document = pymupdf.open(stream=data, filetype="pdf")
    except pymupdf.EmptyFileError as error:
        raise ParserError(
            ParserErrorCode.EMPTY_DOCUMENT,
            "The PDF contains no data.",
            parser_name=_PARSER_NAME,
        ) from error
    except Exception as error:
        raise ParserError(
            ParserErrorCode.CORRUPTED_DOCUMENT,
            f"The PDF could not be opened: {error}",
            parser_name=_PARSER_NAME,
        ) from error

    if document.needs_pass:
        document.close()
        raise ParserError(
            ParserErrorCode.ENCRYPTED_DOCUMENT,
            "The PDF is password protected.",
            parser_name=_PARSER_NAME,
        )
    if document.page_count == 0:
        document.close()
        raise ParserError(
            ParserErrorCode.EMPTY_DOCUMENT,
            "The PDF contains no pages.",
            parser_name=_PARSER_NAME,
        )
    return document


def _metadata(document: pymupdf.Document) -> PdfMetadata:
    raw = document.metadata or {}
    return PdfMetadata(
        title=_clean(raw.get("title")),
        author=_clean(raw.get("author")),
        # PDF has no reliable language field; left to a later sprint.
        language=None,
        page_count=int(document.page_count),
    )


def _text_blocks(page: pymupdf.Page, number: int) -> list[TextBlock]:
    """Text blocks for one page, with images excluded from the extraction."""
    payload = page.get_text("dict", flags=pymupdf.TEXTFLAGS_TEXT)
    height = float(payload.get("height") or page.rect.height or 1.0)
    blocks: list[TextBlock] = []

    for raw_block in payload.get("blocks", ()):
        if raw_block.get("type") != 0:
            continue
        lines: list[TextLine] = []
        for raw_line in raw_block.get("lines", ()):
            spans = raw_line.get("spans", ())
            text = "".join(span.get("text", "") for span in spans).strip()
            if not text:
                continue
            dominant = max(spans, key=lambda span: len(span.get("text", "")))
            lines.append(
                TextLine(
                    text=text,
                    bbox=_rect(raw_line.get("bbox", (0, 0, 0, 0))),
                    size=float(dominant.get("size") or 0.0),
                    font=str(dominant.get("font") or ""),
                    flags=int(dominant.get("flags") or 0),
                )
            )
        if lines:
            blocks.append(
                TextBlock(
                    page_number=number,
                    bbox=_rect(raw_block.get("bbox", (0, 0, 0, 0))),
                    page_height=height,
                    lines=tuple(lines),
                )
            )
    return blocks


def _image_blocks(
    document: pymupdf.Document,
    page: pymupdf.Page,
    number: int,
    cache: dict[int, tuple[str, str | None, int]],
    issues: list[ParserIssue],
) -> list[ImageBlock]:
    """Image descriptors for one page.

    Bytes are read once per unique XObject, hashed for a stable identifier, and
    then released — the parser never holds image payloads in memory, and the
    same image reused across pages is hashed only once.
    """
    blocks: list[ImageBlock] = []
    try:
        entries = page.get_images(full=True)
    except Exception as error:  # pragma: no cover - defensive
        issues.append(
            ParserIssue(
                code="image_listing_failed",
                message=f"Images on page {number} could not be listed: {error}",
                page_number=number,
            )
        )
        return blocks

    # An XObject can be listed more than once per page; its placements all come
    # back from get_image_rects, so each xref is handled exactly once.
    seen_xrefs: set[int] = set()
    for entry in entries:
        xref = int(entry[0])
        if xref in seen_xrefs:
            continue
        seen_xrefs.add(xref)
        if xref not in cache:
            try:
                extracted = document.extract_image(xref)
                payload = extracted.get("image") or b""
                cache[xref] = (
                    hashlib.sha256(payload).hexdigest(),
                    _media_type(extracted.get("ext")),
                    len(payload),
                )
            except Exception as error:
                issues.append(
                    ParserIssue(
                        code="image_unreadable",
                        message=f"Image {xref} could not be read: {error}",
                        page_number=number,
                    )
                )
                continue
        digest, media_type, byte_size = cache[xref]

        try:
            rectangles = page.get_image_rects(xref)
        except Exception:  # pragma: no cover - defensive
            rectangles = []
        if not rectangles:
            continue

        for index, rectangle in enumerate(rectangles):
            width = float(rectangle.width)
            height = float(rectangle.height)
            if (
                width * height < _MIN_IMAGE_AREA
                or width < _MIN_IMAGE_EDGE
                or height < _MIN_IMAGE_EDGE
            ):
                continue
            blocks.append(
                ImageBlock(
                    page_number=number,
                    bbox=_rect(
                        (rectangle.x0, rectangle.y0, rectangle.x1, rectangle.y1)
                    ),
                    identifier=f"sha256:{digest}",
                    width=round(width),
                    height=round(height),
                    media_type=media_type,
                    byte_size=byte_size,
                    reference=f"pdf:page={number};xref={xref};rect={index}",
                )
            )
    return blocks


def _media_type(extension: object) -> str | None:
    if not isinstance(extension, str) or not extension:
        return None
    normalized = extension.lower().lstrip(".")
    return f"image/{'jpeg' if normalized == 'jpg' else normalized}"


def _table_blocks(
    page: pymupdf.Page,
    number: int,
    issues: list[ParserIssue],
) -> list[TableBlock]:
    """Tables detected by PyMuPDF. Structure is never invented."""
    try:
        finder = page.find_tables()
    except Exception as error:
        issues.append(
            ParserIssue(
                code="table_detection_failed",
                message=f"Table detection failed on page {number}: {error}",
                page_number=number,
            )
        )
        return []

    blocks: list[TableBlock] = []
    for table in getattr(finder, "tables", ()):
        try:
            extracted = table.extract()
        except Exception as error:
            issues.append(
                ParserIssue(
                    code="table_extraction_failed",
                    message=f"A table on page {number} could not be read: {error}",
                    page_number=number,
                )
            )
            continue
        rows = tuple(
            tuple((cell or "").strip() for cell in row)
            for row in extracted
            if any((cell or "").strip() for cell in row)
        )
        if rows:
            blocks.append(
                TableBlock(
                    page_number=number,
                    bbox=_rect(tuple(table.bbox)),
                    rows=rows,
                )
            )
    return blocks


def _links(
    page: pymupdf.Page,
    number: int,
    blocks: Sequence[TextBlock],
) -> list[LinkBlock]:
    """External hyperlinks and the visible text they cover."""
    found: list[LinkBlock] = []
    seen: set[tuple[str, Rect]] = set()
    try:
        entries = page.get_links()
    except Exception:  # pragma: no cover - defensive
        return found

    for entry in entries:
        uri = _clean(entry.get("uri"))
        raw_rect = entry.get("from")
        if uri is None or raw_rect is None:
            continue
        rect = _rect((raw_rect.x0, raw_rect.y0, raw_rect.x1, raw_rect.y1))
        key = (uri, rect)
        if key in seen:
            continue
        seen.add(key)
        found.append(
            LinkBlock(
                page_number=number,
                bbox=rect,
                uri=uri,
                text=_link_label(rect, blocks),
            )
        )
    return found


def _overlaps(first: Rect, second: Rect) -> bool:
    return (
        first[0] < second[2]
        and first[2] > second[0]
        and first[1] < second[3]
        and first[3] > second[1]
    )


def _link_label(rect: Rect, blocks: Sequence[TextBlock]) -> str:
    """Label a link from text already extracted for this page.

    Deliberately avoids ``Page.get_textbox``, which re-extracts the page on
    every call and cost ~1.7 s/page on a link-dense 900-page book.
    """
    parts = [
        line.text
        for block in blocks
        if _overlaps(rect, block.bbox)
        for line in block.lines
        if _overlaps(rect, line.bbox)
    ]
    return " ".join(" ".join(parts).split())


def _has_table_rules(page: pymupdf.Page, *, minimum: int = 4) -> bool:
    """Cheap pre-check for ruled tables (~5 ms/page) before full detection."""
    try:
        rules = 0
        for drawing in page.get_drawings():
            for item in drawing.get("items", ()):
                if item[0] in ("l", "re"):
                    rules += 1
                    if rules >= minimum:
                        return True
        return False
    except Exception:  # pragma: no cover - defensive
        return True


def _inside(inner: Rect, outer: Rect) -> bool:
    """Whether the centre of ``inner`` falls within ``outer``."""
    x = (inner[0] + inner[2]) / 2
    y = (inner[1] + inner[3]) / 2
    return outer[0] <= x <= outer[2] and outer[1] <= y <= outer[3]


def _reading_order(blocks: Sequence[PdfBlock]) -> list[PdfBlock]:
    """Sort by page, then top-to-bottom, then left-to-right.

    Reading flow is prioritised over structural cleverness: coordinates are
    rounded so that visually aligned blocks are not reordered by sub-pixel noise.
    """
    return sorted(
        blocks,
        key=lambda block: (
            block.page_number,
            round(block.bbox[1], 1),
            round(block.bbox[0], 1),
        ),
    )


def _body_font_size(blocks: Sequence[PdfBlock]) -> float:
    """The document's dominant font size, weighted by characters."""
    weights: dict[float, int] = {}
    for block in blocks:
        if not isinstance(block, TextBlock):
            continue
        for line in block.lines:
            bucket = round(line.size * 2) / 2
            weights[bucket] = weights.get(bucket, 0) + len(line.text)
    if not weights:
        return 0.0
    return max(weights.items(), key=lambda item: (item[1], -item[0]))[0]


def extract_pdf(
    data: bytes,
    *,
    on_page: _PageProgress | None = None,
    table_budget_seconds: float = DEFAULT_TABLE_BUDGET_SECONDS,
) -> PdfContent:
    """Extract a PDF into ordered value objects.

    Each page is opened exactly once and released before the next one, so peak
    memory stays proportional to a single page rather than the document.

    Table detection is the most expensive operation PyMuPDF offers (~130 ms per
    page, and low-yield on prose books), so it runs only on pages that contain
    ruled lines and only until ``table_budget_seconds`` is spent. Text, images,
    links and structure are never budgeted.
    """
    document = _open(data)
    # Read metadata while the document is open; it is needed after it closes.
    metadata = _metadata(document)
    table_budget = table_budget_seconds
    issues: list[ParserIssue] = []
    image_cache: dict[int, tuple[str, str | None, int]] = {}
    blocks: list[PdfBlock] = []
    links: list[LinkBlock] = []
    total = metadata.page_count

    try:
        for index in range(total):
            number = index + 1
            try:
                page = document.load_page(index)
            except Exception as error:
                issues.append(
                    ParserIssue(
                        code="page_unreadable",
                        message=f"Page {number} could not be read: {error}",
                        page_number=number,
                    )
                )
                continue

            extracted = _text_blocks(page, number)

            tables: list[TableBlock] = []
            if table_budget > 0.0 and _has_table_rules(page):
                started = time.perf_counter()
                tables = _table_blocks(page, number, issues)
                table_budget -= time.perf_counter() - started
                if table_budget <= 0.0:
                    issues.append(
                        ParserIssue(
                            code="table_detection_budget_exhausted",
                            message=(
                                "Table detection stopped after page "
                                f"{number} to keep processing responsive; "
                                "later tables are kept as text."
                            ),
                            page_number=number,
                        )
                    )
            table_areas = [table.bbox for table in tables]
            texts = [
                block
                for block in extracted
                if not any(_inside(block.bbox, area) for area in table_areas)
            ]
            images = _image_blocks(document, page, number, image_cache, issues)

            blocks.extend(texts)
            blocks.extend(images)
            blocks.extend(tables)
            links.extend(_links(page, number, extracted))

            if not texts and not images and not tables:
                issues.append(
                    ParserIssue(
                        code="page_without_content",
                        message=(
                            f"Page {number} has no extractable content "
                            "(it may be a scan; OCR is out of scope)."
                        ),
                        page_number=number,
                    )
                )
            if on_page is not None:
                on_page(number, total)
    finally:
        document.close()

    ordered = _reading_order(blocks)
    return PdfContent(
        metadata=metadata,
        blocks=tuple(ordered),
        links=tuple(links),
        body_font_size=_body_font_size(ordered),
        issues=tuple(issues),
    )
