"""Pydantic schemas for the library module."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.modules.library.enums import BookStatus


class BookResponse(BaseModel):
    """Public representation of a book in the user's library."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID = Field(description="Internal book identifier.")
    title: str = Field(description="Display title of the book.")
    original_filename: str = Field(description="Name of the uploaded file.")
    mime_type: str = Field(description="MIME type of the uploaded file.")
    file_size: int = Field(description="Size of the uploaded file in bytes.")
    status: BookStatus = Field(description="Lifecycle status of the book.")
    total_pages: int | None = Field(
        default=None,
        description="Page count, if known.",
    )
    cover_image_url: str | None = Field(
        default=None,
        description="URL of the cover image, if available.",
    )
    has_cover: bool = Field(
        default=False,
        description="Whether GET /api/v1/books/{id}/cover serves a cover image.",
    )
    uploaded_at: datetime = Field(description="When the file was uploaded.")
    created_at: datetime = Field(description="When the record was created.")
    updated_at: datetime = Field(description="When the record was last updated.")


class BookListResponse(BaseModel):
    """A page of books belonging to the user."""

    items: list[BookResponse] = Field(description="The user's books.")
    total: int = Field(description="Total number of books returned.")
