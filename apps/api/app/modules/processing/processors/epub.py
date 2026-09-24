"""EPUB processor (EPUB 2 and 3), implemented with the standard library only.

Reading order comes from the package document's spine. Each spine document
starts a chapter (titled by its leading heading, when it has one); later
headings in the same document start sections, and block-level elements become
paragraphs. Archives are size-checked before anything is decompressed, and
DRM-encrypted content is reported as unsupported rather than read as garbage.
"""

from __future__ import annotations

import posixpath
import re
import zipfile
from collections.abc import Iterator
from dataclasses import dataclass, field
from html.parser import HTMLParser
from io import BytesIO
from urllib.parse import unquote
from xml.etree import ElementTree

from app.core.images import MAX_COVER_BYTES, sniff_image_type
from app.modules.processing.builder import Block, Heading, TextBlock, build_document
from app.modules.processing.document import CoverImage, StructuredDocument
from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.processors.base import ProcessingError

_EPUB_MIME_TYPE = "application/epub+zip"
_CONTAINER_PATH = "META-INF/container.xml"
_ENCRYPTION_PATH = "META-INF/encryption.xml"
_CONTENT_MEDIA_TYPES = frozenset({"application/xhtml+xml", "text/html"})

# Decompression limits: a small archive can declare enormous members (a zip
# bomb), so declared sizes are checked before any member is read.
_MAX_METADATA_BYTES = 1024 * 1024
_MAX_DOCUMENT_BYTES = 16 * 1024 * 1024
_MAX_TOTAL_BYTES = 256 * 1024 * 1024
_MAX_SPINE_ITEMS = 5000

_HEADING_TAGS = frozenset({"h1", "h2", "h3", "h4", "h5", "h6"})
_BLOCK_TAGS = frozenset(
    {
        "address",
        "article",
        "aside",
        "blockquote",
        "caption",
        "dd",
        "div",
        "dl",
        "dt",
        "figcaption",
        "figure",
        "footer",
        "header",
        "hr",
        "li",
        "main",
        "ol",
        "p",
        "pre",
        "section",
        "table",
        "td",
        "th",
        "tr",
        "ul",
    }
)
_SKIPPED_TAGS = frozenset(
    {"head", "math", "script", "style", "svg", "template", "title"}
)
_WHITESPACE = re.compile(r"\s+")


class EpubProcessor:
    """Processes EPUB e-books into a structured document."""

    @property
    def name(self) -> str:
        return "epub"

    def supports(self, *, mime_type: str, filename: str) -> bool:
        normalized = (mime_type or "").split(";", 1)[0].strip().lower()
        return normalized == _EPUB_MIME_TYPE or filename.lower().endswith(".epub")

    def process(
        self,
        *,
        filename: str,
        mime_type: str,
        data: bytes,
    ) -> StructuredDocument:
        try:
            archive = zipfile.ZipFile(BytesIO(data))
        except (zipfile.BadZipFile, ValueError) as exc:
            raise _malformed("The file is not a valid EPUB archive.") from exc

        with archive:
            try:
                package = _read_package(archive)
                blocks = list(_blocks(archive, package))
            except (KeyError, ElementTree.ParseError, zipfile.BadZipFile) as exc:
                raise _malformed("The EPUB archive is damaged or incomplete.") from exc
            cover = _read_cover(archive, package.cover)

        return build_document(
            blocks,
            title=package.title,
            author=package.author,
            language=package.language,
            cover=cover,
        )


@dataclass(slots=True)
class _Package:
    title: str | None = None
    author: str | None = None
    language: str | None = None
    documents: list[str] = field(default_factory=list)
    cover: str | None = None


def _malformed(message: str) -> ProcessingError:
    return ProcessingError(ProcessingErrorCode.MALFORMED_FILE, message)


def _local(tag: str) -> str:
    """Strip an ElementTree ``{namespace}`` prefix from a tag or attribute."""
    return tag.rsplit("}", 1)[-1]


def _read_member(archive: zipfile.ZipFile, path: str, limit: int) -> bytes:
    info = archive.getinfo(path)
    if info.file_size > limit:
        raise ProcessingError(
            ProcessingErrorCode.TOO_LARGE,
            "The EPUB contains a file that is too large to process.",
        )
    return archive.read(info)


def _parse_xml(archive: zipfile.ZipFile, path: str) -> ElementTree.Element:
    return ElementTree.fromstring(_read_member(archive, path, _MAX_METADATA_BYTES))


