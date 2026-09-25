"""Tests for reading activity: streaks, goals, daily tasks, and recording."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.activity.clock import local_today
from app.modules.activity.models import ReadingActivity
from app.modules.activity.service import (
    MAX_READING_SECONDS_PER_SAVE,
    current_streak,
    longest_streak,
)
from app.modules.auth.models import User
from app.modules.auth.verifier import FirebaseIdentity
from tests.conftest import FakeTokenVerifier

# UTC+05:30 (India), sent the way the app sends it.
_OFFSET = 330
_AUTH = {"Authorization": "Bearer valid-token", "X-Timezone-Offset": str(_OFFSET)}
_BOOKS = "/api/v1/books"
_SUMMARY = "/api/v1/activity/summary"
_TEXT = b"# Title\n\nFirst paragraph. Two sentences here.\n\nSecond paragraph."


def _today() -> date:
    return local_today(_OFFSET)


async def _upload(client: AsyncClient) -> str:
    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": ("book.txt", _TEXT, "text/plain")}
    )
    assert response.status_code == 201
    return str(response.json()["id"])


async def _read(client: AsyncClient, book_id: str, seconds: int) -> None:
    response = await client.put(
        f"{_BOOKS}/{book_id}/progress",
        headers=_AUTH,
        json={
            "current_position": "10",
            "progress_percentage": 10.0,
            "reading_time_seconds": seconds,
        },
    )
    assert response.status_code == 200


async def _seed_days(
    sessionmaker: async_sessionmaker[AsyncSession],
    days_ago: list[int],
    *,
    goal_seconds: int = 600,
) -> None:
    """Record goal-meeting reading for the given days before today."""
    async with sessionmaker() as session:
        user = await session.scalar(select(User))
        assert user is not None
        for ago in days_ago:
            session.add(
                ReadingActivity(
                    user_id=user.id,
                    activity_date=_today() - timedelta(days=ago),
                    reading_seconds=goal_seconds,
                    goal_seconds=goal_seconds,
                )
            )
        await session.commit()


# --- streak rules (pure) ---------------------------------------------------
def test_current_streak_counts_back_from_today() -> None:
    today = date(2026, 9, 25)
    days = {today - timedelta(days=i) for i in range(3)}
    assert current_streak(days, today) == 3


def test_current_streak_survives_until_today_ends() -> None:
    today = date(2026, 9, 25)
    days = {today - timedelta(days=i) for i in range(1, 5)}
    assert current_streak(days, today) == 4


def test_current_streak_breaks_on_a_missed_day() -> None:
    today = date(2026, 9, 25)
    days = {today - timedelta(days=2), today - timedelta(days=3)}
    assert current_streak(days, today) == 0


def test_longest_streak_finds_the_longest_run() -> None:
    start = date(2026, 1, 1)
    days = {start + timedelta(days=i) for i in (0, 1, 2, 5, 6, 7, 8, 12)}
    assert longest_streak(days) == 4
    assert longest_streak(set()) == 0


def test_local_today_uses_the_client_offset() -> None:
    now = datetime(2026, 9, 25, 20, 0, tzinfo=UTC)
    assert local_today(0, now=now) == date(2026, 9, 25)
    assert local_today(330, now=now) == date(2026, 9, 26)  # 01:30 in Kolkata
    assert local_today(-600, now=now) == date(2026, 9, 25)
    # Out-of-range offsets are clamped to real-world bounds (UTC+14).
    assert local_today(10_000, now=now) == date(2026, 9, 26)


# --- API ---------------------------------------------------------------------
async def test_new_reader_starts_with_empty_summary(client: AsyncClient) -> None:
    response = await client.get(_SUMMARY, headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["today"] == _today().isoformat()
    assert body["daily_goal_minutes"] == 10
    assert body["current_streak"] == 0
    assert body["goal_met_today"] is False
    assert len(body["week"]) == 7
    assert body["week"][-1]["date"] == _today().isoformat()
    assert [task["id"] for task in body["tasks"]] == ["read", "explain", "bookmark"]
    assert not any(task["completed"] for task in body["tasks"])


async def test_reading_the_goal_starts_a_streak(client: AsyncClient) -> None:
    book_id = await _upload(client)

    await _read(client, book_id, 4 * 60)
    partial = (await client.get(_SUMMARY, headers=_AUTH)).json()
    await _read(client, book_id, 6 * 60)
    done = (await client.get(_SUMMARY, headers=_AUTH)).json()

    assert partial["tasks"][0] == {
        "id": "read",
        "progress": 4,
        "target": 10,
        "completed": False,
    }
    assert partial["current_streak"] == 0
    assert done["today_reading_seconds"] == 600
    assert done["goal_met_today"] is True
    assert done["current_streak"] == 1
    assert done["tasks"][0]["completed"] is True
    assert done["week"][-1]["goal_met"] is True


async def test_streak_continues_from_previous_days(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _upload(client)  # Provisions the user.
    await _seed_days(sessionmaker, [1, 2, 3, 6, 7])

    before = (await client.get(_SUMMARY, headers=_AUTH)).json()
    await _read(client, book_id, 10 * 60)
    after = (await client.get(_SUMMARY, headers=_AUTH)).json()

    # Yesterday's streak is still alive before reading today...
    assert before["current_streak"] == 3
    assert before["goal_met_today"] is False
    # ...and today's reading extends it.
    assert after["current_streak"] == 4
    assert after["longest_streak"] == 4


async def test_idle_time_per_save_is_capped(client: AsyncClient) -> None:
    book_id = await _upload(client)

    await _read(client, book_id, 3 * 60 * 60)

    body = (await client.get(_SUMMARY, headers=_AUTH)).json()
    assert body["today_reading_seconds"] == MAX_READING_SECONDS_PER_SAVE


async def test_explanations_and_bookmarks_complete_tasks(
    client: AsyncClient,
) -> None:
    book_id = await _upload(client)
    for _ in range(3):
        response = await client.post(
            f"{_BOOKS}/{book_id}/explain",
            headers=_AUTH,
            json={"anchor": "8", "end_anchor": "13", "selected_text": "First"},
        )
        assert response.status_code == 200
    bookmark = await client.post(
        f"{_BOOKS}/{book_id}/bookmarks", headers=_AUTH, json={"anchor": "8"}
    )
    assert bookmark.status_code == 201

    tasks = {
        task["id"]: task
        for task in (await client.get(_SUMMARY, headers=_AUTH)).json()["tasks"]
    }

    assert tasks["explain"]["progress"] == 3
    assert tasks["explain"]["completed"] is True
    assert tasks["bookmark"]["completed"] is True


async def test_activity_is_recorded_on_the_clients_day(client: AsyncClient) -> None:
    book_id = await _upload(client)
    east = {**_AUTH, "X-Timezone-Offset": "840"}  # UTC+14
    west = {**_AUTH, "X-Timezone-Offset": "-720"}  # UTC-12, always a day behind

    response = await client.put(
        f"{_BOOKS}/{book_id}/progress",
        headers=east,
        json={
            "current_position": "1",
            "progress_percentage": 1.0,
            "reading_time_seconds": 120,
        },
    )
    assert response.status_code == 200

    east_summary = (await client.get(_SUMMARY, headers=east)).json()
    west_summary = (await client.get(_SUMMARY, headers=west)).json()
    assert east_summary["today_reading_seconds"] == 120
    assert west_summary["today_reading_seconds"] == 0


async def test_changing_the_goal_applies_from_today(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _upload(client)
    await _seed_days(sessionmaker, [1])
    await _read(client, book_id, 10 * 60)

    response = await client.put(
        "/api/v1/activity/goal", headers=_AUTH, json={"daily_minutes": 20}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["daily_goal_minutes"] == 20
    assert body["tasks"][0]["target"] == 20
    # Today is now judged against 20 minutes; yesterday keeps its old goal.
    assert body["goal_met_today"] is False
    assert body["current_streak"] == 1


async def test_goal_must_be_positive(client: AsyncClient) -> None:
    response = await client.put(
        "/api/v1/activity/goal", headers=_AUTH, json={"daily_minutes": 0}
    )
    assert response.status_code == 422


async def test_activity_requires_authentication(client: AsyncClient) -> None:
    assert (await client.get(_SUMMARY)).status_code == 401


async def test_activity_is_private_to_each_reader(
    client: AsyncClient,
    verifier: FakeTokenVerifier,
) -> None:
    book_id = await _upload(client)
    await _read(client, book_id, 10 * 60)
    verifier.register(
        "other",
        FirebaseIdentity(
            uid=f"other-{uuid.uuid4()}",
            email="other@example.com",
            display_name=None,
            photo_url=None,
        ),
    )

    other = await client.get(
        _SUMMARY,
        headers={"Authorization": "Bearer other", "X-Timezone-Offset": "330"},
    )

    assert other.json()["today_reading_seconds"] == 0
    assert other.json()["current_streak"] == 0
