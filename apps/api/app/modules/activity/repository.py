"""Data-access for reading activity and goals (repository pattern).

Daily totals are incremented with a single ``INSERT ... ON CONFLICT DO UPDATE``
so concurrent requests (e.g. a progress save racing an explanation) can never
lose an update or trip the one-row-per-day constraint. Both PostgreSQL
(production) and SQLite (tests) support the statement.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime

from sqlalchemy import select, update
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.activity.models import ReadingActivity, ReadingGoal


class ActivityRepository:
    """Persistence for daily reading activity and reading goals.

    Every operation is scoped by ``user_id``.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def increment(
        self,
        user_id: uuid.UUID,
        day: date,
        *,
        goal_seconds: int,
        reading_seconds: int = 0,
        explanations: int = 0,
        bookmarks: int = 0,
    ) -> None:
        """Add to the user's totals for ``day``, creating the row if needed.

        ``goal_seconds`` is only written when the day's row is created, so the
        goal a day was judged against stays fixed.
        """
        now = datetime.now(tz=UTC)
        values = {
            "id": uuid.uuid4(),
            "user_id": user_id,
            "activity_date": day,
            "reading_seconds": reading_seconds,
            "explanations": explanations,
            "bookmarks": bookmarks,
            "goal_seconds": goal_seconds,
            "created_at": now,
            "updated_at": now,
        }
        table = ReadingActivity.__table__.c
        dialect = self._session.get_bind().dialect.name
        if dialect == "postgresql":
            pg_stmt = postgresql.insert(ReadingActivity).values(values)
            await self._session.execute(
                pg_stmt.on_conflict_do_update(
                    index_elements=[table.user_id, table.activity_date],
                    set_={
                        "reading_seconds": table.reading_seconds
                        + pg_stmt.excluded.reading_seconds,
                        "explanations": table.explanations
                        + pg_stmt.excluded.explanations,
                        "bookmarks": table.bookmarks + pg_stmt.excluded.bookmarks,
                        "updated_at": now,
                    },
                )
            )
        else:
            lite_stmt = sqlite.insert(ReadingActivity).values(values)
            await self._session.execute(
                lite_stmt.on_conflict_do_update(
                    index_elements=[table.user_id, table.activity_date],
                    set_={
                        "reading_seconds": table.reading_seconds
                        + lite_stmt.excluded.reading_seconds,
                        "explanations": table.explanations
                        + lite_stmt.excluded.explanations,
                        "bookmarks": table.bookmarks + lite_stmt.excluded.bookmarks,
                        "updated_at": now,
                    },
                )
            )

    async def list_since(
        self,
        user_id: uuid.UUID,
        since: date,
    ) -> list[ReadingActivity]:
        """Return the user's daily rows from ``since`` onwards, oldest first."""
        result = await self._session.execute(
            select(ReadingActivity)
            .where(
                ReadingActivity.user_id == user_id,
                ReadingActivity.activity_date >= since,
            )
            .order_by(ReadingActivity.activity_date)
        )
        return list(result.scalars().all())

    async def get_goal(self, user_id: uuid.UUID) -> ReadingGoal | None:
        return await self._session.get(ReadingGoal, user_id)

    async def save_goal(self, user_id: uuid.UUID, daily_minutes: int) -> None:
        goal = await self.get_goal(user_id)
        if goal is None:
            self._session.add(ReadingGoal(user_id=user_id, daily_minutes=daily_minutes))
        else:
            goal.daily_minutes = daily_minutes

    async def set_day_goal(
        self,
        user_id: uuid.UUID,
        day: date,
        goal_seconds: int,
    ) -> None:
        """Re-point an existing day at a new goal (used for "today" only)."""
        await self._session.execute(
            update(ReadingActivity)
            .where(
                ReadingActivity.user_id == user_id,
                ReadingActivity.activity_date == day,
            )
            .values(goal_seconds=goal_seconds)
        )

    async def commit(self) -> None:
        await self._session.commit()
