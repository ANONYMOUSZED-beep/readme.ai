"""create reading_activity and reading_goals; backfill book status

Revision ID: 0005_create_activity_tables
Revises: 0004_create_processing_tables
Create Date: 2026-09-25

Processing now keeps ``books.status`` in step with the processing record
(READY / FAILED). Books processed before that change were left at UPLOADED,
so their status is backfilled from ``processed_books``.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0005_create_activity_tables"
down_revision: str | None = "0004_create_processing_tables"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reading_activity",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("activity_date", sa.Date(), nullable=False),
        sa.Column("reading_seconds", sa.Integer(), nullable=False),
        sa.Column("explanations", sa.Integer(), nullable=False),
        sa.Column("bookmarks", sa.Integer(), nullable=False),
        sa.Column("goal_seconds", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id", "activity_date", name="uq_reading_activity_user_date"
        ),
    )
    op.create_index("ix_reading_activity_user_id", "reading_activity", ["user_id"])

    op.create_table(
        "reading_goals",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("daily_minutes", sa.Integer(), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id"),
    )

    for processing_status, book_status in (
        ("COMPLETED", "READY"),
        ("FAILED", "FAILED"),
        ("PROCESSING", "PROCESSING"),
        ("QUEUED", "PROCESSING"),
    ):
        op.execute(
            sa.text(
                "UPDATE books SET status = :book_status WHERE id IN ("
                "SELECT book_id FROM processed_books WHERE status = :processing"
                ")"
            ).bindparams(book_status=book_status, processing=processing_status)
        )


def downgrade() -> None:
    op.drop_table("reading_goals")
    op.drop_index("ix_reading_activity_user_id", table_name="reading_activity")
    op.drop_table("reading_activity")
