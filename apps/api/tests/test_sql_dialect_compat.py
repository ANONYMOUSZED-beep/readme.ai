"""Dialect compatibility guards for hand-built SQL expressions.

The test suite runs on SQLite; production runs on PostgreSQL. SQLite resolves
function arguments loosely, so a query that is well-formed there can still fail
at runtime on PostgreSQL with ``function ... does not exist``. This module
compiles the affected statements against the PostgreSQL dialect and pins the
properties that make them resolvable there.

Guarded regression: ``DocumentStore.spans_overlapping_types`` slices the
canonical text with ``substr``. The offset columns are ``BIGINT``, and
PostgreSQL only defines ``substr(text, int, int)``, so both numeric arguments
must reach the database already cast to ``INTEGER``.
"""

from __future__ import annotations

import re
import uuid
from typing import Any, cast

import pytest
from sqlalchemy.dialects import postgresql
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import Select

from app.modules.processing.document_store import CONTEXT_TYPES, DocumentStore

_SUBSTR_CALL = re.compile(r"substr\((.*?)\) AS text", re.IGNORECASE | re.DOTALL)


class _EmptyResult:
    def all(self) -> list[Any]:
        return []


class _RecordingSession:
    """Captures the statement instead of executing it."""

    def __init__(self) -> None:
        self.statements: list[Select[Any]] = []

    async def execute(self, statement: Select[Any]) -> _EmptyResult:
        self.statements.append(statement)
        return _EmptyResult()


async def _captured_span_query() -> str:
    session = _RecordingSession()
    store = DocumentStore(cast(AsyncSession, session))
    await store.spans_overlapping_types(uuid.uuid4(), CONTEXT_TYPES, 100, 200)
    assert len(session.statements) == 1
    compiled = session.statements[0].compile(  # type: ignore[no-untyped-call]
        dialect=postgresql.dialect(),
        compile_kwargs={"literal_binds": True},
    )
    return str(compiled)


@pytest.mark.asyncio
async def test_span_query_compiles_for_postgresql() -> None:
    """The statement is valid PostgreSQL, not just valid SQLite."""
    sql = await _captured_span_query()
    assert "substr(" in sql.lower()
    assert "document_elements" in sql
    assert "documents.text" in sql


@pytest.mark.asyncio
async def test_substr_offsets_are_cast_to_integer() -> None:
    """Both numeric ``substr`` arguments are cast, so no BIGINT reaches it.

    PostgreSQL has no ``substr(text, bigint, bigint)`` overload. Passing the
    offset columns through uncast raises ``UndefinedFunctionError`` on the first
    explanation request, which is exactly the failure this pins.
    """
    sql = await _captured_span_query()
    match = _SUBSTR_CALL.search(sql)
    assert match is not None, f"substr projection not found in:\n{sql}"

    arguments = match.group(1)
    # First argument is the text column; the two numeric arguments follow.
    assert arguments.upper().count("AS INTEGER") == 2, arguments
    assert "start_offset + 1" in arguments
    assert "end_offset" in arguments
