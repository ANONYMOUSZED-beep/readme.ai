"""Integration tests for GET /books/{id}/content/elements (task 3).

Covers the HTTP contract: auth, ownership, processing state, window bounds,
ordering, derivable-text omission, schema shape, determinism, and the strict
idempotency guarantee — a GET must never write anything.
"""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.verifier import FirebaseIdentity
from app.modules.processing.element_query import MAX_WINDOW_ELEMENTS, MAX_WINDOW_SPAN
from app.modules.processing.models import (
    ProcessedBook,
    StoredDocument,
    StoredDocumentElement,
)
from app.modules.reader.models import Bookmark, ReadingProgress
from tests.conftest import FakeTokenVerifier
from tests.document_fixtures import (
    CAPTION,
    CELL_ONE,
    CODE,
    TEXT,
    at,
    replace_stored_document,
)

_AUTH = {"Authorization": "Bearer valid-token"}
_BOOKS = "/api/v1/books"
_PLAIN = b"# Title\n\nFirst paragraph. Two sentences here.\n\nSecond paragraph."


async def _upload(
    client: AsyncClient,
    *,
    content: bytes = _PLAIN,
    filename: str = "book.txt",
    mime: str = "text/plain",
) -> str:
    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": (filename, content, mime)}
    )
    assert response.status_code == 201, response.text
    book_id: str = response.json()["id"]
    return book_id


async def _elements(
    client: AsyncClient,
    book_id: str,
    *,
    start: int | None = None,
    end: int | None = None,
    headers: dict[str, str] | None = _AUTH,
) -> dict[str, Any]:
    params: dict[str, int] = {}
    if start is not None:
        params["start"] = start
    if end is not None:
        params["end"] = end
    response = await client.get(
        f"{_BOOKS}/{book_id}/content/elements",
        headers=headers or {},
        params=params,
    )
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


