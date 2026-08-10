"""HTTP routes for the reader module.

Mounted under ``/api/v1/books/{book_id}`` alongside the library routes. All
routes require authentication and operate only on the caller's own books.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.modules.auth.dependencies import CurrentUser
from app.modules.reader.dependencies import ReaderServiceDep
from app.modules.reader.schemas import (
    BookContentResponse,
    BookmarkListResponse,
    BookmarkResponse,
    CreateBookmarkRequest,
    DocumentElementResponse,
    DocumentElementWindowResponse,
    ReadingProgressResponse,
    UpdateProgressRequest,
)

router = APIRouter()

#: Default window span when a client asks for elements without a range. Matches
#: the client's chunk size, so the common request is one chunk.
DEFAULT_WINDOW_SPAN = 20_000


@router.get(
    "/{book_id}/content",
    response_model=BookContentResponse,
    summary="Get readable book content",
)
async def get_content(
    book_id: uuid.UUID,
    user: CurrentUser,
    service: ReaderServiceDep,
) -> BookContentResponse:
    """Return the book's readable content for the reader."""
    view = await service.get_content(user.id, book_id)
    return BookContentResponse(
        book_id=book_id,
        title=view.title,
        format=view.format,
        content=view.text,
        character_count=view.character_count,
    )


@router.get(
    "/{book_id}/content/elements",
    response_model=DocumentElementWindowResponse,
    summary="Get a window of structured document elements",
)
async def get_content_elements(
    book_id: uuid.UUID,
    user: CurrentUser,
    service: ReaderServiceDep,
    start: Annotated[
        int,
        Query(ge=0, description="Canonical start offset of the window."),
    ] = 0,
    end: Annotated[
        int,
        Query(ge=1, description="Canonical end offset of the window (exclusive)."),
    ] = DEFAULT_WINDOW_SPAN,
) -> DocumentElementWindowResponse:
    """Return the document elements covering a canonical offset range.

    A pure read: it never writes progress, timestamps, metadata, or cache state.
    The requested span is clamped and the element count capped, so a response is
    always bounded; ``truncated`` reports when the cap applied.
    """
    window = await service.get_elements(user.id, book_id, start=start, end=end)
    return DocumentElementWindowResponse(
        book_id=book_id,
        start=window.start,
        end=window.end,
        character_count=window.character_count,
        truncated=window.truncated,
        elements=[
            DocumentElementResponse(
                id=element.element_id,
                parent_id=element.parent_id,
                type=element.element_type,
                order_index=element.order_index,
                sequence=element.sequence,
                start_offset=element.start_offset,
                end_offset=element.end_offset,
                page_number=element.page_number,
                payload=element.payload,
                text=element.text,
            )
            for element in window.elements
        ],
    )


@router.get(
    "/{book_id}/progress",
    response_model=ReadingProgressResponse | None,
    summary="Get reading progress",
)
async def get_progress(
    book_id: uuid.UUID,
    user: CurrentUser,
    service: ReaderServiceDep,
) -> ReadingProgressResponse | None:
    """Return saved reading progress, or null if the book is unstarted."""
    progress = await service.get_progress(user.id, book_id)
    if progress is None:
        return None
    return ReadingProgressResponse.model_validate(progress)


@router.put(
    "/{book_id}/progress",
    response_model=ReadingProgressResponse,
    summary="Save reading progress",
)
async def save_progress(
    book_id: uuid.UUID,
    payload: UpdateProgressRequest,
    user: CurrentUser,
    service: ReaderServiceDep,
) -> ReadingProgressResponse:
    """Create or update the reading position for a book."""
    progress = await service.save_progress(
        user_id=user.id,
        book_id=book_id,
        current_position=payload.current_position,
        progress_percentage=payload.progress_percentage,
        reading_time_seconds=payload.reading_time_seconds,
    )
    return ReadingProgressResponse.model_validate(progress)


@router.get(
    "/{book_id}/bookmarks",
    response_model=BookmarkListResponse,
    summary="List bookmarks",
)
async def list_bookmarks(
    book_id: uuid.UUID,
    user: CurrentUser,
    service: ReaderServiceDep,
) -> BookmarkListResponse:
    """Return the user's bookmarks for a book."""
    bookmarks = await service.list_bookmarks(user.id, book_id)
    items = [BookmarkResponse.model_validate(b) for b in bookmarks]
    return BookmarkListResponse(items=items, total=len(items))


@router.post(
    "/{book_id}/bookmarks",
    response_model=BookmarkResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a bookmark",
)
async def create_bookmark(
    book_id: uuid.UUID,
    payload: CreateBookmarkRequest,
    user: CurrentUser,
    service: ReaderServiceDep,
) -> BookmarkResponse:
    """Create a bookmark at a stable position anchor."""
    bookmark = await service.add_bookmark(
        user_id=user.id,
        book_id=book_id,
        anchor=payload.anchor,
        label=payload.label,
    )
    return BookmarkResponse.model_validate(bookmark)


@router.delete(
    "/{book_id}/bookmarks/{bookmark_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a bookmark",
)
async def delete_bookmark(
    book_id: uuid.UUID,
    bookmark_id: uuid.UUID,
    user: CurrentUser,
    service: ReaderServiceDep,
) -> None:
    """Delete one of the user's bookmarks."""
    await service.delete_bookmark(user.id, book_id, bookmark_id)
