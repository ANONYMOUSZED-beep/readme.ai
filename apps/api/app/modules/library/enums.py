"""Enumerations for the library module."""

from __future__ import annotations

from enum import StrEnum


class BookStatus(StrEnum):
    """Lifecycle state of a book.

    A book is ``UPLOADED`` when stored, ``PROCESSING`` while its content is
    being structured, then ``READY`` to read or ``FAILED``. Processing keeps
    this in step with the processing record so clients can poll the book.
    """

    UPLOADING = "UPLOADING"
    UPLOADED = "UPLOADED"
    PROCESSING = "PROCESSING"
    READY = "READY"
    FAILED = "FAILED"
