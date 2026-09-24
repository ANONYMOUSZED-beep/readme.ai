"""HTTP routes for the library module."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, File, Form, UploadFile, status

from app.core.errors import PayloadTooLargeError
from app.modules.auth.dependencies import CurrentUser
from app.modules.library.dependencies import BookServiceDep
from app.modules.library.schemas import BookListResponse, BookResponse
from app.modules.processing.dependencies import ProcessingTriggerDep

router = APIRouter()

# Uploads are read in bounded chunks so an oversized file is rejected as soon as
# it crosses the limit instead of being loaded into memory in full first.
_UPLOAD_CHUNK_BYTES = 1024 * 1024


async def _read_upload(file: UploadFile, limit: int) -> bytes:
    buffer = bytearray()
    while chunk := await file.read(_UPLOAD_CHUNK_BYTES):
        buffer.extend(chunk)
        if len(buffer) > limit:
            raise PayloadTooLargeError(
                "Uploaded file exceeds the maximum allowed size.",
                details={"max_bytes": limit},
            )
    return bytes(buffer)


@router.post(
    "",
    response_model=BookResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a book",
)
async def upload_book(
    user: CurrentUser,
    service: BookServiceDep,
    processing: ProcessingTriggerDep,
    file: UploadFile = File(..., description="The book file to upload."),
    title: str | None = Form(default=None, description="Optional display title."),
) -> BookResponse:
    """Upload a book file, create its library record, and begin processing.

    Processing is triggered through the :class:`ProcessingTrigger` seam (inline
    today, a background worker later) and never fails the upload — processing
    errors are recorded as the book's processing status.
    """
    # Plain ids are captured because a rollback inside processing expires the
    # session's ORM instances (``user`` included).
    user_id = user.id
    content = await _read_upload(file, service.max_upload_size_bytes)
    book = await service.upload(
        user_id=user_id,
        filename=file.filename or "book",
        content=content,
        content_type=file.content_type,
        title=title,
    )
    book_id = book.id
    await processing.schedule(user_id, book_id)
    # Re-read so the response reflects the status processing just recorded.
    book = await service.get_book(user_id, book_id)
    return BookResponse.model_validate(book)


@router.get("", response_model=BookListResponse, summary="List the user's books")
async def list_books(user: CurrentUser, service: BookServiceDep) -> BookListResponse:
    """Return all books owned by the current user."""
    books = await service.list_books(user.id)
    items = [BookResponse.model_validate(book) for book in books]
    return BookListResponse(items=items, total=len(items))


@router.get("/{book_id}", response_model=BookResponse, summary="Get a book")
async def get_book(
    book_id: uuid.UUID,
    user: CurrentUser,
    service: BookServiceDep,
) -> BookResponse:
    """Return a single book owned by the current user."""
    book = await service.get_book(user.id, book_id)
    return BookResponse.model_validate(book)


@router.delete(
    "/{book_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a book",
)
async def delete_book(
    book_id: uuid.UUID,
    user: CurrentUser,
    service: BookServiceDep,
) -> None:
    """Delete a book owned by the current user, including its stored file."""
    await service.delete_book(user.id, book_id)
