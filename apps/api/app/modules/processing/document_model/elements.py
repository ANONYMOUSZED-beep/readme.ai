"""Explicit elements in the format-independent Document Model."""

from __future__ import annotations

from enum import StrEnum
from typing import ClassVar

from pydantic import BaseModel, ConfigDict, Field, JsonValue, model_validator

from .types import InlineContent, SourceLocation


class ElementType(StrEnum):
    """Stable serialized element type names."""

    DOCUMENT = "document"
    CHAPTER = "chapter"
    SECTION = "section"
    PARAGRAPH = "paragraph"
    SENTENCE = "sentence"
    IMAGE = "image"
    CAPTION = "caption"
    TABLE = "table"
    TABLE_ROW = "table_row"
    TABLE_CELL = "table_cell"
    CODE_BLOCK = "code_block"
    QUOTE = "quote"
    LIST = "list"
    LIST_ITEM = "list_item"
    HYPERLINK = "hyperlink"
    FOOTNOTE = "footnote"
    FORMULA = "formula"
    METADATA = "metadata"


class DocumentElement(BaseModel):
    """Common immutable identity, ordering, and source metadata."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    expected_type: ClassVar[str | None] = None

    id: str = Field(min_length=1)
    parent_id: str | None
    order_index: int = Field(ge=0)
    element_type: str = Field(min_length=1)
    source: SourceLocation = Field(default_factory=SourceLocation)
    attributes: dict[str, JsonValue] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_element_type(self) -> DocumentElement:
        if self.expected_type is not None and self.element_type != self.expected_type:
            raise ValueError(
                f"{type(self).__name__} requires element_type={self.expected_type!r}"
            )
        return self


class Chapter(DocumentElement):
    expected_type = ElementType.CHAPTER
    element_type: str = ElementType.CHAPTER
    title: str | None = None


class Section(DocumentElement):
    expected_type = ElementType.SECTION
    element_type: str = ElementType.SECTION
    title: str | None = None


class Paragraph(DocumentElement):
    expected_type = ElementType.PARAGRAPH
    element_type: str = ElementType.PARAGRAPH


class Sentence(DocumentElement):
    expected_type = ElementType.SENTENCE
    element_type: str = ElementType.SENTENCE
    content: tuple[InlineContent, ...] = ()


class Image(DocumentElement):
    expected_type = ElementType.IMAGE
    element_type: str = ElementType.IMAGE
    image_identifier: str = Field(min_length=1)
    caption_id: str | None = None
    media_type: str | None = None
    width: float | None = Field(default=None, ge=0)
    height: float | None = Field(default=None, ge=0)


class Caption(DocumentElement):
    expected_type = ElementType.CAPTION
    element_type: str = ElementType.CAPTION
    describes_id: str = Field(min_length=1)
    content: tuple[InlineContent, ...] = ()


class Table(DocumentElement):
    expected_type = ElementType.TABLE
    element_type: str = ElementType.TABLE


class TableRow(DocumentElement):
    expected_type = ElementType.TABLE_ROW
    element_type: str = ElementType.TABLE_ROW


class TableCell(DocumentElement):
    expected_type = ElementType.TABLE_CELL
    element_type: str = ElementType.TABLE_CELL
    content: tuple[InlineContent, ...] = ()
    row_span: int = Field(default=1, ge=1)
    column_span: int = Field(default=1, ge=1)
    is_header: bool = False


class CodeBlock(DocumentElement):
    expected_type = ElementType.CODE_BLOCK
    element_type: str = ElementType.CODE_BLOCK
    code: str
    language: str | None = None


class Quote(DocumentElement):
    expected_type = ElementType.QUOTE
    element_type: str = ElementType.QUOTE
    content: tuple[InlineContent, ...] = ()
    attribution: str | None = None


class DocumentList(DocumentElement):
    expected_type = ElementType.LIST
    element_type: str = ElementType.LIST
    ordered: bool = False
    start_number: int | None = Field(default=None, ge=1)


class ListItem(DocumentElement):
    expected_type = ElementType.LIST_ITEM
    element_type: str = ElementType.LIST_ITEM
    content: tuple[InlineContent, ...] = ()


class Hyperlink(DocumentElement):
    expected_type = ElementType.HYPERLINK
    element_type: str = ElementType.HYPERLINK
    target: str = Field(min_length=1)
    content: tuple[InlineContent, ...] = ()


class Footnote(DocumentElement):
    expected_type = ElementType.FOOTNOTE
    element_type: str = ElementType.FOOTNOTE
    reference_id: str = Field(min_length=1)
    label: str | None = None
    content: tuple[InlineContent, ...] = ()


class Formula(DocumentElement):
    expected_type = ElementType.FORMULA
    element_type: str = ElementType.FORMULA
    original_representation: str = Field(min_length=1)
    representation_format: str | None = None


class Metadata(DocumentElement):
    expected_type = ElementType.METADATA
    element_type: str = ElementType.METADATA
    key: str = Field(min_length=1)
    value: JsonValue


class UnknownElement(DocumentElement):
    """Forward-compatible envelope for an unrecognized element type."""

    model_config = ConfigDict(frozen=True, extra="allow")


KNOWN_ELEMENT_MODELS: dict[str, type[DocumentElement]] = {
    model.expected_type: model
    for model in (
        Chapter,
        Section,
        Paragraph,
        Sentence,
        Image,
        Caption,
        Table,
        TableRow,
        TableCell,
        CodeBlock,
        Quote,
        DocumentList,
        ListItem,
        Hyperlink,
        Footnote,
        Formula,
        Metadata,
    )
    if model.expected_type is not None
}
