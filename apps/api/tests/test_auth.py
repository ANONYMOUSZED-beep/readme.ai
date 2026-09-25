"""Tests for the authentication module."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.modules.auth.models import User
from app.modules.auth.repository import UserRepository
from app.modules.auth.service import LAST_LOGIN_REFRESH_INTERVAL
from app.modules.auth.verifier import FirebaseIdentity
from tests.conftest import INVALID_TOKEN, FakeTokenVerifier

_AUTH = {"Authorization": "Bearer valid-token"}


async def test_me_provisions_user_on_first_request(
    client: AsyncClient,
    identity,
) -> None:
    response = await client.get("/api/v1/auth/me", headers=_AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["email"] == identity.email
    assert body["display_name"] == identity.display_name
    assert body["photo_url"] == identity.photo_url
    assert body["id"]
    assert body["created_at"]
    assert body["last_login_at"]


async def test_me_does_not_duplicate_existing_user(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
) -> None:
    first = await client.get("/api/v1/auth/me", headers=_AUTH)
    second = await client.get("/api/v1/auth/me", headers=_AUTH)

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["id"] == second.json()["id"]

    async with sessionmaker() as session:
        count = await session.scalar(select(func.count()).select_from(User))
    assert count == 1


async def test_me_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/api/v1/auth/me")

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


async def test_me_rejects_invalid_token(client: AsyncClient) -> None:
    response = await client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {INVALID_TOKEN}"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


async def test_logout_succeeds_when_authenticated(client: AsyncClient) -> None:
    response = await client.post("/api/v1/auth/logout", headers=_AUTH)

    assert response.status_code == 200
    assert response.json()["detail"]


async def test_logout_requires_authentication(client: AsyncClient) -> None:
    response = await client.post("/api/v1/auth/logout")

    assert response.status_code == 401


async def test_token_is_verified_on_every_request(
    client: AsyncClient,
    verifier: FakeTokenVerifier,
) -> None:
    await client.get("/api/v1/auth/me", headers=_AUTH)
    await client.get("/api/v1/auth/me", headers=_AUTH)

    # The client is never trusted: the token is validated on each request.
    assert verifier.verify_calls == 2


def _instant(value: str) -> datetime:
    """Parse an API timestamp as naive UTC (SQLite drops the offset)."""
    return datetime.fromisoformat(value.replace("Z", "+00:00")).replace(tzinfo=None)


async def _stored_user(
    sessionmaker: async_sessionmaker[AsyncSession], uid: str
) -> User:
    async with sessionmaker() as session:
        user = await session.scalar(select(User).where(User.firebase_uid == uid))
    assert user is not None
    return user


async def test_last_login_is_not_rewritten_on_every_request(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    identity: FirebaseIdentity,
) -> None:
    first = await client.get("/api/v1/auth/me", headers=_AUTH)
    second = await client.get("/api/v1/auth/me", headers=_AUTH)

    assert _instant(first.json()["last_login_at"]) == _instant(
        second.json()["last_login_at"]
    )
    stored = await _stored_user(sessionmaker, identity.uid)
    assert stored.last_login_at.replace(tzinfo=None) == _instant(
        first.json()["last_login_at"]
    )


async def test_last_login_is_refreshed_after_the_interval(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    identity: FirebaseIdentity,
) -> None:
    await client.get("/api/v1/auth/me", headers=_AUTH)
    stale = datetime.now(tz=UTC) - LAST_LOGIN_REFRESH_INTERVAL - timedelta(minutes=1)
    async with sessionmaker() as session:
        await session.execute(
            update(User)
            .where(User.firebase_uid == identity.uid)
            .values(last_login_at=stale)
        )
        await session.commit()

    await client.get("/api/v1/auth/me", headers=_AUTH)

    refreshed = (await _stored_user(sessionmaker, identity.uid)).last_login_at
    assert refreshed.replace(tzinfo=UTC) > stale


async def test_profile_changes_are_synced_immediately(
    client: AsyncClient,
    verifier: FakeTokenVerifier,
    identity: FirebaseIdentity,
) -> None:
    await client.get("/api/v1/auth/me", headers=_AUTH)
    verifier.register(
        "renamed",
        FirebaseIdentity(
            uid=identity.uid,
            email=identity.email,
            display_name="New Name",
            photo_url=None,
        ),
    )

    response = await client.get(
        "/api/v1/auth/me", headers={"Authorization": "Bearer renamed"}
    )

    assert response.json()["display_name"] == "New Name"
    assert response.json()["photo_url"] is None


async def test_concurrent_first_request_resolves_to_existing_user(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    identity: FirebaseIdentity,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Another request provisions the user between our lookup and our insert.
    async with sessionmaker() as session:
        session.add(User(firebase_uid=identity.uid, email=identity.email))
        await session.commit()
    original = UserRepository.get_by_firebase_uid
    calls = 0

    async def racing_lookup(self: UserRepository, uid: str) -> User | None:
        nonlocal calls
        calls += 1
        return None if calls == 1 else await original(self, uid)

    monkeypatch.setattr(UserRepository, "get_by_firebase_uid", racing_lookup)

    response = await client.get("/api/v1/auth/me", headers=_AUTH)

    assert response.status_code == 200
    assert response.json()["email"] == identity.email
    async with sessionmaker() as session:
        count = await session.scalar(select(func.count()).select_from(User))
    assert count == 1


async def test_email_owned_by_another_identity_is_a_conflict(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    identity: FirebaseIdentity,
) -> None:
    async with sessionmaker() as session:
        session.add(User(firebase_uid="someone-else", email=identity.email))
        await session.commit()

    response = await client.get("/api/v1/auth/me", headers=_AUTH)

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "conflict"


async def test_email_change_colliding_with_another_account_keeps_profile(
    client: AsyncClient,
    sessionmaker: async_sessionmaker[AsyncSession],
    verifier: FakeTokenVerifier,
    identity: FirebaseIdentity,
) -> None:
    await client.get("/api/v1/auth/me", headers=_AUTH)
    async with sessionmaker() as session:
        session.add(User(firebase_uid="other-uid", email="taken@example.com"))
        await session.commit()
    verifier.register(
        "moved",
        FirebaseIdentity(
            uid=identity.uid,
            email="taken@example.com",
            display_name=identity.display_name,
            photo_url=identity.photo_url,
        ),
    )

    response = await client.get(
        "/api/v1/auth/me", headers={"Authorization": "Bearer moved"}
    )

    assert response.status_code == 200
    assert response.json()["email"] == identity.email
