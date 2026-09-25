"""Data-access for processed content (repository pattern).

This repository owns the ``ProcessedBook`` record and delegates all document
content to :class:`DocumentStore`, which persists the Document Model. Callers —
the processing engine, the reader, and the selection classifier — never see a
structural table or an ORM entity, so the storage layout can evolve without
touching them.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.processing.document import DocumentMetadata
from app.modules.processing.document_model import Document, ElementType
from app.modules.processing.document_store import (
    CONTEXT_TYPES,
    DocumentStore,
    TextSpan,
)
from app.modules.processing.enums import ProcessingErrorCode, ProcessingStatus
from app.modules.processing.models import ProcessedBook


class ProcessingRepository:
    """Persistence for :class:`ProcessedBook` and its Document Model."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._documents = DocumentStore(session)

    @property
    def documents(self) -> DocumentStore:
        """The Document Model store, for callers that need the full document."""
        return self._documents

    async def get_by_book_id(self, book_id: uuid.UUID) -> ProcessedBook | None:
        result = await self._session.execute(
            select(ProcessedBook).where(ProcessedBook.book_id == book_id)
        )
        return result.scalar_one_or_none()

    async def upsert_record(
        self,
        book_id: uuid.UUID,
        status: ProcessingStatus,
    ) -> ProcessedBook:
        """Create the processing record if absent, else set its status."""
        record = await self.get_by_book_id(book_id)
        if record is None:
            record = ProcessedBook(book_id=book_id, status=status)
            self._session.add(record)
            await self._session.flush()
        else:
            record.status = status
        return record

    async def commit(self) -> None:
        await self._session.commit()

    async def rollback(self) -> None:
        await self._session.rollback()

    async def get_chapter_outline(
        self, processed_book_id: uuid.UUID
    ) -> list[tuple[str | None, int]]:
        """Each chapter's title and start offset, in reading order."""
        return await self._documents.chapter_outline(processed_book_id)

    async def get_document_text(self, processed_book_id: uuid.UUID) -> str | None:
        """The canonical reading text, read directly — no reconstruction."""
        return await self._documents.get_text(processed_book_id)

    async def get_document(self, processed_book_id: uuid.UUID) -> Document | None:
        """The complete, re-validated Document Model."""
        return await self._documents.load(processed_book_id)

    async def get_paragraphs_overlapping(
        self,
        processed_book_id: uuid.UUID,
        start: int,
        end: int,
    ) -> list[TextSpan]:
        """Grounding-context spans intersecting ``[start, end)``, in reading order.

        This is the seam the Explanation Engine's selection classifier calls. It
        returns every context-bearing element type (paragraphs, code blocks,
        quotes, list items, footnotes, formulas, captions, table cells), so a
        reader can explain a selection anywhere in the reading flow — not only
        inside prose.

        The method name is retained deliberately: widening happens here, in
        persistence, and the Explanation Engine is not modified. For selections
        that touch only paragraphs the result is identical to the previous
        paragraph-only query, because the context types are non-overlapping
        siblings and sentences are excluded (see ``CONTEXT_TYPES``).
        """
        return await self._documents.spans_overlapping_types(
            processed_book_id, CONTEXT_TYPES, start, end
        )

    async def count_sentences_overlapping(
        self,
        processed_book_id: uuid.UUID,
        start: int,
        end: int,
    ) -> int:
        """Count sentences intersecting ``[start, end)``."""
        return await self._documents.count_overlapping(
            processed_book_id, ElementType.SENTENCE, start, end
        )

    async def save_failed(
        self,
        record: ProcessedBook,
        code: ProcessingErrorCode,
        message: str,
    ) -> None:
        """Mark the record failed with a structured error."""
        await self._documents.clear(record.id)
        record.status = ProcessingStatus.FAILED
        record.error_code = code.value
        record.error_message = message[:1024]
        record.processed_at = datetime.now(tz=UTC)

    async def save_completed(
        self,
        record: ProcessedBook,
        *,
        document: Document,
        text: str,
        metadata: DocumentMetadata,
        parser_name: str,
    ) -> None:
        """Persist the Document Model and mark the record completed."""
        await self._documents.save(record.id, document, text=text)

        record.status = ProcessingStatus.COMPLETED
        record.processor_name = parser_name
        record.title = metadata.title
        record.author = metadata.author
        record.language = metadata.language
        record.page_count = metadata.page_count
        record.word_count = metadata.word_count
        record.character_count = metadata.character_count
        record.estimated_reading_minutes = metadata.estimated_reading_minutes
        record.error_code = None
        record.error_message = None
        record.processed_at = datetime.now(tz=UTC)
