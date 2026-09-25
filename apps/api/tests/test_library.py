"""Tests for the library module (book CRUD, ownership, storage)."""

from __future__ import annotations

import uuid

from httpx import AsyncClient

from app.modules.auth.verifier import FirebaseIdentity
from tests.conftest import FakeStorageService, FakeTokenVerifier

_AUTH = {"Authorization": "Bearer valid-token"}
_BOOKS_URL = "/api/v1/books"


def _upload_payload(filename: str = "book.pdf", title: str | None = "My Book"):
    files = {"file": (filename, b"%PDF-1.4 fake content", "application/pdf")}
    data = {"title": title} if title is not None else {}
    return files, data


async def test_upload_creates_book_and_stores_file(
    client: AsyncClient,
    storage: FakeStorageService,
) -> None:
    files, data = _upload_payload()
    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)

    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "My Book"
    assert body["original_filename"] == "book.pdf"
    assert body["mime_type"] == "application/pdf"
    # Processing continues after the response; the book is queued for it.
    assert body["status"] == "PROCESSING"
    assert body["file_size"] > 0
    assert body["id"]
    # The binary was persisted to storage exactly once.
    assert len(storage.objects) == 1


async def test_upload_defaults_title_to_filename(client: AsyncClient) -> None:
    files, data = _upload_payload(filename="war_and_peace.pdf", title=None)
    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)

    assert response.status_code == 201
    assert response.json()["title"] == "war_and_peace"


async def test_list_returns_only_the_users_books(client: AsyncClient) -> None:
    files, data = _upload_payload(filename="a.pdf")
    await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)
    files, data = _upload_payload(filename="b.pdf")
    await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)

    response = await client.get(_BOOKS_URL, headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    assert len(body["items"]) == 2


async def test_get_book_returns_the_book(client: AsyncClient) -> None:
    files, data = _upload_payload()
    created = await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)
    book_id = created.json()["id"]

    response = await client.get(f"{_BOOKS_URL}/{book_id}", headers=_AUTH)

    assert response.status_code == 200
    assert response.json()["id"] == book_id


async def test_get_missing_book_returns_404(client: AsyncClient) -> None:
    response = await client.get(f"{_BOOKS_URL}/{uuid.uuid4()}", headers=_AUTH)

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


async def test_delete_removes_book_and_file(
    client: AsyncClient,
    storage: FakeStorageService,
) -> None:
    files, data = _upload_payload()
    created = await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)
    book_id = created.json()["id"]

    deleted = await client.delete(f"{_BOOKS_URL}/{book_id}", headers=_AUTH)
    assert deleted.status_code == 204

    # The book is gone and its stored file was removed.
    follow_up = await client.get(f"{_BOOKS_URL}/{book_id}", headers=_AUTH)
    assert follow_up.status_code == 404
    assert storage.objects == {}


async def test_endpoints_require_authentication(client: AsyncClient) -> None:
    assert (await client.get(_BOOKS_URL)).status_code == 401
    files, data = _upload_payload()
    assert (await client.post(_BOOKS_URL, files=files, data=data)).status_code == 401


async def test_user_cannot_access_another_users_book(
    client: AsyncClient,
    verifier: FakeTokenVerifier,
) -> None:
    # Owner uploads a book with the default token.
    files, data = _upload_payload()
    created = await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)
    book_id = created.json()["id"]

    # A second user authenticates with a different token/identity.
    other_token = "other-user-token"
    verifier.register(
        other_token,
        FirebaseIdentity(
            uid="firebase-uid-other",
            email="intruder@example.com",
            display_name="Intruder",
            photo_url=None,
        ),
    )
    other_auth = {"Authorization": f"Bearer {other_token}"}

    # The second user sees an empty library and cannot read or delete the book.
    listing = await client.get(_BOOKS_URL, headers=other_auth)
    assert listing.json()["total"] == 0

    assert (
        await client.get(f"{_BOOKS_URL}/{book_id}", headers=other_auth)
    ).status_code == 404
    assert (
        await client.delete(f"{_BOOKS_URL}/{book_id}", headers=other_auth)
    ).status_code == 404

    # The owner can still access it — it was never deleted.
    assert (
        await client.get(f"{_BOOKS_URL}/{book_id}", headers=_AUTH)
    ).status_code == 200
