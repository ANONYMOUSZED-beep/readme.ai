"""Integration tests for processing: status, persistence, ownership."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.verifier import FirebaseIdentity
from app.modules.processing.models import (
    Paragraph,
    ProcessedBook,
    Sentence,
)
from app.modules.processing.processors.plain_text import PlainTextProcessor
from app.modules.processing.repository import ProcessingRepository
from tests.conftest import FakeTokenVerifier
from tests.documents import make_epub, make_pdf

_AUTH = {"Authorization": "Bearer valid-token"}
_BOOKS = "/api/v1/books"
_TEXT = b"# Title\n\nFirst paragraph. Two sentences here.\n\nSecond paragraph."


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


async def test_damaged_pdf_is_recorded_as_malformed(client: AsyncClient) -> None:
    book_id = await _upload(
        client, filename="scan.pdf", content=b"%PDF-1.4", mime="application/pdf"
    )

    response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    body = response.json()
    assert body["status"] == "FAILED"
    assert body["error_code"] == "malformed_file"


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
        paragraphs = await session.scalar(
            select(func.count())
            .select_from(Paragraph)
            .where(Paragraph.processed_book_id == record.id)
        )
        sentences = await session.scalar(
            select(func.count())
            .select_from(Sentence)
            .where(Sentence.processed_book_id == record.id)
        )
    assert paragraphs == 2
    assert sentences >= 3


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


async def _book(client: AsyncClient, book_id: str) -> dict[str, object]:
    response = await client.get(f"{_BOOKS}/{book_id}", headers=_AUTH)
    assert response.status_code == 200
    body: dict[str, object] = response.json()
    return body


async def test_text_upload_marks_the_book_ready(client: AsyncClient) -> None:
    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": ("book.txt", _TEXT, "text/plain")}
    )

    assert response.json()["status"] == "READY"
    assert (await _book(client, response.json()["id"]))["status"] == "READY"


async def test_failed_processing_marks_the_book_failed(client: AsyncClient) -> None:
    book_id = await _upload(
        client, filename="slides.pptx", content=b"PK", mime="application/zip"
    )

    assert (await _book(client, book_id))["status"] == "FAILED"


async def test_pdf_upload_is_readable(client: AsyncClient) -> None:
    pdf = make_pdf(
        [["A readable PDF sentence.", "Another short line."], ["Page two text."]],
        title="Embedded Producer Title",
    )

    book_id = await _upload(
        client, filename="paper.pdf", content=pdf, mime="application/pdf"
    )

    status = (await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)).json()
    assert status["status"] == "COMPLETED"
    assert status["processor_name"] == "pdf"
    assert status["page_count"] == 2
    book = await _book(client, book_id)
    assert book["status"] == "READY"
    assert book["total_pages"] == 2
    content = (await client.get(f"{_BOOKS}/{book_id}/content", headers=_AUTH)).json()
    assert content["format"] == "text"
    assert "A readable PDF sentence." in content["content"]
    # The reader keeps the library title, not the PDF's embedded metadata.
    assert content["title"] == "paper"


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
    assert response.json()["status"] == "FAILED"
    book_id = response.json()["id"]
    body = (await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)).json()
    assert body["error_code"] == "internal_error"
    # The partially written structure was rolled back, not left behind.
    async with sessionmaker() as session:
        paragraphs = await session.scalar(select(func.count()).select_from(Paragraph))
    assert paragraphs == 0


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
