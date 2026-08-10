"""Unit tests for the parser framework (no PDF/EPUB/DOCX parsing)."""

from __future__ import annotations

import pytest

from app.modules.processing.document import (
    DocumentMetadata,
    ParsedChapter,
    ParsedParagraph,
    ParsedSection,
    ParsedSentence,
    StructuredDocument,
)
from app.modules.processing.document_model import Document, ElementType
from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.parsers import (
    DocumentParser,
    ParserCapability,
    ParseRequest,
    ParserError,
    ParserErrorCode,
    ParseResult,
    ParserMetadata,
    ParserProgress,
    ParserRegistry,
    ParseStage,
    ParseStatistics,
    ProcessorBackedParser,
    ProgressCallback,
    build_document_model,
)
from app.modules.processing.processors.base import ProcessingError
from app.modules.processing.processors.plain_text import PlainTextProcessor

_TEXT = b"# Title\n\nFirst paragraph. Two sentences here.\n\nSecond paragraph."


def _request(
    *,
    filename: str = "book.txt",
    mime_type: str = "text/plain",
    data: bytes = _TEXT,
) -> ParseRequest:
    return ParseRequest(
        filename=filename,
        mime_type=mime_type,
        data=data,
        source_reference=f"storage/{filename}",
    )


def _text_parser(priority: int = 0) -> ProcessorBackedParser:
    """The placeholder parser: wraps existing deterministic text extraction."""
    return ProcessorBackedParser(
        PlainTextProcessor(),
        priority=priority,
        supported_mime_types=("text/plain", "text/markdown"),
        supported_extensions=(".txt", ".md"),
    )


class _StubParser:
    """A minimal DocumentParser used to exercise registry behaviour."""

    def __init__(
        self,
        name: str,
        *,
        mime_type: str = "application/x-stub",
        priority: int = 0,
        capabilities: frozenset[ParserCapability] = frozenset({ParserCapability.TEXT}),
        failure: ParserError | None = None,
    ) -> None:
        self._mime_type = mime_type
        self._failure = failure
        self._metadata = ParserMetadata(
            name=name,
            version="0.1.0",
            display_name=name.title(),
            capabilities=capabilities,
            supported_mime_types=frozenset({mime_type}),
            priority=priority,
        )

    @property
    def metadata(self) -> ParserMetadata:
        return self._metadata

    def supports(self, *, mime_type: str, filename: str) -> bool:
        return mime_type == self._mime_type

    def parse(
        self,
        request: ParseRequest,
        on_progress: ProgressCallback | None = None,
    ) -> ParseResult:
        if self._failure is not None:
            raise self._failure
        document = build_document_model(
            _structured(), source_reference=request.identity
        )
        structured = _structured()
        return ParseResult(
            document=document,
            canonical_text=structured.text,
            metadata=structured.metadata,
            statistics=ParseStatistics.from_document(document, duration_ms=0.0),
            parser_name=self._metadata.name,
        )


class _ExplodingProcessor:
    """A processor that fails, to prove failures never escape the parser layer."""

    def __init__(self, error: BaseException) -> None:
        self._error = error

    @property
    def name(self) -> str:
        return "exploding"

    def supports(self, *, mime_type: str, filename: str) -> bool:
        return True

    def process(
        self,
        *,
        filename: str,
        mime_type: str,
        data: bytes,
    ) -> StructuredDocument:
        raise self._error


def _structured() -> StructuredDocument:
    text = "Alpha sentence. Beta sentence.\n\nGamma paragraph."
    first = ParsedParagraph(
        text="Alpha sentence. Beta sentence.", start_offset=0, end_offset=30
    )
    first.sentences = [
        ParsedSentence(start_offset=0, end_offset=16),
        ParsedSentence(start_offset=16, end_offset=30),
    ]
    second = ParsedParagraph(text="Gamma paragraph.", start_offset=32, end_offset=48)
    second.sentences = [ParsedSentence(start_offset=32, end_offset=48)]
    section = ParsedSection(title="Section", start_offset=0, end_offset=48)
    section.paragraphs = [first, second]
    chapter = ParsedChapter(title="Chapter", start_offset=0, end_offset=48)
    chapter.sections = [section]
    metadata = DocumentMetadata(
        title="Chapter",
        author=None,
        language=None,
        page_count=None,
        word_count=7,
        character_count=len(text),
        estimated_reading_minutes=1,
    )
    return StructuredDocument(metadata=metadata, chapters=[chapter], text=text)


# --- registry --------------------------------------------------------------
def test_registry_registers_and_exposes_parsers() -> None:
    registry = ParserRegistry()
    parser = _StubParser("stub")

    registry.register(parser)

    assert registry.get("stub") is parser
    assert [metadata.name for metadata in registry.describe()] == ["stub"]
    assert isinstance(parser, DocumentParser)


def test_registry_rejects_duplicate_parser_names() -> None:
    registry = ParserRegistry([_StubParser("stub")])

    with pytest.raises(ValueError, match="already registered"):
        registry.register(_StubParser("stub"))


def test_registry_selects_by_mime_type() -> None:
    text = _text_parser()
    registry = ParserRegistry([_StubParser("stub"), text])

    selected = registry.select(mime_type="text/plain", filename="book.txt")

    assert selected is text