async def _rich_book(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> str:
    """A processed book whose stored document holds every readable type."""
    book_id = await _upload(client, content=TEXT.encode())
    async with sessionmaker() as session:
        record = await session.scalar(
            select(ProcessedBook).where(ProcessedBook.book_id == uuid.UUID(book_id))
        )
        assert record is not None
        await replace_stored_document(session, record.id)
        record.character_count = len(TEXT)
        await session.commit()
    return book_id


# --- authentication and authorization ---------------------------------------
async def test_elements_require_authentication(client: AsyncClient) -> None:
    book_id = await _upload(client)

    response = await client.get(f"{_BOOKS}/{book_id}/content/elements")

    assert response.status_code == 401


async def test_invalid_token_is_rejected(client: AsyncClient) -> None:
    book_id = await _upload(client)

    response = await client.get(
        f"{_BOOKS}/{book_id}/content/elements",
        headers={"Authorization": "Bearer invalid-token"},
    )

    assert response.status_code == 401


async def test_another_user_cannot_read_elements(
    client: AsyncClient,
    verifier: FakeTokenVerifier,
) -> None:
    book_id = await _upload(client)
    verifier.register(
        "other",
        FirebaseIdentity(
            uid="other-uid",
            email="other@example.com",
            display_name=None,
            photo_url=None,
        ),
    )

    response = await client.get(
        f"{_BOOKS}/{book_id}/content/elements",
        headers={"Authorization": "Bearer other"},
    )

    # Ownership is resolved exactly as /content does: a foreign book is absent.
    assert response.status_code == 404


async def test_unknown_book_returns_404(client: AsyncClient) -> None:
    await _upload(client)

    response = await client.get(
        f"{_BOOKS}/{uuid.uuid4()}/content/elements", headers=_AUTH
    )

    assert response.status_code == 404


# --- processing state --------------------------------------------------------
async def test_unprocessed_book_returns_an_empty_window(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _upload(client, content=b"   \n\n   ")

    body = await _elements(client, book_id)

    # A failed or pending book degrades to an empty window, never an error, so
    # the reader can fall back to canonical text.
    assert body["elements"] == []
    assert body["character_count"] == 0
    assert body["truncated"] is False


async def test_processed_book_returns_a_populated_window(
    client: AsyncClient,
) -> None:
    book_id = await _upload(client)

    body = await _elements(client, book_id)

    types = {element["type"] for element in body["elements"]}
    assert body["character_count"] > 0
    assert {"chapter", "section", "paragraph"} <= types
    # Sentences are backend-only and never delivered.
    assert "sentence" not in types


async def test_window_beyond_the_document_is_empty_but_valid(
    client: AsyncClient,
) -> None:
    book_id = await _upload(client)
    body = await _elements(client, book_id)

    beyond = await _elements(
        client,
        book_id,
        start=body["character_count"] + 500,
        end=body["character_count"] + 900,
    )

    assert beyond["elements"] == []
    assert beyond["character_count"] == body["character_count"]


# --- window bounds and truncation -------------------------------------------
async def test_default_window_span_is_applied(client: AsyncClient) -> None:
    book_id = await _upload(client)

    body = await _elements(client, book_id)

    assert body["start"] == 0
    assert body["end"] == 20_000


async def test_requested_span_is_clamped(client: AsyncClient) -> None:
    book_id = await _upload(client)

    body = await _elements(client, book_id, start=0, end=MAX_WINDOW_SPAN * 3)

    assert body["end"] == MAX_WINDOW_SPAN


async def test_invalid_range_parameters_are_rejected(client: AsyncClient) -> None:
    book_id = await _upload(client)

    negative = await client.get(
        f"{_BOOKS}/{book_id}/content/elements",
        headers=_AUTH,
        params={"start": -5, "end": 100},
    )
    zero_end = await client.get(
        f"{_BOOKS}/{book_id}/content/elements",
        headers=_AUTH,
        params={"start": 0, "end": 0},
    )

    assert negative.status_code == 422
    assert zero_end.status_code == 422


async def test_element_cap_is_reported_and_respected(
    client: AsyncClient,
) -> None:
    """A document large enough to exceed the cap reports truncation over HTTP."""
    paragraphs = "\n\n".join(
        f"Para {index:04d} reads well." for index in range(MAX_WINDOW_ELEMENTS + 200)
    )
    book_id = await _upload(client, content=paragraphs.encode())

    body = await _elements(client, book_id, start=0, end=MAX_WINDOW_SPAN)

    anchors = [e for e in body["elements"] if e["type"] == "paragraph"]
    assert body["truncated"] is True
    assert len(anchors) == MAX_WINDOW_ELEMENTS
    # Ancestors are added after the cap, so no child arrives orphaned.
    present = {element["id"] for element in body["elements"]}
    for element in body["elements"]:
        if element["parent_id"] is not None and element["parent_id"] in present:
            continue
        assert element["parent_id"] is None or element["type"] == "chapter"


# --- ordering, payload, and schema ------------------------------------------
async def test_elements_are_returned_in_document_order(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _rich_book(client, sessionmaker)

    body = await _elements(client, book_id, start=0, end=len(TEXT))

    sequences = [element["sequence"] for element in body["elements"]]
    ids = [element["id"] for element in body["elements"]]
    assert sequences == sorted(sequences)
    assert ids.index("ch") < ids.index("sec") < ids.index("p-1")


async def test_derivable_text_is_omitted_and_other_text_delivered(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _rich_book(client, sessionmaker)

    body = await _elements(client, book_id, start=0, end=len(TEXT))
    by_id = {element["id"]: element for element in body["elements"]}

    # Paragraph, code, quote, list item, footnote and formula text is sliced by
    # the client from the canonical text it already holds.
    for element_id in ("p-1", "code", "quote", "item", "note", "formula"):
        assert by_id[element_id]["text"] is None, element_id
    # Caption, cell and hyperlink text is not derivable, so it is delivered.
    assert by_id["cap"]["text"] == CAPTION
    assert by_id["cell-1"]["text"] == CELL_ONE


async def test_payload_and_source_metadata_are_passed_through(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _rich_book(client, sessionmaker)

    body = await _elements(client, book_id, start=0, end=len(TEXT))
    by_id = {element["id"]: element for element in body["elements"]}

    assert by_id["code"]["payload"]["language"] == "sql"
    assert by_id["img"]["payload"]["image_identifier"] == "sha256:abc"
    assert by_id["ch"]["payload"]["title"] == "Chapter"
    assert by_id["code"]["start_offset"] == at(CODE)[0]
    assert by_id["code"]["end_offset"] == at(CODE)[1]
    # Span-less elements report null offsets rather than being omitted.
    assert by_id["img"]["start_offset"] is None
    assert by_id["link"]["parent_id"] == "sec"


async def test_response_matches_the_declared_schema(client: AsyncClient) -> None:
    book_id = await _upload(client)

    body = await _elements(client, book_id)

    assert set(body) == {
        "book_id",
        "start",
        "end",
        "character_count",
        "truncated",
        "elements",
    }
    assert body["book_id"] == book_id
    for element in body["elements"]:
        assert set(element) == {
            "id",
            "parent_id",
            "type",
            "order_index",
            "sequence",
            "start_offset",
            "end_offset",
            "page_number",
            "payload",
            "text",
        }


async def test_endpoint_is_documented_in_the_openapi_schema(
    client: AsyncClient,
) -> None:
    schema = (await client.get("/openapi.json")).json()

    path = schema["paths"]["/api/v1/books/{book_id}/content/elements"]

    assert set(path) == {"get"}, "the element window must be read-only"


# --- determinism and idempotency --------------------------------------------
async def test_repeated_requests_return_identical_responses(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _rich_book(client, sessionmaker)

    first = await _elements(client, book_id, start=0, end=len(TEXT))
    second = await _elements(client, book_id, start=0, end=len(TEXT))
    third = await _elements(client, book_id, start=0, end=len(TEXT))

    assert first == second == third


async def test_get_never_mutates_persistence(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    """Strict idempotency: a read changes no row, no timestamp, no state."""
    book_id = await _rich_book(client, sessionmaker)

    async def snapshot() -> tuple[Any, ...]:
        async with sessionmaker() as session:
            record = await session.scalar(
                select(ProcessedBook).where(ProcessedBook.book_id == uuid.UUID(book_id))
            )
            assert record is not None
            documents = (await session.scalars(select(StoredDocument.id))).all()
            elements = (
                await session.scalars(select(StoredDocumentElement.element_id))
            ).all()
            progress = (await session.scalars(select(ReadingProgress.id))).all()
            bookmarks = (await session.scalars(select(Bookmark.id))).all()
            return (
                record.status,
                record.processed_at,
                record.updated_at,
                record.character_count,
                record.processor_name,
                sorted(documents),
                sorted(elements),
                sorted(str(item) for item in progress),
                sorted(str(item) for item in bookmarks),
            )

    before = await snapshot()
    for _ in range(3):
        await _elements(client, book_id, start=0, end=len(TEXT))
        await _elements(client, book_id, start=10, end=40)
    after = await snapshot()

    assert before == after


async def test_reading_progress_is_not_created_by_reading_elements(
    client: AsyncClient,
) -> None:
    book_id = await _upload(client)

    await _elements(client, book_id)
    progress = await client.get(f"{_BOOKS}/{book_id}/progress", headers=_AUTH)

    # The reader has never saved a position, and a GET must not invent one.
    assert progress.json() is None
