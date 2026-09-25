"""backfill book status from processing outcomes

Books are now moved to READY / FAILED when processing finishes. Rows processed
before that change still read UPLOADED; derive their status from the existing
processing record so the library shows the truth for old books too.

Revision ID: 0006_backfill_book_status
Revises: 0005_create_document_tables
Create Date: 2026-09-24
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0006_backfill_book_status"
down_revision: str | None = "0005_create_document_tables"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_OUTCOMES = (
    ("COMPLETED", "READY"),
    ("FAILED", "FAILED"),
    ("PROCESSING", "PROCESSING"),
    ("QUEUED", "PROCESSING"),
)


def upgrade() -> None:
    for processing_status, book_status in _OUTCOMES:
        op.execute(f"""
            UPDATE books SET status = '{book_status}'
            WHERE status = 'UPLOADED'
              AND id IN (
                SELECT book_id FROM processed_books
                WHERE status = '{processing_status}'
              )
            """)


def downgrade() -> None:
    # Data-only migration: the previous code ignored these statuses, so there is
    # nothing to restore.
    pass
