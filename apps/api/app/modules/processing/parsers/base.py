"""Core parser abstractions: capabilities, progress, results, and errors.

Every document format is converted into the Sprint 6.2 Document Model by a
:class:`DocumentParser`. Nothing outside this package may depend on a concrete
parser or on a parser-specific exception type: parsers translate their internal
failures into :class:`ParserError` before they escape.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Protocol, runtime_checkable

from app.modules.processing.document import DocumentMetadata
from app.modules.processing.document_model import Document, ElementType
from app.modules.processing.enums import ProcessingErrorCode


class ParserCapability(StrEnum):
    """What a parser can extract. New capabilities are added here only."""

    TEXT = "text"
    IMAGES = "images"
    TABLES = "tables"
    FORMULAS = "formulas"
    HYPERLINKS = "hyperlinks"
    BOOKMARKS = "bookmarks"
    CODE_BLOCKS = "code_blocks"
    METADATA = "metadata"
    FOOTNOTES = "footnotes"
    PAGE_COORDINATES = "page_coordinates"


class ParserErrorCode(StrEnum):
    """Stable, format-independent reasons parsing failed."""

    UNSUPPORTED_FORMAT = "unsupported_format"
    CORRUPTED_DOCUMENT = "corrupted_document"
    ENCRYPTED_DOCUMENT = "encrypted_document"
    INVALID_STRUCTURE = "invalid_structure"
    EMPTY_DOCUMENT = "empty_document"
    TOO_LARGE = "too_large"
    TIMEOUT = "timeout"
    PARSER_FAILURE = "parser_failure"


# Parser failures are reported to the rest of the application through the
# existing processing vocabulary, so the API contract does not change when a new
# parser (and therefore a new failure mode) is added. Encryption and structural
# damage both surface as a malformed file until the UI distinguishes them.
_PROCESSING_CODES: dict[ParserErrorCode, ProcessingErrorCode] = {
    ParserErrorCode.UNSUPPORTED_FORMAT: ProcessingErrorCode.UNSUPPORTED_FORMAT,
    ParserErrorCode.CORRUPTED_DOCUMENT: ProcessingErrorCode.MALFORMED_FILE,
    ParserErrorCode.ENCRYPTED_DOCUMENT: ProcessingErrorCode.MALFORMED_FILE,
    ParserErrorCode.INVALID_STRUCTURE: ProcessingErrorCode.MALFORMED_FILE,
    ParserErrorCode.EMPTY_DOCUMENT: ProcessingErrorCode.EMPTY_DOCUMENT,
    ParserErrorCode.TOO_LARGE: ProcessingErrorCode.TOO_LARGE,
    ParserErrorCode.TIMEOUT: ProcessingErrorCode.TIMEOUT,
    ParserErrorCode.PARSER_FAILURE: ProcessingErrorCode.INTERNAL,
}


class ParserError(Exception):
    """The single failure type the parser layer exposes to its callers."""

    def __init__(
        self,
        code: ParserErrorCode,
        message: str,
        *,
        parser_name: str | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.parser_name = parser_name

    @property
    def processing_code(self) -> ProcessingErrorCode:
        """The processing-level code this failure is recorded as."""
        return _PROCESSING_CODES[self.code]


class ParseStage(StrEnum):
    """Coarse, format-independent phases every parser reports."""

    STARTED = "started"
    READING = "reading"
    EXTRACTING = "extracting"
    STRUCTURING = "structuring"
    FINALIZING = "finalizing"
    COMPLETED = "completed"


@dataclass(frozen=True, slots=True)
class ParserProgress:
    """An immutable progress snapshot.

    Snapshots are plain values with no I/O and no framework coupling, so the
    same parser drives a synchronous call, an async request, or a future
    background worker that forwards snapshots to a queue or websocket.
    """

    stage: ParseStage
    completed_units: int = 0
    total_units: int | None = None
    detail: str | None = None

    @property
    def fraction(self) -> float | None:
        """Completion in ``[0, 1]``, or ``None`` when the total is unknown."""
        if self.total_units is None or self.total_units <= 0:
            return None
        return min(self.completed_units / self.total_units, 1.0)


#: Progress sink. Deliberately synchronous and non-blocking: parsers run in a
#: worker thread, so an ``async`` callback could not be awaited there.
ProgressCallback = Callable[[ParserProgress], None]


@dataclass(frozen=True, slots=True)
class ParserIssue:
    """A non-fatal warning or recorded error raised during parsing."""

    code: str
    message: str
    element_id: str | None = None
    page_number: int | None = None


@dataclass(frozen=True, slots=True)
class ParseStatistics:
    """Counts describing what a parse produced, for logs and diagnostics."""

    chapters: int = 0
    sections: int = 0
    paragraphs: int = 0
    sentences: int = 0
    images: int = 0
    tables: int = 0
    code_blocks: int = 0
    formulas: int = 0
    hyperlinks: int = 0
    footnotes: int = 0
    duration_ms: float = 0.0

    @classmethod
    def from_document(
        cls, document: Document, *, duration_ms: float
    ) -> ParseStatistics:
        """Derive statistics from the Document Model, never from a raw file."""
        counts: dict[str, int] = {}
        for element in document.elements:
            counts[element.element_type] = counts.get(element.element_type, 0) + 1
        return cls(
            chapters=counts.get(ElementType.CHAPTER, 0),
            sections=counts.get(ElementType.SECTION, 0),
            paragraphs=counts.get(ElementType.PARAGRAPH, 0),
            sentences=counts.get(ElementType.SENTENCE, 0),
            images=counts.get(ElementType.IMAGE, 0),
            tables=counts.get(ElementType.TABLE, 0),
            code_blocks=counts.get(ElementType.CODE_BLOCK, 0),
            formulas=counts.get(ElementType.FORMULA, 0),
            hyperlinks=counts.get(ElementType.HYPERLINK, 0),
            footnotes=counts.get(ElementType.FOOTNOTE, 0),
            duration_ms=duration_ms,
        )


@dataclass(frozen=True, slots=True)
class ParserMetadata:
    """Self-describing parser identity and capabilities.

    ``priority`` resolves overlap when several parsers accept the same file: a
    specialised parser registers above a generic one without either parser
    knowing the other exists.
    """

    name: str
    version: str
    display_name: str
    capabilities: frozenset[ParserCapability] = frozenset()
    supported_mime_types: frozenset[str] = frozenset()
    supported_extensions: frozenset[str] = frozenset()
    priority: int = 0

    def supports_capability(self, capability: ParserCapability) -> bool:
        return capability in self.capabilities

    def supports_all(self, capabilities: Iterable[ParserCapability]) -> bool:
        return all(capability in self.capabilities for capability in capabilities)


@dataclass(frozen=True, slots=True)
class ParseRequest:
    """Everything a parser needs, with no storage or transport coupling."""

    filename: str
    mime_type: str
    data: bytes
    #: Stable identity of the source (e.g. the storage key) used to derive
    #: deterministic element IDs. Falls back to the filename.
    source_reference: str | None = None

    @property
    def identity(self) -> str:
        return self.source_reference or self.filename


@dataclass(frozen=True, slots=True)
class ParseResult:
    """The standardized outcome of a successful parse."""

    #: The format-independent Document Model — the persisted source of truth.
    document: Document
    #: The canonical character stream every element span, bookmark, reading
    #: position, and explanation anchor addresses. Structure indexes this text;
    #: it is stored exactly once and never duplicated per element.
    canonical_text: str
    metadata: DocumentMetadata
    statistics: ParseStatistics
    parser_name: str
    warnings: tuple[ParserIssue, ...] = ()
    errors: tuple[ParserIssue, ...] = ()
    extra: dict[str, str] = field(default_factory=dict)


@runtime_checkable
class DocumentParser(Protocol):
    """Converts one family of source formats into the Document Model.

    Implementations expose no format-specific types: callers see only
    :class:`ParserMetadata`, :class:`ParseResult`, and :class:`ParserError`.
    """

    @property
    def metadata(self) -> ParserMetadata:
        """Stable identity and advertised capabilities."""
        ...

    def supports(self, *, mime_type: str, filename: str) -> bool:
        """Whether this parser can handle the given file."""
        ...

    def parse(
        self,
        request: ParseRequest,
        on_progress: ProgressCallback | None = None,
    ) -> ParseResult:
        """Parse into the Document Model, or raise :class:`ParserError`."""
        ...
