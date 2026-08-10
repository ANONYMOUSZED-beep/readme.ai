"""Tests for the windowed element read model (Sprint 6.5, task 1)."""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.models import User
from app.modules.library.enums import BookStatus
from app.modules.library.models import Book
from app.modules.processing.document_model import (
    Caption,
    Chapter,
    CodeBlock,
    Document,
    DocumentElement,
    DocumentList,
    ElementType,
    Hyperlink,
    Image,
    InlineContent,
    InlineType,
    ListItem,
    Paragraph,
    Section,
    Sentence,
    Table,
    TableCell,
    TableRow,
)
from app.modules.processing.document_store import DocumentStore
from app.modules.processing.element_query import (
    _MAX_ANCESTOR_ROUNDS,
    MAX_WINDOW_ELEMENTS,
    MAX_WINDOW_SPAN,
    DocumentElementQuery,
)
from app.modules.processing.enums import ProcessingStatus
from app.modules.processing.models import ProcessedBook

_TEXT = (
    "Alpha sentence. Beta sentence."  # 0..30   paragraph p-1
    "\n\n"
    "Gamma paragraph."  # 32..48  paragraph p-2
    "\n\n"
    "print('read')"  # 50..63  code
    "\n\n"
    "First item"  # 65..75  list item
    "\n\n"
    "Header | Value"  # 77..91  table row / cells
    "\n\n"
    "Figure 1. A caption."  # 93..113 caption
)


def _span(start: int, end: int) -> dict[str, int]:
    return {"start_offset": start, "end_offset": end}


def _runs(text: str) -> tuple[InlineContent, ...]:
    return (InlineContent(inline_type=InlineType.TEXT, text=text),)


def _document(document_id: str = "doc-1") -> Document:
    """A document holding every element shape the window query must handle."""
    chapter = Chapter(
        id="ch",
        parent_id=document_id,
        order_index=0,
        title="Chapter",
        attributes=_span(0, 113),
    )
    section = Section(
        id="sec",
        parent_id="ch",
        order_index=0,
        title="Section",
        attributes=_span(0, 113),
    )
    first = Paragraph(id="p-1", parent_id="sec", order_index=0, attributes=_span(0, 30))
    sentences: list[DocumentElement] = [
        Sentence(
            id="s-1",
            parent_id="p-1",
            order_index=0,
            content=_runs(_TEXT[0:16]),
            attributes=_span(0, 16),
        ),
        Sentence(
            id="s-2",
            parent_id="p-1",
            order_index=1,
            content=_runs(_TEXT[16:30]),
            attributes=_span(16, 30),
        ),
    ]
    second = Paragraph(
        id="p-2", parent_id="sec", order_index=1, attributes=_span(32, 48)
    )
    code = CodeBlock(
        id="code",
        parent_id="sec",
        order_index=2,
        code=_TEXT[50:63],
        language="python",
        attributes=_span(50, 63),
    )
    listing = DocumentList(id="list", parent_id="sec", order_index=3, ordered=False)
    item = ListItem(
        id="item",
        parent_id="list",
        order_index=0,
        content=_runs(_TEXT[65:75]),
        attributes=_span(65, 75),
    )
    table = Table(id="tbl", parent_id="sec", order_index=4, attributes=_span(77, 91))
    row = TableRow(id="row", parent_id="tbl", order_index=0, attributes=_span(77, 91))
    header = TableCell(
        id="cell-1",
        parent_id="row",
        order_index=0,
        is_header=True,
        content=_runs("Header"),
        attributes=_span(77, 83),
    )
    value = TableCell(
        id="cell-2",
        parent_id="row",
        order_index=1,
        content=_runs("Value"),
        attributes=_span(86, 91),
    )
    image = Image(
        id="img",
        parent_id="sec",
        order_index=5,
        image_identifier="sha256:abc",
        caption_id="cap",
        media_type="image/png",
        width=200,
        height=100,
    )
    caption = Caption(
        id="cap",
        parent_id="img",
        order_index=0,
        describes_id="img",
        content=_runs(_TEXT[93:113]),
        attributes=_span(93, 113),
    )
    link = Hyperlink(
        id="link",
        parent_id="sec",
        order_index=6,
        target="https://example.test",
        content=_runs("Reference"),
    )
    return Document(
        id=document_id,
        parent_id=None,
        order_index=0,
        elements=(
            chapter,
            section,
            first,
            *sentences,
            second,
            code,
            listing,
            item,
            table,
            row,
            header,
            value,
            image,
            caption,
            link,
        ),
    )


