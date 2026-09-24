"""Reader service — content delivery, progress, and bookmarks.

Ownership is delegated to the library's :class:`BookService`: every operation
first resolves the book within the requesting user's scope (raising
``NotFoundError`` otherwise), so a user can never read or annotate a book that
is not theirs.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy.exc import IntegrityError

from app.core.errors import NotFoundError
from app.modules.library.service import BookService
from app.modules.processing.enums import ProcessingStatus
from app.modules.processing.service import ProcessingService
from app.modules.reader.content import ContentFormat, ReaderContentView
from app.modules.reader.models import Bookmark, ReadingProgress
from app.modules.reader.repository import ReaderRepository


class ReaderService:
    def __init__(
        self,
        repository: ReaderRepository,
        book_service: BookService,
        processing_service: ProcessingService,
    ) -> None:
        self._repository = repository
        self._book_service = book_service
        self._processing = processing_service

    async def get_content(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> ReaderContentView:
        """Return readable content from the structured document (Completed only).

        Ownership is enforced by the processing service. Books that are not yet
        processed (or failed/unsupported) render as ``UNSUPPORTED``.
        """
        content = await self._processing.get_reader_content(user_id, book_id)
        if content.status is ProcessingStatus.COMPLETED and content.text is not None:
            return ReaderContentView(
                format=ContentFormat.TEXT,
                title=content.title,
                text=content.text,
                character_count=content.character_count,
                chapters=[
                    (chapter.title, chapter.start_offset)
                    for chapter in content.chapters
                ],
            )
        return ReaderContentView(
            format=ContentFormat.UNSUPPORTED,
            title=content.title,
            text=None,
            character_count=0,
        )

    async def get_progress(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> ReadingProgress | None:
        """Return saved progress for a book, or ``None`` if not started."""
        await self._book_service.get_book(user_id, book_id)
        return await self._repository.get_progress(user_id, book_id)

    async def save_progress(
        self,
        *,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
        current_position: str,
        progress_percentage: float,
        reading_time_seconds: int,
    ) -> ReadingProgress:
        """Create or update the user's reading position for a book.

        Two concurrent first saves (e.g. a debounced save racing the save on
        leaving the reader) both see "no progress"; the loser of the unique
        constraint re-reads the winner's row and applies its update to it.
        """
        await self._book_service.get_book(user_id, book_id)

        progress = await self._repository.get_progress(user_id, book_id)
        if progress is None:
            try:
                progress = await self._repository.add_progress(
                    ReadingProgress(
                        user_id=user_id,
                        book_id=book_id,
                        current_position=current_position,
                        progress_percentage=progress_percentage,
                        total_reading_time_seconds=reading_time_seconds,
                    )
                )
                await self._repository.commit()
                return progress
            except IntegrityError:
                await self._repository.rollback()
                progress = await self._repository.get_progress(user_id, book_id)
                if progress is None:
                    raise

        progress.current_position = current_position
        progress.progress_percentage = progress_percentage
        progress.total_reading_time_seconds += reading_time_seconds
        progress.last_read_at = datetime.now(tz=UTC)
        await self._repository.commit()
        return progress

    async def list_recent(
        self,
        user_id: uuid.UUID,
        limit: int,
    ) -> list[ReadingProgress]:
        """Books the user has been reading, most recent first.

        Progress rows are owned by the user and deleted with their book, so no
        per-book ownership check is needed.
        """
        return await self._repository.list_recent_progress(user_id, limit)

    async def list_bookmarks(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> list[Bookmark]:
        await self._book_service.get_book(user_id, book_id)
        return await self._repository.list_bookmarks(user_id, book_id)

    async def add_bookmark(
        self,
        *,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
        anchor: str,
        label: str | None,
    ) -> Bookmark:
        await self._book_service.get_book(user_id, book_id)
        bookmark = Bookmark(
            user_id=user_id,
            book_id=book_id,
            anchor=anchor,
            label=label,
        )
        await self._repository.add_bookmark(bookmark)
        await self._repository.commit()
        return bookmark

    async def delete_bookmark(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
        bookmark_id: uuid.UUID,
    ) -> None:
        await self._book_service.get_book(user_id, book_id)
        bookmark = await self._repository.get_bookmark(bookmark_id, user_id, book_id)
        if bookmark is None:
            raise NotFoundError("Bookmark not found.")
        await self._repository.delete_bookmark(bookmark)
        await self._repository.commit()
