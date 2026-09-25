"""Explanation provider abstraction and the Ollama implementation.

The reader and service depend only on :class:`ExplanationProvider`; the concrete
Ollama transport is quarantined here (ADR 0003), so the model/provider can be
swapped without touching the service or reader.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol

import httpx


class ExplanationErrorCode(StrEnum):
    """Structured reasons an explanation could not be produced."""

    UNSUPPORTED_MODEL = "unsupported_model"
    TIMEOUT = "timeout"
    INVALID_RESPONSE = "invalid_response"
    UNAVAILABLE = "unavailable"


class ExplanationError(Exception):
    """A structured provider failure."""

    def __init__(self, code: ExplanationErrorCode, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True, slots=True)
class GeneratedExplanation:
    """Raw explanation fields returned by a provider."""

    meaning: str
    explanation: str
    example: str


class ExplanationProvider(Protocol):
    """Produces an explanation from a fully-rendered prompt."""

    async def explain(self, *, prompt: str) -> GeneratedExplanation:
        """Return a generated explanation, or raise :class:`ExplanationError`."""
        ...


class OllamaExplanationProvider:
    """Generates explanations via a local/remote Ollama server."""

    def __init__(self, *, base_url: str, model: str, timeout_seconds: float) -> None:
        self._base_url = base_url.rstrip("/")
        self._model = model
        self._timeout = timeout_seconds

    async def explain(self, *, prompt: str) -> GeneratedExplanation:
        payload = {
            "model": self._model,
            "prompt": prompt,
            "stream": False,
            "format": "json",
        }
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(
                    f"{self._base_url}/api/generate", json=payload
                )
                response.raise_for_status()
                body = response.json()
        except httpx.TimeoutException as exc:
            raise ExplanationError(
                ExplanationErrorCode.TIMEOUT, "The model timed out."
            ) from exc
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == httpx.codes.NOT_FOUND:
                raise ExplanationError(
                    ExplanationErrorCode.UNSUPPORTED_MODEL,
                    f"Model '{self._model}' is not available.",
                ) from exc
            raise ExplanationError(
                ExplanationErrorCode.UNAVAILABLE, "The model is unavailable."
            ) from exc
        except httpx.HTTPError as exc:
            raise ExplanationError(
                ExplanationErrorCode.UNAVAILABLE, "The model is unavailable."
            ) from exc
        except ValueError as exc:  # the server did not answer with JSON
            raise ExplanationError(
                ExplanationErrorCode.INVALID_RESPONSE, "Malformed model response."
            ) from exc

        if not isinstance(body, dict):
            raise ExplanationError(
                ExplanationErrorCode.INVALID_RESPONSE, "Unexpected model response."
            )
        return _parse(body.get("response"))


def _parse(raw: object) -> GeneratedExplanation:
    if not isinstance(raw, str) or not raw.strip():
        raise ExplanationError(
            ExplanationErrorCode.INVALID_RESPONSE, "Empty model response."
        )
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError) as exc:
        raise ExplanationError(
            ExplanationErrorCode.INVALID_RESPONSE, "Malformed model response."
        ) from exc
    if not isinstance(data, dict):
        raise ExplanationError(
            ExplanationErrorCode.INVALID_RESPONSE, "Unexpected model response."
        )
    return GeneratedExplanation(
        meaning=_text_field(data, "meaning"),
        explanation=_text_field(data, "explanation"),
        example=_text_field(data, "example"),
    )


def _text_field(data: dict[str, object], key: str) -> str:
    """Read a string field; a missing, null, or non-string value is empty.

    Models occasionally emit ``null`` or a nested object for a field; coercing
    those with ``str()`` would show the reader "None" or a Python repr.
    """
    value = data.get(key)
    return value.strip() if isinstance(value, str) else ""
