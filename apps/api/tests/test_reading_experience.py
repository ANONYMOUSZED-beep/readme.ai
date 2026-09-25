"""Tests for covers, the chapter outline, and "continue reading"."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from app.modules.auth.verifier import FirebaseIdentity
from app.modules.library.service import BookService
from tests.conftest import FakeStorageService, FakeTokenVerifier
from tests.documents import make_epub

_AUTH = {"Authorization": "Bearer valid-token"}
_BOOKS = "/api/v1/books"
_RECENT = "/api/v1/reading/recent"
_JPEG = b"\xff\xd8\xff\xe0" + b"\x01" * 64


async def _upload(
    client: AsyncClient,
    content: bytes,
    filename: str = "book.epub",
    mime: str = "application/epub+zip",
) -> dict[str, Any]:
    response = await client.post(
        _BOOKS, headers=_AUTH, files={"file": (filename, content, mime)}
    )
    assert response.status_code == 201, response.text
    # Processing runs after the upload responds; return the book as it stands
    # once that has finished.
    book = await client.get(f"{_BOOKS}/{response.json()['id']}", headers=_AUTH)
    body: dict[str, Any] = book.json()
    return body


def _other_user(verifier: FakeTokenVerifier) -> dict[str, str]:
    verifier.register(
        "other",
        FirebaseIdentity(
            uid="other-uid",
            email="other@example.com",
            display_name=None,
            photo_url=None,
        ),
    )
    return {"Authorization": "Bearer other"}


# --- covers ----------------------------------------------------------------------
async def test_epub_cover_is_served(client: AsyncClient) -> None:
    book = await _upload(client, make_epub(["<p>Hi.</p>"], cover=_JPEG))

    assert book["has_cover"] is True
    response = await client.get(f"{_BOOKS}/{book['id']}/cover", headers=_AUTH)

    assert response.status_code == 200
    assert response.content == _JPEG
    assert response.headers["content-type"] == "image/jpeg"
    assert "private" in response.headers["cache-control"]


async def test_book_without_cover_has_no_cover(client: AsyncClient) -> None:
    book = await _upload(client, b"Plain text.", "a.txt", "text/plain")

    assert book["has_cover"] is False
    response = await client.get(f"{_BOOKS}/{book['id']}/cover", headers=_AUTH)
    assert response.status_code == 404


async def test_cover_is_private_to_its_owner(
    client: AsyncClient, verifier: FakeTokenVerifier
) -> None:
    book = await _upload(client, make_epub(["<p>Hi.</p>"], cover=_JPEG))

    response = await client.get(
        f"{_BOOKS}/{book['id']}/cover", headers=_other_user(verifier)
    )

    assert response.status_code == 404
    assert (await client.get(f"{_BOOKS}/{book['id']}/cover")).status_code == 401


async def test_deleting_a_book_removes_its_cover(
    client: AsyncClient, storage: FakeStorageService
) -> None:
    book = await _upload(client, make_epub(["<p>Hi.</p>"], cover=_JPEG))
    assert len(storage.objects) == 2

    await client.delete(f"{_BOOKS}/{book['id']}", headers=_AUTH)

    assert storage.objects == {}


async def test_reprocessing_keeps_a_single_cover(
    client: AsyncClient, storage: FakeStorageService
) -> None:
    book = await _upload(client, make_epub(["<p>Hi.</p>"], cover=_JPEG))

    response = await client.post(f"{_BOOKS}/{book['id']}/processing", headers=_AUTH)

    assert response.json()["status"] == "COMPLETED"
    assert len(storage.objects) == 2


async def test_cover_failure_does_not_fail_the_book(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def broken(self: BookService, *args: Any) -> None:
        raise OSError("disk full")

    monkeypatch.setattr(BookService, "replace_cover", broken)

    book = await _upload(client, make_epub(["<p>Hi.</p>"], cover=_JPEG))

    assert book["status"] == "READY"
    assert book["has_cover"] is False
    reprocessed = await client.post(f"{_BOOKS}/{book['id']}/processing", headers=_AUTH)
    assert reprocessed.status_code == 200
    assert reprocessed.json()["status"] == "COMPLETED"


# --- chapter outline ---------------------------------------------------------------
async def test_content_includes_the_chapter_outline(client: AsyncClient) -> None:
    text = b"# One\n\nFirst chapter.\n\n# Two\n\nSecond chapter.\n\nMore."
    book = await _upload(client, text, "novel.md", "text/markdown")

    body = (await client.get(f"{_BOOKS}/{book['id']}/content", headers=_AUTH)).json()

    chapters = body["chapters"]
    assert [c["title"] for c in chapters] == ["One", "Two"]
    content = body["content"]
    assert content[chapters[0]["start_offset"] :].startswith("First chapter.")
    assert content[chapters[1]["start_offset"] :].startswith("Second chapter.")


async def test_unreadable_book_has_no_outline(client: AsyncClient) -> None:
    book = await _upload(client, b"PK", "x.pptx", "application/zip")

    body = (await client.get(f"{_BOOKS}/{book['id']}/content", headers=_AUTH)).json()

    assert body["chapters"] == []


# --- continue reading ---------------------------------------------------------------
async def _read(client: AsyncClient, book_id: str, percentage: float) -> None:
    response = await client.put(
        f"{_BOOKS}/{book_id}/progress",
        headers=_AUTH,
        json={"current_position": "1", "progress_percentage": percentage},
    )
    assert response.status_code == 200


async def test_recent_lists_most_recently_read_first(client: AsyncClient) -> None:
    first = await _upload(client, b"One.", "a.txt", "text/plain")
    second = await _upload(client, b"Two.", "b.txt", "text/plain")
    await _read(client, first["id"], 10)
    await _read(client, second["id"], 20)
    await _read(client, first["id"], 30)

    response = await client.get(_RECENT, headers=_AUTH)

    items = response.json()["items"]
    assert [item["book_id"] for item in items] == [first["id"], second["id"]]
    assert items[0]["progress_percentage"] == 30


async def test_recent_respects_limit_and_ownership(
    client: AsyncClient, verifier: FakeTokenVerifier
) -> None:
    for name in ("a.txt", "b.txt"):
        book = await _upload(client, b"Text.", name, "text/plain")
        await _read(client, book["id"], 5)

    limited = await client.get(_RECENT, headers=_AUTH, params={"limit": 1})
    other = await client.get(_RECENT, headers=_other_user(verifier))

    assert len(limited.json()["items"]) == 1
    assert other.json()["items"] == []
    assert (
        await client.get(_RECENT, params={"limit": 0}, headers=_AUTH)
    ).status_code == 422
    assert (await client.get(_RECENT)).status_code == 401


async def test_recent_forgets_deleted_books(client: AsyncClient) -> None:
    book = await _upload(client, b"Text.", "a.txt", "text/plain")
    await _read(client, book["id"], 50)

    await client.delete(f"{_BOOKS}/{book['id']}", headers=_AUTH)

    assert (await client.get(_RECENT, headers=_AUTH)).json()["items"] == []
