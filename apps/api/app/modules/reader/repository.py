"""Data-access for the reader module (repository pattern)."""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.reader.models import Bookmark, ReadingProgress


class ReaderRepository:
    """Persistence for reading progress and bookmarks.

    All operations are scoped by ``user_id`` so the repository cannot read or
    mutate another user's data.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # --- Reading progress --------------------------------------------------
    async def get_progress(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> ReadingProgress | None:
        result = await self._session.execute(
            select(ReadingProgress).where(
                ReadingProgress.user_id == user_id,
                ReadingProgress.book_id == book_id,
            )
        )
        return result.scalar_one_or_none()

    async def add_progress(self, progress: ReadingProgress) -> ReadingProgress:
        self._session.add(progress)
        await self._session.flush()
        return progress

    async def list_recent_progress(
        self,
        user_id: uuid.UUID,
        limit: int,
    ) -> list[ReadingProgress]:
        """The user's reading positions, most recently read first."""
        result = await self._session.execute(
            select(ReadingProgress)
            .where(ReadingProgress.user_id == user_id)
            .order_by(ReadingProgress.last_read_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    # --- Bookmarks ---------------------------------------------------------
    async def list_bookmarks(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> list[Bookmark]:
        result = await self._session.execute(
            select(Bookmark)
            .where(Bookmark.user_id == user_id, Bookmark.book_id == book_id)
            .order_by(Bookmark.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_bookmark(
        self,
        bookmark_id: uuid.UUID,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> Bookmark | None:
        result = await self._session.execute(
            select(Bookmark).where(
                Bookmark.id == bookmark_id,
                Bookmark.user_id == user_id,
                Bookmark.book_id == book_id,
            )
        )
        return result.scalar_one_or_none()

    async def add_bookmark(self, bookmark: Bookmark) -> Bookmark:
        self._session.add(bookmark)
        await self._session.flush()
        return bookmark

    async def delete_bookmark(self, bookmark: Bookmark) -> None:
        await self._session.delete(bookmark)

    async def commit(self) -> None:
        await self._session.commit()

    async def rollback(self) -> None:
        await self._session.rollback()
