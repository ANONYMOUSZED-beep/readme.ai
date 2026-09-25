"""Activity service — records reading, and derives streaks and daily tasks.

A day counts toward the streak when its reading time meets the goal in force
that day. The current streak runs back from today, or from yesterday while
today's goal is still open, so a streak survives until the day actually ends.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, timedelta
from enum import StrEnum

from app.modules.activity.models import ReadingActivity
from app.modules.activity.repository import ActivityRepository

DEFAULT_GOAL_MINUTES = 10

# One progress save covers the time since the previous save. Cap it so a
# reader left open while the user is away doesn't count as hours of reading.
MAX_READING_SECONDS_PER_SAVE = 15 * 60

EXPLAIN_TARGET = 3
BOOKMARK_TARGET = 1
_WEEK_DAYS = 7


class TaskId(StrEnum):
    """Daily tasks; clients render titles for these ids."""

    READ = "read"
    EXPLAIN = "explain"
    BOOKMARK = "bookmark"


@dataclass(frozen=True, slots=True)
class DailyTask:
    id: TaskId
    progress: int
    target: int

    @property
    def completed(self) -> bool:
        return self.progress >= self.target


@dataclass(frozen=True, slots=True)
class DayActivity:
    date: date
    reading_seconds: int
    goal_met: bool


@dataclass(frozen=True, slots=True)
class ActivitySummary:
    today: date
    daily_goal_minutes: int
    today_reading_seconds: int
    goal_met_today: bool
    current_streak: int
    longest_streak: int
    week: list[DayActivity]
    tasks: list[DailyTask]


class ActivityService:
    def __init__(self, repository: ActivityRepository) -> None:
        self._repository = repository

    # --- recording ---------------------------------------------------------
    async def record_reading(
        self,
        user_id: uuid.UUID,
        day: date,
        seconds: int,
    ) -> None:
        """Add reading time to ``day`` (capped per save; ignores zero)."""
        if seconds <= 0:
            return
        await self._increment(
            user_id, day, reading_seconds=min(seconds, MAX_READING_SECONDS_PER_SAVE)
        )

    async def record_explanation(self, user_id: uuid.UUID, day: date) -> None:
        await self._increment(user_id, day, explanations=1)

    async def record_bookmark(self, user_id: uuid.UUID, day: date) -> None:
        await self._increment(user_id, day, bookmarks=1)

    async def _increment(
        self,
        user_id: uuid.UUID,
        day: date,
        *,
        reading_seconds: int = 0,
        explanations: int = 0,
        bookmarks: int = 0,
    ) -> None:
        goal_minutes = await self._goal_minutes(user_id)
        await self._repository.increment(
            user_id,
            day,
            goal_seconds=goal_minutes * 60,
            reading_seconds=reading_seconds,
            explanations=explanations,
            bookmarks=bookmarks,
        )
        await self._repository.commit()

    # --- goal --------------------------------------------------------------
    async def set_goal(
        self,
        user_id: uuid.UUID,
        daily_minutes: int,
        today: date,
    ) -> ActivitySummary:
        """Change the daily goal from today onwards and return the summary."""
        await self._repository.save_goal(user_id, daily_minutes)
        await self._repository.set_day_goal(user_id, today, daily_minutes * 60)
        await self._repository.commit()
        return await self.get_summary(user_id, today)

    async def _goal_minutes(self, user_id: uuid.UUID) -> int:
        goal = await self._repository.get_goal(user_id)
        return goal.daily_minutes if goal is not None else DEFAULT_GOAL_MINUTES

    # --- summary -----------------------------------------------------------
    async def get_summary(self, user_id: uuid.UUID, today: date) -> ActivitySummary:
        goal_minutes = await self._goal_minutes(user_id)
        # One row per active day, so a user's full history stays small.
        rows = await self._repository.list_since(user_id, date.min)
        by_day = {row.activity_date: row for row in rows}
        met = {row.activity_date for row in rows if _goal_met(row)}

        today_row = by_day.get(today)
        today_seconds = today_row.reading_seconds if today_row else 0
        week_start = today - timedelta(days=_WEEK_DAYS - 1)
        week = [
            DayActivity(
                date=day,
                reading_seconds=by_day[day].reading_seconds if day in by_day else 0,
                goal_met=day in met,
            )
            for day in (week_start + timedelta(days=i) for i in range(_WEEK_DAYS))
        ]
        tasks = [
            DailyTask(
                TaskId.READ,
                progress=min(today_seconds // 60, goal_minutes),
                target=goal_minutes,
            ),
            DailyTask(
                TaskId.EXPLAIN,
                progress=min(
                    today_row.explanations if today_row else 0, EXPLAIN_TARGET
                ),
                target=EXPLAIN_TARGET,
            ),
            DailyTask(
                TaskId.BOOKMARK,
                progress=min(today_row.bookmarks if today_row else 0, BOOKMARK_TARGET),
                target=BOOKMARK_TARGET,
            ),
        ]
        return ActivitySummary(
            today=today,
            daily_goal_minutes=goal_minutes,
            today_reading_seconds=today_seconds,
            goal_met_today=today in met,
            current_streak=current_streak(met, today),
            longest_streak=longest_streak(met),
            week=week,
            tasks=tasks,
        )


def _goal_met(row: ReadingActivity) -> bool:
    return row.goal_seconds > 0 and row.reading_seconds >= row.goal_seconds


def current_streak(met_days: set[date], today: date) -> int:
    """Consecutive goal days ending today, or yesterday if today is still open."""
    day = today if today in met_days else today - timedelta(days=1)
    streak = 0
    while day in met_days:
        streak += 1
        day -= timedelta(days=1)
    return streak


def longest_streak(met_days: set[date]) -> int:
    """Length of the longest run of consecutive goal days."""
    best = 0
    for day in met_days:
        if day - timedelta(days=1) in met_days:
            continue  # Not the start of a run.
        length = 1
        while day + timedelta(days=length) in met_days:
            length += 1
        best = max(best, length)
    return best
