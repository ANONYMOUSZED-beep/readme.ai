"""Pydantic schemas for the activity module."""

from __future__ import annotations

from datetime import date

from pydantic import BaseModel, ConfigDict, Field

from app.modules.activity.service import TaskId


class DayActivityResponse(BaseModel):
    """Reading on one day of the recent week."""

    model_config = ConfigDict(from_attributes=True)

    date: date
    reading_seconds: int
    goal_met: bool


class DailyTaskResponse(BaseModel):
    """Progress on one of today's tasks; clients render titles by ``id``."""

    model_config = ConfigDict(from_attributes=True)

    id: TaskId
    progress: int
    target: int
    completed: bool


class ActivitySummaryResponse(BaseModel):
    """Streak, goal, recent week, and today's tasks for the current user."""

    model_config = ConfigDict(from_attributes=True)

    today: date = Field(description="The client's local date the summary is for.")
    daily_goal_minutes: int
    today_reading_seconds: int
    goal_met_today: bool
    current_streak: int = Field(description="Consecutive days the goal was met.")
    longest_streak: int
    week: list[DayActivityResponse] = Field(description="Last 7 days, oldest first.")
    tasks: list[DailyTaskResponse]


class UpdateGoalRequest(BaseModel):
    """Payload to change the daily reading goal."""

    daily_minutes: int = Field(ge=1, le=240, description="Daily goal in minutes.")
