"""Data-access for processed content (repository pattern).

Reprocessing clears a book's structural rows explicitly (in FK-safe order)
rather than relying on database cascade, so behaviour is identical on SQLite
(tests) and PostgreSQL (production).

Structural rows are written with bulk ``INSERT ... VALUES`` statements rather
than through the ORM unit of work: a long book produces tens of thousands of
sentence rows, and per-object ORM bookkeeping was the dominant processing cost.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import Table, delete, func, insert, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import Base
from app.modules.processing.document import StructuredDocument
from app.modules.processing.enums import ProcessingErrorCode, ProcessingStatus
from app.modules.processing.models import (
    Chapter,
    Paragraph,
    ProcessedBook,
    Section,
    Sentence,
)

# Rows per bulk INSERT statement; bounds memory and driver parameter counts.
_INSERT_BATCH_SIZE = 5_000

_Row = dict[str, Any]


class ProcessingRepository:
    """Persistence for :class:`ProcessedBook` and its structural rows."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

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

    async def get_paragraph_texts(
        self,
        processed_book_id: uuid.UUID,
    ) -> list[str]:
        """Return paragraph texts in document order, for reconstruction."""
        result = await self._session.execute(
            select(Paragraph.text)
            .where(Paragraph.processed_book_id == processed_book_id)
            .order_by(Paragraph.order_index)
        )
        return list(result.scalars().all())

    async def get_paragraphs_overlapping(
        self,
        processed_book_id: uuid.UUID,
        start: int,
        end: int,
    ) -> list[Paragraph]:
        """Return paragraphs whose span intersects ``[start, end)``, in order."""
        result = await self._session.execute(
            select(Paragraph)
            .where(
                Paragraph.processed_book_id == processed_book_id,
                Paragraph.start_offset < end,
                Paragraph.end_offset > start,
            )
            .order_by(Paragraph.order_index)
        )
        return list(result.scalars().all())

    async def count_sentences_overlapping(
        self,
        processed_book_id: uuid.UUID,
        start: int,
        end: int,
    ) -> int:
        """Count sentences whose span intersects ``[start, end)``."""
        result = await self._session.execute(
            select(func.count())
            .select_from(Sentence)
            .where(
                Sentence.processed_book_id == processed_book_id,
                Sentence.start_offset < end,
                Sentence.end_offset > start,
            )
        )
        return int(result.scalar_one())

    async def save_failed(
        self,
        record: ProcessedBook,
        code: ProcessingErrorCode,
        message: str,
    ) -> None:
        """Mark the record failed with a structured error."""
        await self._clear_structure(record.id)
        record.status = ProcessingStatus.FAILED
        record.error_code = code.value
        record.error_message = message[:1024]
        record.processed_at = datetime.now(tz=UTC)

    async def save_completed(
        self,
        record: ProcessedBook,
        document: StructuredDocument,
        processor_name: str,
    ) -> None:
        """Persist the structured document and mark the record completed."""
        await self._clear_structure(record.id)
        await self._insert_structure(record.id, document)

        metadata = document.metadata
        record.status = ProcessingStatus.COMPLETED
        record.processor_name = processor_name
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

    async def _clear_structure(self, processed_book_id: uuid.UUID) -> None:
        # FK-safe order: leaves first.
        for model in (Sentence, Paragraph, Section, Chapter):
            await self._session.execute(
                delete(model).where(model.processed_book_id == processed_book_id)
            )

    async def _insert_structure(
        self,
        processed_book_id: uuid.UUID,
        document: StructuredDocument,
    ) -> None:
        """Bulk-insert all structural rows with deterministic anchors.

        Levels are inserted in order (chapters -> sections -> paragraphs ->
        sentences) so each parent exists before its children — required by the
        foreign keys under PostgreSQL, where insert order is enforced.
        """
        chapters: list[_Row] = []
        sections: list[_Row] = []
        paragraphs: list[_Row] = []
        sentences: list[_Row] = []
        paragraph_order = 0

        for chapter_index, chapter in enumerate(document.chapters, start=1):
            chapter_anchor = f"ch{chapter_index}"
            chapter_id = uuid.uuid4()
            chapters.append(
                {
                    "id": chapter_id,
                    "processed_book_id": processed_book_id,
                    "order_index": chapter_index,
                    "anchor": chapter_anchor,
                    "title": chapter.title,
                    "start_offset": chapter.start_offset,
                    "end_offset": chapter.end_offset,
                }
            )

            for section_index, section in enumerate(chapter.sections, start=1):
                section_anchor = f"{chapter_anchor}-sec{section_index}"
                section_id = uuid.uuid4()
                sections.append(
                    {
                        "id": section_id,
                        "processed_book_id": processed_book_id,
                        "chapter_id": chapter_id,
                        "order_index": section_index,
                        "anchor": section_anchor,
                        "title": section.title,
                        "start_offset": section.start_offset,
                        "end_offset": section.end_offset,
                    }
                )

                for para_index, paragraph in enumerate(section.paragraphs, start=1):
                    paragraph_order += 1
                    paragraph_anchor = f"{section_anchor}-p{para_index}"
                    paragraph_id = uuid.uuid4()
                    paragraphs.append(
                        {
                            "id": paragraph_id,
                            "processed_book_id": processed_book_id,
                            "section_id": section_id,
                            "order_index": paragraph_order,
                            "anchor": paragraph_anchor,
                            "start_offset": paragraph.start_offset,
                            "end_offset": paragraph.end_offset,
                            "text": paragraph.text,
                        }
                    )

                    for sent_index, sentence in enumerate(paragraph.sentences, start=1):
                        sentences.append(
                            {
                                "id": uuid.uuid4(),
                                "processed_book_id": processed_book_id,
                                "paragraph_id": paragraph_id,
                                "order_index": sent_index,
                                "anchor": f"{paragraph_anchor}-s{sent_index}",
                                "start_offset": sentence.start_offset,
                                "end_offset": sentence.end_offset,
                            }
                        )

        # Insert parents before children so foreign keys are satisfied.
        for model, rows in (
            (Chapter, chapters),
            (Section, sections),
            (Paragraph, paragraphs),
            (Sentence, sentences),
        ):
            table = _table_of(model)
            for batch in _batched(rows, _INSERT_BATCH_SIZE):
                await self._session.execute(insert(table), batch)


def _table_of(model: type[Base]) -> Table:
    """Return the Core table behind an ORM model, for bulk statements."""
    table = model.__table__
    assert isinstance(table, Table)
    return table


def _batched(rows: list[_Row], size: int) -> Iterator[list[_Row]]:
    """Yield consecutive slices of ``rows`` holding at most ``size`` items."""
    for start in range(0, len(rows), size):
        yield rows[start : start + size]
