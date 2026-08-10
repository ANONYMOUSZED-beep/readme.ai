"""Validated root aggregate for the format-independent Document Model."""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Mapping
from typing import Any, Self

from pydantic import Field, model_validator

from .codec import DEFAULT_ELEMENT_CODEC, ElementCodec
from .elements import (
    Caption,
    DocumentElement,
    ElementType,
    Image,
)

_ALLOWED_CHILDREN: dict[str, frozenset[str]] = {
    ElementType.DOCUMENT: frozenset({ElementType.CHAPTER, ElementType.METADATA}),
    ElementType.CHAPTER: frozenset({ElementType.SECTION}),
    ElementType.SECTION: frozenset(
        {
            ElementType.PARAGRAPH,
            ElementType.IMAGE,
            ElementType.TABLE,
            ElementType.CODE_BLOCK,
            ElementType.QUOTE,
            ElementType.LIST,
            ElementType.HYPERLINK,
            ElementType.FOOTNOTE,
            ElementType.FORMULA,
        }
    ),
    ElementType.PARAGRAPH: frozenset({ElementType.SENTENCE}),
    ElementType.IMAGE: frozenset({ElementType.CAPTION}),
    ElementType.TABLE: frozenset({ElementType.TABLE_ROW}),
    ElementType.TABLE_ROW: frozenset({ElementType.TABLE_CELL}),
    ElementType.LIST: frozenset({ElementType.LIST_ITEM}),
    ElementType.LIST_ITEM: frozenset({ElementType.LIST}),
}
_KNOWN_TYPES = frozenset(_ALLOWED_CHILDREN) | frozenset(
    child for children in _ALLOWED_CHILDREN.values() for child in children
)


class Document(DocumentElement):
    """Immutable document root containing a normalized, validated element tree."""

    expected_type = ElementType.DOCUMENT

    element_type: str = ElementType.DOCUMENT
    schema_version: int = Field(default=1, ge=1)
    elements: tuple[DocumentElement, ...] = ()

    @model_validator(mode="after")
    def validate_tree(self) -> Self:
        if self.parent_id is not None:
            raise ValueError("Document parent_id must be None")
        if self.order_index != 0:
            raise ValueError("Document order_index must be 0")

        by_id: dict[str, DocumentElement] = {self.id: self}
        for element in self.elements:
            if element.id in by_id:
                raise ValueError(f"Duplicate element id: {element.id}")
            if element.element_type == ElementType.DOCUMENT:
                raise ValueError("elements cannot contain another document root")
            by_id[element.id] = element

        siblings: dict[str, list[DocumentElement]] = defaultdict(list)
        for element in self.elements:
            if element.parent_id is None or element.parent_id not in by_id:
                raise ValueError(
                    f"Element {element.id} has unknown parent {element.parent_id!r}"
                )
            if element.parent_id == element.id:
                raise ValueError(f"Element {element.id} cannot parent itself")
            siblings[element.parent_id].append(element)

            parent = by_id[element.parent_id]
            allowed = _ALLOWED_CHILDREN.get(parent.element_type)
            if (
                allowed is not None
                and element.element_type in _KNOWN_TYPES
                and element.element_type not in allowed
            ):
                raise ValueError(
                    f"{element.element_type} cannot be a child of "
                    f"{parent.element_type}"
                )

        for sibling_parent_id, children in siblings.items():
            indexes = sorted(child.order_index for child in children)
            if indexes != list(range(len(children))):
                raise ValueError(
                    f"Children of {sibling_parent_id} require unique contiguous "
                    "order indexes"
                )

        for element in self.elements:
            seen = {element.id}
            ancestor_id: str | None = element.parent_id
            while ancestor_id != self.id:
                if ancestor_id is None or ancestor_id not in by_id:
                    raise ValueError(f"Element {element.id} is disconnected")
                if ancestor_id in seen:
                    raise ValueError(f"Cycle detected at element {ancestor_id}")
                seen.add(ancestor_id)
                ancestor_id = by_id[ancestor_id].parent_id

        self._validate_captions(by_id)
        return self

    def _validate_captions(self, by_id: Mapping[str, DocumentElement]) -> None:
        for element in self.elements:
            if isinstance(element, Image) and element.caption_id is not None:
                caption = by_id.get(element.caption_id)
                if (
                    not isinstance(caption, Caption)
                    or caption.parent_id != element.id
                    or caption.describes_id != element.id
                ):
                    raise ValueError(
                        f"Image {element.id} has an invalid caption relationship"
                    )
            if isinstance(element, Caption):
                image = by_id.get(element.describes_id)
                if not isinstance(image, Image) or image.caption_id != element.id:
                    raise ValueError(
                        f"Caption {element.id} has an invalid image relationship"
                    )

    def children_of(self, parent_id: str) -> tuple[DocumentElement, ...]:
        """Return direct children in canonical sibling order."""
        children = (
            element for element in self.elements if element.parent_id == parent_id
        )
        return tuple(
            sorted(
                children,
                key=lambda element: element.order_index,
            )
        )

    def to_dict(self, codec: ElementCodec | None = None) -> dict[str, Any]:
        """Serialize the aggregate without losing concrete element types."""
        active_codec = codec or DEFAULT_ELEMENT_CODEC
        payload = self.model_dump(mode="json", exclude={"elements"})
        payload["elements"] = [
            active_codec.serialize(element) for element in self.elements
        ]
        return payload

    @classmethod
    def from_dict(
        cls,
        payload: Mapping[str, Any],
        codec: ElementCodec | None = None,
    ) -> Document:
        """Deserialize and validate a complete polymorphic document tree."""
        data = dict(payload)
        raw_elements = data.get("elements", [])
        if not isinstance(raw_elements, (list, tuple)):
            raise ValueError("Document elements must be an array")
        active_codec = codec or DEFAULT_ELEMENT_CODEC
        elements: list[DocumentElement] = []
        for raw_element in raw_elements:
            if not isinstance(raw_element, Mapping):
                raise ValueError("Every document element must be an object")
            elements.append(active_codec.deserialize(raw_element))
        data["elements"] = tuple(elements)
        return cls.model_validate(data)
