"""Plain-text processor: the initial, dependency-free structured processor.

Builds the Document -> Chapter -> Section -> Paragraph -> Sentence hierarchy from
a UTF-8 text file using deterministic, non-AI heuristics:

* Markdown-style ``#``/``##`` heading lines become chapter/section titles.
* Blank-line-separated blocks become paragraphs.
* Paragraphs are split into sentences on terminal punctuation.

All offsets index into a canonical reading text built by joining body
paragraphs with blank lines, so persisted offsets and the text the reader
reconstructs always agree.
"""

from __future__ import annotations

import math

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

_TEXT_MIME_TYPES = frozenset(
    {
        "text/plain",
        "text/markdown",
        "application/json",
        "application/xml",
        "text/xml",
    }
)
_TEXT_SUFFIXES = frozenset({".txt", ".md", ".markdown", ".text"})
_PARAGRAPH_SEPARATOR = "\n\n"
_WORDS_PER_MINUTE = 200


class PlainTextProcessor:
    """Processes already-textual files into a structured document."""

    @property
    def name(self) -> str:
        return "plain_text"

    def supports(self, *, mime_type: str, filename: str) -> bool:
        normalized = (mime_type or "").split(";", 1)[0].strip().lower()
        return normalized in _TEXT_MIME_TYPES or _suffix(filename) in _TEXT_SUFFIXES

    def process(
        self,
        *,
        filename: str,
        mime_type: str,
        data: bytes,
    ) -> StructuredDocument:
        raw = data.decode("utf-8", errors="replace")
        normalized = raw.replace("\r\n", "\n").replace("\r", "\n")
        chapters = self._build_structure(normalized)

        paragraphs = [
            paragraph
            for chapter in chapters
            for section in chapter.sections
            for paragraph in section.paragraphs
        ]
        if not paragraphs:
            raise ProcessingError(
                ProcessingErrorCode.EMPTY_DOCUMENT,
                "The document contains no readable text.",
            )

        text = self._assign_offsets(chapters, paragraphs)
        metadata = self._build_metadata(chapters, text)
        return StructuredDocument(metadata=metadata, chapters=chapters, text=text)

    # --- structure ---------------------------------------------------------
    def _build_structure(self, text: str) -> list[ParsedChapter]:
        chapters: list[ParsedChapter] = []

        def new_chapter(title: str | None) -> ParsedChapter:
            chapter = ParsedChapter(title=title, start_offset=0, end_offset=0)
            chapters.append(chapter)
            section = ParsedSection(title=None, start_offset=0, end_offset=0)
            chapter.sections.append(section)
            return chapter

        current_chapter: ParsedChapter | None = None

        for block in _blocks(text):
            heading = _heading(block)
            if heading is not None:
                level, title = heading
                if level == 1 or current_chapter is None:
                    current_chapter = new_chapter(title if level == 1 else None)
                    if level == 2:
                        current_chapter.sections[-1] = ParsedSection(
                            title=title, start_offset=0, end_offset=0
                        )
                else:
                    current_chapter.sections.append(
                        ParsedSection(title=title, start_offset=0, end_offset=0)
                    )
                continue

            if current_chapter is None:
                current_chapter = new_chapter(None)
            current_chapter.sections[-1].paragraphs.append(
                ParsedParagraph(text=block, start_offset=0, end_offset=0)
            )

        return chapters

    # --- offsets -----------------------------------------------------------
    def _assign_offsets(
        self,
        chapters: list[ParsedChapter],
        paragraphs: list[ParsedParagraph],
    ) -> str:
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

    def _build_metadata(
        self,
        chapters: list[ParsedChapter],
        text: str,
    ) -> DocumentMetadata:
        title = next((chapter.title for chapter in chapters if chapter.title), None)
        word_count = len(text.split())
        minutes = math.ceil(word_count / _WORDS_PER_MINUTE) if word_count else None
        return DocumentMetadata(
            title=title,
            author=None,
            language=None,
            page_count=None,
            word_count=word_count,
            character_count=len(text),
            estimated_reading_minutes=minutes,
        )


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


def _blocks(text: str) -> list[str]:
    blocks: list[str] = []
    for chunk in text.split("\n\n"):
        stripped = chunk.strip()
        if stripped:
            blocks.append(stripped)
    return blocks


def _heading(block: str) -> tuple[int, str] | None:
    """Return ``(level, title)`` for a single-line markdown heading, else None."""
    if "\n" in block:
        return None
    if block.startswith("## "):
        return 2, block.removeprefix("## ").strip()
    if block.startswith("# "):
        return 1, block.removeprefix("# ").strip()
    return None
