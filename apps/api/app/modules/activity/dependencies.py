"""Dependency wiring for the activity module."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db_session
from app.modules.activity.repository import ActivityRepository
from app.modules.activity.service import ActivityService


def get_activity_service(
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> ActivityService:
    """Provide the activity service for the current request."""
    return ActivityService(ActivityRepository(session))


ActivityServiceDep = Annotated[ActivityService, Depends(get_activity_service)]
