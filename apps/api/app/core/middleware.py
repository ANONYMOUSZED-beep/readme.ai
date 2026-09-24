"""HTTP middleware.

The correlation-id middleware assigns (or honours a well-formed inbound)
``X-Request-ID`` for every request, exposes it on the response, and binds it to
the logging context so all log lines for that request are correlated. It also
applies baseline security headers and converts any unhandled exception into the
canonical ``internal_error`` envelope *while the request id is still bound*, so
even a 500 can be correlated with the server-side log line.
"""

from __future__ import annotations

import re
import time
import uuid
from collections.abc import Awaitable, Callable

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.errors import ErrorCode, error_envelope
from app.core.logging import get_logger, request_id_var

logger = get_logger("app.request")

_REQUEST_ID_HEADER = "X-Request-ID"

# Inbound ids are echoed into logs and headers, so only short, printable,
# token-like values are honoured; anything else is replaced with a fresh id.
_VALID_REQUEST_ID = re.compile(r"^[A-Za-z0-9._\-]{1,128}$")

# Conservative defaults for a JSON API. None of these affect API clients; they
# harden any response that ends up rendered by a browser.
_SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
}


def _resolve_request_id(inbound: str | None) -> str:
    if inbound and _VALID_REQUEST_ID.fullmatch(inbound):
        return inbound
    return uuid.uuid4().hex


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Attach a correlation id and emit a structured access log per request."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = _resolve_request_id(request.headers.get(_REQUEST_ID_HEADER))
        token = request_id_var.set(request_id)
        start = time.perf_counter()
        try:
            try:
                response = await call_next(request)
            except Exception as exc:
                # Handled here rather than by the outermost server-error
                # handler so the envelope and log line carry the request id.
                logger.exception(
                    "Unhandled exception",
                    extra={"error_type": type(exc).__name__},
                )
                response = JSONResponse(
                    status_code=500,
                    content=error_envelope(
                        ErrorCode.INTERNAL, "An unexpected error occurred.", {}
                    ),
                )

            elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
            response.headers[_REQUEST_ID_HEADER] = request_id
            for header, value in _SECURITY_HEADERS.items():
                response.headers.setdefault(header, value)
            logger.info(
                "request.completed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": elapsed_ms,
                },
            )
            return response
        finally:
            request_id_var.reset(token)
