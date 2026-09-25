"""Enumerations for the processing module."""

from __future__ import annotations

from enum import StrEnum


class ProcessingStatus(StrEnum):
    """Lifecycle of a book's processing.

    Uploading records ``QUEUED``; the background run then moves the book
    ``PROCESSING -> COMPLETED|FAILED`` after the upload has responded.
    """

    QUEUED = "QUEUED"
    PROCESSING = "PROCESSING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


class ProcessingErrorCode(StrEnum):
    """Stable, structured reasons a book failed to process."""

    UNSUPPORTED_FORMAT = "unsupported_format"
    MALFORMED_FILE = "malformed_file"
    EMPTY_DOCUMENT = "empty_document"
    TOO_LARGE = "too_large"
    TIMEOUT = "timeout"
    INTERNAL = "internal_error"
