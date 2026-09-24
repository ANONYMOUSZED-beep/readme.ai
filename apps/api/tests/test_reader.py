"""Tests for the reader module (content, progress, bookmarks, ownership)."""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient

from app.modules.auth.verifier import FirebaseIdentity
from app.modules.reader.models import ReadingProgress
from app.modules.reader.repository import ReaderRepository
from tests.conftest import FakeTokenVerifier

_AUTH = {"Authorization": "Bearer valid-token"}
_BOOKS_URL = "/api/v1/books"


async def _upload_text_book(
    client: AsyncClient,
    *,
    filename: str = "book.txt",
    content: bytes = b"Chapter one. It was a bright cold day in April.",
    mime: str = "text/plain",
) -> str:
    files = {"file": (filename, content, mime)}
    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files)
    assert response.status_code == 201
    return response.json()["id"]


async def test_get_content_returns_text(client: AsyncClient) -> None:
    book_id = await _upload_text_book(client, content=b"Hello reader")

    response = await client.get(f"{_BOOKS_URL}/{book_id}/content", headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["format"] == "text"
    assert body["content"] == "Hello reader"
    assert body["character_count"] == len("Hello reader")
    assert body["title"]


async def test_get_content_unsupported_for_binary(client: AsyncClient) -> None:
    book_id = await _upload_text_book(
        client, filename="book.pdf", content=b"%PDF-1.4 binary", mime="application/pdf"
    )

    response = await client.get(f"{_BOOKS_URL}/{book_id}/content", headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["format"] == "unsupported"
    assert body["content"] is None


async def test_progress_unstarted_is_null(client: AsyncClient) -> None:
    book_id = await _upload_text_book(client)

    response = await client.get(f"{_BOOKS_URL}/{book_id}/progress", headers=_AUTH)

    assert response.status_code == 200
    assert response.json() is None


async def test_save_and_resume_progress(client: AsyncClient) -> None:
    book_id = await _upload_text_book(client)

    saved = await client.put(
        f"{_BOOKS_URL}/{book_id}/progress",
        headers=_AUTH,
        json={
            "current_position": "120",
            "progress_percentage": 42.5,
            "reading_time_seconds": 30,
        },
    )
    assert saved.status_code == 200

    resumed = await client.get(f"{_BOOKS_URL}/{book_id}/progress", headers=_AUTH)
    body = resumed.json()
    assert body["current_position"] == "120"
    assert body["progress_percentage"] == 42.5
    assert body["total_reading_time_seconds"] == 30


async def test_progress_accumulates_reading_time(client: AsyncClient) -> None:
    book_id = await _upload_text_book(client)
    payload = {
        "current_position": "10",
        "progress_percentage": 5.0,
        "reading_time_seconds": 15,
    }
    await client.put(f"{_BOOKS_URL}/{book_id}/progress", headers=_AUTH, json=payload)
    await client.put(f"{_BOOKS_URL}/{book_id}/progress", headers=_AUTH, json=payload)

    resumed = await client.get(f"{_BOOKS_URL}/{book_id}/progress", headers=_AUTH)
    assert resumed.json()["total_reading_time_seconds"] == 30


async def test_bookmark_crud(client: AsyncClient) -> None:
    book_id = await _upload_text_book(client)

    created = await client.post(
        f"{_BOOKS_URL}/{book_id}/bookmarks",
        headers=_AUTH,
        json={"anchor": "250", "label": "A good bit"},
    )
    assert created.status_code == 201
    bookmark_id = created.json()["id"]
    assert created.json()["anchor"] == "250"

    listing = await client.get(f"{_BOOKS_URL}/{book_id}/bookmarks", headers=_AUTH)
    assert listing.json()["total"] == 1

    deleted = await client.delete(
        f"{_BOOKS_URL}/{book_id}/bookmarks/{bookmark_id}", headers=_AUTH
    )
    assert deleted.status_code == 204

    listing = await client.get(f"{_BOOKS_URL}/{book_id}/bookmarks", headers=_AUTH)
    assert listing.json()["total"] == 0


async def test_reader_endpoints_require_authentication(
    client: AsyncClient,
) -> None:
    book_id = await _upload_text_book(client)

    assert (await client.get(f"{_BOOKS_URL}/{book_id}/content")).status_code == 401
    assert (await client.get(f"{_BOOKS_URL}/{book_id}/progress")).status_code == 401
    assert (await client.get(f"{_BOOKS_URL}/{book_id}/bookmarks")).status_code == 401


async def test_user_cannot_read_another_users_book(
    client: AsyncClient,
    verifier: FakeTokenVerifier,
) -> None:
    book_id = await _upload_text_book(client)

    other_token = "other-user-token"
    verifier.register(
        other_token,
        FirebaseIdentity(
            uid="firebase-uid-other",
            email="intruder@example.com",
            display_name=None,
            photo_url=None,
        ),
    )
    other = {"Authorization": f"Bearer {other_token}"}

    assert (
        await client.get(f"{_BOOKS_URL}/{book_id}/content", headers=other)
    ).status_code == 404
    assert (
        await client.get(f"{_BOOKS_URL}/{book_id}/progress", headers=other)
    ).status_code == 404
    assert (
        await client.post(
            f"{_BOOKS_URL}/{book_id}/bookmarks",
            headers=other,
            json={"anchor": "1"},
        )
    ).status_code == 404


async def test_get_content_missing_book_returns_404(client: AsyncClient) -> None:
    response = await client.get(f"{_BOOKS_URL}/{uuid.uuid4()}/content", headers=_AUTH)
    assert response.status_code == 404


async def test_reading_time_per_save_is_bounded(client: AsyncClient) -> None:
    book_id = await _upload_text_book(client)

    response = await client.put(
        f"{_BOOKS_URL}/{book_id}/progress",
        headers=_AUTH,
        json={
            "current_position": "0",
            "progress_percentage": 1.0,
            "reading_time_seconds": 86_401,
        },
    )

    assert response.status_code == 422


async def test_concurrent_first_progress_save_updates_winning_row(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    book_id = await _upload_text_book(client)
    first = await client.put(
        f"{_BOOKS_URL}/{book_id}/progress",
        headers=_AUTH,
        json={
            "current_position": "10",
            "progress_percentage": 10.0,
            "reading_time_seconds": 5,
        },
    )
    assert first.status_code == 200

    # The next save's lookup misses the row a concurrent request just created.
    original = ReaderRepository.get_progress
    calls = 0

    async def racing_lookup(
        self: ReaderRepository, user_id: uuid.UUID, book: uuid.UUID
    ) -> ReadingProgress | None:
        nonlocal calls
        calls += 1
        return None if calls == 1 else await original(self, user_id, book)

    monkeypatch.setattr(ReaderRepository, "get_progress", racing_lookup)

    second = await client.put(
        f"{_BOOKS_URL}/{book_id}/progress",
        headers=_AUTH,
        json={
            "current_position": "20",
            "progress_percentage": 20.0,
            "reading_time_seconds": 7,
        },
    )

    assert second.status_code == 200
    body = second.json()
    assert body["current_position"] == "20"
    assert body["total_reading_time_seconds"] == 12
