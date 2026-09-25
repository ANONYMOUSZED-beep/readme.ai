"""Tests for Document Model persistence, reconstruction, and queries."""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.models import User
from app.modules.library.enums import BookStatus
from app.modules.library.models import Book
from app.modules.processing.document import DocumentMetadata
from app.modules.processing.document_model import (
    Caption,
    Chapter,
    CodeBlock,
    Document,
    ElementType,
    Image,
    InlineContent,
    InlineType,
    Paragraph,
    Section,
    Sentence,
    SourceLocation,
    Table,
    TableCell,
    TableRow,
)
from app.modules.processing.document_store import DocumentStore
from app.modules.processing.enums import ProcessingErrorCode, ProcessingStatus
from app.modules.processing.models import (
    ProcessedBook,
    StoredDocument,
    StoredDocumentElement,
)
from app.modules.processing.parsers import ParseRequest, ProcessorBackedParser
from app.modules.processing.processors.plain_text import PlainTextProcessor
from app.modules.processing.repository import ProcessingRepository

_TEXT = "Alpha sentence. Beta sentence.\n\nGamma paragraph."


def _metadata() -> DocumentMetadata:
    return DocumentMetadata(
        title="Title",
        author=None,
        language=None,
        page_count=None,
        word_count=7,
        character_count=len(_TEXT),
        estimated_reading_minutes=1,
    )


def _span(start: int, end: int) -> dict[str, int]:
    return {"start_offset": start, "end_offset": end}


def _document(document_id: str = "doc-1") -> Document:
    """A document exercising hierarchy, spans, rich elements, and inline runs."""
    chapter = Chapter(
        id="ch-1",
        parent_id=document_id,
        order_index=0,
        title="Chapter",
        attributes=_span(0, 48),
    )
    section = Section(
        id="sec-1",
        parent_id="ch-1",
        order_index=0,
        title="Section",
        attributes=_span(0, 48),
    )
    first = Paragraph(
        id="p-1", parent_id="sec-1", order_index=0, attributes=_span(0, 30)
    )
    sentences = [
        Sentence(
            id="s-1",
            parent_id="p-1",
            order_index=0,
            content=(InlineContent(inline_type=InlineType.TEXT, text=_TEXT[0:16]),),
            attributes=_span(0, 16),
        ),
        Sentence(
            id="s-2",
            parent_id="p-1",
            order_index=1,
            content=(InlineContent(inline_type=InlineType.TEXT, text=_TEXT[16:30]),),
            attributes=_span(16, 30),
        ),
    ]
    second = Paragraph(
        id="p-2", parent_id="sec-1", order_index=1, attributes=_span(32, 48)
    )
    image = Image(
        id="img-1",
        parent_id="sec-1",
        order_index=2,
        image_identifier="figure-1",
        caption_id="cap-1",
        media_type="image/png",
        source=SourceLocation(
            page_number=4,
            bounding_box={"x": 10, "y": 20, "width": 100, "height": 50},
            original_reference="images/figure-1.png",
        ),
    )
    caption = Caption(
        id="cap-1",
        parent_id="img-1",
        order_index=0,
        describes_id="img-1",
        content=(InlineContent(inline_type=InlineType.ITALIC, text="Figure one"),),
    )
    table = Table(id="tbl-1", parent_id="sec-1", order_index=3)
    row = TableRow(id="row-1", parent_id="tbl-1", order_index=0)
    cell = TableCell(
        id="cell-1",
        parent_id="row-1",
        order_index=0,
        is_header=True,
        content=(InlineContent(inline_type=InlineType.TEXT, text="Header"),),
    )
    code = CodeBlock(
        id="code-1",
        parent_id="sec-1",
        order_index=4,
        code="print('read')",
        language="python",
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
            image,
            caption,
            table,
            row,
            cell,
            code,
        ),
        source=SourceLocation(original_reference="storage/book.txt"),
    )


async def _processed_book(session: AsyncSession) -> ProcessedBook:
    """Create the FK chain a processing record needs (user -> book -> record)."""
    user = User(firebase_uid=f"uid-{uuid.uuid4()}", email=f"{uuid.uuid4()}@test.dev")
    session.add(user)
    await session.flush()
    book = Book(
        user_id=user.id,
        title="Book",
        original_filename="book.txt",
        storage_key=f"books/{uuid.uuid4()}.txt",
        mime_type="text/plain",
        file_size=len(_TEXT),
        status=BookStatus.UPLOADED,
    )
    session.add(book)
    await session.flush()
    record = ProcessedBook(book_id=book.id, status=ProcessingStatus.PROCESSING)
    session.add(record)
    await session.flush()
    return record


@pytest.fixture
async def session(
    sessionmaker: async_sessionmaker[AsyncSession],
) -> AsyncIterator[AsyncSession]:
    async with sessionmaker() as active:
        yield active


# --- persistence & reconstruction ------------------------------------------
async def test_document_round_trips_through_storage(session: AsyncSession) -> None:
    record = await _processed_book(session)
    store = DocumentStore(session)
    original = _document()

    await store.save(record.id, original, text=_TEXT)
    restored = await store.load(record.id)

    # Reconstruction is exact, including concrete element types.
    assert restored == original


