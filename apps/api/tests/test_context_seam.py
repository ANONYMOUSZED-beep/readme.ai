"""Tests for the widened explanation context seam (Sprint 6.5, task 14).

The seam lives in persistence: ``ProcessingRepository.get_paragraphs_overlapping``
keeps its name and signature, and the Explanation Engine is not modified. These
tests pin the two properties that make the widening safe — every readable element
type provides context, and paragraph-only selections behave exactly as before.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.models import User
from app.modules.library.enums import BookStatus
from app.modules.library.models import Book
from app.modules.processing.document_model import ElementType
from app.modules.processing.document_store import CONTEXT_TYPES, DocumentStore
from app.modules.processing.enums import ProcessingStatus
from app.modules.processing.models import ProcessedBook
from app.modules.processing.repository import ProcessingRepository
from tests.document_fixtures import (
    CAPTION,
    CELL_ONE,
    CODE,
    FOOTNOTE,
    FORMULA,
    ITEM,
    PARAGRAPH_ONE,
    PARAGRAPH_TWO,
    QUOTE,
    TEXT,
    all_readable_document,
    at,
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
        file_size=len(TEXT),
        status=BookStatus.READY,
    )
    session.add(book)
    await session.flush()
    record = ProcessedBook(book_id=book.id, status=ProcessingStatus.COMPLETED)
    session.add(record)
    await session.flush()
    await DocumentStore(session).save(record.id, all_readable_document(), text=TEXT)
    return record.id


@pytest.fixture
async def session(
    sessionmaker: async_sessionmaker[AsyncSession],
) -> AsyncIterator[AsyncSession]:
    async with sessionmaker() as active:
        yield active


def test_context_types_are_frozen_and_exclude_nested_spans() -> None:
    expected = frozenset(
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

    assert expected == CONTEXT_TYPES
    # Both exclusions are load-bearing: sentences nest inside paragraphs, and a
    # table row's span is the union of its cells.
    assert ElementType.SENTENCE not in CONTEXT_TYPES
    assert ElementType.TABLE_ROW not in CONTEXT_TYPES


@pytest.mark.parametrize(
    ("fragment", "label"),
    [
        (CODE, "code block"),
        (QUOTE, "quote"),
        (ITEM, "list item"),
        (FOOTNOTE, "footnote"),
        (FORMULA, "formula"),
        (CAPTION, "caption"),
        (CELL_ONE, "table cell"),
    ],
)
async def test_every_readable_type_provides_context(
    session: AsyncSession,
    fragment: str,
    label: str,
) -> None:
    record_id = await _seed(session)
    repository = ProcessingRepository(session)
    start, end = at(fragment)

    spans = await repository.get_paragraphs_overlapping(record_id, start, end)

    assert spans, f"no context returned for a selection inside a {label}"
    assert fragment in "\n\n".join(span.text for span in spans)


async def test_selection_inside_code_preserves_whitespace(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)
    repository = ProcessingRepository(session)
    start, end = at(CODE)

    spans = await repository.get_paragraphs_overlapping(record_id, start, end)

    assert spans[0].text == CODE
    assert "\n  " in spans[0].text


async def test_paragraph_only_selections_are_byte_identical(
    session: AsyncSession,
) -> None:
    """Property 11: widening must not change paragraph-selection behaviour."""
    record_id = await _seed(session)
    repository = ProcessingRepository(session)
    store = repository.documents
    paragraph_bounds = [at(PARAGRAPH_ONE), at(PARAGRAPH_TWO)]

    ranges = [
        (0, 1),  # single word at the start
        paragraph_bounds[0],  # exactly one paragraph
        (paragraph_bounds[0][0], paragraph_bounds[1][1]),  # two paragraphs
        (paragraph_bounds[0][1] - 5, paragraph_bounds[1][0] + 5),  # across the gap
    ]

    for start, end in ranges:
        widened = await repository.get_paragraphs_overlapping(record_id, start, end)
        paragraphs_only = await store.spans_overlapping(
            record_id, ElementType.PARAGRAPH, start, end
        )
        assert widened == paragraphs_only, f"divergence for range ({start}, {end})"


async def test_sentences_and_table_rows_never_appear_as_context(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)
    repository = ProcessingRepository(session)
    store = repository.documents

    whole = await repository.get_paragraphs_overlapping(record_id, 0, len(TEXT))
    sentences = await store.spans_overlapping(
        record_id, ElementType.SENTENCE, 0, len(TEXT)
    )
    rows = await store.spans_overlapping(record_id, ElementType.TABLE_ROW, 0, len(TEXT))

    # Sentences and rows exist in storage but are not context spans, so their
    # characters are never counted twice.
    assert sentences and rows
    returned = {(span.start_offset, span.end_offset) for span in whole}
    assert not returned & {(s.start_offset, s.end_offset) for s in sentences}
    assert (rows[0].start_offset, rows[0].end_offset) not in returned


async def test_word_selection_returns_a_single_context_span(
    session: AsyncSession,
) -> None:
    """The classifier reads span count as passage size, so a word must yield one."""
    record_id = await _seed(session)
    repository = ProcessingRepository(session)
    start, _ = at(PARAGRAPH_ONE)

    spans = await repository.get_paragraphs_overlapping(record_id, start, start + 5)

    assert len(spans) == 1
    assert spans[0].text == PARAGRAPH_ONE


async def test_context_spans_are_returned_in_reading_order(
    session: AsyncSession,
) -> None:
    record_id = await _seed(session)
    repository = ProcessingRepository(session)

    spans = await repository.get_paragraphs_overlapping(record_id, 0, len(TEXT))

    offsets = [span.start_offset for span in spans]
    assert offsets == sorted(offsets)


async def test_sentence_counting_is_unchanged(session: AsyncSession) -> None:
    record_id = await _seed(session)
    repository = ProcessingRepository(session)
    start, end = at(PARAGRAPH_ONE)

    inside_one = await repository.count_sentences_overlapping(
        record_id, start, start + 5
    )
    across_both = await repository.count_sentences_overlapping(record_id, start, end)
    inside_code = await repository.count_sentences_overlapping(record_id, *at(CODE))

    assert inside_one == 1
    assert across_both == 2
    # Code blocks have no sentence children, so counting there yields nothing.
    assert inside_code == 0
