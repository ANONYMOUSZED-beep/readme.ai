"""The client's calendar day.

Streaks are about the reader's own days, not UTC's: reading at 00:30 in
Kolkata belongs to that local day. Clients send their UTC offset in minutes
(e.g. ``330`` for IST) via the ``X-Timezone-Offset`` header; without it the
server falls back to UTC.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from fastapi import Depends, Header

# Real-world offsets span UTC-12:00 to UTC+14:00.
_MIN_OFFSET_MINUTES = -12 * 60
_MAX_OFFSET_MINUTES = 14 * 60


def local_today(offset_minutes: int, *, now: datetime | None = None) -> date:
    """Return the calendar date at ``offset_minutes`` east of UTC."""
    offset = max(_MIN_OFFSET_MINUTES, min(_MAX_OFFSET_MINUTES, offset_minutes))
    current = now or datetime.now(tz=UTC)
    return (current.astimezone(UTC) + timedelta(minutes=offset)).date()


def get_client_today(
    x_timezone_offset: Annotated[int | None, Header()] = None,
) -> date:
    """FastAPI dependency resolving "today" for the requesting client."""
    return local_today(x_timezone_offset or 0)


ClientToday = Annotated[date, Depends(get_client_today)]