async def test_reconstruction_preserves_rich_elements_and_source_metadata(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    store = DocumentStore(session)

    await store.save(record.id, _document(), text=_TEXT)
    restored = await store.load(record.id)

    assert restored is not None
    by_id = {element.id: element for element in restored.elements}
    image = by_id["img-1"]
    assert isinstance(image, Image)
    assert image.image_identifier == "figure-1"
    assert image.source.page_number == 4
    assert image.source.bounding_box is not None
    assert image.source.bounding_box.width == 100
    assert isinstance(by_id["cap-1"], Caption)
    assert isinstance(by_id["cell-1"], TableCell)
    code = by_id["code-1"]
    assert isinstance(code, CodeBlock)
    assert code.code == "print('read')"


async def test_hierarchy_integrity_is_revalidated_on_load(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    store = DocumentStore(session)
    await store.save(record.id, _document(), text=_TEXT)

    restored = await store.load(record.id)

    assert restored is not None
    chapters = [
        element
        for element in restored.children_of(restored.id)
        if element.element_type == ElementType.CHAPTER
    ]
    sections = restored.children_of(chapters[0].id)
    paragraphs = [
        element
        for element in restored.children_of(sections[0].id)
        if element.element_type == ElementType.PARAGRAPH
    ]
    sentences = restored.children_of(paragraphs[0].id)

    assert [element.order_index for element in sentences] == [0, 1]
    assert paragraphs[0].attributes["start_offset"] == 0
    assert paragraphs[1].attributes["end_offset"] == 48


async def test_corrupted_hierarchy_is_rejected_on_load(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    store = DocumentStore(session)
    await store.save(record.id, _document(), text=_TEXT)

    # Simulate storage damage: point a section at a parent that does not exist.
    element = await session.scalar(
        select(StoredDocumentElement).where(StoredDocumentElement.element_id == "sec-1")
    )
    assert element is not None
    element.parent_element_id = "missing-chapter"
    await session.flush()

    with pytest.raises(ValidationError):
        await store.load(record.id)


# --- storage efficiency ----------------------------------------------------
async def test_text_is_stored_once_and_sentences_derive_their_content(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    store = DocumentStore(session)

    await store.save(record.id, _document(), text=_TEXT)

    stored = await session.scalar(
        select(StoredDocument).where(StoredDocument.processed_book_id == record.id)
    )
    assert stored is not None
    assert stored.text == _TEXT
    assert stored.character_count == len(_TEXT)

    sentence_content = await session.scalars(
        select(StoredDocumentElement.content).where(
            StoredDocumentElement.document_id == stored.id,
            StoredDocumentElement.element_type == ElementType.SENTENCE.value,
        )
    )
    # Derivable inline runs are not duplicated into element rows.
    assert all(content is None for content in sentence_content.all())

    caption_content = await session.scalar(
        select(StoredDocumentElement.content).where(
            StoredDocumentElement.document_id == stored.id,
            StoredDocumentElement.element_id == "cap-1",
        )
    )
    # Non-derivable inline runs (styled, non-span text) are stored explicitly.
    assert caption_content is not None


async def test_saving_again_replaces_the_previous_document(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    store = DocumentStore(session)

    await store.save(record.id, _document(), text=_TEXT)
    await store.save(record.id, _document("doc-2"), text=_TEXT)

    documents = await session.scalar(select(func.count()).select_from(StoredDocument))
    orphans = await session.scalar(
        select(func.count())
        .select_from(StoredDocumentElement)
        .where(StoredDocumentElement.document_id == "doc-1")
    )
    assert documents == 1
    assert orphans == 0


# --- repository operations --------------------------------------------------
async def test_repository_serves_reader_text_and_selection_queries(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    repository = ProcessingRepository(session)
    await repository.documents.save(record.id, _document(), text=_TEXT)

    text = await repository.get_document_text(record.id)
    spans = await repository.get_paragraphs_overlapping(record.id, 0, 5)
    both = await repository.get_paragraphs_overlapping(record.id, 0, 40)
    sentences = await repository.count_sentences_overlapping(record.id, 0, 20)

    assert text == _TEXT
    # Paragraph text is sliced in the database from the single stored copy.
    assert [span.text for span in spans] == ["Alpha sentence. Beta sentence."]
    assert len(both) == 2
    assert sentences == 2


async def test_repository_clears_document_on_failure(session: AsyncSession) -> None:
    record = await _processed_book(session)
    repository = ProcessingRepository(session)
    await repository.documents.save(record.id, _document(), text=_TEXT)

    await repository.save_failed(record, ProcessingErrorCode.MALFORMED_FILE, "broken")

    assert await repository.get_document_text(record.id) is None
    assert record.status is ProcessingStatus.FAILED
    assert record.error_code == "malformed_file"


async def test_repository_save_completed_persists_model_and_metadata(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    repository = ProcessingRepository(session)

    await repository.save_completed(
        record,
        document=_document(),
        text=_TEXT,
        metadata=_metadata(),
        parser_name="plain_text",
    )

    assert record.status is ProcessingStatus.COMPLETED
    assert record.processor_name == "plain_text"
    assert record.character_count == len(_TEXT)
    assert await repository.get_document(record.id) is not None


# --- parser -> persistence integration -------------------------------------
async def test_parser_output_persists_and_reconstructs(
    session: AsyncSession,
) -> None:
    record = await _processed_book(session)
    repository = ProcessingRepository(session)
    parser = ProcessorBackedParser(PlainTextProcessor())

    result = parser.parse(
        ParseRequest(
            filename="book.txt",
            mime_type="text/plain",
            data=b"# Title\n\nFirst paragraph. Two sentences here.\n\nSecond one.",
            source_reference="books/book.txt",
        )
    )
    await repository.save_completed(
        record,
        document=result.document,
        text=result.canonical_text,
        metadata=result.metadata,
        parser_name=result.parser_name,
    )

    restored = await repository.get_document(record.id)
    text = await repository.get_document_text(record.id)

    assert restored == result.document
    assert text == result.canonical_text
