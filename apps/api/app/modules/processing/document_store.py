"""Persistence for the Document Model — the single source of truth.

Row mapping rules:

* Common identity/ordering/source fields get real columns, so hierarchy and
  span queries are indexed.
* Type-specific fields go to ``payload``, so a new element type (or an unknown
  future one) needs no schema change.
* Inline runs go to ``content``, except when they are exactly the element's own
  span of the canonical text — then the column stays ``NULL`` and the run is
  rebuilt on read. Without that rule every sentence row would restate the whole
  book, doubling storage.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

from sqlalchemy import Integer, cast, delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.processing.document_model import (
    DEFAULT_ELEMENT_CODEC,
    Document,
    DocumentElement,
    ElementType,
    InlineType,
)
from app.modules.processing.models import StoredDocument, StoredDocumentElement

# Fields owned by dedicated columns; everything else is type-specific payload.
_COMMON_FIELDS = frozenset(
    {"id", "parent_id", "order_index", "element_type", "source", "attributes"}
)
_START = "start_offset"
_END = "end_offset"

#: Element types that provide grounding context for a reader's selection.
#:
#: Two exclusions are load-bearing:
#:
#: * ``SENTENCE`` — sentences nest inside paragraphs, so including them would make
#:   a single-word selection return two overlapping spans. The selection
#:   classifier reads "more than one span" as a passage, so every word would be
#:   reclassified as a paragraph. Excluding sentences is what keeps classification
#:   of paragraph selections byte-identical to the pre-widening behaviour.
#: * ``TABLE_ROW`` — a row's span is the union of its cells, so including both
#:   would double-count the same characters.
#:
#: The remaining types are non-overlapping siblings in canonical space, which is
#: why span *count* keeps the meaning the classifier already assigns it.
CONTEXT_TYPES: frozenset[ElementType] = frozenset(
    {
        ElementType.PARAGRAPH,
        ElementType.CODE_BLOCK,
        ElementType.QUOTE,
        ElementType.LIST_ITEM,
        ElementType.FOOTNOTE,
        ElementType.FORMULA,
        ElementType.CAPTION,
        ElementType.TABLE_CELL,
    }
)


@dataclass(frozen=True, slots=True)
class TextSpan:
    """A readable span reconstructed from storage (no ORM leakage)."""

    text: str
    start_offset: int
    end_offset: int


def _int_or_none(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _is_derivable_content(
    element_type: str,
    content: object,
    text: str,
    start: int | None,
    end: int | None,
) -> bool:
    """Whether inline runs are exactly the element's own slice of the text."""
    if element_type != ElementType.SENTENCE or start is None or end is None:
        return False
    if not isinstance(content, list) or len(content) != 1:
        return False
    run = content[0]
    return (
        isinstance(run, dict)
        and run.get("inline_type") == InlineType.TEXT.value
        and run.get("target") is None
        and run.get("original_representation") is None
        and run.get("reference_id") is None
        and not run.get("attributes")
        and run.get("text") == text[start:end]
    )


def encode_element(
    element: DocumentElement,
    *,
    document_id: str,
    sequence: int,
    text: str,
) -> StoredDocumentElement:
    """Map a Document Model element onto its storage row."""
    dumped = element.model_dump(mode="json")
    payload = {
        key: value
        for key, value in dumped.items()
        if key not in _COMMON_FIELDS and key != "content"
    }
    attributes = dict(element.attributes)
    start = _int_or_none(attributes.pop(_START, None))
    end = _int_or_none(attributes.pop(_END, None))

    content = dumped.get("content") if "content" in dumped else None
    if _is_derivable_content(element.element_type, content, text, start, end):
        content = None

    box = element.source.bounding_box
    return StoredDocumentElement(
        id=uuid.uuid4(),
        document_id=document_id,
        element_id=element.id,
        parent_element_id=element.parent_id,
        element_type=element.element_type,
        order_index=element.order_index,
        sequence=sequence,
        start_offset=start,
        end_offset=end,
        source_page_number=element.source.page_number,
        source_bounding_box=box.model_dump(mode="json") if box else None,
        source_reference=element.source.original_reference,
        payload=payload,
        attributes=attributes,
        content=content,
    )


def decode_element(row: StoredDocumentElement, *, text: str) -> DocumentElement:
    """Rebuild the concrete element (or an unknown-type envelope) from a row."""
    attributes: dict[str, Any] = dict(row.attributes or {})
    if row.start_offset is not None:
        attributes[_START] = row.start_offset
    if row.end_offset is not None:
        attributes[_END] = row.end_offset

    data: dict[str, Any] = {
        "id": row.element_id,
        "parent_id": row.parent_element_id,
        "order_index": row.order_index,
        "element_type": row.element_type,
        "source": {
            "page_number": row.source_page_number,
            "bounding_box": row.source_bounding_box,
            "original_reference": row.source_reference,
        },
        "attributes": attributes,
        **(row.payload or {}),
    }

    content = row.content
    if (
        content is None
        and row.element_type == ElementType.SENTENCE
        and row.start_offset is not None
        and row.end_offset is not None
    ):
        content = [
            {
                "inline_type": InlineType.TEXT.value,
                "text": text[row.start_offset : row.end_offset],
            }
        ]
    if content is not None:
        data["content"] = content

    return DEFAULT_ELEMENT_CODEC.deserialize(data)


