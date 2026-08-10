"""Processing service — orchestrates the processing pipeline.

Pipeline: resolve owned book -> mark PROCESSING -> read bytes -> select a parser
from the registry -> parse into the Document Model -> persist -> COMPLETED /
FAILED. The engine depends only on ``ParserRegistry`` and the ``DocumentParser``
interface, never on a concrete parser or a format-specific exception.
All failures are recorded as structured errors; processing never raises to the
caller for an expected failure (unsupported/malformed/too-large), so triggering
it during upload cannot fail the upload.
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
from app.modules.processing.parsers import (
    ParseRequest,
    ParserError,
    ParserRegistry,
)
from app.modules.processing.processors.base import ProcessingError
from app.modules.processing.repository import ProcessingRepository


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
        registry: ParserRegistry,
        *,
        max_document_bytes: int,
    ) -> None:
        self._repository = repository
        self._book_service = book_service
        self._storage = storage
        self._registry = registry
        self._max_document_bytes = max_document_bytes

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
        book.status = BookStatus.PROCESSING
        await self._repository.commit()

        try:
            data = await self._storage.read(book.storage_key)
            if len(data) > self._max_document_bytes:
                raise ProcessingError(
                    ProcessingErrorCode.TOO_LARGE,
                    "The document is too large to process.",
                )
            # The engine knows only the registry and the parser interface; which
            # parser runs, and which format it understands, is not its concern.
            parser = self._registry.require(
                mime_type=book.mime_type, filename=book.original_filename
            )
            result = await asyncio.to_thread(
                parser.parse,
                ParseRequest(
                    filename=book.original_filename,
                    mime_type=book.mime_type,
                    data=data,
                    source_reference=book.storage_key,
                ),
            )
            await self._repository.save_completed(
                record,
                document=result.document,
                text=result.canonical_text,
                metadata=result.metadata,
                parser_name=result.parser_name,
            )
            book.status = BookStatus.READY
            book.total_pages = result.metadata.page_count
        except ParserError as error:
            await self._repository.save_failed(
                record, error.processing_code, error.message
            )
            book.status = BookStatus.FAILED
        except ProcessingError as error:
            await self._repository.save_failed(record, error.code, error.message)
            book.status = BookStatus.FAILED
        except Exception as error:
            # Record any unexpected failure as a structured internal error
            # rather than letting it escape and break the triggering request.
            await self._repository.save_failed(
                record, ProcessingErrorCode.INTERNAL, str(error)
            )
            book.status = BookStatus.FAILED

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

        # A single row read of the canonical text — no per-paragraph
        # reconstruction, regardless of document size.
        text = await self._repository.get_document_text(record.id) or ""
        return ReaderContent(
            status=ProcessingStatus.COMPLETED,
            title=record.title or book.title,
            text=text,
            character_count=len(text),
        )
