"""Parser registry — the only place that knows which parsers exist.

Open for extension, closed for modification: registering a parser is the whole
change needed to support a new format. No existing parser, the processing
engine, the reader, or the pagination layer is touched.
"""

from __future__ import annotations

from collections.abc import Iterable

from app.modules.processing.parsers.base import (
    DocumentParser,
    ParserCapability,
    ParserError,
    ParserErrorCode,
    ParserMetadata,
)


class ParserRegistry:
    """Holds available parsers and selects one for a file."""

    def __init__(self, parsers: Iterable[DocumentParser] = ()) -> None:
        self._parsers: list[DocumentParser] = []
        for parser in parsers:
            self.register(parser)

    def register(self, parser: DocumentParser) -> None:
        """Register a parser, rejecting duplicate names."""
        name = parser.metadata.name
        if not name:
            raise ValueError("A parser must expose a non-empty name")
        if any(existing.metadata.name == name for existing in self._parsers):
            raise ValueError(f"A parser named '{name}' is already registered")
        self._parsers.append(parser)

    def available(self) -> tuple[DocumentParser, ...]:
        """Parsers in resolution order: highest priority first, then insertion."""
        ordered = sorted(
            enumerate(self._parsers),
            key=lambda item: (-item[1].metadata.priority, item[0]),
        )
        return tuple(parser for _, parser in ordered)

    def describe(self) -> tuple[ParserMetadata, ...]:
        """Advertised metadata for every parser, in resolution order."""
        return tuple(parser.metadata for parser in self.available())

    def get(self, name: str) -> DocumentParser | None:
        """Return the parser registered under ``name``, if any."""
        for parser in self._parsers:
            if parser.metadata.name == name:
                return parser
        return None

    def select(self, *, mime_type: str, filename: str) -> DocumentParser | None:
        """Return the highest-priority parser that supports the file."""
        for parser in self.available():
            if parser.supports(mime_type=mime_type, filename=filename):
                return parser
        return None

    def require(self, *, mime_type: str, filename: str) -> DocumentParser:
        """Like :meth:`select`, but raises a structured unsupported-format error."""
        parser = self.select(mime_type=mime_type, filename=filename)
        if parser is None:
            raise ParserError(
                ParserErrorCode.UNSUPPORTED_FORMAT,
                f"No parser supports '{mime_type}'.",
            )
        return parser

    def with_capability(
        self,
        capability: ParserCapability,
    ) -> tuple[DocumentParser, ...]:
        """Parsers advertising a capability — used for future routing decisions."""
        return tuple(
            parser
            for parser in self.available()
            if parser.metadata.supports_capability(capability)
        )
