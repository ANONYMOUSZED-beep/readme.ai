"""Library service — book CRUD with ownership enforcement."""

from __future__ import annotations

import uuid
from pathlib import PurePosixPath

from app.core.errors import NotFoundError, ValidationError
from app.core.storage.base import StorageService
from app.modules.library.enums import BookStatus
from app.modules.library.models import Book
from app.modules.library.repository import BookRepository

_DEFAULT_MIME_TYPE = "application/octet-stream"


class BookService:
    """Coordinates storage and persistence for a user's library.

    Ownership is enforced here: reads and deletes resolve the book only within
    the requesting user's scope, and a miss is reported as "not found" so the
    existence of other users' books is never revealed.
    """

    def __init__(
        self,
        repository: BookRepository,
        storage: StorageService,
        *,
        max_upload_size_bytes: int,
    ) -> None:
        self._repository = repository
        self._storage = storage
        self._max_upload_size_bytes = max_upload_size_bytes

    async def upload(
        self,
        *,
        user_id: uuid.UUID,
        filename: str,
        content: bytes,
        content_type: str | None,
        title: str | None,
    ) -> Book:
        """Store an uploaded file and create its library record."""
        if not content:
            raise ValidationError("Uploaded file is empty.")
        if len(content) > self._max_upload_size_bytes:
            raise ValidationError("Uploaded file exceeds the maximum allowed size.")

        safe_name = PurePosixPath(filename).name or "book"
        book_id = uuid.uuid4()
        suffix = PurePosixPath(safe_name).suffix
        storage_key = f"users/{user_id}/books/{book_id}{suffix}"

        await self._storage.save(
            storage_key,
            content,
            content_type=content_type,
        )

        book = Book(
            id=book_id,
            user_id=user_id,
            title=(title or PurePosixPath(safe_name).stem or safe_name).strip(),
            original_filename=safe_name,
            storage_key=storage_key,
            mime_type=content_type or _DEFAULT_MIME_TYPE,
            file_size=len(content),
            status=BookStatus.UPLOADED,
        )
        await self._repository.add(book)
        await self._repository.commit()
        return book

    async def list_books(self, user_id: uuid.UUID) -> list[Book]:
        """Return all books owned by the user."""
        return await self._repository.list_for_user(user_id)

    async def get_book(self, user_id: uuid.UUID, book_id: uuid.UUID) -> Book:
        """Return a single owned book or raise :class:`NotFoundError`."""
        book = await self._repository.get_for_user(book_id, user_id)
        if book is None:
            raise NotFoundError("Book not found.")
        return book

    def set_status(self, book: Book, status: BookStatus) -> None:
        """Update a book's lifecycle status within the current unit of work.

        The caller commits, so the change lands atomically with related writes
        (e.g. the processing result).
        """
        book.status = status

    async def delete_book(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        """Delete an owned book and its stored file."""
        book = await self.get_book(user_id, book_id)
        await self._storage.delete(book.storage_key)
        await self._repository.delete(book)
        await self._repository.commit()
