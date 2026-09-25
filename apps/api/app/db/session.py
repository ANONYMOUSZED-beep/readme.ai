"""Async database engine and session management.

The engine is created lazily and held as a module-level singleton so the process
maintains a single connection pool. Creation is lazy (rather than at import
time) so the application can start even when the database is temporarily
unavailable — readiness is reported separately via :func:`ping`.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import get_settings

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def get_engine() -> AsyncEngine:
    """Return the process-wide async engine, creating it on first use."""
    global _engine
    if _engine is None:
        settings = get_settings()
        _engine = create_async_engine(
            settings.database_url,
            echo=settings.app_debug,
            pool_pre_ping=True,
        )
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    """Return the process-wide session factory, creating it on first use."""
    global _session_factory
    if _session_factory is None:
        _session_factory = async_sessionmaker(
            bind=get_engine(),
            expire_on_commit=False,
            autoflush=False,
        )
    return _session_factory


def get_db_sessionmaker() -> async_sessionmaker[AsyncSession]:
    """FastAPI dependency providing the session factory itself.

    For work that outlives a request (e.g. background processing), which must
    open its own session once the request-scoped one has closed.
    """
    return get_session_factory()


async def get_db_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency yielding a scoped async session.

    The session is closed when the request completes. Transaction management is
    the responsibility of the calling service in later sprints.
    """
    factory = get_session_factory()
    async with factory() as session:
        yield session


async def ping() -> bool:
    """Return ``True`` if a trivial query against the database succeeds.

    Used by the readiness probe. Never raises — connectivity failures are
    reported as ``False`` so the probe can return a controlled 503.
    """
    try:
        async with get_engine().connect() as connection:
            await connection.execute(text("SELECT 1"))
        return True
    except Exception:
        # Readiness must never raise: any connectivity failure is reported as
        # an unhealthy result so the probe can return a controlled 503.
        return False


async def dispose_engine() -> None:
    """Dispose the engine and its connection pool (called on shutdown)."""
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
        _engine = None
        _session_factory = None
