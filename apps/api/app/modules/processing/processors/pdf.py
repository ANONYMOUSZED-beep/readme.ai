"""PDF processor: extracts text from PDF files using pypdf.

Produces the same Document -> Chapter -> Section -> Paragraph -> Sentence
hierarchy as the plain-text processor. Each PDF page becomes a section within a
single chapter; page breaks are preserved as section boundaries so the reader
can report accurate page-based progress.
"""

from __future__ import annotations

import math

from pypdf import PdfReader

from app.modules.processing.document import (
    DocumentMetadata,
    ParsedChapter,
    ParsedParagraph,
    ParsedSection,
    ParsedSentence,
    StructuredDocument,
)
from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.processors.base import ProcessingError
from app.modules.processing.sentence_splitter import split_sentences

_PDF_MIME_TYPES = frozenset({"application/pdf", "application/x-pdf"})
_PDF_SUFFIXES = frozenset({".pdf"})
_PARAGRAPH_SEPARATOR = "\n\n"
_WORDS_PER_MINUTE = 200


class PdfProcessor:
    """Processes PDF files into a structured document via text extraction."""

    @property
    def name(self) -> str:
        return "pdf"

    def supports(self, *, mime_type: str, filename: str) -> bool:
        normalized = (mime_type or "").split(";", 1)[0].strip().lower()
        return normalized in _PDF_MIME_TYPES or _suffix(filename) in _PDF_SUFFIXES

    def process(
        self,
        *,
        filename: str,
        mime_type: str,
        data: bytes,
    ) -> StructuredDocument:
        import io

        try:
            reader = PdfReader(io.BytesIO(data))
        except Exception as exc:
            raise ProcessingError(
                ProcessingErrorCode.MALFORMED_FILE,
                f"Cannot parse PDF: {exc}",
            ) from exc

        page_count = len(reader.pages)
        if page_count == 0:
            raise ProcessingError(
                ProcessingErrorCode.EMPTY_DOCUMENT,
                "The PDF contains no pages.",
            )

        # Extract text per page; each page becomes a section.
        sections: list[ParsedSection] = []
        for page_num, page in enumerate(reader.pages, start=1):
            raw_text = page.extract_text() or ""
            paragraphs = _extract_paragraphs(raw_text)
            section = ParsedSection(
                title=f"Page {page_num}" if page_count > 1 else None,
                start_offset=0,
                end_offset=0,
                paragraphs=paragraphs,
            )
            sections.append(section)

        # Flatten to check for empty documents.
        all_paragraphs = [p for s in sections for p in s.paragraphs]
        if not all_paragraphs:
            raise ProcessingError(
                ProcessingErrorCode.EMPTY_DOCUMENT,
                "The PDF contains no extractable text.",
            )

        # Build a single chapter containing all page-sections.
        title = (reader.metadata.title if reader.metadata else None) or None
        author = (reader.metadata.author if reader.metadata else None) or None
        chapter = ParsedChapter(
            title=title,
            start_offset=0,
            end_offset=0,
            sections=sections,
        )

        # Assign offsets and build canonical text.
        text = _assign_offsets([chapter], all_paragraphs)
        word_count = len(text.split())
        metadata = DocumentMetadata(
            title=title,
            author=author,
            language=None,
            page_count=page_count,
            word_count=word_count,
            character_count=len(text),
            estimated_reading_minutes=(
                math.ceil(word_count / _WORDS_PER_MINUTE) if word_count else None
            ),
        )
        return StructuredDocument(metadata=metadata, chapters=[chapter], text=text)


def _extract_paragraphs(page_text: str) -> list[ParsedParagraph]:
    """Split page text into paragraphs on blank lines."""
    paragraphs: list[ParsedParagraph] = []
    for block in page_text.split("\n\n"):
        # Collapse internal newlines to spaces for cleaner reading.
        cleaned = " ".join(block.split())
        if cleaned:
            paragraphs.append(
                ParsedParagraph(text=cleaned, start_offset=0, end_offset=0)
            )
    return paragraphs


def _assign_offsets(
    chapters: list[ParsedChapter],
    paragraphs: list[ParsedParagraph],
) -> str:
    """Assign character offsets and return the canonical reading text."""
    cursor = 0
    for index, paragraph in enumerate(paragraphs):
        if index > 0:
            cursor += len(_PARAGRAPH_SEPARATOR)
        paragraph.start_offset = cursor
        paragraph.end_offset = cursor + len(paragraph.text)
        for start, end in split_sentences(paragraph.text):
            paragraph.sentences.append(
                ParsedSentence(
                    start_offset=paragraph.start_offset + start,
                    end_offset=paragraph.start_offset + end,
                )
            )
        cursor = paragraph.end_offset

    for chapter in chapters:
        chapter_paragraphs = [
            p for section in chapter.sections for p in section.paragraphs
        ]
        _span(chapter, chapter_paragraphs)
        for section in chapter.sections:
            _span(section, section.paragraphs)

    return _PARAGRAPH_SEPARATOR.join(p.text for p in paragraphs)


def _span(
    element: ParsedChapter | ParsedSection,
    paragraphs: list[ParsedParagraph],
) -> None:
    if paragraphs:
        element.start_offset = paragraphs[0].start_offset
        element.end_offset = paragraphs[-1].end_offset


def _suffix(filename: str) -> str:
    dot = filename.rfind(".")
    return filename[dot:].lower() if dot != -1 else ""
