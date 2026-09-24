"""Processing trigger — the seam between "a book was uploaded" and "process it".

Today the only implementation runs processing inline within the request. A
future ``QueuedProcessingTrigger`` can enqueue work for a background worker
instead; because callers depend on the :class:`ProcessingTrigger` protocol, that
change requires no edits at the call site (the library upload route).
"""

from __future__ import annotations

import uuid
from typing import Protocol

from app.core.logging import get_logger
from app.modules.processing.service import ProcessingService

logger = get_logger(__name__)


class ProcessingTrigger(Protocol):
    """Schedules processing for a freshly uploaded book."""

    async def schedule(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        """Begin (or enqueue) processing for the given book."""
        ...


class InlineProcessingTrigger:
    """Runs processing synchronously within the current request.

    Processing records its own failures; anything that still escapes (e.g. the
    database dropping out) is logged and swallowed, because the upload itself
    has already been committed and must be reported as a success. The book can
    be re-processed later through the processing endpoint.
    """

    def __init__(self, service: ProcessingService) -> None:
        self._service = service

    async def schedule(self, user_id: uuid.UUID, book_id: uuid.UUID) -> None:
        try:
            await self._service.process_book(user_id, book_id)
        except Exception:
            logger.exception(
                "processing.trigger_failed", extra={"book_id": str(book_id)}
            )
