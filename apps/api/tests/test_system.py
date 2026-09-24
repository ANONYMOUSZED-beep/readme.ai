"""Tests for the operational endpoints."""

from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError as PydanticValidationError

from app.core.config import Environment, Settings
from app.db import session as db
from app.main import create_app


async def test_health_returns_ok(client: AsyncClient) -> None:
    response = await client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_version_reports_configured_metadata(client: AsyncClient) -> None:
    response = await client.get("/version")

    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "ReadMe.ai API (test)"
    assert body["version"] == "0.0.0-test"
    assert body["environment"] == "development"


async def test_readiness_ok_when_dependencies_healthy(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def _healthy() -> bool:
        return True

    monkeypatch.setattr(db, "ping", _healthy)

    response = await client.get("/health/ready")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert {"name": "postgres", "healthy": True} in body["dependencies"]


async def test_readiness_degraded_when_dependency_down(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def _unhealthy() -> bool:
        return False

    monkeypatch.setattr(db, "ping", _unhealthy)

    response = await client.get("/health/ready")

    assert response.status_code == 503
    assert response.json()["status"] == "degraded"


async def test_unknown_route_uses_error_envelope(client: AsyncClient) -> None:
    response = await client.get("/does-not-exist")

    assert response.status_code == 404
    body = response.json()
    assert body["error"]["code"] == "not_found"
    assert "request_id" in body["error"]


async def test_valid_inbound_request_id_is_echoed(client: AsyncClient) -> None:
    response = await client.get("/health", headers={"X-Request-ID": "abc-123.x_y"})

    assert response.headers["X-Request-ID"] == "abc-123.x_y"


@pytest.mark.parametrize("inbound", ["has spaces", "x" * 129, "semi;colon"])
async def test_malformed_inbound_request_id_is_replaced(
    client: AsyncClient, inbound: str
) -> None:
    response = await client.get("/health", headers={"X-Request-ID": inbound})

    echoed = response.headers["X-Request-ID"]
    assert echoed != inbound
    assert len(echoed) == 32


async def test_security_headers_are_applied(client: AsyncClient) -> None:
    response = await client.get("/health")

    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["Referrer-Policy"] == "no-referrer"


async def test_unhandled_error_returns_correlated_envelope(
    settings: Settings,
) -> None:
    app = create_app(settings=settings)

    @app.get("/boom")
    async def boom() -> None:
        raise RuntimeError("secret internal detail")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        response = await ac.get("/boom", headers={"X-Request-ID": "trace-1"})

    assert response.status_code == 500
    error = response.json()["error"]
    assert error["code"] == "internal_error"
    assert "secret" not in error["message"]
    assert error["request_id"] == "trace-1"
    assert response.headers["X-Request-ID"] == "trace-1"


def test_production_rejects_dev_auth() -> None:
    with pytest.raises(PydanticValidationError, match="DEV_AUTH"):
        Settings(
            APP_ENV=Environment.PRODUCTION,
            FIREBASE_PROJECT_ID="prod-project",
            DEV_AUTH=True,
        )


def test_production_requires_firebase_project() -> None:
    with pytest.raises(PydanticValidationError, match="FIREBASE_PROJECT_ID"):
        Settings(APP_ENV=Environment.PRODUCTION, FIREBASE_PROJECT_ID="")


def test_production_accepts_safe_configuration() -> None:
    settings = Settings(
        APP_ENV=Environment.PRODUCTION, FIREBASE_PROJECT_ID="prod-project"
    )

    assert settings.is_production
