"""Integration tests for processing: status, persistence, ownership."""

from __future__ import annotations

import uuid

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.verifier import FirebaseIdentity
from app.modules.processing.models import (
    Paragraph,
    ProcessedBook,
    Sentence,
)
from tests.conftest import FakeTokenVerifier

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
        client, filename="scan.pdf", content=b"%PDF-1.4", mime="application/pdf"
    )

    response = await client.get(f"{_BOOKS}/{book_id}/processing", headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "FAILED"
    assert body["error_code"] == "unsupported_format"


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
