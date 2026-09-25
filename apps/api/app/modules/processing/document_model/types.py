"""Shared value types for the format-independent Document Model."""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, model_validator


class BoundingBox(BaseModel):
    """Optional coordinates in the source format's coordinate space."""

    model_config = ConfigDict(frozen=True)

    x: float
    y: float
    width: float = Field(ge=0)
    height: float = Field(ge=0)
    coordinate_space: str | None = None


class SourceLocation(BaseModel):
    """Traceability back to the source without affecting logical hierarchy."""

    model_config = ConfigDict(frozen=True)

    page_number: int | None = Field(default=None, ge=1)
    bounding_box: BoundingBox | None = None
    original_reference: str | None = None


class InlineType(StrEnum):
    TEXT = "text"
    BOLD = "bold"
    ITALIC = "italic"
    INLINE_CODE = "inline_code"
    HYPERLINK = "hyperlink"
    FORMULA = "formula"
    CITATION = "citation"


class InlineContent(BaseModel):
    """A format-preserving inline run; rendering remains a client concern."""

    model_config = ConfigDict(frozen=True)

    inline_type: InlineType
    text: str | None = None
    target: str | None = None
    original_representation: str | None = None
    reference_id: str | None = None
    attributes: dict[str, str] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_required_fields(self) -> InlineContent:
        if self.inline_type is InlineType.HYPERLINK and not self.target:
            raise ValueError("Inline hyperlinks require a target")
        if self.inline_type is InlineType.FORMULA and not self.original_representation:
            raise ValueError("Inline formulas require their original representation")
        if self.inline_type is InlineType.CITATION and not self.reference_id:
            raise ValueError("Inline citations require a reference id")
        return self
