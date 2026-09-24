"""Format-independent construction of a :class:`StructuredDocument`.

Processors only translate their file format into a flat stream of
:class:`Heading` and :class:`TextBlock` items; this module owns everything that
must behave identically across formats:

* the Document -> Chapter -> Section -> Paragraph -> Sentence hierarchy,
* text sanitising (control characters that PostgreSQL ``TEXT`` rejects),
* canonical text and character offsets (the basis of stable anchors),
* sentence splitting and document metadata.
"""

from __future__ import annotations

import math
import re
from collections.abc import Iterable
from dataclasses import dataclass

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

PARAGRAPH_SEPARATOR = "\n\n"
_WORDS_PER_MINUTE = 200

# Column limits of the persisted metadata/structure (see ``models.py``).
_MAX_TITLE_LENGTH = 512
_MAX_AUTHOR_LENGTH = 512
_MAX_LANGUAGE_LENGTH = 32

# C0/C1 control characters other than tab and newline. NUL in particular is
# rejected by PostgreSQL text columns and would fail the whole insert.
_CONTROL_CHARACTERS = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")
_INLINE_WHITESPACE = re.compile(r"[ \t]+")


@dataclass(frozen=True, slots=True)
class Heading:
    """A structural heading. Level 1 starts a chapter; deeper levels a section.

    ``title`` may be ``None`` to mark an untitled chapter/section boundary
    (e.g. the start of an EPUB spine document without a heading).
    """

    level: int
    title: str | None


@dataclass(frozen=True, slots=True)
class TextBlock:
    """A paragraph of body text. Single newlines inside are preserved."""

    text: str


Block = Heading | TextBlock


def build_document(
    blocks: Iterable[Block],
    *,
    title: str | None = None,
    author: str | None = None,
    language: str | None = None,
    page_count: int | None = None,
) -> StructuredDocument:
    """Assemble a structured document from a processor's block stream.

    Raises :class:`ProcessingError` (``EMPTY_DOCUMENT``) when no readable text
    remains after sanitising.
    """
    chapters = _prune(_assemble(blocks))
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

    text = _assign_offsets(chapters, paragraphs)
    word_count = len(text.split())
    metadata = DocumentMetadata(
        title=_clean_line(title, _MAX_TITLE_LENGTH)
        or next((chapter.title for chapter in chapters if chapter.title), None),
        author=_clean_line(author, _MAX_AUTHOR_LENGTH),
        language=_clean_line(language, _MAX_LANGUAGE_LENGTH),
        page_count=page_count,
        word_count=word_count,
        character_count=len(text),
        estimated_reading_minutes=(
            math.ceil(word_count / _WORDS_PER_MINUTE) if word_count else None
        ),
    )
    return StructuredDocument(metadata=metadata, chapters=chapters, text=text)


def clean_paragraph(text: str) -> str:
    """Sanitise body text: drop control characters, tidy whitespace per line."""
    lines = (
        _INLINE_WHITESPACE.sub(" ", line).strip()
        for line in _CONTROL_CHARACTERS.sub("", text).split("\n")
    )
    return "\n".join(line for line in lines if line)


def _clean_line(value: str | None, max_length: int) -> str | None:
    if value is None:
        return None
    cleaned = " ".join(_CONTROL_CHARACTERS.sub(" ", value).split())
    return cleaned[:max_length] or None


# --- hierarchy -----------------------------------------------------------------
def _new_chapter(chapters: list[ParsedChapter], title: str | None) -> ParsedChapter:
    chapter = ParsedChapter(title=title, start_offset=0, end_offset=0)
    chapter.sections.append(ParsedSection(title=None, start_offset=0, end_offset=0))
    chapters.append(chapter)
    return chapter


def _assemble(blocks: Iterable[Block]) -> list[ParsedChapter]:
    chapters: list[ParsedChapter] = []
    current: ParsedChapter | None = None

    for block in blocks:
        if isinstance(block, Heading):
            title = _clean_line(block.title, _MAX_TITLE_LENGTH)
            if block.level <= 1:
                current = _new_chapter(chapters, title)
                continue
            if current is None:
                current = _new_chapter(chapters, None)
            section = ParsedSection(title=title, start_offset=0, end_offset=0)
            last = current.sections[-1]
            if not last.paragraphs and last.title is None:
                # Replace the chapter's implicit, still-empty leading section.
                current.sections[-1] = section
            else:
                current.sections.append(section)
            continue

        text = clean_paragraph(block.text)
        if not text:
            continue
        if current is None:
            current = _new_chapter(chapters, None)
        current.sections[-1].paragraphs.append(
            ParsedParagraph(text=text, start_offset=0, end_offset=0)
        )

    return chapters


def _prune(chapters: list[ParsedChapter]) -> list[ParsedChapter]:
    """Drop sections and chapters without text.

    Empty structure has no meaningful span in the canonical text, so keeping
    it would produce anchors that point nowhere.
    """
    kept: list[ParsedChapter] = []
    for chapter in chapters:
        chapter.sections = [s for s in chapter.sections if s.paragraphs]
        if chapter.sections:
            kept.append(chapter)
    return kept


# --- offsets -------------------------------------------------------------------
def _assign_offsets(
    chapters: list[ParsedChapter],
    paragraphs: list[ParsedParagraph],
) -> str:
    cursor = 0
    for index, paragraph in enumerate(paragraphs):
        if index > 0:
            cursor += len(PARAGRAPH_SEPARATOR)
        paragraph.start_offset = cursor
        paragraph.end_offset = cursor + len(paragraph.text)
        paragraph.sentences = [
            ParsedSentence(
                start_offset=paragraph.start_offset + start,
                end_offset=paragraph.start_offset + end,
            )
            for start, end in split_sentences(paragraph.text)
        ]
        cursor = paragraph.end_offset

    for chapter in chapters:
        for section in chapter.sections:
            section.start_offset = section.paragraphs[0].start_offset
            section.end_offset = section.paragraphs[-1].end_offset
        chapter.start_offset = chapter.sections[0].start_offset
        chapter.end_offset = chapter.sections[-1].end_offset

    return PARAGRAPH_SEPARATOR.join(p.text for p in paragraphs)


def split_sentences(text: str) -> list[tuple[int, int]]:
    """Return trimmed ``(start, end)`` spans of sentences within ``text``."""
    spans: list[tuple[int, int]] = []
    length = len(text)
    index = 0
    start: int | None = None

    while index < length:
        char = text[index]
        if start is None and not char.isspace():
            start = index
        if char in ".!?":
            end = index + 1
            while end < length and text[end] in ".!?":
                end += 1
            boundary = end >= length or text[end].isspace()
            if boundary and start is not None:
                spans.append((start, end))
                start = None
            index = end
            continue
        index += 1

    if start is not None:
        end = length
        while end > start and text[end - 1].isspace():
            end -= 1
        spans.append((start, end))

    if not spans and text.strip():
        return [(0, len(text.rstrip()))]
    return spans
