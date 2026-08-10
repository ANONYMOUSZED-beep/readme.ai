"""Truncation and bound tests against a realistic large document (task 2).

The task-1 fixture is deliberately small, so the caps there are verified by
construction rather than by execution. This module builds a document that exceeds
both limits — more than 2,000 anchor elements and more than 50,000 canonical
scalar offsets — and exercises the real truncation path.

Paragraph geometry is fixed-width so every offset in the assertions below is
computable by hand:

    text  = "Para {i:04d} reads well."   -> 21 characters
    stride = 21 + len("\\n\\n")           -> 23 characters
    start(i) = i * 23,  end(i) = i * 23 + 21
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.models import User
from app.modules.library.enums import BookStatus
from app.modules.library.models import Book
from app.modules.processing.document_model import (
    Chapter,
    Document,
    DocumentElement,
    ElementType,
    Paragraph,
    Section,
)
from app.modules.processing.document_store import DocumentStore
from app.modules.processing.element_query import (
    MAX_WINDOW_ELEMENTS,
    MAX_WINDOW_SPAN,
    DocumentElementQuery,
    ElementWindow,
)
from app.modules.processing.enums import ProcessingStatus
from app.modules.processing.models import ProcessedBook

#: Enough paragraphs to exceed the element cap, and enough characters to exceed
#: the span cap: 2600 * 23 - 2 = 59,798 canonical offsets.
_PARAGRAPH_COUNT = 2600
_SEPARATOR = "\n\n"
_PARAGRAPH_LENGTH = 21
_STRIDE = _PARAGRAPH_LENGTH + len(_SEPARATOR)


def _paragraph_text(index: int) -> str:
    text = f"Para {index:04d} reads well."
    assert len(text) == _PARAGRAPH_LENGTH, text
    return text


_TEXT = _SEPARATOR.join(_paragraph_text(index) for index in range(_PARAGRAPH_COUNT))


def _start_of(index: int) -> int:
    return index * _STRIDE


def _end_of(index: int) -> int:
    return index * _STRIDE + _PARAGRAPH_LENGTH


def _window_covering(count: int) -> tuple[int, int]:
    """A range overlapping exactly the first ``count`` paragraphs."""
    return 0, _end_of(count - 1)


def _document(document_id: str = "large-doc") -> Document:
    """One chapter, one section, and 2,600 paragraph anchors."""
    elements: list[DocumentElement] = [
        Chapter(
            id="ch",
            parent_id=document_id,
            order_index=0,
            title="Large Chapter",
            attributes={"start_offset": 0, "end_offset": len(_TEXT)},
        ),
        Section(
            id="sec",
            parent_id="ch",
            order_index=0,
            title="Large Section",
            attributes={"start_offset": 0, "end_offset": len(_TEXT)},
        ),
    ]
    for index in range(_PARAGRAPH_COUNT):
        elements.append(
            Paragraph(
                id=f"p-{index:04d}",
                parent_id="sec",
                order_index=index,
                attributes={
                    "start_offset": _start_of(index),
                    "end_offset": _end_of(index),
                },
            )
        )
    return Document(
        id=document_id, parent_id=None, order_index=0, elements=tuple(elements)
    )


async def _seed(session: AsyncSession) -> uuid.UUID:
    user = User(firebase_uid=f"uid-{uuid.uuid4()}", email=f"{uuid.uuid4()}@test.dev")
    session.add(user)
    await session.flush()
    book = Book(
        user_id=user.id,
        title="Large Book",
        original_filename="large.pdf",
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


@pytest.fixture
async def large_book(session: AsyncSession) -> uuid.UUID:
    return await _seed(session)


def _anchors(window: ElementWindow) -> list[str]:
    return [
        element.element_id
        for element in window.elements
        if element.element_type == ElementType.PARAGRAPH.value
    ]


def test_fixture_exceeds_both_implementation_limits() -> None:
    # The premise of every assertion below.
    assert _PARAGRAPH_COUNT > MAX_WINDOW_ELEMENTS
    assert len(_TEXT) > MAX_WINDOW_SPAN
    assert len(_TEXT) == _PARAGRAPH_COUNT * _STRIDE - len(_SEPARATOR)


async def test_span_is_clamped_and_the_window_truncates(
    session: AsyncSession,
    large_book: uuid.UUID,
) -> None:
    window = await DocumentElementQuery(session).window(
        large_book, start=0, end=len(_TEXT)
    )

    assert window.end == MAX_WINDOW_SPAN
    assert window.truncated is True
    assert len(_anchors(window)) == MAX_WINDOW_ELEMENTS
    assert window.character_count == len(_TEXT)


@pytest.mark.parametrize(
    ("count", "expected_truncated", "expected_anchors"),
    [
        (MAX_WINDOW_ELEMENTS - 1, False, MAX_WINDOW_ELEMENTS - 1),
        (MAX_WINDOW_ELEMENTS, False, MAX_WINDOW_ELEMENTS),
        (MAX_WINDOW_ELEMENTS + 1, True, MAX_WINDOW_ELEMENTS),
    ],
)
async def test_element_cap_boundary(
    session: AsyncSession,
    large_book: uuid.UUID,
    count: int,
    expected_truncated: bool,
    expected_anchors: int,
) -> None:
    """Exactly 1,999 / 2,000 / 2,001 overlapping anchors."""
    start, end = _window_covering(count)
    assert end <= MAX_WINDOW_SPAN, "boundary ranges must not be span-clamped"

    window = await DocumentElementQuery(session).window(
        large_book, start=start, end=end
    )

    assert window.truncated is expected_truncated
    assert len(_anchors(window)) == expected_anchors
    # Ancestors are added after the cap, so they never displace an anchor.
    assert len(window.elements) == expected_anchors + 2


async def test_truncation_keeps_the_first_anchors_in_document_order(
    session: AsyncSession,
    large_book: uuid.UUID,
) -> None:
    start, end = _window_covering(MAX_WINDOW_ELEMENTS + 1)

    window = await DocumentElementQuery(session).window(
        large_book, start=start, end=end
    )
    anchors = _anchors(window)

    # Truncation drops the tail, never the head, and never reorders.
    assert anchors[0] == "p-0000"
    assert anchors[-1] == f"p-{MAX_WINDOW_ELEMENTS - 1:04d}"
    assert anchors == sorted(anchors)
    assert f"p-{MAX_WINDOW_ELEMENTS:04d}" not in anchors


async def test_truncated_window_preserves_element_and_parent_ordering(
    session: AsyncSession,
    large_book: uuid.UUID,
) -> None:
    window = await DocumentElementQuery(session).window(
        large_book, start=0, end=MAX_WINDOW_SPAN
    )

    sequences = [element.sequence for element in window.elements]
    ids = [element.element_id for element in window.elements]

    assert sequences == sorted(sequences)
    # Parents precede their children in document order.
    assert ids.index("ch") < ids.index("sec") < ids.index("p-0000")


async def test_truncated_window_has_no_orphan_children(
    session: AsyncSession,
    large_book: uuid.UUID,
) -> None:
    window = await DocumentElementQuery(session).window(
        large_book, start=0, end=MAX_WINDOW_SPAN
    )
    present = {element.element_id for element in window.elements}

    for element in window.elements:
        if element.parent_id is not None and element.parent_id != "large-doc":
            assert element.parent_id in present, element.element_id


async def test_canonical_ranges_survive_truncation(
    session: AsyncSession,
    large_book: uuid.UUID,
) -> None:
    window = await DocumentElementQuery(session).window(
        large_book, start=0, end=MAX_WINDOW_SPAN
    )

    paragraphs = [
        element
        for element in window.elements
        if element.element_type == ElementType.PARAGRAPH.value
    ]
    for element in paragraphs:
        assert element.start_offset is not None
        assert element.end_offset is not None
        index = int(element.element_id.removeprefix("p-"))
        assert element.start_offset == _start_of(index)
        assert element.end_offset == _end_of(index)
        # The span still addresses exactly the element's own characters.
        assert _TEXT[element.start_offset : element.end_offset] == _paragraph_text(
            index
        )


async def test_repeated_requests_return_identical_windows(
    session: AsyncSession,
    large_book: uuid.UUID,
) -> None:
    query = DocumentElementQuery(session)

    first = await query.window(large_book, start=0, end=MAX_WINDOW_SPAN)
    second = await query.window(large_book, start=0, end=MAX_WINDOW_SPAN)
    third = await query.window(large_book, start=0, end=len(_TEXT))

    assert first == second
    # A clamped request resolves to the same window as the clamped range itself.
    assert first == third


async def test_a_later_window_is_bounded_and_untruncated(
    session: AsyncSession,
    large_book: uuid.UUID,
) -> None:
    """A mid-document window returns only its own elements, with no truncation."""
    start = _start_of(2400)
    end = _end_of(2450)

    window = await DocumentElementQuery(session).window(
        large_book, start=start, end=end
    )
    anchors = _anchors(window)

    assert window.truncated is False
    assert anchors == [f"p-{index:04d}" for index in range(2400, 2451)]
    assert {"ch", "sec"} <= {element.element_id for element in window.elements}
