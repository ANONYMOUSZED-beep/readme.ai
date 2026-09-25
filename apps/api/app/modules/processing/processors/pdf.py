"""PDF processor built on ``pypdf`` (pure Python, no system dependencies).

PDF has no notion of paragraphs, only positioned lines, so the extracted text is
re-flowed with deterministic heuristics:

* lines are joined into paragraphs, and words hyphenated across a line break
  are re-joined;
* a paragraph ends at a blank line, or at a short line that closes a sentence
  (the ragged last line of a typeset paragraph);
* bare page numbers at the top or bottom of a page are dropped;
* a paragraph interrupted by a page break is stitched back together.

Scanned (image-only) PDFs have no extractable text and fail as an empty
document; OCR is a separate, future processor.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from io import BytesIO

from pypdf import PasswordType, PdfReader
from pypdf.errors import PyPdfError

from app.modules.processing.builder import TextBlock, build_document, clean_paragraph
from app.modules.processing.document import StructuredDocument
from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.processors.base import ProcessingError

_PDF_MIME_TYPE = "application/pdf"
_MAX_PAGES = 5000

# Characters that may close a sentence (incl. curly quotes and an ellipsis).
_TERMINAL = (".", "!", "?", ":", '"', "'", "\u201d", "\u2019", ")", "\u2026")
_PAGE_NUMBER = re.compile(r"^(?:page\s+)?\d{1,4}(?:\s*(?:of|/)\s*\d{1,4})?$", re.I)
# A line shorter than this share of the page's typical line length is treated
# as the ragged final line of a paragraph (when it also ends a sentence).
_SHORT_LINE_RATIO = 0.75


class PdfProcessor:
    """Processes text-based PDF documents into a structured document."""

    @property
    def name(self) -> str:
        return "pdf"

    def supports(self, *, mime_type: str, filename: str) -> bool:
        normalized = (mime_type or "").split(";", 1)[0].strip().lower()
        return normalized == _PDF_MIME_TYPE or filename.lower().endswith(".pdf")

    def process(
        self,
        *,
        filename: str,
        mime_type: str,
        data: bytes,
    ) -> StructuredDocument:
        try:
            reader = PdfReader(BytesIO(data))
            if reader.is_encrypted and (
                reader.decrypt("") == PasswordType.NOT_DECRYPTED
            ):
                raise ProcessingError(
                    ProcessingErrorCode.UNSUPPORTED_FORMAT,
                    "This PDF is password-protected and cannot be read.",
                )
            page_count = len(reader.pages)
            if page_count > _MAX_PAGES:
                raise ProcessingError(
                    ProcessingErrorCode.TOO_LARGE,
                    f"The PDF has more than {_MAX_PAGES} pages.",
                )
            pages = [_page_text(reader, index) for index in range(page_count)]
            title, author = _metadata(reader)
        except ProcessingError:
            raise
        except (PyPdfError, ValueError, KeyError, TypeError) as exc:
            raise ProcessingError(
                ProcessingErrorCode.MALFORMED_FILE,
                "The PDF is damaged or could not be read.",
            ) from exc

        paragraphs = reflow_pages(pages)
        if not paragraphs:
            raise ProcessingError(
                ProcessingErrorCode.EMPTY_DOCUMENT,
                "The PDF has no extractable text (it may be a scanned image).",
            )
        return build_document(
            (TextBlock(text) for text in paragraphs),
            title=title,
            author=author,
            page_count=page_count,
        )


def _page_text(reader: PdfReader, index: int) -> str:
    try:
        return reader.pages[index].extract_text() or ""
    except (PyPdfError, ValueError, KeyError, TypeError):
        # One undecodable page should not cost the reader the whole book.
        return ""


def _metadata(reader: PdfReader) -> tuple[str | None, str | None]:
    try:
        info = reader.metadata
    except (PyPdfError, ValueError, KeyError, TypeError):
        return None, None
    if info is None:
        return None, None
    title = info.title if isinstance(info.title, str) else None
    author = info.author if isinstance(info.author, str) else None
    return title, author


def reflow_pages(pages: list[str]) -> list[str]:
    """Turn per-page extracted text into document paragraphs."""
    paragraphs: list[str] = []
    for page in pages:
        page_paragraphs = list(_page_paragraphs(page))
        if not page_paragraphs:
            continue
        if paragraphs and _continues(paragraphs[-1], page_paragraphs[0]):
            paragraphs[-1] = _join_lines([paragraphs[-1], page_paragraphs[0]])
            page_paragraphs = page_paragraphs[1:]
        paragraphs.extend(page_paragraphs)
    return [text for text in (clean_paragraph(p) for p in paragraphs) if text]


def _page_paragraphs(text: str) -> Iterator[str]:
    lines = [line.strip() for line in text.replace("\r", "\n").split("\n")]
    content = [index for index, line in enumerate(lines) if line]
    if not content:
        return
    # Running headers/footers most often carry just the page number.
    for index in (content[0], content[-1]):
        if _PAGE_NUMBER.fullmatch(lines[index]):
            lines[index] = ""

    lengths = sorted(len(line) for line in lines if line)
    if not lengths:
        return
    typical = lengths[(len(lengths) * 3) // 4]

    current: list[str] = []
    for line in lines:
        if not line:
            if current:
                yield _join_lines(current)
                current = []
            continue
        current.append(line)
        if line.endswith(_TERMINAL) and len(line) < typical * _SHORT_LINE_RATIO:
            yield _join_lines(current)
            current = []
    if current:
        yield _join_lines(current)


def _join_lines(lines: list[str]) -> str:
    joined = lines[0]
    for line in lines[1:]:
        if len(joined) > 1 and joined.endswith("-") and joined[-2].isalpha():
            if line[:1].islower():
                joined = joined[:-1] + line  # "hyphen-" + "ated" -> "hyphenated"
            else:
                joined += line  # "Anglo-" + "Saxon" -> "Anglo-Saxon"
        else:
            joined = f"{joined} {line}"
    return joined


def _continues(previous: str, following: str) -> bool:
    """Whether ``following`` continues a paragraph cut by a page break."""
    return not previous.rstrip().endswith(_TERMINAL) and following[:1].islower()
