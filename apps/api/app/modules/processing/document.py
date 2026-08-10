"""Intermediate structured output of the built-in text processors.

Scope note (Sprint 6.3.5): this type is **internal to the parser layer**. It is
no longer persisted and no longer a downstream contract — parsers convert it into
the Document Model (``document_model``), which is the single source of truth.
A parser written directly against the Document Model does not use it at all.

Offsets are character positions into :attr:`StructuredDocument.text`, the
canonical text that stable anchors address.
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
class StructuredDocument:
    """The complete structured representation a processor produces."""

    metadata: DocumentMetadata
    chapters: list[ParsedChapter]
    # Canonical reading text; all offsets index into this string.
    text: str
