"""Shared pytest fixtures for the backend test suite."""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool

from app.core.config import Environment, LogFormat, LogLevel, Settings
from app.core.errors import UnauthorizedError
from app.core.storage.provider import get_storage_service
from app.db.base import Base
from app.db.session import get_db_session, get_db_sessionmaker
from app.main import create_app
from app.modules.auth.dependencies import get_token_verifier
from app.modules.auth.verifier import FirebaseIdentity
from app.modules.explanation.dependencies import get_explanation_provider
from app.modules.explanation.provider import (
    ExplanationError,
    GeneratedExplanation,
)
from app.modules.processing.dependencies import get_parser_registry
from app.modules.processing.parsers import ParserRegistry

# A token value the fake verifier treats as invalid, for exercising the 401 path.
INVALID_TOKEN = "invalid-token"


class FakeTokenVerifier:
    """In-memory token verifier for tests.

    Returns the identity registered for a token (or a default), and raises for
    :data:`INVALID_TOKEN`. Additional tokens can be mapped to distinct
    identities to exercise multi-user ownership scenarios.
    """

    def __init__(self, default_identity: FirebaseIdentity) -> None:
        self._default = default_identity
        self._by_token: dict[str, FirebaseIdentity] = {}
        self.verify_calls = 0

    def register(self, token: str, identity: FirebaseIdentity) -> None:
        self._by_token[token] = identity

    async def verify(self, token: str) -> FirebaseIdentity:
        self.verify_calls += 1
        if token == INVALID_TOKEN:
            raise UnauthorizedError("Invalid authentication token.")
        return self._by_token.get(token, self._default)


class FakeStorageService:
    """In-memory StorageService for tests."""

    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}

    async def save(
        self,
        key: str,
        content: bytes,
        *,
        content_type: str | None = None,
    ) -> None:
        self.objects[key] = content

    async def read(self, key: str) -> bytes:
        return self.objects[key]

    async def delete(self, key: str) -> None:
        self.objects.pop(key, None)

    async def exists(self, key: str) -> bool:
        return key in self.objects


class FakeExplanationProvider:
    """In-memory explanation provider for tests.

    Returns a canned explanation, or raises when ``error`` is set, so the
    service and failure paths can be exercised without a real model.
    """

    def __init__(self) -> None:
        self.result = GeneratedExplanation(
            meaning="a small, portable computer",
            explanation="A laptop is a portable computer. It fits on your lap.",
            example="Winston opened his laptop to write.",
        )
        self.error: ExplanationError | None = None
        self.last_prompt: str | None = None

    async def explain(self, *, prompt: str) -> GeneratedExplanation:
        self.last_prompt = prompt
        if self.error is not None:
            raise self.error
        return self.result


@pytest.fixture
def settings() -> Settings:
    """Deterministic settings for tests, independent of the environment."""
    return Settings(
        APP_ENV=Environment.DEVELOPMENT,
        APP_NAME="ReadMe.ai API (test)",
        APP_VERSION="0.0.0-test",
        APP_DEBUG=True,
        LOG_LEVEL=LogLevel.WARNING,
        LOG_FORMAT=LogFormat.CONSOLE,
        FIREBASE_PROJECT_ID="test-project",
    )


@pytest.fixture
def identity() -> FirebaseIdentity:
    """A representative verified Firebase identity."""
    return FirebaseIdentity(
        uid="firebase-uid-123",
        email="reader@example.com",
        display_name="Test Reader",
        photo_url="https://example.com/avatar.png",
    )


@pytest.fixture
def verifier(identity: FirebaseIdentity) -> FakeTokenVerifier:
    """A fake token verifier seeded with the test identity as default."""
    return FakeTokenVerifier(identity)


@pytest.fixture
def storage() -> FakeStorageService:
    """An in-memory storage service for tests."""
    return FakeStorageService()


@pytest.fixture
def explanation_provider() -> FakeExplanationProvider:
    """An in-memory explanation provider for tests."""
    return FakeExplanationProvider()


@pytest.fixture
def parser_registry() -> ParserRegistry:
    """A fresh registry holding the application's parsers.

    Parsers are stateless, so they are shared; the registry itself is rebuilt per
    test so a test can register an extra parser without affecting others.
    """
    return ParserRegistry(list(get_parser_registry().available()))


@pytest.fixture
async def sessionmaker() -> AsyncIterator[async_sessionmaker[AsyncSession]]:
    """Create an isolated in-memory SQLite database with the schema applied.

    A StaticPool keeps a single underlying connection so the in-memory database
    is shared across sessions for the duration of the test.
    """
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )

    # Enforce foreign keys on SQLite (off by default) so FK-ordering bugs that
    # PostgreSQL would reject are caught in tests too.
    @event.listens_for(engine.sync_engine, "connect")
    def _enable_sqlite_fk(dbapi_connection: object, _: object) -> None:
        cursor = dbapi_connection.cursor()  # type: ignore[attr-defined]
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        yield factory
    finally:
        await engine.dispose()


@pytest.fixture
async def client(
    settings: Settings,
    sessionmaker: async_sessionmaker[AsyncSession],
    verifier: FakeTokenVerifier,
    storage: FakeStorageService,
    explanation_provider: FakeExplanationProvider,
    parser_registry: ParserRegistry,
) -> AsyncIterator[AsyncClient]:
    """An HTTP client bound to the ASGI app with test doubles wired in.

    The database session, token verifier, and storage service dependencies are
    overridden so the suite runs without real PostgreSQL, Firebase, or disk I/O.
    """
    app = create_app(settings=settings)

    async def _override_session() -> AsyncIterator[AsyncSession]:
        async with sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db_session] = _override_session
    app.dependency_overrides[get_db_sessionmaker] = lambda: sessionmaker
    app.dependency_overrides[get_token_verifier] = lambda: verifier
    app.dependency_overrides[get_storage_service] = lambda: storage
    app.dependency_overrides[get_explanation_provider] = lambda: explanation_provider
    app.dependency_overrides[get_parser_registry] = lambda: parser_registry

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
