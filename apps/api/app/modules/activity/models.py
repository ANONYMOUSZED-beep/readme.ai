"""ORM models for the activity module."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime

from sqlalchemy import (
    Date,
    DateTime,
    ForeignKey,
    Integer,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


class ReadingActivity(Base):
    """A user's reading totals for one calendar day (in their local time).

    ``goal_seconds`` snapshots the daily goal in force that day, so changing
    the goal later never rewrites whether past days counted toward a streak.
    """

    __tablename__ = "reading_activity"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "activity_date", name="uq_reading_activity_user_date"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    activity_date: Mapped[date] = mapped_column(Date, nullable=False)
    reading_seconds: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    explanations: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    bookmarks: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    goal_seconds: Mapped[int] = mapped_column(Integer, nullable=False)

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


class ReadingGoal(Base):
    """A user's daily reading goal (absent until they change the default)."""

    __tablename__ = "reading_goals"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    daily_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        server_default=func.now(),
        onupdate=_utcnow,
        nullable=False,
    )
