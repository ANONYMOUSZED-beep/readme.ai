"""Recognise the raster image formats accepted as book covers.

Covers are served back to clients, so their type is decided from the bytes
themselves (never from a file name or a declared type inside the book).
"""

from __future__ import annotations

# Covers larger than this are ignored rather than stored and served.
MAX_COVER_BYTES = 5 * 1024 * 1024


def sniff_image_type(data: bytes) -> str | None:
    """Return the MIME type of a JPEG/PNG/GIF/WebP image, else ``None``."""
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if len(data) >= 12 and data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    return None
