"""Application-wide error model.

A single typed taxonomy maps every failure to a stable, client-facing shape.
Internal/provider errors are never leaked verbatim — they are caught by the
generic handler and reported as an opaque ``internal`` error while the detail is
logged server-side with the request's correlation id.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import get_logger, request_id_var

logger = get_logger(__name__)


class ErrorCode(StrEnum):
    """Stable, client-facing error categories."""

    VALIDATION = "validation_error"
    UNAUTHORIZED = "unauthorized"
    FORBIDDEN = "forbidden"
    NOT_FOUND = "not_found"
    CONFLICT = "conflict"
    PAYLOAD_TOO_LARGE = "payload_too_large"
    DEPENDENCY_UNAVAILABLE = "dependency_unavailable"
    INTERNAL = "internal_error"


# Maps each error category to the HTTP status code it is served with.
_STATUS_BY_CODE: dict[ErrorCode, int] = {
    ErrorCode.VALIDATION: status.HTTP_422_UNPROCESSABLE_CONTENT,
    ErrorCode.UNAUTHORIZED: status.HTTP_401_UNAUTHORIZED,
    ErrorCode.FORBIDDEN: status.HTTP_403_FORBIDDEN,
    ErrorCode.NOT_FOUND: status.HTTP_404_NOT_FOUND,
    ErrorCode.CONFLICT: status.HTTP_409_CONFLICT,
    ErrorCode.PAYLOAD_TOO_LARGE: status.HTTP_413_CONTENT_TOO_LARGE,
    ErrorCode.DEPENDENCY_UNAVAILABLE: status.HTTP_503_SERVICE_UNAVAILABLE,
    ErrorCode.INTERNAL: status.HTTP_500_INTERNAL_SERVER_ERROR,
}

# Reverse map for translating raw HTTP status codes into our error taxonomy.
_CODE_BY_STATUS: dict[int, ErrorCode] = {
    value: key for key, value in _STATUS_BY_CODE.items()
}


class AppError(Exception):
    """Base class for all expected, domain-level errors.

    Raising an :class:`AppError` (or subclass) anywhere in the request path
    produces a consistent error envelope via the registered handler.
    """

    code: ErrorCode = ErrorCode.INTERNAL

    def __init__(
        self,
        message: str,
        *,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.details = details or {}

    @property
    def status_code(self) -> int:
        return _STATUS_BY_CODE[self.code]


class NotFoundError(AppError):
    code = ErrorCode.NOT_FOUND


class ConflictError(AppError):
    code = ErrorCode.CONFLICT


class ValidationError(AppError):
    code = ErrorCode.VALIDATION


class UnauthorizedError(AppError):
    code = ErrorCode.UNAUTHORIZED


class ForbiddenError(AppError):
    code = ErrorCode.FORBIDDEN


class PayloadTooLargeError(AppError):
    code = ErrorCode.PAYLOAD_TOO_LARGE


class DependencyUnavailableError(AppError):
    code = ErrorCode.DEPENDENCY_UNAVAILABLE


def error_envelope(
    code: ErrorCode, message: str, details: dict[str, Any]
) -> dict[str, Any]:
    """Build the canonical error response body."""
    return {
        "error": {
            "code": code.value,
            "message": message,
            "details": details,
            "request_id": request_id_var.get(),
        }
    }


def register_error_handlers(app: FastAPI) -> None:
    """Register exception handlers that enforce the canonical error envelope."""

    @app.exception_handler(AppError)
    async def handle_app_error(_: Request, exc: AppError) -> JSONResponse:
        # Expected errors: logged at WARNING, returned with their mapped status.
        logger.warning(
            "Handled application error",
            extra={"error_code": exc.code.value, "detail": exc.message},
        )
        return JSONResponse(
            status_code=exc.status_code,
            content=error_envelope(exc.code, exc.message, exc.details),
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        _: Request, exc: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=_STATUS_BY_CODE[ErrorCode.VALIDATION],
            content=error_envelope(
                ErrorCode.VALIDATION,
                "Request validation failed.",
                {"errors": jsonable_encoder(exc.errors())},
            ),
        )

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_exception(
        _: Request, exc: StarletteHTTPException
    ) -> JSONResponse:
        # Framework-raised HTTP errors (e.g. 404, 405) are normalised into the
        # canonical envelope so clients see one consistent error shape.
        code = _CODE_BY_STATUS.get(exc.status_code, ErrorCode.INTERNAL)
        message = exc.detail if isinstance(exc.detail, str) else "Request failed."
        return JSONResponse(
            status_code=exc.status_code,
            content=error_envelope(code, message, {}),
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(_: Request, exc: Exception) -> JSONResponse:
        # Unexpected errors: full detail logged, opaque message returned.
        logger.exception(
            "Unhandled exception",
            extra={"error_type": type(exc).__name__},
        )
        return JSONResponse(
            status_code=_STATUS_BY_CODE[ErrorCode.INTERNAL],
            content=error_envelope(
                ErrorCode.INTERNAL,
                "An unexpected error occurred.",
                {},
            ),
        )
