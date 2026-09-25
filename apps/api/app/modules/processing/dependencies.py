"""Dependency wiring for the processing module."""

from __future__ import annotations

import uuid
from functools import lru_cache
from typing import Annotated

from fastapi import BackgroundTasks, Depends
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.config import Settings, get_settings
from app.core.storage.base import StorageService
from app.core.storage.provider import get_storage_service
from app.db.session import get_db_session, get_db_sessionmaker
from app.modules.library.dependencies import get_book_service
from app.modules.library.repository import BookRepository
from app.modules.library.service import BookService
from app.modules.processing.parsers import (
    ParserCapability,
    ParserRegistry,
    ProcessorBackedParser,
    PyMuPdfParser,
)
from app.modules.processing.processors.epub import EpubProcessor
from app.modules.processing.processors.pdf import PdfProcessor
from app.modules.processing.processors.plain_text import PlainTextProcessor
from app.modules.processing.repository import ProcessingRepository
from app.modules.processing.service import ProcessingService
from app.modules.processing.trigger import (
    BackgroundProcessingTrigger,
    ProcessingRunner,
    ProcessingTrigger,
)


@lru_cache(maxsize=1)
def get_parser_registry() -> ParserRegistry:
    """Registry of available document parsers.

    This list is the only place that changes to support a new format. A future
    PyMuPDF, EPUB, DOCX, HTML, Markdown, or OCR parser registers here with a
    higher priority than the generic parsers, and nothing else in the pipeline
    — engine, reader, pagination, explanation, or LIE — is modified.
    """
    return ParserRegistry(
        [
            # PyMuPDF is the production PDF parser (rich structure, page
            # coordinates). The pypdf-backed parser stays registered beneath it
            # as a plain text-extraction fallback for operators who must disable
            # PyMuPDF (it is AGPL/commercial dual-licensed).
            PyMuPdfParser(),
            ProcessorBackedParser(
                PdfProcessor(),
                priority=10,
                display_name="PDF (text layer only)",
                supported_mime_types=("application/pdf",),
                supported_extensions=(".pdf",),
            ),
            # EPUB 2/3 (stdlib-only): chapters follow the spine, headings start
            # sections, and a cover image is kept when the book has one.
            ProcessorBackedParser(
                EpubProcessor(),
                display_name="EPUB",
                supported_mime_types=("application/epub+zip",),
                supported_extensions=(".epub",),
            ),
            ProcessorBackedParser(
                PlainTextProcessor(),
                display_name="Plain text & Markdown",
                capabilities=(
                    ParserCapability.TEXT,
                    ParserCapability.METADATA,
                ),
                supported_mime_types=("text/plain", "text/markdown"),
                supported_extensions=(".txt", ".md"),
            ),
        ]
    )


def get_processing_repository(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> ProcessingRepository:
    return ProcessingRepository(session)


def get_processing_service(
    repository: Annotated[ProcessingRepository, Depends(get_processing_repository)],
    book_service: Annotated[BookService, Depends(get_book_service)],
    storage: Annotated[StorageService, Depends(get_storage_service)],
    registry: Annotated[ParserRegistry, Depends(get_parser_registry)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ProcessingService:
    return ProcessingService(
        repository,
        book_service,
        storage,
        registry,
        max_document_bytes=settings.max_upload_size_bytes,
    )


def get_processing_trigger(
    service: Annotated[ProcessingService, Depends(get_processing_service)],
    background_tasks: BackgroundTasks,
    session_factory: Annotated[
        async_sessionmaker[AsyncSession], Depends(get_db_sessionmaker)
    ],
    storage: Annotated[StorageService, Depends(get_storage_service)],
    registry: Annotated[ParserRegistry, Depends(get_parser_registry)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ProcessingTrigger:
    async def run(user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        # The request's session is closed by now; process in a fresh one.
        async with session_factory() as session:
            background_service = ProcessingService(
                ProcessingRepository(session),
                BookService(
                    BookRepository(session),
                    storage,
                    max_upload_size_bytes=settings.max_upload_size_bytes,
                ),
                storage,
                registry,
                max_document_bytes=settings.max_upload_size_bytes,
            )
            await background_service.process_book(user_id, book_id)

    runner: ProcessingRunner = run
    return BackgroundProcessingTrigger(service, background_tasks, runner)


ProcessingServiceDep = Annotated[ProcessingService, Depends(get_processing_service)]
ProcessingTriggerDep = Annotated[ProcessingTrigger, Depends(get_processing_trigger)]