def test_registry_resolves_conflicts_by_priority() -> None:
    generic = _StubParser("generic", mime_type="application/pdf", priority=0)
    specialised = _StubParser("specialised", mime_type="application/pdf", priority=10)
    registry = ParserRegistry([generic, specialised])

    selected = registry.select(mime_type="application/pdf", filename="a.pdf")

    assert selected is specialised
    assert [parser.metadata.name for parser in registry.available()] == [
        "specialised",
        "generic",
    ]


def test_unsupported_format_returns_none_and_raises_structured_error() -> None:
    registry = ParserRegistry([_text_parser()])

    assert registry.select(mime_type="application/epub+zip", filename="a.epub") is None
    with pytest.raises(ParserError) as exc:
        registry.require(mime_type="application/epub+zip", filename="a.epub")

    assert exc.value.code is ParserErrorCode.UNSUPPORTED_FORMAT
    assert exc.value.processing_code is ProcessingErrorCode.UNSUPPORTED_FORMAT


def test_registry_filters_by_capability() -> None:
    tables = _StubParser(
        "tabular",
        mime_type="text/tabular",
        capabilities=frozenset({ParserCapability.TABLES}),
    )
    registry = ParserRegistry([_text_parser(), tables])

    assert registry.with_capability(ParserCapability.TABLES) == (tables,)
    assert len(registry.with_capability(ParserCapability.TEXT)) == 1


# --- capabilities ----------------------------------------------------------
def test_parser_reports_capabilities_and_metadata() -> None:
    metadata = _text_parser().metadata

    assert metadata.name == "plain_text"
    assert metadata.supports_capability(ParserCapability.TEXT)
    assert metadata.supports_all([ParserCapability.TEXT, ParserCapability.METADATA])
    assert not metadata.supports_capability(ParserCapability.TABLES)
    assert ".md" in metadata.supported_extensions


# --- progress --------------------------------------------------------------
def test_parser_reports_progress_stages_in_order() -> None:
    updates: list[ParserProgress] = []

    _text_parser().parse(_request(), updates.append)

    assert [update.stage for update in updates] == [
        ParseStage.STARTED,
        ParseStage.EXTRACTING,
        ParseStage.STRUCTURING,
        ParseStage.FINALIZING,
        ParseStage.COMPLETED,
    ]
    assert updates[-1].fraction == 1.0
    assert ParserProgress(stage=ParseStage.STARTED).fraction is None


# --- error handling --------------------------------------------------------
def test_processing_errors_are_translated_to_parser_errors() -> None:
    parser = ProcessorBackedParser(
        _ExplodingProcessor(
            ProcessingError(ProcessingErrorCode.MALFORMED_FILE, "broken file")
        )
    )

    with pytest.raises(ParserError) as exc:
        parser.parse(_request())

    assert exc.value.code is ParserErrorCode.CORRUPTED_DOCUMENT
    assert exc.value.processing_code is ProcessingErrorCode.MALFORMED_FILE
    assert exc.value.parser_name == "exploding"


def test_unexpected_parser_exceptions_do_not_escape_the_parser_layer() -> None:
    parser = ProcessorBackedParser(_ExplodingProcessor(RuntimeError("segfault")))

    with pytest.raises(ParserError) as exc:
        parser.parse(_request())

    assert exc.value.code is ParserErrorCode.PARSER_FAILURE
    assert exc.value.processing_code is ProcessingErrorCode.INTERNAL


def test_empty_document_is_reported_structurally() -> None:
    with pytest.raises(ParserError) as exc:
        _text_parser().parse(_request(data=b"   \n\n  "))

    assert exc.value.code is ParserErrorCode.EMPTY_DOCUMENT


# --- placeholder parser ----------------------------------------------------
def test_placeholder_parser_produces_document_model_and_statistics() -> None:
    result = _text_parser().parse(_request())

    assert isinstance(result.document, Document)
    assert result.parser_name == "plain_text"
    assert result.metadata.title == "Title"
    assert result.statistics.chapters == 1
    assert result.statistics.paragraphs == 2
    assert result.statistics.sentences >= 3
    assert result.statistics.duration_ms >= 0
    assert result.canonical_text.startswith("First paragraph.")
    assert result.warnings == ()


def test_document_model_hierarchy_is_deterministic_and_ordered() -> None:
    first = build_document_model(_structured(), source_reference="storage/book.txt")
    second = build_document_model(_structured(), source_reference="storage/book.txt")

    assert first == second
    chapters = [
        element
        for element in first.children_of(first.id)
        if element.element_type == ElementType.CHAPTER
    ]
    sections = first.children_of(chapters[0].id)
    paragraphs = first.children_of(sections[0].id)
    sentences = first.children_of(paragraphs[0].id)

    assert len(chapters) == 1
    assert [element.order_index for element in paragraphs] == [0, 1]
    assert len(sentences) == 2
    assert paragraphs[0].attributes["start_offset"] == 0


def test_metadata_is_represented_as_document_elements() -> None:
    document = build_document_model(_structured(), source_reference="storage/book.txt")

    metadata = {
        element.key: element.value  # type: ignore[attr-defined]
        for element in document.elements
        if element.element_type == ElementType.METADATA
    }

    assert metadata["title"] == "Chapter"
    assert metadata["word_count"] == 7
    assert "author" not in metadata
