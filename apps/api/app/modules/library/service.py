"""Library service — book CRUD with ownership enforcement."""

from __future__ import annotations

import mimetypes
import uuid
from pathlib import PurePosixPath

from app.core.errors import NotFoundError, PayloadTooLargeError, ValidationError
from app.core.logging import get_logger
from app.core.storage.base import StorageService
from app.modules.library.enums import BookStatus
from app.modules.library.models import Book
from app.modules.library.repository import BookRepository

logger = get_logger(__name__)

_DEFAULT_MIME_TYPE = "application/octet-stream"
_DEFAULT_FILENAME = "book"

# Column limits (see ``Book``); values are clamped so oversized client input
# can never surface as a database error.
_MAX_TITLE_LENGTH = 512
_MAX_FILENAME_LENGTH = 512
_MAX_MIME_LENGTH = 255

# Canonical types for the formats the reader understands. Clients (notably
# mobile file pickers) frequently omit the content type or send a generic one.
_MIME_BY_SUFFIX = {
    ".txt": "text/plain",
    ".text": "text/plain",
    ".md": "text/markdown",
    ".markdown": "text/markdown",
    ".pdf": "application/pdf",
    ".epub": "application/epub+zip",
}


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

    @property
    def max_upload_size_bytes(self) -> int:
        """The largest accepted upload, in bytes."""
        return self._max_upload_size_bytes

    async def upload(
        self,
        *,
        user_id: uuid.UUID,
        filename: str,
        content: bytes,
        content_type: str | None,
        title: str | None,
    ) -> Book:
        """Store an uploaded file and create its library record.

        The file is written before the row; if persisting the row fails the
        stored object is removed again so storage never accumulates orphans.
        """
        if not content:
            raise ValidationError("Uploaded file is empty.")
        if len(content) > self._max_upload_size_bytes:
            raise PayloadTooLargeError(
                "Uploaded file exceeds the maximum allowed size.",
                details={"max_bytes": self._max_upload_size_bytes},
            )

        safe_name = _safe_filename(filename)
        suffix = PurePosixPath(safe_name).suffix.lower()
        book_id = uuid.uuid4()
        storage_key = f"users/{user_id}/books/{book_id}{suffix}"
        mime_type = _resolve_mime_type(content_type, safe_name)

        await self._storage.save(storage_key, content, content_type=mime_type)

        book = Book(
            id=book_id,
            user_id=user_id,
            title=_resolve_title(title, safe_name),
            original_filename=safe_name,
            storage_key=storage_key,
            mime_type=mime_type,
            file_size=len(content),
            status=BookStatus.UPLOADED,
        )
        try:
            await self._repository.add(book)
            await self._repository.commit()
        except Exception:
            await self._repository.rollback()
            await self._discard_object(storage_key)
            raise
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

    async def delete_book(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        """Delete an owned book and its stored file.

        The row is removed first: if the commit fails the book (and its file)
        remain intact. File removal afterwards is best-effort, so a storage
        hiccup can at worst leave an unreachable object, never a broken book.
        """
        book = await self.get_book(user_id, book_id)
        storage_key = book.storage_key
        await self._repository.delete(book)
        await self._repository.commit()
        await self._discard_object(storage_key)

    def apply_processing_state(
        self,
        book: Book,
        status: BookStatus,
        *,
        total_pages: int | None = None,
    ) -> None:
        """Reflect processing progress on the book (the caller commits).

        Lets the processing pipeline keep the library view current without
        reaching into the book's columns directly.
        """
        book.status = status
        if total_pages is not None:
            book.total_pages = total_pages

    async def _discard_object(self, storage_key: str) -> None:
        try:
            await self._storage.delete(storage_key)
        except Exception:
            logger.exception(
                "library.storage_cleanup_failed",
                extra={"storage_key": storage_key},
            )


def _safe_filename(filename: str) -> str:
    # Strip any client-supplied directory components (either separator style).
    name = PurePosixPath(filename.replace("\\", "/")).name.strip()
    if not name:
        return _DEFAULT_FILENAME
    if len(name) <= _MAX_FILENAME_LENGTH:
        return name
    suffix = PurePosixPath(name).suffix
    if len(suffix) > 16:  # not a meaningful extension; don't preserve it
        suffix = ""
    return name[: _MAX_FILENAME_LENGTH - len(suffix)] + suffix


def _resolve_title(title: str | None, filename: str) -> str:
    candidate = (title or "").strip()
    if not candidate:
        candidate = PurePosixPath(filename).stem.strip() or filename
    return candidate[:_MAX_TITLE_LENGTH]


def _resolve_mime_type(content_type: str | None, filename: str) -> str:
    declared = (content_type or "").split(";", 1)[0].strip().lower()
    if declared and declared != _DEFAULT_MIME_TYPE:
        return declared[:_MAX_MIME_LENGTH]
    suffix = PurePosixPath(filename).suffix.lower()
    guessed = _MIME_BY_SUFFIX.get(suffix) or mimetypes.guess_type(filename)[0]
    return guessed or _DEFAULT_MIME_TYPE
