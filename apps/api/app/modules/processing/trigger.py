"""Processing trigger — the seam between "a book was uploaded" and "process it".

Uploads respond as soon as the file is stored: the trigger marks the book as
``PROCESSING`` within the request, then runs the pipeline after the response is
sent. Clients follow progress by polling the book's status. A future
``QueuedProcessingTrigger`` can hand the same work to a durable worker instead;
because callers depend on the :class:`ProcessingTrigger` protocol, that change
requires no edits at the call site (the library upload route).
"""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable
from typing import Protocol

from fastapi import BackgroundTasks

from app.core.logging import get_logger
from app.modules.processing.service import ProcessingService

logger = get_logger(__name__)

# Runs processing for (user_id, book_id) in its own database session.
ProcessingRunner = Callable[[uuid.UUID, uuid.UUID], Awaitable[None]]


class ProcessingTrigger(Protocol):
    """Schedules processing for a freshly uploaded book."""

    async def schedule(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        """Begin (or enqueue) processing for the given book."""
        ...


class BackgroundProcessingTrigger:
    """Marks the book as processing, then processes it after the response.

    The request-scoped ``service`` records the queued state so the upload
    response already reports ``PROCESSING``; the work itself goes through
    ``runner``, which opens a fresh session because the request's session is
    closed by the time background tasks execute.
    """

    def __init__(
        self,
        service: ProcessingService,
        background_tasks: BackgroundTasks,
        runner: ProcessingRunner,
    ) -> None:
        self._service = service
        self._background_tasks = background_tasks
        self._runner = runner

    async def schedule(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        try:
            await self._service.mark_queued(user_id, book_id)
        except Exception:
            # The upload is already committed and must still succeed; the book
            # stays UPLOADED and can be processed later via the processing API.
            logger.exception("processing.queue_failed", extra={"book_id": str(book_id)})
            return
        self._background_tasks.add_task(_run_logged, self._runner, user_id, book_id)


async def _run_logged(
    runner: ProcessingRunner,
    user_id: uuid.UUID,
    book_id: uuid.UUID,
) -> None:
    """Run processing, logging failures that escape the pipeline itself.

    Expected failures are already recorded on the book by the service; this
    only catches infrastructure errors (e.g. the database becoming
    unavailable), which have no request left to report to.
    """
    try:
        await runner(user_id, book_id)
    except Exception:
        logger.exception("processing.background_failed", extra={"book_id": book_id})
