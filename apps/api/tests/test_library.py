"""Tests for the library module (book CRUD, ownership, storage)."""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient

from app.core.config import Settings
from app.modules.auth.verifier import FirebaseIdentity
from app.modules.library.repository import BookRepository
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
    # The placeholder bytes are not a real PDF, so processing records a failure.
    assert body["status"] == "FAILED"
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


async def test_oversized_upload_is_rejected_with_413(
    client: AsyncClient,
    settings: Settings,
    storage: FakeStorageService,
) -> None:
    settings.max_upload_size_bytes = 10
    files = {"file": ("big.txt", b"x" * 11, "text/plain")}

    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files)

    assert response.status_code == 413
    body = response.json()["error"]
    assert body["code"] == "payload_too_large"
    assert body["details"]["max_bytes"] == 10
    assert storage.objects == {}


async def test_upload_at_exact_limit_is_accepted(
    client: AsyncClient, settings: Settings
) -> None:
    settings.max_upload_size_bytes = 10
    files = {"file": ("fits.txt", b"x" * 10, "text/plain")}

    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files)

    assert response.status_code == 201


async def test_empty_upload_is_rejected(client: AsyncClient) -> None:
    files = {"file": ("empty.txt", b"", "text/plain")}

    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


async def test_blank_title_falls_back_to_filename(client: AsyncClient) -> None:
    files, _ = _upload_payload(filename="dune.pdf")

    response = await client.post(
        _BOOKS_URL, headers=_AUTH, files=files, data={"title": "   "}
    )

    assert response.json()["title"] == "dune"


async def test_overlong_title_and_filename_are_bounded(client: AsyncClient) -> None:
    files = {"file": ("n" * 600 + ".txt", b"Some text.", "text/plain")}

    response = await client.post(
        _BOOKS_URL, headers=_AUTH, files=files, data={"title": "t" * 900}
    )

    assert response.status_code == 201
    body = response.json()
    assert len(body["title"]) == 512
    assert len(body["original_filename"]) == 512
    assert body["original_filename"].endswith(".txt")


@pytest.mark.parametrize(
    ("filename", "expected"),
    [
        ("../../etc/passwd.txt", "passwd.txt"),
        ("C:\\Users\\me\\novel.txt", "novel.txt"),
        ("/", "book"),
    ],
)
async def test_client_paths_are_stripped_from_filenames(
    client: AsyncClient, filename: str, expected: str
) -> None:
    files = {"file": (filename, b"Some text.", "text/plain")}

    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files)

    assert response.status_code == 201
    assert response.json()["original_filename"] == expected


@pytest.mark.parametrize(
    ("filename", "declared", "expected"),
    [
        ("notes.md", "application/octet-stream", "text/markdown"),
        ("novel.epub", "application/octet-stream", "application/epub+zip"),
        ("scan.PDF", "application/octet-stream", "application/pdf"),
        ("story.txt", "text/plain; charset=utf-8", "text/plain"),
        ("mystery.bin", "application/octet-stream", "application/octet-stream"),
    ],
)
async def test_mime_type_is_normalised_and_inferred(
    client: AsyncClient, filename: str, declared: str, expected: str
) -> None:
    files = {"file": (filename, b"Some text.", declared)}

    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files)

    assert response.json()["mime_type"] == expected


async def test_stored_file_is_removed_when_the_row_cannot_be_saved(
    client: AsyncClient,
    storage: FakeStorageService,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def failing_commit(self: BookRepository) -> None:
        raise RuntimeError("database unavailable")

    monkeypatch.setattr(BookRepository, "commit", failing_commit)
    files, data = _upload_payload()

    response = await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)

    assert response.status_code == 500
    assert storage.objects == {}


async def test_delete_succeeds_even_if_file_cleanup_fails(
    client: AsyncClient,
    storage: FakeStorageService,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    files, data = _upload_payload()
    created = await client.post(_BOOKS_URL, headers=_AUTH, files=files, data=data)
    book_id = created.json()["id"]

    async def failing_delete(key: str) -> None:
        raise OSError("disk unavailable")

    monkeypatch.setattr(storage, "delete", failing_delete)

    deleted = await client.delete(f"{_BOOKS_URL}/{book_id}", headers=_AUTH)

    assert deleted.status_code == 204
    follow_up = await client.get(f"{_BOOKS_URL}/{book_id}", headers=_AUTH)
    assert follow_up.status_code == 404
