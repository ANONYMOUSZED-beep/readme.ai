"""Top-level API router aggregation.

Routers are composed here so :mod:`app.main` wires a single object. Operational
endpoints (health, version) are unversioned; product endpoints are mounted
under ``/api/v1``.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api.routes import system
from app.modules.activity import router as activity
from app.modules.auth import router as auth
from app.modules.explanation import router as explanation
from app.modules.library import router as library
from app.modules.processing import router as processing
from app.modules.reader import router as reader

api_router = APIRouter()

# Operational endpoints (unversioned, stable contract).
api_router.include_router(system.router)

# Versioned product API.
api_router.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
api_router.include_router(library.router, prefix="/api/v1/books", tags=["library"])
api_router.include_router(reader.router, prefix="/api/v1/books", tags=["reader"])
api_router.include_router(
    processing.router, prefix="/api/v1/books", tags=["processing"]
)
api_router.include_router(
    explanation.router, prefix="/api/v1/books", tags=["explanation"]
)
api_router.include_router(activity.router, prefix="/api/v1/activity", tags=["activity"])