async def _seed(session: AsyncSession) -> uuid.UUID:
    user = User(firebase_uid=f"uid-{uuid.uuid4()}", email=f"{uuid.uuid4()}@test.dev")
    session.add(user)
    await session.flush()
    book = Book(
        user_id=user.id,
        title="Book",
        original_filename="book.pdf",
        storage_key=f"books/{uuid.uuid4()}.pdf",
        mime_type="application/pdf",
        file_size=len(_TEXT),
        status=BookStatus.READY,
    )
    session.add(book)
    await session.flush()
    record = ProcessedBook(book_id=book.id, status=ProcessingStatus.COMPLETED)
    session.add(record)
    await session.flush()
    await DocumentStore(session).save(record.id, _document(), text=_TEXT)
    return record.id


@pytest.fixture
async def session(
    sessionmaker: async_sessionmaker[AsyncSession],
) -> AsyncIterator[AsyncSession]:
    async with sessionmaker() as active:
        yield active


def _ids(window: object) -> list[str]:
    return [element.element_id for element in window.elements]  # type: ignore[attr-defined]


async def test_window_returns_elements_overlapping_the_range(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(record_id, start=0, end=31)

    assert "p-1" in _ids(window)
    assert "p-2" not in _ids(window)
    assert window.character_count == len(_TEXT)
    assert window.truncated is False


async def test_overlap_predicate_boundaries_are_half_open(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)
    query = DocumentElementQuery(session)

    touching_end = await query.window(record_id, start=30, end=32)
    contained = await query.window(record_id, start=33, end=40)
    spanning = await query.window(record_id, start=0, end=113)

    # A span ending exactly at the window start does not overlap it.
    assert "p-1" not in _ids(touching_end)
    assert "p-2" in _ids(contained)
    assert {"p-1", "p-2", "code", "item", "cell-1", "cap"} <= set(_ids(spanning))


async def test_structural_ancestors_are_included(session: AsyncSession) -> None:
    record_id = await _seed(session)

    # A range covering only a list item and a table cell.
    window = await DocumentElementQuery(session).window(record_id, start=65, end=91)
    ids = set(_ids(window))

    assert {"item", "cell-1", "cell-2"} <= ids
    # The list, table, row, section and chapter arrive so nothing renders orphaned.
    assert {"list", "tbl", "row", "sec", "ch"} <= ids


async def test_spanless_children_are_attached_via_their_container(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(record_id, start=0, end=31)
    ids = set(_ids(window))

    # Images and hyperlinks carry no offsets, so an overlap predicate cannot reach
    # them; they arrive through their section.
    assert "img" in ids
    assert "link" in ids


async def test_sentences_are_never_delivered(session: AsyncSession) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(record_id, start=0, end=113)

    assert not [
        element
        for element in window.elements
        if element.element_type == ElementType.SENTENCE.value
    ]


async def test_elements_are_ordered_by_document_sequence(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(record_id, start=0, end=113)

    sequences = [element.sequence for element in window.elements]
    assert sequences == sorted(sequences)
    ids = _ids(window)
    assert ids.index("ch") < ids.index("sec") < ids.index("p-1")
    assert ids.index("p-1") < ids.index("p-2") < ids.index("code")


async def test_payload_and_text_delivery_rules(session: AsyncSession) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(record_id, start=0, end=113)
    by_id = {element.element_id: element for element in window.elements}

    # Payload passes through exactly as stored.
    assert by_id["code"].payload["language"] == "python"
    assert by_id["img"].payload["image_identifier"] == "sha256:abc"
    assert by_id["ch"].payload["title"] == "Chapter"
    # Derivable text is omitted; the client slices it from the canonical text.
    assert by_id["p-1"].text is None
    assert by_id["code"].text is None
    # Non-derivable text is delivered.
    assert by_id["cell-1"].text == "Header"
    assert by_id["cap"].text == _TEXT[93:113]
    assert by_id["link"].text == "Reference"


async def test_source_metadata_is_delivered(session: AsyncSession) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(record_id, start=0, end=113)
    by_id = {element.element_id: element for element in window.elements}

    assert by_id["p-1"].start_offset == 0
    assert by_id["p-1"].end_offset == 30
    assert by_id["img"].start_offset is None
    assert by_id["p-1"].parent_id == "sec"
    assert by_id["p-1"].order_index == 0


async def test_requested_span_is_clamped(session: AsyncSession) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(
        record_id, start=0, end=MAX_WINDOW_SPAN * 4
    )
    reversed_window = await DocumentElementQuery(session).window(
        record_id, start=50, end=10
    )
    negative = await DocumentElementQuery(session).window(record_id, start=-100, end=20)

    assert window.end == MAX_WINDOW_SPAN
    assert reversed_window.start == 50
    assert reversed_window.end == 50
    assert negative.start == 0


async def test_element_cap_truncates_at_an_element_boundary(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)
    query = DocumentElementQuery(session)

    window = await query.window(record_id, start=0, end=113)

    # This fixture is far below the cap, so the flag is off and the cap is a
    # named constant rather than a magic number.
    assert window.truncated is False
    assert len(window.elements) <= MAX_WINDOW_ELEMENTS


async def test_truncation_never_orphans_a_child(session: AsyncSession) -> None:
    record_id = await _seed(session)

    window = await DocumentElementQuery(session).window(record_id, start=0, end=113)
    ids = set(_ids(window))

    for element in window.elements:
        if element.parent_id is not None and element.parent_id != "doc-1":
            assert element.parent_id in ids


async def test_unprocessed_book_returns_an_empty_window(
    session: AsyncSession,
) -> None:
    query = DocumentElementQuery(session)

    window = await query.window(uuid.uuid4(), start=0, end=100)

    assert window.elements == ()
    assert window.character_count == 0
    assert window.truncated is False


async def test_window_is_deterministic_across_calls(session: AsyncSession) -> None:
    record_id = await _seed(session)
    query = DocumentElementQuery(session)

    first = await query.window(record_id, start=0, end=113)
    second = await query.window(record_id, start=0, end=113)

    assert first == second


async def test_query_count_is_bounded_per_window(session: AsyncSession) -> None:
    """Ancestors resolve breadth-first, so queries scale with depth, not elements.

    A per-element (N+1) lookup would make a full window on the reference book
    thousands of round trips; this pins the bound instead of trusting it.
    """
    record_id = await _seed(session)
    query = DocumentElementQuery(session)
    executions = 0

    original_execute = session.execute

    async def counting_execute(*args: object, **kwargs: object) -> object:
        nonlocal executions
        executions += 1
        return await original_execute(*args, **kwargs)  # type: ignore[arg-type]

    session.execute = counting_execute  # type: ignore[method-assign]
    try:
        window = await query.window(record_id, start=0, end=113)
    finally:
        session.execute = original_execute  # type: ignore[method-assign]

    # document lookup + anchors + span-less children + at most one query per
    # hierarchy level (document > chapter > section > table > row > cell).
    assert executions <= 3 + _MAX_ANCESTOR_ROUNDS
    assert len(window.elements) > executions
