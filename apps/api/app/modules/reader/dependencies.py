"""Dependency wiring for the reader module."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db_session
from app.modules.library.dependencies import get_book_service
from app.modules.library.service import BookService
from app.modules.processing.dependencies import (
    get_processing_repository,
    get_processing_service,
)
from app.modules.processing.element_query import DocumentElementQuery
from app.modules.processing.repository import ProcessingRepository
from app.modules.processing.service import ProcessingService
from app.modules.reader.repository import ReaderRepository
from app.modules.reader.service import ReaderService


def get_document_element_query(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> DocumentElementQuery:
    """Provide the request-scoped element read model."""
    return DocumentElementQuery(session)


def get_reader_repository(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> ReaderRepository:
    """Provide a request-scoped reader repository."""
    return ReaderRepository(session)


def get_reader_service(
    repository: Annotated[ReaderRepository, Depends(get_reader_repository)],
    book_service: Annotated[BookService, Depends(get_book_service)],
    processing_service: Annotated[ProcessingService, Depends(get_processing_service)],
    processing_repository: Annotated[
        ProcessingRepository, Depends(get_processing_repository)
    ],
    elements: Annotated[DocumentElementQuery, Depends(get_document_element_query)],
) -> ReaderService:
    """Provide the reader service for the current request."""
    return ReaderService(
        repository,
        book_service,
        processing_service,
        processing_repository,
        elements,
    )


ReaderServiceDep = Annotated[ReaderService, Depends(get_reader_service)]
