"""HTTP routes for the library module."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, File, Form, UploadFile, status

from app.modules.auth.dependencies import CurrentUser
from app.modules.library.dependencies import BookServiceDep
from app.modules.library.schemas import BookListResponse, BookResponse
from app.modules.processing.dependencies import ProcessingTriggerDep

router = APIRouter()


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

    Responds as soon as the file is stored, with the book in ``PROCESSING``;
    structuring its content runs afterwards through the
    :class:`ProcessingTrigger` seam and never fails the upload. Clients poll
    the book until it is ``READY`` (or ``FAILED``).
    """
    content = await file.read()
    book = await service.upload(
        user_id=user.id,
        filename=file.filename or "book",
        content=content,
        content_type=file.content_type,
        title=title,
    )
    await processing.schedule(user.id, book.id)
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
