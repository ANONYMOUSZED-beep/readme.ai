"""Explanation endpoint verification across every readable element (task 15).

These tests exercise the real HTTP path — auth, ownership, the Learning
Intelligence Engine, the selection classifier, and the widened persistence seam —
for a document containing a paragraph, code block, quote, list item, formula,
caption, footnote and table cell.

Nothing in the Explanation Engine is modified or stubbed beyond the existing fake
provider from ``conftest``: only the stored document is crafted, because parsers
decide which element types a real upload produces.
"""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.processing.models import ProcessedBook
from tests.document_fixtures import (
    CAPTION,
    CELL_ONE,
    CELL_TWO,
    CODE,
    FOOTNOTE,
    FORMULA,
    ITEM,
    PARAGRAPH_ONE,
    PARAGRAPH_TWO,
    QUOTE,
    READABLE_FRAGMENTS,
    TEXT,
    at,
    replace_stored_document,
)

_AUTH = {"Authorization": "Bearer valid-token"}
_BOOKS = "/api/v1/books"


async def _book_with_every_element(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> str:
    """Upload a book, then replace its stored document with the rich fixture."""
    response = await client.post(
        _BOOKS,
        headers=_AUTH,
        files={"file": ("book.txt", TEXT.encode(), "text/plain")},
    )
    assert response.status_code == 201, response.text
    book_id = response.json()["id"]

    async with sessionmaker() as session:
        record = await session.scalar(
            select(ProcessedBook).where(ProcessedBook.book_id == uuid.UUID(book_id))
        )
        assert record is not None
        await replace_stored_document(session, record.id)
        record.character_count = len(TEXT)
        await session.commit()
    return book_id


async def _explain(
    client: AsyncClient,
    book_id: str,
    *,
    text: str,
    start: int,
    end: int,
) -> dict[str, object]:
    response = await client.post(
        f"{_BOOKS}/{book_id}/explain",
        headers=_AUTH,
        json={
            "anchor": str(start),
            "end_anchor": str(end),
            "selected_text": text,
        },
    )
    assert response.status_code == 200, (
        f"selection {text!r} at [{start}, {end}) failed: "
        f"{response.status_code} {response.text}"
    )
    return response.json()


@pytest.mark.parametrize(("fragment", "label"), READABLE_FRAGMENTS)
async def test_every_readable_element_produces_an_explanation(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    fragment: str,
    label: str,
) -> None:
    book_id = await _book_with_every_element(client, sessionmaker)
    start, end = at(fragment)

    body = await _explain(client, book_id, text=fragment, start=start, end=end)

    assert body["explanation"], f"no explanation returned for a {label}"
    assert body["selection_type"] in {"word", "sentence", "paragraph"}


@pytest.mark.parametrize(("fragment", "label"), READABLE_FRAGMENTS)
async def test_no_readable_element_reports_outside_book_content(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    fragment: str,
    label: str,
) -> None:
    """Requirement 4.8: the outside-content error must be impossible here."""
    book_id = await _book_with_every_element(client, sessionmaker)
    start, end = at(fragment)

    response = await client.post(
        f"{_BOOKS}/{book_id}/explain",
        headers=_AUTH,
        json={
            "anchor": str(start),
            "end_anchor": str(end),
            "selected_text": fragment,
        },
    )

    assert response.status_code == 200, f"{label} selection rejected"
    assert "outside" not in response.text.lower()


async def test_word_inside_a_code_block_is_explained(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _book_with_every_element(client, sessionmaker)
    code_start, _ = at(CODE)

    body = await _explain(
        client, book_id, text="SELECT", start=code_start, end=code_start + 6
    )

    assert body["selection_type"] == "word"
    assert body["explanation"]


async def test_multi_line_code_selection_is_explained(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _book_with_every_element(client, sessionmaker)
    start, end = at(CODE)

    body = await _explain(client, book_id, text=CODE, start=start, end=end)

    assert body["explanation"]
    assert body["selection_type"] in {"sentence", "paragraph"}


async def test_selection_spanning_adjacent_elements_is_explained(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    """A range crossing a code block and a quote resolves as one passage."""
    book_id = await _book_with_every_element(client, sessionmaker)
    start = at(CODE)[0]
    end = at(QUOTE)[1]

    body = await _explain(client, book_id, text=TEXT[start:end], start=start, end=end)

    assert body["selection_type"] == "paragraph"
    assert body["explanation"]


async def test_selection_spanning_two_table_cells_is_explained(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _book_with_every_element(client, sessionmaker)
    start = at(CELL_ONE)[0]
    end = at(CELL_TWO)[1]

    body = await _explain(client, book_id, text=TEXT[start:end], start=start, end=end)

    assert body["explanation"]


async def test_paragraph_classification_is_unchanged(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    """Requirement 4.2 / 9.3: paragraph behaviour is the regression baseline."""
    book_id = await _book_with_every_element(client, sessionmaker)
    paragraph_start, paragraph_end = at(PARAGRAPH_ONE)

    word = await _explain(
        client, book_id, text="Alpha", start=paragraph_start, end=paragraph_start + 5
    )
    sentence = await _explain(
        client,
        book_id,
        text="Alpha sentence.",
        start=paragraph_start,
        end=paragraph_start + 15,
    )
    paragraph = await _explain(
        client,
        book_id,
        text=PARAGRAPH_ONE,
        start=paragraph_start,
        end=paragraph_end,
    )
    across = await _explain(
        client,
        book_id,
        text=f"{PARAGRAPH_ONE}\n\n{PARAGRAPH_TWO}",
        start=paragraph_start,
        end=at(PARAGRAPH_TWO)[1],
    )

    assert word["selection_type"] == "word"
    assert word["meaning"]
    assert sentence["selection_type"] == "sentence"
    assert sentence["meaning"] is None
    assert paragraph["selection_type"] == "paragraph"
    assert across["selection_type"] == "paragraph"


async def test_selection_beyond_the_document_still_reports_outside_content(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    """Widening must not make genuinely invalid selections succeed."""
    book_id = await _book_with_every_element(client, sessionmaker)
    beyond = len(TEXT) + 500

    response = await client.post(
        f"{_BOOKS}/{book_id}/explain",
        headers=_AUTH,
        json={
            "anchor": str(beyond),
            "end_anchor": str(beyond + 10),
            "selected_text": "nothing",
        },
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    "fragment",
    [ITEM, FOOTNOTE, FORMULA, CAPTION],
)
async def test_grounding_context_includes_the_selected_element(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    explanation_provider: object,
    fragment: str,
) -> None:
    """The prompt is grounded in the element the reader actually selected."""
    book_id = await _book_with_every_element(client, sessionmaker)
    start, end = at(fragment)

    await _explain(client, book_id, text=fragment, start=start, end=end)

    prompt = explanation_provider.last_prompt  # type: ignore[attr-defined]
    assert prompt is not None
    assert fragment.split("\n")[0][:20] in prompt
