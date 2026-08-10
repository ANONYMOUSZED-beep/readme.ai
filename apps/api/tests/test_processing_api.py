"""Integration tests for processing: status, persistence, ownership."""

from __future__ import annotations

import asyncio
import uuid

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
from tests.conftest import FakeTokenVerifier

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
