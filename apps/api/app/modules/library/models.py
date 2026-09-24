"""ORM models for the library module."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import (
    BigInteger,
    DateTime,
    Enum,
    ForeignKey,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.modules.library.enums import BookStatus


def _utcnow() -> datetime:
    """Return the current timezone-aware UTC timestamp."""
    return datetime.now(tz=UTC)


class Book(Base):
    """A single uploaded book belonging to a user.

    The binary file lives in object storage under :attr:`storage_key`; this row
    holds only metadata. AI-related columns are nullable placeholders reserved
    for later sprints and are never populated here.
    """

    __tablename__ = "books"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    title: Mapped[str] = mapped_column(String(512), nullable=False)
    original_filename: Mapped[str] = mapped_column(String(512), nullable=False)
    storage_key: Mapped[str] = mapped_column(
        String(1024),
        unique=True,
        index=True,
        nullable=False,
    )
    mime_type: Mapped[str] = mapped_column(String(255), nullable=False)
    file_size: Mapped[int] = mapped_column(BigInteger, nullable=False)
    status: Mapped[BookStatus] = mapped_column(
        Enum(
            BookStatus,
            native_enum=False,
            length=20,
            values_callable=lambda enum: [member.value for member in enum],
        ),
        default=BookStatus.UPLOADED,
        nullable=False,
    )

    # Optional metadata, populated opportunistically.
    total_pages: Mapped[int | None] = mapped_column(nullable=True)
    cover_image_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    # Storage key of the cover extracted during processing (served by the API).
    cover_storage_key: Mapped[str | None] = mapped_column(String(1024), nullable=True)

    # Reserved for a future AI sprint — never written in the Library Foundation.
    ai_summary: Mapped[str | None] = mapped_column(Text, nullable=True)

    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        nullable=False,
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

    @property
    def has_cover(self) -> bool:
        """Whether a cover image is available from the cover endpoint."""
        return self.cover_storage_key is not None

    def __repr__(self) -> str:  # pragma: no cover - debug aid only
        return f"Book(id={self.id!r}, user_id={self.user_id!r}, title={self.title!r})"
