"""Processing service — orchestrates the processing pipeline.

Pipeline: resolve owned book -> mark PROCESSING -> read bytes -> select a parser
from the registry -> parse into the Document Model -> persist -> COMPLETED /
FAILED. The engine depends only on ``ParserRegistry`` and the ``DocumentParser``
interface, never on a concrete parser or a format-specific exception.
The library book's status mirrors the outcome (PROCESSING -> READY | FAILED)
so clients can show it without a second call.

All failures are recorded as structured errors; processing never raises to the
caller for an expected failure (unsupported/malformed/too-large), so triggering
it during upload cannot fail the upload. Unexpected failures are logged in full
but reported to clients with a generic message, never internal detail.
"""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass, field

from app.core.logging import get_logger
from app.core.storage.base import StorageService
from app.modules.library.enums import BookStatus
from app.modules.library.models import Book
from app.modules.library.service import BookService
from app.modules.processing.document import CoverImage
from app.modules.processing.enums import ProcessingErrorCode, ProcessingStatus
from app.modules.processing.models import ProcessedBook
from app.modules.processing.parsers import (
    ParseRequest,
    ParserError,
    ParseResult,
    ParserRegistry,
)
from app.modules.processing.processors.base import ProcessingError
from app.modules.processing.repository import ProcessingRepository

logger = get_logger(__name__)

_INTERNAL_ERROR_MESSAGE = "An unexpected error occurred while processing the book."


@dataclass(frozen=True, slots=True)
class ChapterMark:
    """Where a chapter starts in the reader's text (for a table of contents)."""

    title: str | None
    start_offset: int


@dataclass(frozen=True, slots=True)
class ReaderContent:
    """Readable content derived from a processed document, for the reader."""

    status: ProcessingStatus | None
    title: str
    text: str | None
    character_count: int
    chapters: list[ChapterMark] = field(default_factory=list)


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

    async def mark_queued(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        """Record that processing is about to run, before it starts.

        Lets the upload respond immediately with a ``PROCESSING`` book whose
        status endpoint already exists, while the work itself runs later.
        """
        book = await self._book_service.get_book(user_id, book_id)
        try:
            await self._repository.upsert_record(book_id, ProcessingStatus.QUEUED)
            self._book_service.apply_processing_state(book, BookStatus.PROCESSING)
            await self._repository.commit()
        except Exception:
            # Leave the session usable for the caller before propagating.
            await self._repository.rollback()
            raise

    async def process_book(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
    ) -> ProcessedBook:
        """Process a book into structured content (ownership enforced)."""
        book = await self._book_service.get_book(user_id, book_id)
        storage_key = book.storage_key
        mime_type = book.mime_type
        filename = book.original_filename

        try:
            record = await self._repository.upsert_record(
                book_id, ProcessingStatus.PROCESSING
            )
            self._book_service.apply_processing_state(book, BookStatus.PROCESSING)
            await self._repository.commit()
        except Exception:
            # Leave the session usable for the caller before propagating.
            await self._repository.rollback()
            raise

        try:
            result = await self._parse(
                storage_key=storage_key, mime_type=mime_type, filename=filename
            )
        except ParserError as error:
            if error.processing_code is ProcessingErrorCode.INTERNAL:
                # A parser crash carries internal detail (paths, library
                # messages): keep it in the logs, never in the API response.
                logger.error(
                    "processing.parser_failed",
                    extra={"book_id": str(book_id), "error": error.message},
                )
                return await self._record_failure(
                    user_id,
                    book_id,
                    ProcessingErrorCode.INTERNAL,
                    _INTERNAL_ERROR_MESSAGE,
                )
            return await self._record_failure(
                user_id, book_id, error.processing_code, error.message
            )
        except ProcessingError as error:
            return await self._record_failure(
                user_id, book_id, error.code, error.message
            )
        except Exception:
            logger.exception("processing.failed", extra={"book_id": str(book_id)})
            return await self._record_failure(
                user_id, book_id, ProcessingErrorCode.INTERNAL, _INTERNAL_ERROR_MESSAGE
            )

        try:
            await self._repository.save_completed(
                record,
                document=result.document,
                text=result.canonical_text,
                metadata=result.metadata,
                parser_name=result.parser_name,
            )
            self._book_service.apply_processing_state(
                book, BookStatus.READY, total_pages=result.metadata.page_count
            )
            await self._repository.commit()
        except Exception:
            logger.exception(
                "processing.persist_failed", extra={"book_id": str(book_id)}
            )
            await self._repository.rollback()
            return await self._record_failure(
                user_id, book_id, ProcessingErrorCode.INTERNAL, _INTERNAL_ERROR_MESSAGE
            )

        if await self._store_cover(book, result.cover, book_id):
            return record
        # The rollback expired loaded rows; re-read the committed record.
        refreshed = await self._repository.get_by_book_id(book_id)
        return refreshed if refreshed is not None else record

    async def _store_cover(
        self, book: Book, cover: CoverImage | None, book_id: uuid.UUID
    ) -> bool:
        """Save (or clear) the cover. Best effort: never fails the book.

        Returns ``False`` when it failed and the session was rolled back.
        """
        try:
            await self._book_service.replace_cover(book, cover.data if cover else None)
        except Exception:
            logger.exception("processing.cover_failed", extra={"book_id": str(book_id)})
            await self._repository.rollback()
            return False
        return True

    async def _parse(
        self,
        *,
        storage_key: str,
        mime_type: str,
        filename: str,
    ) -> ParseResult:
        data = await self._storage.read(storage_key)
        if len(data) > self._max_document_bytes:
            raise ProcessingError(
                ProcessingErrorCode.TOO_LARGE,
                "The document is too large to process.",
            )
        # The engine knows only the registry and the parser interface; which
        # parser runs, and which format it understands, is not its concern.
        parser = self._registry.require(mime_type=mime_type, filename=filename)
        # Parsing is CPU-bound; keep it off the event loop so one large book
        # cannot stall every other request served by this process.
        return await asyncio.to_thread(
            parser.parse,
            ParseRequest(
                filename=filename,
                mime_type=mime_type,
                data=data,
                source_reference=storage_key,
            ),
        )

    async def _record_failure(
        self,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
        code: ProcessingErrorCode,
        message: str,
    ) -> ProcessedBook:
        # Re-resolve both rows: a preceding rollback expires loaded instances.
        book: Book = await self._book_service.get_book(user_id, book_id)
        record = await self._repository.upsert_record(book_id, ProcessingStatus.FAILED)
        await self._repository.save_failed(record, code, message)
        self._book_service.apply_processing_state(book, BookStatus.FAILED)
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
        reader renders an unsupported/placeholder state. The title is always the
        library title, so the reader matches what the user sees (and chose) in
        their library rather than, say, a PDF's embedded producer metadata.
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
                title=book.title,
                text=None,
                character_count=0,
            )

        # A single row read of the canonical text — no per-paragraph
        # reconstruction, regardless of document size.
        text = await self._repository.get_document_text(record.id) or ""
        outline = await self._repository.get_chapter_outline(record.id)
        return ReaderContent(
            status=ProcessingStatus.COMPLETED,
            title=book.title,
            text=text,
            character_count=len(text),
            chapters=[
                ChapterMark(title=title, start_offset=start) for title, start in outline
            ],
        )
