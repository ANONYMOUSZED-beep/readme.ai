"""HTTP routes for the explanation module.

The endpoint is unchanged for the reader, but requests now flow through the
Learning Intelligence Engine, which runs learner-aware capabilities and then
delegates to the Explanation Service.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter

from app.modules.activity.clock import ClientToday
from app.modules.activity.dependencies import ActivityServiceDep
from app.modules.auth.dependencies import CurrentUser
from app.modules.explanation.schemas import ExplainRequest, ExplanationResponse
from app.modules.learning.dependencies import LearningEngineDep

router = APIRouter()


@router.post(
    "/{book_id}/explain",
    response_model=ExplanationResponse,
    summary="Explain a selection (word, sentence, or paragraph)",
)
async def explain(
    book_id: uuid.UUID,
    payload: ExplainRequest,
    user: CurrentUser,
    engine: LearningEngineDep,
    activity: ActivityServiceDep,
    today: ClientToday,
) -> ExplanationResponse:
    """Explain a selection; the Learning Intelligence Engine orchestrates.

    Successful explanations count toward today's tasks.
    """
    explanation = await engine.explain(
        user_id=user.id,
        book_id=book_id,
        anchor=payload.anchor,
        end_anchor=payload.end_anchor,
        selected_text=payload.selected_text,
    )
    await activity.record_explanation(user.id, today)
    return explanation
