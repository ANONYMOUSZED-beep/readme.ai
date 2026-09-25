"""Explanation service — classify the selection, then delegate to a strategy.

Reader -> API -> this service -> SelectionClassifier -> Strategy -> Provider ->
Ollama. The reader never reaches the provider. Ownership is enforced via the
library's BookService; classification uses the structured document.
"""

from __future__ import annotations

import uuid

from app.core.errors import DependencyUnavailableError, ValidationError
from app.modules.explanation.classifier import SelectionClassifier
from app.modules.explanation.context_extractor import ContextExtractor
from app.modules.explanation.enums import SelectionType
from app.modules.explanation.provider import ExplanationError
from app.modules.explanation.schemas import ExplanationResponse
from app.modules.explanation.strategies.base import ExplanationStrategy
from app.modules.library.service import BookService


class ExplanationService:
    def __init__(
        self,
        classifier: SelectionClassifier,
        strategies: dict[SelectionType, ExplanationStrategy],
        context_extractor: ContextExtractor,
        book_service: BookService,
    ) -> None:
        self._classifier = classifier
        self._strategies = strategies
        self._context_extractor = context_extractor
        self._book_service = book_service

    async def explain(
        self,
        *,
        user_id: uuid.UUID,
        book_id: uuid.UUID,
        anchor: str,
        end_anchor: str | None,
        selected_text: str,
    ) -> ExplanationResponse:
        book = await self._book_service.get_book(user_id, book_id)

        start = _parse_offset(anchor, "anchor")
        end = (
            _parse_offset(end_anchor, "end_anchor")
            if end_anchor
            else start + len(selected_text)
        )
        if end < start:
            raise ValidationError(
                "The selection ends before it starts.",
                details={"anchor": anchor, "end_anchor": end_anchor},
            )

        analysis = await self._classifier.analyze(
            book_id=book_id,
            start=start,
            end=max(end, start + 1),
            selected_text=selected_text,
        )
        context = self._context_extractor.extract(
            reader_context=analysis.context, word=selected_text[:80]
        )

        strategy = self._strategies[analysis.selection_type]
        try:
            result = await strategy.explain(
                selected_text=selected_text,
                context=context,
                book_title=book.title,
            )
        except ExplanationError as error:
            raise DependencyUnavailableError(
                "The explanation service is unavailable.",
                details={"reason": error.code.value},
            ) from error

        if not result.explanation and not result.meaning:
            raise DependencyUnavailableError(
                "The explanation service returned no result.",
                details={"reason": "empty"},
            )

        return ExplanationResponse(
            selection_type=analysis.selection_type,
            explanation=result.explanation,
            meaning=result.meaning,
            example=result.example,
        )


def _parse_offset(value: str, field: str) -> int:
    """Parse a character-offset anchor, rejecting anything else.

    Silently mapping a malformed anchor to offset 0 would explain the wrong
    passage (the beginning of the book) instead of reporting the bad request.
    """
    stripped = value.strip()
    if not stripped.isdigit() or not stripped.isascii():
        raise ValidationError(
            "Selection anchors must be non-negative character offsets.",
            details={field: value},
        )
    return int(stripped)
