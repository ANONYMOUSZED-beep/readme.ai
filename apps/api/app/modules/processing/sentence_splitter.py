"""Deterministic sentence segmentation shared by every text extractor.

Splits on terminal punctuation followed by whitespace. No language model, no
AI — the same input always produces the same spans, which is what stable
sentence anchors require.
"""

from __future__ import annotations

_TERMINALS = ".!?"


def split_sentences(text: str) -> list[tuple[int, int]]:
    """Return trimmed ``(start, end)`` spans of sentences within ``text``."""
    spans: list[tuple[int, int]] = []
    length = len(text)
    index = 0
    start: int | None = None

    while index < length:
        char = text[index]
        if start is None and not char.isspace():
            start = index
        if char in _TERMINALS:
            end = index + 1
            while end < length and text[end] in _TERMINALS:
                end += 1
            boundary = end >= length or text[end].isspace()
            if boundary and start is not None:
                spans.append((start, end))
                start = None
            index = end
            continue
        index += 1

    if start is not None:
        end = length
        while end > start and text[end - 1].isspace():
            end -= 1
        spans.append((start, end))

    if not spans and text.strip():
        return [(0, len(text.rstrip()))]
    return spans
