"""Integration tests for processing: status, persistence, ownership."""

from __future__ import annotations

import asyncio
import uuid
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.verifier import FirebaseIdentity
from app.modules.processing.document_model import ElementType
from app.modules.processing.models import (
    ProcessedBook,
    StoredDocument,
    StoredDocumentElement,
)
from app.modules.processing.parsers import (
    ParserCapability,
    ParseRequest,
    ParserError,
    ParserErrorCode,
    ParseResult,
    ParserMetadata,
    ParserRegistry,
    ProgressCallback,
)
from app.modules.processing.processors.plain_text import PlainTextProcessor
from app.modules.processing.repository import ProcessingRepository
from tests.conftest import FakeTokenVerifier
from tests.documents import make_epub

_AUTH = {"Authorization": "Bearer valid-token"}
_BOOKS = "/api/v1/books"
_TEXT = b"# Title\n\nFirst paragraph. Two sentences here.\n\nSecond paragraph."


def _text_pdf(text: str = "Readable PDF content.") -> bytes:
    stream = f"BT /F1 18 Tf 72 720 Td ({text}) Tj ET".encode("ascii")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
        ),
        b"<< /Length "
        + str(len(stream)).encode()
        + b" >>\nstream\n"
        + stream
        + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    pdf = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, body in enumerate(objects, 1):
        offsets.append(len(pdf))
        pdf.extend(f"{number} 0 obj\n".encode())
        pdf.extend(body + b"\nendobj\n")
    xref = len(pdf)
    pdf.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        pdf.extend(f"{offset:010d} 00000 n \n".encode())
    pdf.extend(
        f"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    )
    return bytes(pdf)


async def _upload(
    client: AsyncClient,
    *,
    filename: str = "book.txt",
    content: bytes = _TEXT,
    mime: str = "text/plain",
) -> str:
    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": (filename, content, mime)}
    )
    assert response.status_code == 201
    return response.json()["id"]


async def test_upload_produces_completed_processing(client: AsyncClient) -> None:
    book_id = await _upload(client)

    response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "COMPLETED"
    assert body["processor_name"] == "plain_text"
    assert body["word_count"] > 0
    assert body["error_code"] is None


async def test_corrupt_pdf_is_recorded_as_malformed(
    client: AsyncClient,
) -> None:
    book_id = await _upload(
        client, filename="scan.pdf", content=b"%PDF-1.4", mime="application/pdf"
    )

    response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "FAILED"
    assert body["error_code"] == "malformed_file"


async def test_pdf_upload_is_processed_and_readable(client: AsyncClient) -> None:
    book_id = await _upload(
        client,
        filename="guide.pdf",
        content=_text_pdf(),
        mime="application/pdf",
    )

    status_response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)
    content_response = await client.get(f"{_BOOKS}/{book_id}/content", headers=_AUTH)
    book_response = await client.get(f"{_BOOKS}/{book_id}", headers=_AUTH)

    assert status_response.status_code == 200
    assert status_response.json()["status"] == "COMPLETED"
    # PyMuPDF is the registered production PDF parser (Sprint 6.4).
    assert status_response.json()["processor_name"] == "pymupdf"
    assert status_response.json()["page_count"] == 1
    assert content_response.status_code == 200
    assert content_response.json()["format"] == "text"
    assert content_response.json()["content"] == "Readable PDF content."
    assert book_response.json()["status"] == "READY"
    assert book_response.json()["total_pages"] == 1


async def test_pdf_processing_runs_parser_off_event_loop(
    client: AsyncClient,
    monkeypatch: object,
) -> None:
    real_to_thread = asyncio.to_thread
    offloaded_functions: list[object] = []

    async def recording_to_thread(function, /, *args, **kwargs):
        offloaded_functions.append(function)
        return await real_to_thread(function, *args, **kwargs)

    monkeypatch.setattr(asyncio, "to_thread", recording_to_thread)

    await _upload(
        client,
        filename="threaded.pdf",
        content=_text_pdf(),
        mime="application/pdf",
    )

    assert offloaded_functions


