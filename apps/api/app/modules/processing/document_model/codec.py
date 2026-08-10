"""Registry-based polymorphic Document Element serialization."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from .elements import (
    KNOWN_ELEMENT_MODELS,
    DocumentElement,
    UnknownElement,
)


class ElementCodec:
    """Encode/decode elements while preserving unknown future types."""

    def __init__(
        self,
        registry: Mapping[str, type[DocumentElement]] | None = None,
    ) -> None:
        self._registry = dict(registry or KNOWN_ELEMENT_MODELS)

    @property
    def registry(self) -> Mapping[str, type[DocumentElement]]:
        return self._registry.copy()

    def with_element(
        self,
        element_type: str,
        model: type[DocumentElement],
    ) -> ElementCodec:
        """Return a new codec extended with one element implementation."""
        if not element_type:
            raise ValueError("element_type cannot be empty")
        registry = self._registry.copy()
        registry[element_type] = model
        return ElementCodec(registry)

    def serialize(self, element: DocumentElement) -> dict[str, Any]:
        """Serialize an element to JSON-compatible data."""
        return element.model_dump(
            mode="json",
            exclude_unset=isinstance(element, UnknownElement),
        )

    def deserialize(self, payload: Mapping[str, Any]) -> DocumentElement:
        """Restore the concrete known type or an unknown-type envelope."""
        element_type = payload.get("element_type")
        if not isinstance(element_type, str) or not element_type:
            raise ValueError("Element payload requires a non-empty element_type")
        model = self._registry.get(element_type, UnknownElement)
        return model.model_validate(dict(payload))


DEFAULT_ELEMENT_CODEC = ElementCodec()
