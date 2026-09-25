"""Deterministic stable identifiers for documents and their elements."""

from __future__ import annotations

import json
import uuid
from collections.abc import Sequence
from dataclasses import dataclass

_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "https://readme.ai/document-model/v1")


def stable_document_id(source_reference: str) -> str:
    """Return the stable document ID for a canonical source reference."""
    if not source_reference:
        raise ValueError("source_reference cannot be empty")
    return str(uuid.uuid5(_NAMESPACE, f"document:{source_reference}"))


def stable_element_id(
    document_id: str,
    element_type: str,
    source_path: Sequence[str | int],
    *,
    original_reference: str | None = None,
) -> str:
    """Return an ID stable for the same document, type, and source path."""
    if not document_id:
        raise ValueError("document_id cannot be empty")
    if not element_type:
        raise ValueError("element_type cannot be empty")
    if not source_path:
        raise ValueError("source_path cannot be empty")
    identity = json.dumps(
        {
            "document_id": document_id,
            "element_type": element_type,
            "source_path": list(source_path),
            "original_reference": original_reference,
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    return str(uuid.uuid5(_NAMESPACE, identity))


@dataclass(frozen=True, slots=True)
class StableIdFactory:
    """Convenient document-scoped stable ID factory for future parsers."""

    source_reference: str

    @property
    def document_id(self) -> str:
        return stable_document_id(self.source_reference)

    def element_id(
        self,
        element_type: str,
        source_path: Sequence[str | int],
        *,
        original_reference: str | None = None,
    ) -> str:
        return stable_element_id(
            self.document_id,
            element_type,
            source_path,
            original_reference=original_reference,
        )
