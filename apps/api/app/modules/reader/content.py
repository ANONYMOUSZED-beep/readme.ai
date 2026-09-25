"""Reader-facing content view.

The reader serves content derived from the processing module's structured
document, never from raw uploaded files.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum


class ContentFormat(StrEnum):
    """How the reader should render a book's content."""

    TEXT = "text"
    UNSUPPORTED = "unsupported"


@dataclass(frozen=True, slots=True)
class ReaderContentView:
    """Readable content presented to the reader client."""

    format: ContentFormat
    title: str
    text: str | None
    character_count: int
    # (title, start offset) per chapter; empty when there is no text.
    chapters: list[tuple[str | None, int]] = field(default_factory=list)
