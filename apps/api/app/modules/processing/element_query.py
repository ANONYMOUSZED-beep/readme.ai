"""Read model for windowed Document Model element retrieval.

The Reader consumes documents as typed elements, but a large book holds tens of
thousands of them, so elements are served in bounded windows keyed to canonical
scalar offsets rather than all at once.

This module is read-only. It performs no writes, owns no schema, and interprets
no element semantics: ``payload`` is passed through exactly as stored, which is
what keeps element delivery parser-agnostic — a future element type reaches the
client without a backend change.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.processing.document_model import ElementType
from app.modules.processing.models import StoredDocument, StoredDocumentElement

#: Largest canonical span one request may ask for. Requests are clamped, never
#: rejected, so a naive client cannot overload the server.
MAX_WINDOW_SPAN = 50_000

#: Largest number of element records one window may return.
MAX_WINDOW_ELEMENTS = 2_000

#: Element types that carry readable text and therefore anchor a window.
#:
#: ``SENTENCE`` is excluded deliberately: sentences are sub-spans of paragraphs
#: with no independent presentation, and including them would multiply window
#: size several times over (the 911-page reference book holds ~37,000 of them)
#: for no rendering benefit. ``TABLE_ROW`` is excluded as an anchor because a
#: row's span is the union of its cells; rows still arrive as ancestors of the
#: cells that anchor the window.
ANCHOR_TYPES = frozenset(
    {
        ElementType.PARAGRAPH,
        ElementType.CODE_BLOCK,
        ElementType.QUOTE,
        ElementType.LIST_ITEM,
        ElementType.FOOTNOTE,
        ElementType.FORMULA,
        ElementType.CAPTION,
        ElementType.TABLE_CELL,
        ElementType.TABLE,
    }
)

#: Containers whose span-less children (images, hyperlinks) belong to a window
#: whenever the container itself is in it. Those children carry no offsets, so an
#: overlap predicate can never reach them.
_SPANLESS_PARENT_TYPES = frozenset({ElementType.SECTION})

#: Maximum ancestor-resolution rounds. The Document Model hierarchy is at most
#: document > chapter > section > table > row > cell deep, so this terminates.
_MAX_ANCESTOR_ROUNDS = 6

#: Types whose text the client derives from the canonical slice it already holds,
#: so a window omits it rather than sending the same characters twice.
_DERIVABLE_TEXT_TYPES = frozenset(
    {
        ElementType.PARAGRAPH,
        ElementType.CODE_BLOCK,
        ElementType.QUOTE,
        ElementType.LIST_ITEM,
        ElementType.FOOTNOTE,
        ElementType.FORMULA,
    }
)


@dataclass(frozen=True, slots=True)
class ElementRecord:
    """One element as delivered to a client. No ORM entity escapes this layer."""

    element_id: str
    parent_id: str | None
    element_type: str
    order_index: int
    sequence: int
    start_offset: int | None
    end_offset: int | None
    page_number: int | None
    payload: dict[str, Any]
    text: str | None


@dataclass(frozen=True, slots=True)
class ElementWindow:
    """A bounded slice of a document's elements, in document order."""

    start: int
    end: int
    character_count: int
    elements: tuple[ElementRecord, ...]
    truncated: bool


def _inline_text(content: object) -> str | None:
    """Concatenate inline runs into plain text, ignoring styling."""
    if not isinstance(content, list):
        return None
    parts: list[str] = []
    for run in content:
        if not isinstance(run, dict):
            continue
        value = run.get("text")
        if isinstance(value, str):
            parts.append(value)
    joined = "".join(parts)
    return joined or None


def _record(row: StoredDocumentElement) -> ElementRecord:
    """Map a storage row onto a delivery record, payload untouched."""
    text: str | None = None
    if row.element_type not in _DERIVABLE_TEXT_TYPES:
        text = _inline_text(row.content)
    return ElementRecord(
        element_id=row.element_id,
        parent_id=row.parent_element_id,
        element_type=row.element_type,
        order_index=row.order_index,
        sequence=row.sequence,
        start_offset=row.start_offset,
        end_offset=row.end_offset,
        page_number=row.source_page_number,
        payload=dict(row.payload or {}),
        text=text,
    )


