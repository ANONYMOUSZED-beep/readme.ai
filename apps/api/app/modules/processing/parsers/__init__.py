"""Public API of the parser framework.

Callers depend on these abstractions only — never on a concrete parser:

``Upload -> ParserRegistry -> DocumentParser -> Document Model -> Processing
Engine -> Reader``
"""

from app.modules.processing.parsers.base import (
    DocumentParser,
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
from app.modules.processing.parsers.pdf_parser import PyMuPdfParser
from app.modules.processing.parsers.processor_backed import ProcessorBackedParser
from app.modules.processing.parsers.registry import ParserRegistry

__all__ = [
    "DocumentParser",
    "ParseRequest",
    "ParseResult",
    "ParseStage",
    "ParseStatistics",
    "ParserCapability",
    "ParserError",
    "ParserErrorCode",
    "ParserIssue",
    "ParserMetadata",
    "ParserProgress",
    "ParserRegistry",
    "ProcessorBackedParser",
    "ProgressCallback",
    "PyMuPdfParser",
    "build_document_model",
]
