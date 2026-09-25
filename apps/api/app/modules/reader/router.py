"""HTTP routes for the reader module.

Mounted under ``/api/v1/books/{book_id}`` alongside the library routes. All
routes require authentication and operate only on the caller's own books.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Query, status

from app.modules.activity.clock import ClientToday
from app.modules.activity.dependencies import ActivityServiceDep
from app.modules.auth.dependencies import CurrentUser
from app.modules.reader.dependencies import ReaderServiceDep
from app.modules.reader.schemas import (
    BookContentResponse,
    BookmarkListResponse,
    BookmarkResponse,
    ChapterResponse,
    CreateBookmarkRequest,
    ReadingProgressResponse,
    RecentReadingListResponse,
    UpdateProgressRequest,
)

router = APIRouter()

# Mounted under /api/v1/reading: a path such as /api/v1/books/recent would be
# captured by the library's /api/v1/books/{book_id} route.
recent_router = APIRouter()


@recent_router.get(
    "/recent",
    response_model=RecentReadingListResponse,
    summary="Books the user is reading",
)
async def list_recent(
    user: CurrentUser,
    service: ReaderServiceDep,
    limit: int = Query(default=10, ge=1, le=50, description="Maximum items."),
) -> RecentReadingListResponse:
    """Return saved reading positions, most recently read first."""
    progress = await service.list_recent(user.id, limit)
    return RecentReadingListResponse(
        items=[ReadingProgressResponse.model_validate(item) for item in progress]
    )


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
        chapters=[
            ChapterResponse(title=title, start_offset=start)
            for title, start in view.chapters
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
    activity: ActivityServiceDep,
    today: ClientToday,
) -> ReadingProgressResponse:
    """Create or update the reading position for a book.

    The reading time also counts toward today's goal and streak.
    """
    # Read before the call: a rollback inside it expires `user`.
    user_id = user.id
    progress = await service.save_progress(
        user_id=user_id,
        book_id=book_id,
        current_position=payload.current_position,
        progress_percentage=payload.progress_percentage,
        reading_time_seconds=payload.reading_time_seconds,
    )
    response = ReadingProgressResponse.model_validate(progress)
    await activity.record_reading(user_id, today, payload.reading_time_seconds)
    return response


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
    activity: ActivityServiceDep,
    today: ClientToday,
) -> BookmarkResponse:
    """Create a bookmark at a stable position anchor (counts toward tasks)."""
    # Read before the call: a rollback inside it expires `user`.
    user_id = user.id
    bookmark = await service.add_bookmark(
        user_id=user_id,
        book_id=book_id,
        anchor=payload.anchor,
        label=payload.label,
    )
    response = BookmarkResponse.model_validate(bookmark)
    await activity.record_bookmark(user_id, today)
    return response


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
