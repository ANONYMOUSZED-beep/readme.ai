"""Unit tests for the format-independent Document Model (no parsers)."""

from __future__ import annotations

from typing import Any

import pytest
from pydantic import ValidationError

from app.modules.processing.document_model import (
    BoundingBox,
    Caption,
    Chapter,
    CodeBlock,
    Document,
    DocumentList,
    ElementType,
    Footnote,
    Formula,
    Hyperlink,
    Image,
    InlineContent,
    InlineType,
    ListItem,
    Metadata,
    Paragraph,
    Quote,
    Section,
    Sentence,
    SourceLocation,
    StableIdFactory,
    Table,
    TableCell,
    TableRow,
    UnknownElement,
)


def _common(
    element_id: str,
    parent_id: str | None,
    order_index: int,
    element_type: str,
) -> dict[str, Any]:
    return {
        "id": element_id,
        "parent_id": parent_id,
        "order_index": order_index,
        "element_type": element_type,
    }


def _basic_document() -> Document:
    document_id = "document-1"
    chapter = Chapter(**_common("chapter-1", document_id, 0, ElementType.CHAPTER))
    section = Section(**_common("section-1", chapter.id, 0, ElementType.SECTION))
    paragraph = Paragraph(
        **_common("paragraph-1", section.id, 0, ElementType.PARAGRAPH)
    )
    sentence = Sentence(
        **_common("sentence-1", paragraph.id, 0, ElementType.SENTENCE),
        content=(InlineContent(inline_type=InlineType.TEXT, text="Read deeply."),),
    )
    return Document(
        **_common(document_id, None, 0, ElementType.DOCUMENT),
        elements=(chapter, section, paragraph, sentence),
        source=SourceLocation(original_reference="book.epub"),
    )


def _rich_document() -> Document:
    document_id = "rich-document"
    chapter = Chapter(**_common("chapter", document_id, 0, ElementType.CHAPTER))
    metadata = Metadata(
        **_common("metadata", document_id, 1, ElementType.METADATA),
        key="creator",
        value={"name": "Ada"},
    )
    section = Section(**_common("section", chapter.id, 0, ElementType.SECTION))
    image = Image(
        **_common("image", section.id, 0, ElementType.IMAGE),
        image_identifier="cover-image",
        caption_id="caption",
        media_type="image/png",
        source=SourceLocation(
            page_number=3,
            bounding_box=BoundingBox(x=10, y=20, width=200, height=100),
            original_reference="images/cover.png",
        ),
    )
    caption = Caption(
        **_common("caption", image.id, 0, ElementType.CAPTION),
        describes_id=image.id,
        content=(InlineContent(inline_type=InlineType.ITALIC, text="Architecture"),),
    )
    table = Table(**_common("table", section.id, 1, ElementType.TABLE))
    row = TableRow(**_common("row", table.id, 0, ElementType.TABLE_ROW))
    cell = TableCell(
        **_common("cell", row.id, 0, ElementType.TABLE_CELL),
        content=(InlineContent(inline_type=InlineType.TEXT, text="Value"),),
        is_header=True,
    )
    code = CodeBlock(
        **_common("code", section.id, 2, ElementType.CODE_BLOCK),
        code="print('read')",
        language="python",
    )
    formula = Formula(
        **_common("formula", section.id, 3, ElementType.FORMULA),
        original_representation=r"E = mc^2",
        representation_format="latex",
    )
    document_list = DocumentList(
        **_common("list", section.id, 4, ElementType.LIST), ordered=True
    )
    list_item = ListItem(
        **_common("item", document_list.id, 0, ElementType.LIST_ITEM),
        content=(InlineContent(inline_type=InlineType.BOLD, text="First"),),
    )
    quote = Quote(
        **_common("quote", section.id, 5, ElementType.QUOTE),
        content=(InlineContent(inline_type=InlineType.TEXT, text="Keep reading"),),
    )
    hyperlink = Hyperlink(
        **_common("link", section.id, 6, ElementType.HYPERLINK),
        target="https://example.test/reference",
        content=(InlineContent(inline_type=InlineType.TEXT, text="Reference"),),
    )
    footnote = Footnote(
        **_common("footnote", section.id, 7, ElementType.FOOTNOTE),
        reference_id="note-1",
        content=(InlineContent(inline_type=InlineType.TEXT, text="A note"),),
    )
    paragraph = Paragraph(**_common("paragraph", section.id, 8, ElementType.PARAGRAPH))
    sentence = Sentence(
        **_common("sentence", paragraph.id, 0, ElementType.SENTENCE),
        content=(
            InlineContent(inline_type=InlineType.TEXT, text="A "),
            InlineContent(inline_type=InlineType.BOLD, text="rich"),
            InlineContent(
                inline_type=InlineType.HYPERLINK,
                text=" document",
                target="https://example.test",
            ),
            InlineContent(
                inline_type=InlineType.FORMULA,
                original_representation=r"x^2",
            ),
            InlineContent(
                inline_type=InlineType.CITATION,
                text="[1]",
                reference_id=footnote.reference_id,
            ),
        ),
    )
    return Document(
        **_common(document_id, None, 0, ElementType.DOCUMENT),
        elements=(
            chapter,
            metadata,
            section,
            image,
            caption,
            table,
            row,
            cell,
            code,
            formula,
            document_list,
            list_item,
            quote,
            hyperlink,
            footnote,
            paragraph,
            sentence,
        ),
    )


