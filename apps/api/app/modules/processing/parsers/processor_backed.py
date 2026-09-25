"""A parser that adapts an existing deterministic processor.

This is the framework's verification parser. It introduces no new format
support and no external libraries: it wraps the existing text extraction, lifts
the result into the Document Model, and proves the interface, registry, progress
reporting, and error translation work end to end.

A real Sprint 6.4+ parser implements :class:`DocumentParser` directly instead of
wrapping a processor; nothing else in the pipeline changes.
"""

from __future__ import annotations

import time
from collections.abc import Iterable

from app.modules.processing.document import StructuredDocument
from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.parsers.base import (
    ParserCapability,
    ParseRequest,
    ParserError,
    ParserErrorCode,
    ParseResult,
    ParserIssue,
    ParserMetadata,
    ParserProgress,
    ParseStage,
    ParseStatistics,
    ProgressCallback,
)
from app.modules.processing.parsers.document_builder import build_document_model
from app.modules.processing.processors.base import BookProcessor, ProcessingError

_ERROR_CODES: dict[ProcessingErrorCode, ParserErrorCode] = {
    ProcessingErrorCode.UNSUPPORTED_FORMAT: ParserErrorCode.UNSUPPORTED_FORMAT,
    ProcessingErrorCode.MALFORMED_FILE: ParserErrorCode.CORRUPTED_DOCUMENT,
    ProcessingErrorCode.EMPTY_DOCUMENT: ParserErrorCode.EMPTY_DOCUMENT,
    ProcessingErrorCode.TOO_LARGE: ParserErrorCode.TOO_LARGE,
    ProcessingErrorCode.TIMEOUT: ParserErrorCode.TIMEOUT,
    ProcessingErrorCode.INTERNAL: ParserErrorCode.PARSER_FAILURE,
}


class ProcessorBackedParser:
    """Exposes an existing :class:`BookProcessor` as a :class:`DocumentParser`."""

    def __init__(
        self,
        processor: BookProcessor,
        *,
        capabilities: Iterable[ParserCapability] = (
            ParserCapability.TEXT,
            ParserCapability.METADATA,
        ),
        display_name: str | None = None,
        version: str = "1.0.0",
        priority: int = 0,
        supported_mime_types: Iterable[str] = (),
        supported_extensions: Iterable[str] = (),
    ) -> None:
        self._processor = processor
        self._metadata = ParserMetadata(
            name=processor.name,
            version=version,
            display_name=display_name or processor.name.replace("_", " ").title(),
            capabilities=frozenset(capabilities),
            supported_mime_types=frozenset(supported_mime_types),
            supported_extensions=frozenset(supported_extensions),
            priority=priority,
        )

    @property
    def metadata(self) -> ParserMetadata:
        return self._metadata

    def supports(self, *, mime_type: str, filename: str) -> bool:
        # Delegated so format knowledge lives in exactly one place.
        return self._processor.supports(mime_type=mime_type, filename=filename)

    def parse(
        self,
        request: ParseRequest,
        on_progress: ProgressCallback | None = None,
    ) -> ParseResult:
        started = time.perf_counter()

        def report(stage: ParseStage, completed: int) -> None:
            if on_progress is not None:
                on_progress(
                    ParserProgress(
                        stage=stage,
                        completed_units=completed,
                        total_units=4,
                        detail=self._metadata.name,
                    )
                )

        report(ParseStage.STARTED, 0)
        report(ParseStage.EXTRACTING, 1)
        structured = self._extract(request)

        report(ParseStage.STRUCTURING, 2)
        document = build_document_model(structured, source_reference=request.identity)

        report(ParseStage.FINALIZING, 3)
        duration_ms = (time.perf_counter() - started) * 1000
        warnings = self._warnings(structured)
        report(ParseStage.COMPLETED, 4)

        return ParseResult(
            document=document,
            metadata=structured.metadata,
            statistics=ParseStatistics.from_document(document, duration_ms=duration_ms),
            parser_name=self._metadata.name,
            warnings=warnings,
            canonical_text=structured.text,
            cover=structured.cover,
        )

    def _extract(self, request: ParseRequest) -> StructuredDocument:
        """Run the wrapped processor, translating every failure to ParserError."""
        try:
            return self._processor.process(
                filename=request.filename,
                mime_type=request.mime_type,
                data=request.data,
            )
        except ProcessingError as error:
            raise ParserError(
                _ERROR_CODES.get(error.code, ParserErrorCode.PARSER_FAILURE),
                error.message,
                parser_name=self._metadata.name,
            ) from error
        except Exception as error:
            raise ParserError(
                ParserErrorCode.PARSER_FAILURE,
                f"The {self._metadata.name} parser failed: {error}",
                parser_name=self._metadata.name,
            ) from error

    def _warnings(self, structured: StructuredDocument) -> tuple[ParserIssue, ...]:
        issues: list[ParserIssue] = []
        if structured.metadata.title is None:
            issues.append(
                ParserIssue(
                    code="missing_title",
                    message="No document title could be determined.",
                )
            )
        return tuple(issues)