async def test_structure_is_persisted(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    book_id = await _upload(client)

    async with sessionmaker() as session:
        record = await session.scalar(
            select(ProcessedBook).where(ProcessedBook.book_id == uuid.UUID(book_id))
        )
        assert record is not None
        stored = await session.scalar(
            select(StoredDocument).where(StoredDocument.processed_book_id == record.id)
        )
        assert stored is not None
        paragraphs = await session.scalar(
            select(func.count())
            .select_from(StoredDocumentElement)
            .where(
                StoredDocumentElement.document_id == stored.id,
                StoredDocumentElement.element_type == ElementType.PARAGRAPH.value,
            )
        )
        sentences = await session.scalar(
            select(func.count())
            .select_from(StoredDocumentElement)
            .where(
                StoredDocumentElement.document_id == stored.id,
                StoredDocumentElement.element_type == ElementType.SENTENCE.value,
            )
        )
        sentence_rows = await session.scalars(
            select(StoredDocumentElement.content).where(
                StoredDocumentElement.document_id == stored.id,
                StoredDocumentElement.element_type == ElementType.SENTENCE.value,
            )
        )
    assert paragraphs == 2
    assert sentences >= 3
    # The canonical text is stored once, on the document row.
    assert stored.text == "First paragraph. Two sentences here.\n\nSecond paragraph."
    # Sentence rows derive their text from the span instead of duplicating it.
    assert all(content is None for content in sentence_rows.all())


async def test_reprocess_transitions_to_completed(client: AsyncClient) -> None:
    book_id = await _upload(client)

    response = await client.post(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    assert response.status_code == 200
    assert response.json()["status"] == "COMPLETED"


async def test_processing_requires_authentication(client: AsyncClient) -> None:
    book_id = await _upload(client)

    assert (await client.get(f"{_BOOKS}/{book_id}/processing")).status_code == 401


async def test_other_user_cannot_see_processing(
    client: AsyncClient,
    verifier: FakeTokenVerifier,
) -> None:
    book_id = await _upload(client)
    verifier.register(
        "other",
        FirebaseIdentity(
            uid="other-uid",
            email="other@example.com",
            display_name=None,
            photo_url=None,
        ),
    )

    response = await client.get(
        f"{_BOOKS}/{book_id}/processing",
        headers={"Authorization": "Bearer other"},
    )

    assert response.status_code == 404


async def test_reader_serves_structured_text(client: AsyncClient) -> None:
    book_id = await _upload(client)

    response = await client.get(f"{_BOOKS}/{book_id}/content", headers=_AUTH)

    body = response.json()
    assert body["format"] == "text"
    # Reconstructed from the structured document (headings become structure).
    assert "First paragraph." in body["content"]
    assert (
        body["content"] == "First paragraph. Two sentences here.\n\nSecond paragraph."
    )


class _EncryptedStubParser:
    """A parser that always reports an encrypted document.

    Registered with a high priority to prove the engine resolves parsers purely
    through the registry and records parser failures structurally.
    """

    @property
    def metadata(self) -> ParserMetadata:
        return ParserMetadata(
            name="encrypted_stub",
            version="0.1.0",
            display_name="Encrypted Stub",
            capabilities=frozenset({ParserCapability.TEXT}),
            priority=100,
        )

    def supports(self, *, mime_type: str, filename: str) -> bool:
        return filename.endswith(".locked")

    def parse(
        self,
        request: ParseRequest,
        on_progress: ProgressCallback | None = None,
    ) -> ParseResult:
        raise ParserError(
            ParserErrorCode.ENCRYPTED_DOCUMENT,
            "The document is password protected.",
            parser_name="encrypted_stub",
        )


async def test_engine_selects_a_newly_registered_parser(
    client: AsyncClient,
    parser_registry: ParserRegistry,
) -> None:
    parser_registry.register(_EncryptedStubParser())

    book_id = await _upload(client, filename="secret.txt.locked", mime="text/plain")
    response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    body = response.json()
    assert body["status"] == "FAILED"
    # Parser-layer failures are recorded through the existing processing codes.
    assert body["error_code"] == "malformed_file"


async def test_engine_records_the_selected_parser_name(client: AsyncClient) -> None:
    book_id = await _upload(client)

    response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    assert response.json()["processor_name"] == "plain_text"


async def test_upload_responds_before_processing_then_book_becomes_ready(
    client: AsyncClient,
) -> None:
    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": ("book.txt", _TEXT, "text/plain")}
    )

    # The upload answers immediately with the book queued for processing...
    assert response.status_code == 201
    assert response.json()["status"] == "PROCESSING"

    # ...and processing, run after the response, leaves the book readable.
    book_id = response.json()["id"]
    book = await client.get(f"{_BOOKS}/{book_id}", headers=_AUTH)
    assert book.json()["status"] == "READY"
    content = await client.get(f"{_BOOKS}/{book_id}/content", headers=_AUTH)
    assert content.json()["format"] == "text"


async def test_failed_processing_marks_the_book_failed(client: AsyncClient) -> None:
    book_id = await _upload(
        client, filename="scan.pdf", content=b"%PDF-1.4", mime="application/pdf"
    )

    book = await client.get(f"{_BOOKS}/{book_id}", headers=_AUTH)

    assert book.json()["status"] == "FAILED"


async def test_unsupported_format_is_recorded_as_failed(
    client: AsyncClient,
) -> None:
    book_id = await _upload(
        client, filename="slides.pptx", content=b"PK\x03\x04", mime="application/zip"
    )

    response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "FAILED"
    assert body["error_code"] == "unsupported_format"


async def _book(client: AsyncClient, book_id: str) -> dict[str, object]:
    response = await client.get(f"{_BOOKS}/{book_id}", headers=_AUTH)
    assert response.status_code == 200
    body: dict[str, object] = response.json()
    return body


async def test_epub_upload_is_readable(client: AsyncClient) -> None:
    epub = make_epub(["<h1>One</h1><p>Chapter one text.</p>", "<p>Two.</p>"])

    book_id = await _upload(
        client,
        filename="novel.epub",
        content=epub,
        mime="application/octet-stream",
    )

    status = (await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)).json()
    assert status["status"] == "COMPLETED"
    assert status["processor_name"] == "epub"
    assert status["author"] == "Ada Author"
    content = (await client.get(f"{_BOOKS}/{book_id}/content", headers=_AUTH)).json()
    assert content["content"] == "Chapter one text.\n\nTwo."


