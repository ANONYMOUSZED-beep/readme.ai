"""Pydantic schemas for the reader module."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.modules.reader.content import ContentFormat


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
