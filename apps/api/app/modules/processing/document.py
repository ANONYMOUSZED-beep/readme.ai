"""In-memory structured-document model produced by processors.

This is the processor output contract — independent of persistence and of any
specific file format. Offsets are character positions into the document's
canonical text (:attr:`StructuredDocument.text`), which downstream modules use
as the basis for stable anchors.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(slots=True)
class ParsedSentence:
    """A sentence, addressed by its span in the canonical document text."""

    start_offset: int
    end_offset: int


@dataclass(slots=True)
class ParsedParagraph:
    """A paragraph and its sentences. Holds the only stored copy of the text."""

    text: str
    start_offset: int
    end_offset: int
    sentences: list[ParsedSentence] = field(default_factory=list)


@dataclass(slots=True)
class ParsedSection:
    """A section within a chapter."""

    title: str | None
    start_offset: int
    end_offset: int
    paragraphs: list[ParsedParagraph] = field(default_factory=list)


@dataclass(slots=True)
class ParsedChapter:
    """A chapter within the document."""

    title: str | None
    start_offset: int
    end_offset: int
    sections: list[ParsedSection] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class DocumentMetadata:
    """Document-level metadata. Unsupported fields are ``None``."""

    title: str | None
    author: str | None
    language: str | None
    page_count: int | None
    word_count: int
    character_count: int
    estimated_reading_minutes: int | None


@dataclass(frozen=True, slots=True)
class CoverImage:
    """A book's cover picture, as found in the source file."""

    data: bytes
    media_type: str


@dataclass(frozen=True, slots=True)
class StructuredDocument:
    """The complete structured representation a processor produces."""

    metadata: DocumentMetadata
    chapters: list[ParsedChapter]
    # Canonical reading text; all offsets index into this string.
    text: str
    cover: CoverImage | None = None
