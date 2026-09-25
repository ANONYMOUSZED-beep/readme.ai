"""Processing service — orchestrates the processing pipeline.

Pipeline: resolve owned book -> mark PROCESSING -> read bytes -> select
processor -> produce structured document -> persist -> COMPLETED / FAILED.
All failures are recorded as structured errors; processing never raises to the
caller for an expected failure (unsupported/malformed/too-large), so triggering
it during upload cannot fail the upload.

The book's own status mirrors the pipeline (PROCESSING -> READY / FAILED) so
clients can follow progress through the library API.
"""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass

from app.core.storage.base import StorageService
from app.modules.library.enums import BookStatus
from app.modules.library.service import BookService
from app.modules.processing.enums import ProcessingErrorCode, ProcessingStatus
from app.modules.processing.models import ProcessedBook
from app.modules.processing.processors.base import ProcessingError
from app.modules.processing.registry import ProcessorRegistry
from app.modules.processing.repository import ProcessingRepository

_PARAGRAPH_SEPARATOR = "\n\n"


@dataclass(frozen=True, slots=True)
class ReaderContent:
    """Readable content derived from a processed document, for the reader."""

    status: ProcessingStatus | None
    title: str
    text: str | None
    character_count: int


class ProcessingService:
    def __init__(
        self,
        repository: ProcessingRepository,
        book_service: BookService,
        storage: StorageService,
        registry: ProcessorRegistry,
        *,
        max_document_bytes: int,
    ) -> None:
        self._repository = repository
        self._book_service = book_service
        self._storage = storage
        self._registry = registry
        self._max_document_bytes = max_document_bytes

    async def mark_queued(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        """Record that processing is about to run, before it starts.

        Lets the upload respond immediately with a ``PROCESSING`` book whose
        status endpoint already exists, while the work itself runs later.
        """
        book = await self._book_service.get_book(user_id, book_id)
        await self._repository.upsert_record(book_id, ProcessingStatus.QUEUED)
        self._book_service.set_status(book, BookStatus.PROCESSING)
        await self._repository.commit()

    async def process_book(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> ProcessedBook:
        """Process a book into structured content (ownership enforced)."""
        book = await self._book_service.get_book(user_id, book_id)

        record = await self._repository.upsert_record(
            book_id, ProcessingStatus.PROCESSING
        )
        self._book_service.set_status(book, BookStatus.PROCESSING)
        await self._repository.commit()

        try:
            data = await self._storage.read(book.storage_key)
            if len(data) > self._max_document_bytes:
                raise ProcessingError(
                    ProcessingErrorCode.TOO_LARGE,
                    "The document is too large to process.",
                )
            processor = self._registry.select(
                mime_type=book.mime_type, filename=book.original_filename
            )
            if processor is None:
                raise ProcessingError(
                    ProcessingErrorCode.UNSUPPORTED_FORMAT,
                    f"No processor supports '{book.mime_type}'.",
                )
            # Parsing is CPU-bound; run it off the event loop so a large book
            # never stalls other requests.
            document = await asyncio.to_thread(
                processor.process,
                filename=book.original_filename,
                mime_type=book.mime_type,
                data=data,
            )
            await self._repository.save_completed(record, document, processor.name)
            self._book_service.set_status(book, BookStatus.READY)
        except ProcessingError as error:
            await self._repository.save_failed(record, error.code, error.message)
            self._book_service.set_status(book, BookStatus.FAILED)
        except Exception as error:
            # Record any unexpected failure as a structured internal error
            # rather than letting it escape and break the triggering request.
            await self._repository.save_failed(
                record, ProcessingErrorCode.INTERNAL, str(error)
            )
            self._book_service.set_status(book, BookStatus.FAILED)

        await self._repository.commit()
        return record

    async def get_status(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> ProcessedBook | None:
        """Return the processing record for an owned book, or ``None``."""
        await self._book_service.get_book(user_id, book_id)
        return await self._repository.get_by_book_id(book_id)

    async def get_reader_content(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> ReaderContent:
        """Return readable content reconstructed from the structured document.

        Text is available only when processing has COMPLETED; otherwise the
        reader renders an unsupported/placeholder state.
        """
        book = await self._book_service.get_book(user_id, book_id)
        record = await self._repository.get_by_book_id(book_id)

        if record is None:
            return ReaderContent(
                status=None, title=book.title, text=None, character_count=0
            )
        if record.status is not ProcessingStatus.COMPLETED:
            return ReaderContent(
                status=record.status,
                title=record.title or book.title,
                text=None,
                character_count=0,
            )

        paragraphs = await self._repository.get_paragraph_texts(record.id)
        text = _PARAGRAPH_SEPARATOR.join(paragraphs)
        return ReaderContent(
            status=ProcessingStatus.COMPLETED,
            title=record.title or book.title,
            text=text,
            character_count=len(text),
        )
