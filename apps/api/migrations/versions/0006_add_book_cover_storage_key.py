"""add books.cover_storage_key

Processing now extracts a cover picture (EPUB) and stores it next to the book
file; this column records where.

Revision ID: 0006_add_book_cover_storage_key
Revises: 0005_backfill_book_status
Create Date: 2026-09-24
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0006_add_book_cover_storage_key"
down_revision: str | None = "0005_backfill_book_status"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "books",
        sa.Column("cover_storage_key", sa.String(length=1024), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("books", "cover_storage_key")
