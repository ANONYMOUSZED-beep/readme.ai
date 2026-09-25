"""ORM models for processed content.

Two concerns, deliberately separated:

* ``ProcessedBook`` — the processing *record*: lifecycle status, the parser that
  ran, document-level metadata, and failure detail. One row per book.
* ``StoredDocument`` + ``StoredDocumentElement`` — the persisted **Document
  Model** (Sprint 6.2), the single source of truth for document content.

The canonical reading text is stored exactly once, on ``StoredDocument.text``.
Every element carries only ``start_offset``/``end_offset`` into that text, so no
element duplicates document characters. Element rows are a flat, adjacency-list
representation of the tree: ``parent_element_id`` plus ``order_index`` reproduce
the hierarchy on read, which keeps writes to a single bulk insert and makes
child lookups a single indexed range scan instead of a chain of joins.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import (
    JSON,
    BigInteger,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.modules.processing.enums import ProcessingStatus

_ID_LEN = 128
_REFERENCE_LEN = 1024

# JSONB on PostgreSQL (indexable, binary) and JSON on SQLite (tests).
_JSON = JSON().with_variant(JSONB, "postgresql")


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


class StoredDocument(Base):
    """The persisted Document Model root and its canonical reading text."""

    __tablename__ = "documents"

    # The Document Model's own stable, deterministic ID — not a surrogate key.
    id: Mapped[str] = mapped_column(String(_ID_LEN), primary_key=True)
    processed_book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("processed_books.id", ondelete="CASCADE"),
        unique=True,
        index=True,
        nullable=False,
    )
    schema_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    # Source traceability (never part of the logical hierarchy).
    source_page_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_bounding_box: Mapped[dict[str, Any] | None] = mapped_column(
        _JSON, nullable=True
    )
    source_reference: Mapped[str | None] = mapped_column(
        String(_REFERENCE_LEN), nullable=True
    )
    attributes: Mapped[dict[str, Any]] = mapped_column(
        _JSON, default=dict, nullable=False
    )

    # The canonical character stream every offset and anchor addresses. Stored
    # once, here; the reader reads it in a single row lookup.
    text: Mapped[str] = mapped_column(Text, nullable=False)
    character_count: Mapped[int] = mapped_column(BigInteger, nullable=False)


class StoredDocumentElement(Base):
    """One Document Model element, stored as an adjacency-list row."""

    __tablename__ = "document_elements"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    document_id: Mapped[str] = mapped_column(
        ForeignKey("documents.id", ondelete="CASCADE"),
        nullable=False,
    )
    element_id: Mapped[str] = mapped_column(String(_ID_LEN), nullable=False)
    # Intentionally not a foreign key: the tree is validated by the Document
    # Model aggregate on save and on load, so the database does not impose an
    # insert order and the whole document is written in one bulk insert.
    parent_element_id: Mapped[str | None] = mapped_column(
        String(_ID_LEN), nullable=True
    )
    element_type: Mapped[str] = mapped_column(String(64), nullable=False)
    # Sibling order within the parent (semantic, from the Document Model).
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    # Position in the document's element collection (storage order), so a load
    # reconstructs the aggregate exactly as the parser produced it.
    sequence: Mapped[int] = mapped_column(Integer, nullable=False)

    # Span into StoredDocument.text; NULL for elements without readable text.
    start_offset: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    end_offset: Mapped[int | None] = mapped_column(BigInteger, nullable=True)

    source_page_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_bounding_box: Mapped[dict[str, Any] | None] = mapped_column(
        _JSON, nullable=True
    )
    source_reference: Mapped[str | None] = mapped_column(
        String(_REFERENCE_LEN), nullable=True
    )

    # Type-specific fields (title, code, language, image identifier, table cell
    # spans, metadata key/value, and unknown future fields) — one column, so a
    # new element type needs no schema change.
    payload: Mapped[dict[str, Any]] = mapped_column(_JSON, default=dict, nullable=False)
    attributes: Mapped[dict[str, Any]] = mapped_column(
        _JSON, default=dict, nullable=False
    )
    # Inline runs. NULL when they are derivable from the span (see the codec),
    # which keeps sentence rows from duplicating the entire book text.
    content: Mapped[list[Any] | None] = mapped_column(_JSON, nullable=True)

    __table_args__ = (
        UniqueConstraint("document_id", "element_id", name="uq_document_element_id"),
        Index("ix_document_elements_sequence", "document_id", "sequence"),
        Index(
            "ix_document_elements_children",
            "document_id",
            "parent_element_id",
            "order_index",
        ),
        Index(
            "ix_document_elements_span",
            "document_id",
            "element_type",
            "start_offset",
            "end_offset",
        ),
    )