async def test_text_with_nul_bytes_is_processed(client: AsyncClient) -> None:
    book_id = await _upload(client, content=b"Bad\x00 bytes here.")

    content = (await client.get(f"{_BOOKS}/{book_id}/content", headers=_AUTH)).json()

    assert content["content"] == "Bad bytes here."


async def test_unexpected_processor_error_is_generic_and_upload_succeeds(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def explode(self: PlainTextProcessor, **_: object) -> None:
        raise RuntimeError("/srv/secret/path exploded")

    monkeypatch.setattr(PlainTextProcessor, "process", explode)

    book_id = await _upload(client)

    body = (await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)).json()
    assert body["status"] == "FAILED"
    assert body["error_code"] == "internal_error"
    assert "secret" not in body["error_message"]
    assert (await _book(client, book_id))["status"] == "FAILED"


async def test_persistence_failure_is_rolled_back_and_recorded(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    original = ProcessingRepository.save_completed

    async def half_written(
        self: ProcessingRepository, *args: Any, **kwargs: Any
    ) -> None:
        await original(self, *args, **kwargs)
        raise RuntimeError("connection lost mid-write")

    monkeypatch.setattr(ProcessingRepository, "save_completed", half_written)

    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": ("book.txt", _TEXT, "text/plain")}
    )

    assert response.status_code == 201
    book_id = response.json()["id"]
    assert (await _book(client, book_id))["status"] == "FAILED"
    body = (await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)).json()
    assert body["error_code"] == "internal_error"
    # The partially written structure was rolled back, not left behind.
    async with sessionmaker() as session:
        elements = await session.scalar(
            select(func.count()).select_from(StoredDocumentElement)
        )
    assert elements == 0


async def test_reprocess_recovers_a_failed_book(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def explode(self: PlainTextProcessor, **_: object) -> None:
        raise RuntimeError("transient")

    with monkeypatch.context() as patch:
        patch.setattr(PlainTextProcessor, "process", explode)
        book_id = await _upload(client)

    response = await client.post(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    assert response.json()["status"] == "COMPLETED"
    assert (await _book(client, book_id))["status"] == "READY"


async def test_upload_succeeds_even_if_processing_cannot_start(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def unavailable(self: ProcessingRepository, *args: Any) -> None:
        raise RuntimeError("database went away")

    monkeypatch.setattr(ProcessingRepository, "upsert_record", unavailable)

    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": ("book.txt", _TEXT, "text/plain")}
    )

    assert response.status_code == 201
    assert response.json()["status"] == "UPLOADED"