class DocumentStore:
    """Repository for the persisted Document Model.

    Callers pass and receive Document Model objects; nothing above this class
    sees a table, a row, or an ORM entity.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def save(
        self,
        processed_book_id: uuid.UUID,
        document: Document,
        *,
        text: str,
    ) -> None:
        """Replace the stored document for a processing record."""
        await self.clear(processed_book_id)

        box = document.source.bounding_box
        self._session.add(
            StoredDocument(
                id=document.id,
                processed_book_id=processed_book_id,
                schema_version=document.schema_version,
                source_page_number=document.source.page_number,
                source_bounding_box=box.model_dump(mode="json") if box else None,
                source_reference=document.source.original_reference,
                attributes=dict(document.attributes),
                text=text,
                character_count=len(text),
            )
        )
        await self._session.flush()

        rows = [
            encode_element(
                element, document_id=document.id, sequence=sequence, text=text
            )
            for sequence, element in enumerate(document.elements)
        ]
        if rows:
            # One bulk insert: element rows carry no foreign key to each other,
            # so no level-by-level flush is needed regardless of tree depth.
            self._session.add_all(rows)
            await self._session.flush()

    async def clear(self, processed_book_id: uuid.UUID) -> None:
        """Delete the stored document and its elements, if present."""
        result = await self._session.execute(
            select(StoredDocument.id).where(
                StoredDocument.processed_book_id == processed_book_id
            )
        )
        document_ids = list(result.scalars().all())
        if not document_ids:
            return
        await self._session.execute(
            delete(StoredDocumentElement).where(
                StoredDocumentElement.document_id.in_(document_ids)
            )
        )
        await self._session.execute(
            delete(StoredDocument).where(StoredDocument.id.in_(document_ids))
        )

    async def get_text(self, processed_book_id: uuid.UUID) -> str | None:
        """The canonical reading text — a single indexed row read."""
        result = await self._session.execute(
            select(StoredDocument.text).where(
                StoredDocument.processed_book_id == processed_book_id
            )
        )
        return result.scalar_one_or_none()

    async def load(self, processed_book_id: uuid.UUID) -> Document | None:
        """Reconstruct and re-validate the complete Document Model."""
        record = await self._session.execute(
            select(StoredDocument).where(
                StoredDocument.processed_book_id == processed_book_id
            )
        )
        stored = record.scalar_one_or_none()
        if stored is None:
            return None

        rows = await self._session.execute(
            select(StoredDocumentElement)
            .where(StoredDocumentElement.document_id == stored.id)
            .order_by(StoredDocumentElement.sequence)
        )
        elements = tuple(
            decode_element(row, text=stored.text) for row in rows.scalars().all()
        )
        return Document(
            id=stored.id,
            parent_id=None,
            order_index=0,
            schema_version=stored.schema_version,
            source={
                "page_number": stored.source_page_number,
                "bounding_box": stored.source_bounding_box,
                "original_reference": stored.source_reference,
            },
            attributes=dict(stored.attributes or {}),
            elements=elements,
        )

    async def spans_overlapping(
        self,
        processed_book_id: uuid.UUID,
        element_type: ElementType,
        start: int,
        end: int,
    ) -> list[TextSpan]:
        """Readable spans of one element type intersecting ``[start, end)``."""
        return await self.spans_overlapping_types(
            processed_book_id, frozenset({element_type}), start, end
        )

    async def spans_overlapping_types(
        self,
        processed_book_id: uuid.UUID,
        element_types: frozenset[ElementType],
        start: int,
        end: int,
    ) -> list[TextSpan]:
        """Readable spans of several element types intersecting ``[start, end)``.

        The text is sliced in the database, so a selection never loads the whole
        document into memory.

        The offset columns are ``BIGINT`` because a book's character count has no
        small upper bound, but PostgreSQL only defines ``substr(text, int, int)``.
        Without the explicit casts below the query fails at runtime with
        ``function substr(text, bigint, bigint) does not exist``. SQLite accepts
        the uncast form, which is why this only surfaces on PostgreSQL.
        """
        begin = cast(StoredDocumentElement.start_offset + 1, Integer)
        length = cast(
            StoredDocumentElement.end_offset - StoredDocumentElement.start_offset,
            Integer,
        )
        result = await self._session.execute(
            select(
                StoredDocumentElement.start_offset,
                StoredDocumentElement.end_offset,
                func.substr(StoredDocument.text, begin, length).label("text"),
            )
            .join(
                StoredDocument, StoredDocument.id == StoredDocumentElement.document_id
            )
            .where(
                StoredDocument.processed_book_id == processed_book_id,
                StoredDocumentElement.element_type.in_(
                    sorted(element_type.value for element_type in element_types)
                ),
                StoredDocumentElement.start_offset < end,
                StoredDocumentElement.end_offset > start,
            )
            .order_by(StoredDocumentElement.start_offset)
        )
        return [
            TextSpan(
                text=row.text or "",
                start_offset=row.start_offset,
                end_offset=row.end_offset,
            )
            for row in result.all()
        ]

    async def count_overlapping(
        self,
        processed_book_id: uuid.UUID,
        element_type: ElementType,
        start: int,
        end: int,
    ) -> int:
        """Count elements of one type intersecting ``[start, end)``."""
        result = await self._session.execute(
            select(func.count())
            .select_from(StoredDocumentElement)
            .join(
                StoredDocument, StoredDocument.id == StoredDocumentElement.document_id
            )
            .where(
                StoredDocument.processed_book_id == processed_book_id,
                StoredDocumentElement.element_type == element_type.value,
                StoredDocumentElement.start_offset < end,
                StoredDocumentElement.end_offset > start,
            )
        )
        return int(result.scalar_one())
