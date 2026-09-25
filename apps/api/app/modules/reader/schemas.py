"""Pydantic schemas for the reader module."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.modules.reader.content import ContentFormat


class ChapterResponse(BaseModel):
    """One entry of a book's table of contents."""

    title: str | None = Field(
        default=None, description="Chapter title, when the book provides one."
    )
    start_offset: int = Field(
        description="Character offset in `content` where the chapter begins.",
    )


class BookContentResponse(BaseModel):
    """Readable content of a book served to the reader."""

    book_id: uuid.UUID = Field(description="The book this content belongs to.")
    title: str = Field(description="Display title of the book.")
    format: ContentFormat = Field(description="How the content should be rendered.")
    content: str | None = Field(
        default=None,
        description="The readable text, or null when the format is unsupported.",
    )
    character_count: int = Field(description="Number of characters in the content.")
    chapters: list[ChapterResponse] = Field(
        default_factory=list,
        description="Table of contents (chapter starts), in reading order.",
    )


class ReadingProgressResponse(BaseModel):
    """A user's reading position within a book."""

    model_config = ConfigDict(from_attributes=True)

    book_id: uuid.UUID = Field(description="The book this progress belongs to.")
    current_position: str = Field(description="Stable position anchor.")
    progress_percentage: float = Field(description="Completion percentage (0-100).")
    total_reading_time_seconds: int = Field(
        description="Accumulated reading time in seconds.",
    )
    last_read_at: datetime = Field(description="When the book was last read.")


class UpdateProgressRequest(BaseModel):
    """Payload to persist reading position."""

    current_position: str = Field(
        min_length=1,
        max_length=255,
        description="Stable position anchor (e.g. a character offset).",
    )
    progress_percentage: float = Field(
        ge=0.0,
        le=100.0,
        description="Completion percentage (0-100).",
    )
    reading_time_seconds: int = Field(
        default=0,
        ge=0,
        # One save never accounts for more than a day of reading; this also
        # keeps the running total well inside the column's integer range.
        le=86_400,
        description="Reading time to add for this session, in seconds.",
    )


class BookmarkResponse(BaseModel):
    """A saved reading position."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID = Field(description="Bookmark identifier.")
    book_id: uuid.UUID = Field(description="The book this bookmark belongs to.")
    anchor: str = Field(description="Stable position anchor.")
    label: str | None = Field(default=None, description="Optional label.")
    created_at: datetime = Field(description="When the bookmark was created.")


class CreateBookmarkRequest(BaseModel):
    """Payload to create a bookmark."""

    anchor: str = Field(
        min_length=1,
        max_length=255,
        description="Stable position anchor to bookmark.",
    )
    label: str | None = Field(
        default=None,
        max_length=255,
        description="Optional human-readable label.",
    )


class BookmarkListResponse(BaseModel):
    """A book's bookmarks."""

    items: list[BookmarkResponse] = Field(description="The bookmarks.")
    total: int = Field(description="Number of bookmarks returned.")


class RecentReadingListResponse(BaseModel):
    """Books the user has been reading, most recently read first."""

    items: list[ReadingProgressResponse] = Field(
        description="Reading positions, newest first.",
    )


class DocumentElementResponse(BaseModel):
    """One document element as delivered to the reader.

    ``payload`` carries type-specific fields exactly as stored, so a future
    element type reaches the client without a schema change here.
    """

    id: str = Field(description="Stable element identifier.")
    parent_id: str | None = Field(
        default=None,
        description="Parent element, or the document id for top-level elements.",
    )
    type: str = Field(description="Element type name.")
    order_index: int = Field(description="Order among siblings.")
    sequence: int = Field(description="Position in document order.")
    start_offset: int | None = Field(
        default=None,
        description="Canonical start offset, or null for elements without text.",
    )
    end_offset: int | None = Field(
        default=None,
        description="Canonical end offset (exclusive), or null.",
    )
    page_number: int | None = Field(
        default=None,
        description="Source page number when the origin format had one (metadata).",
    )
    payload: dict[str, Any] = Field(
        default_factory=dict,
        description="Type-specific fields, passed through as stored.",
    )
    text: str | None = Field(
        default=None,
        description=(
            "Element text, sent only when it cannot be derived from the "
            "canonical text the client already holds."
        ),
    )


class DocumentElementWindowResponse(BaseModel):
    """A bounded window of a book's document elements, in document order."""

    book_id: uuid.UUID = Field(description="The book these elements belong to.")
    start: int = Field(description="Canonical start offset of the window served.")
    end: int = Field(
        description="Canonical end offset of the window served, after clamping.",
    )
    character_count: int = Field(
        description="Total canonical characters in the document.",
    )
    truncated: bool = Field(
        description="Whether the element cap stopped the window short.",
    )
    elements: list[DocumentElementResponse] = Field(
        description="Elements in document order.",
    )
