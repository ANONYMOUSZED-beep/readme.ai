"""Plain-text processor: the dependency-free structured processor.

Builds the Document -> Chapter -> Section -> Paragraph -> Sentence hierarchy from
a text file using deterministic, non-AI heuristics:

* Markdown-style ATX heading lines (``#`` .. ``######``) become structure:
  ``#`` starts a chapter, deeper levels start a section.
* Blocks separated by blank (or whitespace-only) lines become paragraphs.
* Paragraphs are split into sentences on terminal punctuation.

Text is decoded tolerantly: a UTF-8/UTF-16 byte-order mark is honoured, valid
UTF-8 is preferred, and legacy single-byte files fall back to Windows-1252.
"""

from __future__ import annotations

import codecs
import re
from collections.abc import Iterator

from app.modules.processing.builder import Block, Heading, TextBlock, build_document
from app.modules.processing.document import StructuredDocument

_TEXT_MIME_TYPES = frozenset(
    {
        "text/plain",
        "text/markdown",
        "application/json",
        "application/xml",
        "text/xml",
    }
)
_TEXT_SUFFIXES = frozenset({".txt", ".md", ".markdown", ".text"})

_BLANK_LINE = re.compile(r"\n[ \t]*\n")
# An optional closing ``#`` run only counts when preceded by whitespace, so a
# title such as "Learn C#" keeps its trailing hash (CommonMark semantics).
_ATX_HEADING = re.compile(r"^(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")

# Tolerated share of undecodable bytes before a file is treated as legacy
# single-byte text rather than UTF-8 with a few corrupt sequences.
_MAX_INVALID_UTF8_RATIO = 0.001


class PlainTextProcessor:
    """Processes already-textual files into a structured document."""

    @property
    def name(self) -> str:
        return "plain_text"

    def supports(self, *, mime_type: str, filename: str) -> bool:
        normalized = (mime_type or "").split(";", 1)[0].strip().lower()
        return normalized in _TEXT_MIME_TYPES or _suffix(filename) in _TEXT_SUFFIXES

    def process(
        self,
        *,
        filename: str,
        mime_type: str,
        data: bytes,
    ) -> StructuredDocument:
        text = decode_text(data)
        normalized = (
            text.replace("\r\n", "\n").replace("\r", "\n").replace("\f", "\n\n")
        )
        return build_document(_blocks(normalized))


def decode_text(data: bytes) -> str:
    """Decode bytes of unknown encoding into text, never raising."""
    if data.startswith(codecs.BOM_UTF8):
        return data[len(codecs.BOM_UTF8) :].decode("utf-8", errors="replace")
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return data.decode("utf-16", errors="replace")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        pass
    lenient = data.decode("utf-8", errors="replace")
    invalid = lenient.count("�")
    if invalid <= max(1, int(len(data) * _MAX_INVALID_UTF8_RATIO)):
        return lenient
    return data.decode("cp1252", errors="replace")


def _blocks(text: str) -> Iterator[Block]:
    for chunk in _BLANK_LINE.split(text):
        body: list[str] = []
        for line in chunk.split("\n"):
            heading = _heading(line)
            if heading is None:
                body.append(line)
                continue
            if body:
                yield TextBlock("\n".join(body))
                body = []
            yield heading
        if body:
            yield TextBlock("\n".join(body))


def _heading(line: str) -> Heading | None:
    match = _ATX_HEADING.match(line.strip())
    if match is None:
        return None
    level = 1 if len(match.group(1)) == 1 else 2
    return Heading(level=level, title=match.group(2) or None)


def _suffix(filename: str) -> str:
    dot = filename.rfind(".")
    return filename[dot:].lower() if dot != -1 else ""