def _read_package(archive: zipfile.ZipFile) -> _Package:
    container = _parse_xml(archive, _CONTAINER_PATH)
    rootfile = next(
        (
            element.get("full-path")
            for element in container.iter()
            if _local(element.tag) == "rootfile" and element.get("full-path")
        ),
        None,
    )
    if not rootfile:
        raise _malformed("The EPUB does not declare a package document.")

    opf = _parse_xml(archive, rootfile)
    base = posixpath.dirname(rootfile)
    package = _Package()

    manifest: dict[str, tuple[str, str, str]] = {}
    spine: list[str] = []
    cover_id: str | None = None
    for element in opf.iter():
        tag = _local(element.tag)
        text = (element.text or "").strip()
        if tag == "title" and package.title is None and text:
            package.title = text
        elif tag == "creator" and package.author is None and text:
            package.author = text
        elif tag == "language" and package.language is None and text:
            package.language = text
        elif tag == "item" and element.get("id") and element.get("href"):
            manifest[element.get("id", "")] = (
                element.get("href", ""),
                (element.get("media-type") or "").lower(),
                element.get("properties") or "",
            )
        elif tag == "itemref" and element.get("linear", "yes") != "no":
            spine.append(element.get("idref", ""))
        elif tag == "meta" and element.get("name") == "cover":
            # EPUB 2 convention: <meta name="cover" content="manifest-id"/>.
            cover_id = cover_id or element.get("content")

    # EPUB 3 marks the cover with a manifest property; fall back to EPUB 2.
    cover_href = next(
        (
            href
            for href, _, props in manifest.values()
            if "cover-image" in props.split()
        ),
        None,
    )
    if cover_href is None and cover_id in manifest:
        cover_href = manifest[cover_id][0]
    if cover_href:
        package.cover = posixpath.normpath(
            posixpath.join(base, unquote(cover_href.split("#")[0]))
        )

    for idref in spine[:_MAX_SPINE_ITEMS]:
        item = manifest.get(idref)
        if item is None:
            continue
        href, media_type, properties = item
        if media_type not in _CONTENT_MEDIA_TYPES or "nav" in properties.split():
            continue
        path = posixpath.normpath(posixpath.join(base, unquote(href.split("#")[0])))
        if path not in package.documents:
            package.documents.append(path)

    if not package.documents:
        raise _malformed("The EPUB has no readable content documents.")
    _reject_encrypted(archive, package.documents)
    return package


def _read_cover(archive: zipfile.ZipFile, path: str | None) -> CoverImage | None:
    """Best-effort cover extraction: a missing or odd cover never fails a book."""
    if path is None:
        return None
    try:
        info = archive.getinfo(path)
        if info.file_size > MAX_COVER_BYTES:
            return None
        data = archive.read(info)
    except (KeyError, zipfile.BadZipFile, ValueError):
        return None
    media_type = sniff_image_type(data)
    return CoverImage(data=data, media_type=media_type) if media_type else None


def _reject_encrypted(archive: zipfile.ZipFile, documents: list[str]) -> None:
    """Refuse DRM-protected books (font obfuscation alone is harmless)."""
    if _ENCRYPTION_PATH not in archive.namelist():
        return
    encryption = _parse_xml(archive, _ENCRYPTION_PATH)
    encrypted = {
        posixpath.normpath(unquote(element.get("URI", "")))
        for element in encryption.iter()
        if _local(element.tag) == "CipherReference"
    }
    if encrypted.intersection(documents):
        raise ProcessingError(
            ProcessingErrorCode.UNSUPPORTED_FORMAT,
            "This EPUB is DRM-protected and cannot be read.",
        )


def _blocks(archive: zipfile.ZipFile, package: _Package) -> Iterator[Block]:
    total = 0
    for path in package.documents:
        try:
            raw = _read_member(archive, path, _MAX_DOCUMENT_BYTES)
        except KeyError:
            continue  # A dangling manifest entry: skip it, keep the rest.
        total += len(raw)
        if total > _MAX_TOTAL_BYTES:
            raise ProcessingError(
                ProcessingErrorCode.TOO_LARGE,
                "The EPUB is too large to process.",
            )
        yield from _document_blocks(raw.decode("utf-8", errors="replace"))


def _document_blocks(markup: str) -> Iterator[Block]:
    """Blocks for one spine document; it always opens a new chapter."""
    extractor = _TextExtractor()
    extractor.feed(markup)
    extractor.close()
    items = extractor.items

    if items and isinstance(items[0], Heading):
        yield Heading(level=1, title=items[0].title)
        items = items[1:]
    else:
        yield Heading(level=1, title=None)
    yield from items


class _TextExtractor(HTMLParser):
    """Collects headings and paragraph text from (X)HTML markup."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.items: list[Block] = []
        self._buffer: list[str] = []
        self._skip_depth = 0
        self._heading_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = _local(tag).lower()
        if tag in _SKIPPED_TAGS:
            self._skip_depth += 1
        elif tag == "br":
            self._buffer.append("\n")
        elif tag in _HEADING_TAGS:
            self._flush()
            self._heading_depth += 1
        elif tag in _BLOCK_TAGS:
            self._flush()

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        # Self-closing elements (``<br/>``, ``<hr/>``) have no end tag.
        tag = _local(tag).lower()
        if tag == "br":
            self._buffer.append("\n")
        elif tag in _BLOCK_TAGS:
            self._flush()

    def handle_endtag(self, tag: str) -> None:
        tag = _local(tag).lower()
        if tag in _SKIPPED_TAGS:
            self._skip_depth = max(0, self._skip_depth - 1)
        elif tag in _HEADING_TAGS:
            if self._heading_depth:
                title = self._take_text().replace("\n", " ")
                self._heading_depth -= 1
                if title:
                    self.items.append(Heading(level=2, title=title))
        elif tag in _BLOCK_TAGS:
            self._flush()

    def handle_data(self, data: str) -> None:
        if not self._skip_depth:
            self._buffer.append(_WHITESPACE.sub(" ", data))

    def close(self) -> None:
        super().close()
        self._flush()

    def _take_text(self) -> str:
        text = "".join(self._buffer)
        self._buffer = []
        return "\n".join(
            line.strip() for line in text.split("\n") if line.strip()
        ).strip()

    def _flush(self) -> None:
        if self._heading_depth:
            return  # Block tags nested inside a heading belong to its title.
        text = self._take_text()
        if text:
            self.items.append(TextBlock(text))
