"""Reader service — content delivery, progress, and bookmarks.

Ownership is delegated to the library's :class:`BookService`: every operation
first resolves the book within the requesting user's scope (raising
``NotFoundError`` otherwise), so a user can never read or annotate a book that
is not theirs.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from app.core.errors import NotFoundError
from app.modules.library.service import BookService
from app.modules.processing.element_query import DocumentElementQuery, ElementWindow
from app.modules.processing.enums import ProcessingStatus
from app.modules.processing.repository import ProcessingRepository
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
        processing_repository: ProcessingRepository,
        elements: DocumentElementQuery,
    ) -> None:
        self._repository = repository
        self._book_service = book_service
        self._processing = processing_service
        self._processing_repository = processing_repository
        self._elements = elements

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
            )
        return ReaderContentView(
            format=ContentFormat.UNSUPPORTED,
            title=content.title,
            text=None,
            character_count=0,
        )

    async def get_elements(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
        *,
        start: int,
        end: int,
    ) -> ElementWindow:
        """Return a bounded window of the book's document elements.

        A pure read: ownership is resolved through the library service exactly as
        :meth:`get_content` does, and nothing is written — no progress, no
        timestamps, no metadata. Books that are not processed yield an empty
        window rather than an error, so the reader can degrade to canonical text
        instead of handling a failure.
        """
        await self._book_service.get_book(user_id, book_id)
        record = await self._processing_repository.get_by_book_id(book_id)
        if record is None or record.status is not ProcessingStatus.COMPLETED:
            return ElementWindow(
                start=max(0, start),
                end=max(max(0, start), end),
                character_count=0,
                elements=(),
                truncated=False,
            )
        return await self._elements.window(record.id, start=start, end=end)

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
        """Create or update the user's reading position for a book."""
        await self._book_service.get_book(user_id, book_id)

        progress = await self._repository.get_progress(user_id, book_id)
        if progress is None:
            progress = ReadingProgress(
                user_id=user_id,
                book_id=book_id,
                current_position=current_position,
                progress_percentage=progress_percentage,
                total_reading_time_seconds=reading_time_seconds,
            )
            await self._repository.add_progress(progress)
        else:
            progress.current_position = current_position
            progress.progress_percentage = progress_percentage
            progress.total_reading_time_seconds += reading_time_seconds
            progress.last_read_at = datetime.now(tz=UTC)

        await self._repository.commit()
        return progress

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
