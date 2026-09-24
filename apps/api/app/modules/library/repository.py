"""Data-access for the library module (repository pattern)."""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.library.models import Book


class BookRepository:
    """Persistence operations for :class:`Book`.

    Every read is scoped by ``user_id`` so the repository cannot return another
    user's data; the service layer enforces ownership on top of this.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, book: Book) -> Book:
        """Persist a new book."""
        self._session.add(book)
        await self._session.flush()
        return book

    async def list_for_user(self, user_id: uuid.UUID) -> list[Book]:
        """Return all books owned by ``user_id``, newest first."""
        result = await self._session.execute(
            select(Book).where(Book.user_id == user_id).order_by(Book.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_for_user(
        self,
        book_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> Book | None:
        """Return a single owned book, or ``None`` if absent or not owned."""
        result = await self._session.execute(
            select(Book).where(Book.id == book_id, Book.user_id == user_id)
        )
        return result.scalar_one_or_none()

    async def delete(self, book: Book) -> None:
        """Remove a book row."""
        await self._session.delete(book)

    async def commit(self) -> None:
        """Commit the current unit of work."""
        await self._session.commit()

    async def rollback(self) -> None:
        """Discard the current unit of work."""
        await self._session.rollback()
