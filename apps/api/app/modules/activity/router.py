"""HTTP routes for the activity module (mounted at ``/api/v1/activity``).

"Today" is the client's local day, taken from the ``X-Timezone-Offset`` header.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.modules.activity.clock import ClientToday
from app.modules.activity.dependencies import ActivityServiceDep
from app.modules.activity.schemas import ActivitySummaryResponse, UpdateGoalRequest
from app.modules.auth.dependencies import CurrentUser

router = APIRouter()


@router.get(
    "/summary",
    response_model=ActivitySummaryResponse,
    summary="Get streak, goal, and today's tasks",
)
async def get_summary(
    user: CurrentUser,
    service: ActivityServiceDep,
    today: ClientToday,
) -> ActivitySummaryResponse:
    """Return the reader's streak, recent week, and progress on today's tasks."""
    summary = await service.get_summary(user.id, today)
    return ActivitySummaryResponse.model_validate(summary)


@router.put(
    "/goal",
    response_model=ActivitySummaryResponse,
    summary="Set the daily reading goal",
)
async def set_goal(
    payload: UpdateGoalRequest,
    user: CurrentUser,
    service: ActivityServiceDep,
    today: ClientToday,
) -> ActivitySummaryResponse:
    """Change the daily goal (applies from today) and return the new summary."""
    summary = await service.set_goal(user.id, payload.daily_minutes, today)
    return ActivitySummaryResponse.model_validate(summary)
