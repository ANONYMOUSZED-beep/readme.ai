"""Helpers that keep untrusted text inside a prompt's delimiters."""

from __future__ import annotations

import re

_TRIPLE_QUOTES = re.compile(r'"{3,}')


def fence_safe(text: str) -> str:
    """Collapse runs of three or more double quotes into one.

    Prompts wrap book text in triple-quoted fences. Book content is untrusted,
    so a passage containing ``\"\"\"`` could otherwise close the fence early and
    have the text that follows read as instructions.
    """
    return _TRIPLE_QUOTES.sub('"', text)