class DocumentElementQuery:
    """Serves bounded element windows for a processed book."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def window(
        self,
        processed_book_id: uuid.UUID,
        *,
        start: int,
        end: int,
    ) -> ElementWindow:
        """Elements intersecting ``[start, end)`` plus what they need to render.

        Returned in document order (storage ``sequence``), which is the order the
        parser produced and therefore deterministic. An unprocessed book yields an
        empty window rather than an error.
        """
        window_start = max(0, start)
        window_end = max(window_start, end)
        # Clamp rather than reject: the response stays bounded whatever is asked.
        window_end = min(window_end, window_start + MAX_WINDOW_SPAN)

        stored = (
            await self._session.execute(
                select(StoredDocument.id, StoredDocument.character_count).where(
                    StoredDocument.processed_book_id == processed_book_id
                )
            )
        ).one_or_none()
        if stored is None:
            return ElementWindow(
                start=window_start,
                end=window_end,
                character_count=0,
                elements=(),
                truncated=False,
            )
        document_id, character_count = stored

        anchors, truncated = await self._anchors(document_id, window_start, window_end)
        rows = {row.element_id: row for row in anchors}
        rows.update(await self._ancestors(document_id, anchors))
        rows.update(await self._spanless_children(document_id, rows.values()))

        ordered = sorted(rows.values(), key=lambda row: row.sequence)
        return ElementWindow(
            start=window_start,
            end=window_end,
            character_count=int(character_count),
            elements=tuple(_record(row) for row in ordered),
            truncated=truncated,
        )

    async def _anchors(
        self,
        document_id: str,
        start: int,
        end: int,
    ) -> tuple[list[StoredDocumentElement], bool]:
        """Readable elements whose span overlaps the window.

        Uses ``ix_document_elements_span``. One extra row is fetched so the cap can
        be reported without a second count query, and the cap is applied to anchors
        only — ancestors are always added afterwards, so a child can never be
        returned without its parent.
        """
        result = await self._session.execute(
            select(StoredDocumentElement)
            .where(
                StoredDocumentElement.document_id == document_id,
                StoredDocumentElement.element_type.in_(
                    [element_type.value for element_type in ANCHOR_TYPES]
                ),
                StoredDocumentElement.start_offset < end,
                StoredDocumentElement.end_offset > start,
            )
            .order_by(StoredDocumentElement.sequence)
            .limit(MAX_WINDOW_ELEMENTS + 1)
        )
        found = list(result.scalars().all())
        if len(found) > MAX_WINDOW_ELEMENTS:
            return found[:MAX_WINDOW_ELEMENTS], True
        return found, False

    async def _ancestors(
        self,
        document_id: str,
        anchors: list[StoredDocumentElement],
    ) -> dict[str, StoredDocumentElement]:
        """Every ancestor of the anchors, resolved by parent id.

        Without this a page could render a list item with no list, or a caption
        with no image. Resolution is breadth-first per level, so the number of
        queries is bounded by hierarchy depth rather than by element count.
        """
        collected: dict[str, StoredDocumentElement] = {}
        known = {anchor.element_id for anchor in anchors}
        pending = {
            anchor.parent_element_id
            for anchor in anchors
            if anchor.parent_element_id is not None
        } - known

        for _ in range(_MAX_ANCESTOR_ROUNDS):
            if not pending:
                break
            result = await self._session.execute(
                select(StoredDocumentElement).where(
                    StoredDocumentElement.document_id == document_id,
                    StoredDocumentElement.element_id.in_(sorted(pending)),
                )
            )
            level = list(result.scalars().all())
            if not level:
                break
            for row in level:
                collected[row.element_id] = row
                known.add(row.element_id)
            pending = {
                row.parent_element_id
                for row in level
                if row.parent_element_id is not None
            } - known
        return collected

    async def _spanless_children(
        self,
        document_id: str,
        rows: Iterable[StoredDocumentElement],
    ) -> dict[str, StoredDocumentElement]:
        """Span-less children (images, hyperlinks) of included containers."""
        parents = sorted(
            {
                row.element_id
                for row in rows
                if row.element_type in {t.value for t in _SPANLESS_PARENT_TYPES}
            }
        )
        if not parents:
            return {}
        result = await self._session.execute(
            select(StoredDocumentElement)
            .where(
                StoredDocumentElement.document_id == document_id,
                StoredDocumentElement.parent_element_id.in_(parents),
                StoredDocumentElement.start_offset.is_(None),
            )
            .order_by(StoredDocumentElement.sequence)
        )
        return {row.element_id: row for row in result.scalars().all()}
