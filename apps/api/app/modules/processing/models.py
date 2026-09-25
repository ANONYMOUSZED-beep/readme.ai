"""ORM models for processed (structured) book content.

Normalised hierarchy: ``ProcessedBook`` -> ``Chapter`` -> ``Section`` ->
``Paragraph`` -> ``Sentence``. Text is stored exactly once, on ``Paragraph``;
sentences and higher levels carry only character offsets into the canonical
document text, so there is no content duplication.

Each structural row carries a ``processed_book_id`` (a denormalised parent
reference) and a deterministic ``anchor``. The denormalisation enables efficient
single-table reads (e.g. reconstructing the document by ordering paragraphs)
without walking the hierarchy, which matters for very large books.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import (
    BigInteger,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.modules.processing.enums import ProcessingStatus

_ANCHOR_LEN = 128


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


class ProcessedBook(Base):
    """Document-level processing record and metadata (one per book)."""

    __tablename__ = "processed_books"
    # Mirrors migration 0004: a named unique constraint plus a plain index.
    __table_args__ = (UniqueConstraint("book_id", name="uq_processed_books_book_id"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("books.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    status: Mapped[ProcessingStatus] = mapped_column(
        Enum(
            ProcessingStatus,
            native_enum=False,
            length=20,
            values_callable=lambda enum: [member.value for member in enum],
        ),
        nullable=False,
    )
    processor_name: Mapped[str | None] = mapped_column(String(64), nullable=True)

    # Metadata (nullable where unavailable).
    title: Mapped[str | None] = mapped_column(String(512), nullable=True)
    author: Mapped[str | None] = mapped_column(String(512), nullable=True)
    language: Mapped[str | None] = mapped_column(String(32), nullable=True)
    page_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    word_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    character_count: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    estimated_reading_minutes: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )

    # Failure detail (nullable on success).
    error_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    error_message: Mapped[str | None] = mapped_column(String(1024), nullable=True)

    processed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        server_default=func.now(),
        onupdate=_utcnow,
        nullable=False,
    )


class Chapter(Base):
    """A chapter within a processed document."""

    __tablename__ = "processed_chapters"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    processed_book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_books.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    anchor: Mapped[str] = mapped_column(String(_ANCHOR_LEN), nullable=False)
    title: Mapped[str | None] = mapped_column(String(512), nullable=True)
    start_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)
    end_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)


class Section(Base):
    """A section within a chapter."""

    __tablename__ = "processed_sections"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    processed_book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_books.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    chapter_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_chapters.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    anchor: Mapped[str] = mapped_column(String(_ANCHOR_LEN), nullable=False)
    title: Mapped[str | None] = mapped_column(String(512), nullable=True)
    start_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)
    end_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)


class Paragraph(Base):
    """A paragraph — the only row that stores text."""

    __tablename__ = "processed_paragraphs"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    processed_book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_books.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    section_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_sections.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    # Global ordering across the whole document for efficient reconstruction.
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    anchor: Mapped[str] = mapped_column(String(_ANCHOR_LEN), nullable=False)
    start_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)
    end_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)


class Sentence(Base):
    """A sentence, addressed only by offsets (text derived from the paragraph)."""

    __tablename__ = "processed_sentences"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    processed_book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_books.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    paragraph_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_paragraphs.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    anchor: Mapped[str] = mapped_column(String(_ANCHOR_LEN), nullable=False)
    start_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)
    end_offset: Mapped[int] = mapped_column(BigInteger, nullable=False)
