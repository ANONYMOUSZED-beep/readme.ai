"""persist the document model and drop the legacy structural hierarchy

The Document Model becomes the single source of truth. ``processed_books`` keeps
the processing record (status, parser, metadata); the legacy
chapter/section/paragraph/sentence tables are replaced by ``documents`` (root +
canonical text) and ``document_elements`` (flat adjacency list of elements).

Structural content is derived data: books are reprocessed from their stored
source files, so the legacy rows are dropped rather than back-filled. The
downgrade recreates the legacy schema, but structural data is not recoverable.

Revision ID: 0005_create_document_tables
Revises: 0004_create_processing_tables
Create Date: 2026-07-27
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "0005_create_document_tables"
down_revision: str | None = "0004_create_processing_tables"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_ID = sa.String(length=128)
_REFERENCE = sa.String(length=1024)
_ANCHOR = sa.String(length=128)
_JSON = sa.JSON().with_variant(JSONB, "postgresql")

_LEGACY_TABLES = (
    "processed_sentences",
    "processed_paragraphs",
    "processed_sections",
    "processed_chapters",
)


def upgrade() -> None:
    _create_documents()
    _create_document_elements()
    for table in _LEGACY_TABLES:
        op.drop_table(table)


def downgrade() -> None:
    op.drop_table("document_elements")
    op.drop_table("documents")
    _create_legacy_tables()


def _create_documents() -> None:
    op.create_table(
        "documents",
        sa.Column("id", _ID, nullable=False),
        sa.Column("processed_book_id", sa.Uuid(), nullable=False),
        sa.Column("schema_version", sa.Integer(), nullable=False),
        sa.Column("source_page_number", sa.Integer(), nullable=True),
        sa.Column("source_bounding_box", _JSON, nullable=True),
        sa.Column("source_reference", _REFERENCE, nullable=True),
        sa.Column("attributes", _JSON, nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("character_count", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["processed_book_id"], ["processed_books.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("processed_book_id"),
    )
    op.create_index(
        "ix_documents_processed_book_id",
        "documents",
        ["processed_book_id"],
    )


def _create_document_elements() -> None:
    op.create_table(
        "document_elements",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("document_id", _ID, nullable=False),
        sa.Column("element_id", _ID, nullable=False),
        sa.Column("parent_element_id", _ID, nullable=True),
        sa.Column("element_type", sa.String(length=64), nullable=False),
        sa.Column("order_index", sa.Integer(), nullable=False),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("start_offset", sa.BigInteger(), nullable=True),
        sa.Column("end_offset", sa.BigInteger(), nullable=True),
        sa.Column("source_page_number", sa.Integer(), nullable=True),
        sa.Column("source_bounding_box", _JSON, nullable=True),
        sa.Column("source_reference", _REFERENCE, nullable=True),
        sa.Column("payload", _JSON, nullable=False),
        sa.Column("attributes", _JSON, nullable=False),
        sa.Column("content", _JSON, nullable=True),
        sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("document_id", "element_id", name="uq_document_element_id"),
    )
    op.create_index(
        "ix_document_elements_sequence",
        "document_elements",
        ["document_id", "sequence"],
    )
    op.create_index(
        "ix_document_elements_children",
        "document_elements",
        ["document_id", "parent_element_id", "order_index"],
    )
    op.create_index(
        "ix_document_elements_span",
        "document_elements",
        ["document_id", "element_type", "start_offset", "end_offset"],
    )


def _create_legacy_tables() -> None:
    """Recreate the pre-6.3.5 hierarchy (schema only; content is derived)."""
    op.create_table(
        "processed_chapters",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("processed_book_id", sa.Uuid(), nullable=False),
        sa.Column("order_index", sa.Integer(), nullable=False),
        sa.Column("anchor", _ANCHOR, nullable=False),
        sa.Column("title", sa.String(length=512), nullable=True),
        sa.Column("start_offset", sa.BigInteger(), nullable=False),
        sa.Column("end_offset", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["processed_book_id"], ["processed_books.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_processed_chapters_processed_book_id",
        "processed_chapters",
        ["processed_book_id"],
    )
    op.create_table(
        "processed_sections",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("processed_book_id", sa.Uuid(), nullable=False),
        sa.Column("chapter_id", sa.Uuid(), nullable=False),
        sa.Column("order_index", sa.Integer(), nullable=False),
        sa.Column("anchor", _ANCHOR, nullable=False),
        sa.Column("title", sa.String(length=512), nullable=True),
        sa.Column("start_offset", sa.BigInteger(), nullable=False),
        sa.Column("end_offset", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["processed_book_id"], ["processed_books.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["chapter_id"], ["processed_chapters.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_processed_sections_processed_book_id",
        "processed_sections",
        ["processed_book_id"],
    )
    op.create_index(
        "ix_processed_sections_chapter_id", "processed_sections", ["chapter_id"]
    )
    op.create_table(
        "processed_paragraphs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("processed_book_id", sa.Uuid(), nullable=False),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("order_index", sa.Integer(), nullable=False),
        sa.Column("anchor", _ANCHOR, nullable=False),
        sa.Column("start_offset", sa.BigInteger(), nullable=False),
        sa.Column("end_offset", sa.BigInteger(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(
            ["processed_book_id"], ["processed_books.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["section_id"], ["processed_sections.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_processed_paragraphs_processed_book_id",
        "processed_paragraphs",
        ["processed_book_id"],
    )
    op.create_index(
        "ix_processed_paragraphs_section_id", "processed_paragraphs", ["section_id"]
    )
    op.create_table(
        "processed_sentences",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("processed_book_id", sa.Uuid(), nullable=False),
        sa.Column("paragraph_id", sa.Uuid(), nullable=False),
        sa.Column("order_index", sa.Integer(), nullable=False),
        sa.Column("anchor", _ANCHOR, nullable=False),
        sa.Column("start_offset", sa.BigInteger(), nullable=False),
        sa.Column("end_offset", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["processed_book_id"], ["processed_books.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["paragraph_id"], ["processed_paragraphs.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_processed_sentences_processed_book_id",
        "processed_sentences",
        ["processed_book_id"],
    )
    op.create_index(
        "ix_processed_sentences_paragraph_id", "processed_sentences", ["paragraph_id"]
    )
