"""Shared Document Model fixtures for reader-integration tests.

One document holding every readable element type, used by both the persistence
seam tests and the explanation endpoint tests so the two can never drift apart.

Offsets are derived from the canonical text itself (see :func:`at`), so the
fixture stays checkable by hand as fragments change.
"""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.processing.document_model import (
    Caption,
    Chapter,
    CodeBlock,
    Document,
    DocumentElement,
    DocumentList,
    Footnote,
    Formula,
    Hyperlink,
    Image,
    InlineContent,
    InlineType,
    ListItem,
    Paragraph,
    Quote,
    Section,
    Sentence,
    Table,
    TableCell,
    TableRow,
)

PARAGRAPH_ONE = "Alpha sentence. Beta sentence."
PARAGRAPH_TWO = "Gamma paragraph."
CODE = "SELECT 1;\n  SELECT 2;"
QUOTE = "Reading comes first."
ITEM = "First guideline"
FOOTNOTE = "1. A clarifying note."
FORMULA = "E = mc^2"
CAPTION = "Figure 1. A diagram."
CELL_ONE = "Header"
CELL_TWO = "Value"

#: Canonical reading text: every readable element joined in reading order.
TEXT = "\n\n".join(
    [
        PARAGRAPH_ONE,
        PARAGRAPH_TWO,
        CODE,
        QUOTE,
        ITEM,
        FOOTNOTE,
        FORMULA,
        CAPTION,
        f"{CELL_ONE} | {CELL_TWO}",
    ]
)

#: Every readable fragment paired with the element type that carries it.
READABLE_FRAGMENTS: tuple[tuple[str, str], ...] = (
    (PARAGRAPH_ONE, "paragraph"),
    (CODE, "code block"),
    (QUOTE, "quote"),
    (ITEM, "list item"),
    (FOOTNOTE, "footnote"),
    (FORMULA, "formula"),
    (CAPTION, "caption"),
    (CELL_ONE, "table cell"),
)


def at(fragment: str) -> tuple[int, int]:
    """The canonical ``[start, end)`` range of a fragment in :data:`TEXT`."""
    start = TEXT.index(fragment)
    return start, start + len(fragment)


def span(bounds: tuple[int, int]) -> dict[str, int]:
    return {"start_offset": bounds[0], "end_offset": bounds[1]}


def runs(text: str) -> tuple[InlineContent, ...]:
    return (InlineContent(inline_type=InlineType.TEXT, text=text),)


def all_readable_document(document_id: str = "doc-1") -> Document:
    """A document holding one element of every readable type, plus structure."""
    whole = (0, len(TEXT))
    chapter = Chapter(
        id="ch",
        parent_id=document_id,
        order_index=0,
        title="Chapter",
        attributes=span(whole),
    )
    section = Section(
        id="sec",
        parent_id="ch",
        order_index=0,
        title="Section",
        attributes=span(whole),
    )

    first_bounds = at(PARAGRAPH_ONE)
    first = Paragraph(
        id="p-1", parent_id="sec", order_index=0, attributes=span(first_bounds)
    )
    # Sentences exist in storage; the context seam must never surface them.
    sentence_one = Sentence(
        id="s-1",
        parent_id="p-1",
        order_index=0,
        content=runs("Alpha sentence."),
        attributes=span((first_bounds[0], first_bounds[0] + 15)),
    )
    sentence_two = Sentence(
        id="s-2",
        parent_id="p-1",
        order_index=1,
        content=runs(" Beta sentence."),
        attributes=span((first_bounds[0] + 15, first_bounds[1])),
    )
    second = Paragraph(
        id="p-2", parent_id="sec", order_index=1, attributes=span(at(PARAGRAPH_TWO))
    )
    code = CodeBlock(
        id="code",
        parent_id="sec",
        order_index=2,
        code=CODE,
        language="sql",
        attributes=span(at(CODE)),
    )
    quote = Quote(
        id="quote",
        parent_id="sec",
        order_index=3,
        content=runs(QUOTE),
        attributes=span(at(QUOTE)),
    )
    listing = DocumentList(id="list", parent_id="sec", order_index=4)
    item = ListItem(
        id="item",
        parent_id="list",
        order_index=0,
        content=runs(ITEM),
        attributes=span(at(ITEM)),
    )
    footnote = Footnote(
        id="note",
        parent_id="sec",
        order_index=5,
        reference_id="1",
        label="1",
        content=runs(FOOTNOTE),
        attributes=span(at(FOOTNOTE)),
    )
    formula = Formula(
        id="formula",
        parent_id="sec",
        order_index=6,
        original_representation=FORMULA,
        attributes=span(at(FORMULA)),
    )
    image = Image(
        id="img",
        parent_id="sec",
        order_index=7,
        image_identifier="sha256:abc",
        caption_id="cap",
    )
    caption = Caption(
        id="cap",
        parent_id="img",
        order_index=0,
        describes_id="img",
        content=runs(CAPTION),
        attributes=span(at(CAPTION)),
    )
    row_bounds = (at(CELL_ONE)[0], at(CELL_TWO)[1])
    table = Table(id="tbl", parent_id="sec", order_index=8, attributes=span(row_bounds))
    # A row's span is the union of its cells — the reason rows are not context.
    row = TableRow(
        id="row", parent_id="tbl", order_index=0, attributes=span(row_bounds)
    )
    header = TableCell(
        id="cell-1",
        parent_id="row",
        order_index=0,
        is_header=True,
        content=runs(CELL_ONE),
        attributes=span(at(CELL_ONE)),
    )
    value = TableCell(
        id="cell-2",
        parent_id="row",
        order_index=1,
        content=runs(CELL_TWO),
        attributes=span(at(CELL_TWO)),
    )
    # Span-less: its label already appears in the surrounding text, so giving it
    # a span would duplicate characters. It reaches a window via its section.
    link = Hyperlink(
        id="link",
        parent_id="sec",
        order_index=9,
        target="https://example.test/reference",
        content=runs("Reference"),
    )

    elements: tuple[DocumentElement, ...] = (
        chapter,
        section,
        first,
        sentence_one,
        sentence_two,
        second,
        code,
        quote,
        listing,
        item,
        footnote,
        formula,
        image,
        caption,
        table,
        row,
        header,
        value,
        link,
    )
    return Document(id=document_id, parent_id=None, order_index=0, elements=elements)


async def replace_stored_document(
    session: AsyncSession,
    processed_book_id: uuid.UUID,
    *,
    document: Document | None = None,
    text: str = TEXT,
) -> None:
    """Swap a processed book's stored document for a crafted one.

    Parsers decide which elements a real upload produces, so tests that need
    every element type replace the stored document directly. Nothing else in the
    processing pipeline is bypassed: the document is written through
    :class:`DocumentStore`, exactly as processing writes it.
    """
    from app.modules.processing.document_store import DocumentStore

    await DocumentStore(session).save(
        processed_book_id, document or all_readable_document(), text=text
    )