def test_valid_hierarchy_and_canonical_order() -> None:
    document = _basic_document()

    assert [child.id for child in document.children_of(document.id)] == ["chapter-1"]
    assert document.children_of("chapter-1")[0].id == "section-1"
    assert document.children_of("paragraph-1")[0].element_type == ElementType.SENTENCE


def test_parent_child_mismatch_is_rejected() -> None:
    document = _basic_document()
    invalid_paragraph = Paragraph(
        **_common("invalid-paragraph", "chapter-1", 1, ElementType.PARAGRAPH)
    )

    with pytest.raises(ValidationError, match="cannot be a child"):
        Document(
            **_common("document-1", None, 0, ElementType.DOCUMENT),
            elements=(*document.elements, invalid_paragraph),
        )


def test_duplicate_ids_are_rejected() -> None:
    document = _basic_document()
    duplicate = Sentence(**_common("chapter-1", "paragraph-1", 1, ElementType.SENTENCE))

    with pytest.raises(ValidationError, match="Duplicate element id"):
        Document(
            **_common("document-1", None, 0, ElementType.DOCUMENT),
            elements=(*document.elements, duplicate),
        )


def test_non_contiguous_sibling_order_is_rejected() -> None:
    document = _basic_document()
    skipped_order = Sentence(
        **_common("sentence-2", "paragraph-1", 2, ElementType.SENTENCE)
    )

    with pytest.raises(ValidationError, match="contiguous order indexes"):
        Document(
            **_common("document-1", None, 0, ElementType.DOCUMENT),
            elements=(*document.elements, skipped_order),
        )


def test_stable_ids_are_deterministic_and_path_sensitive() -> None:
    first = StableIdFactory("library/book.epub")
    second = StableIdFactory("library/book.epub")

    assert first.document_id == second.document_id
    assert first.element_id(ElementType.PARAGRAPH, (1, 2, 3)) == second.element_id(
        ElementType.PARAGRAPH, (1, 2, 3)
    )
    assert first.element_id(ElementType.PARAGRAPH, (1, 2, 3)) != first.element_id(
        ElementType.PARAGRAPH, (1, 2, 4)
    )


def test_rich_elements_and_inline_content_are_preserved_explicitly() -> None:
    document = _rich_document()
    by_type = {element.element_type: element for element in document.elements}

    assert isinstance(by_type[ElementType.IMAGE], Image)
    assert isinstance(by_type[ElementType.TABLE], Table)
    assert isinstance(by_type[ElementType.TABLE_ROW], TableRow)
    assert isinstance(by_type[ElementType.TABLE_CELL], TableCell)
    assert isinstance(by_type[ElementType.CODE_BLOCK], CodeBlock)
    assert isinstance(by_type[ElementType.FORMULA], Formula)
    assert isinstance(by_type[ElementType.LIST], DocumentList)
    assert isinstance(by_type[ElementType.LIST_ITEM], ListItem)
    assert isinstance(by_type[ElementType.QUOTE], Quote)
    assert isinstance(by_type[ElementType.HYPERLINK], Hyperlink)
    assert isinstance(by_type[ElementType.FOOTNOTE], Footnote)
    sentence = by_type[ElementType.SENTENCE]
    assert isinstance(sentence, Sentence)
    assert [run.inline_type for run in sentence.content] == [
        InlineType.TEXT,
        InlineType.BOLD,
        InlineType.HYPERLINK,
        InlineType.FORMULA,
        InlineType.CITATION,
    ]


def test_serialization_round_trip_restores_concrete_types() -> None:
    original = _rich_document()

    restored = Document.from_dict(original.to_dict())

    assert restored == original
    assert isinstance(restored.children_of("section")[0], Image)
    assert isinstance(restored.children_of("table")[0], TableRow)
    assert isinstance(restored.children_of("row")[0], TableCell)


def test_unknown_future_element_round_trips_without_data_loss() -> None:
    payload = _basic_document().to_dict()
    future_element = {
        "id": "diagram-1",
        "parent_id": "section-1",
        "order_index": 1,
        "element_type": "interactive_diagram",
        "source": {"page_number": 4, "original_reference": "diagram:7"},
        "future_config": {"layers": ["base", "labels"], "interactive": True},
    }
    payload["elements"].append(future_element)

    restored = Document.from_dict(payload)
    serialized = restored.to_dict()
    unknown = restored.children_of("section-1")[1]

    assert isinstance(unknown, UnknownElement)
    assert serialized["elements"][-1] == future_element


def test_invalid_inline_specializations_are_rejected() -> None:
    with pytest.raises(ValidationError, match="require a target"):
        InlineContent(inline_type=InlineType.HYPERLINK, text="broken")
