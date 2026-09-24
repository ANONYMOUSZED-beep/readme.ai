"""Unit tests for the document builder and the PDF/EPUB/text processors."""

from __future__ import annotations

import io
import zipfile

import pytest

from app.modules.processing.builder import Heading, TextBlock, build_document
from app.modules.processing.document import StructuredDocument
from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.processors.base import ProcessingError
from app.modules.processing.processors.epub import EpubProcessor
from app.modules.processing.processors.pdf import PdfProcessor, reflow_pages
from app.modules.processing.processors.plain_text import (
    PlainTextProcessor,
    decode_text,
)
from app.modules.processing.registry import ProcessorRegistry
from tests.documents import make_epub, make_pdf


def _paragraphs(document: StructuredDocument) -> list[str]:
    return [
        paragraph.text
        for chapter in document.chapters
        for section in chapter.sections
        for paragraph in section.paragraphs
    ]


def _assert_offsets_consistent(document: StructuredDocument) -> None:
    for chapter in document.chapters:
        assert document.text[chapter.start_offset : chapter.end_offset]
        for section in chapter.sections:
            for paragraph in section.paragraphs:
                span = document.text[paragraph.start_offset : paragraph.end_offset]
                assert span == paragraph.text
                for sentence in paragraph.sentences:
                    assert paragraph.start_offset <= sentence.start_offset
                    assert sentence.end_offset <= paragraph.end_offset


def _zip(members: dict[str, str]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, content in members.items():
            archive.writestr(name, content)
    return buffer.getvalue()


# --- builder -------------------------------------------------------------------
def test_builder_strips_control_characters_postgres_rejects() -> None:
    document = build_document([TextBlock("Null\x00 byte and\x07 bell.")])

    assert document.text == "Null byte and bell."


def test_builder_prunes_empty_chapters_and_sections() -> None:
    document = build_document(
        [
            Heading(1, "Part One"),
            Heading(1, "Chapter 1"),
            Heading(2, "Empty section"),
            Heading(2, "Real section"),
            TextBlock("Body."),
        ]
    )

    assert [c.title for c in document.chapters] == ["Chapter 1"]
    assert [s.title for s in document.chapters[0].sections] == ["Real section"]
    _assert_offsets_consistent(document)


def test_builder_prefers_explicit_metadata_and_bounds_it() -> None:
    document = build_document(
        [Heading(1, "Heading Title"), TextBlock("Words here.")],
        title="  Explicit\n Title ",
        author="A" * 600,
        language="en-GB",
        page_count=3,
    )

    assert document.metadata.title == "Explicit Title"
    assert document.metadata.author is not None
    assert len(document.metadata.author) == 512
    assert document.metadata.language == "en-GB"
    assert document.metadata.page_count == 3


def test_builder_raises_for_documents_without_text() -> None:
    with pytest.raises(ProcessingError) as exc:
        build_document([Heading(1, "Only a title"), TextBlock(" \x00 ")])

    assert exc.value.code is ProcessingErrorCode.EMPTY_DOCUMENT


# --- plain text ------------------------------------------------------------------
@pytest.mark.parametrize(
    ("data", "expected"),
    [
        (b"\xef\xbb\xbfHello", "Hello"),
        ("Grüße".encode("utf-16"), "Grüße"),
        ("café".encode(), "café"),
        ("café naïve résumé".encode("cp1252"), "café naïve résumé"),
    ],
)
def test_decode_text_handles_common_encodings(data: bytes, expected: str) -> None:
    assert decode_text(data) == expected


def test_decode_text_tolerates_isolated_corruption_in_utf8() -> None:
    data = ("é" * 3000).encode() + b"\xff"

    decoded = decode_text(data)

    assert decoded.startswith("é" * 3000)


def test_plain_text_treats_whitespace_only_lines_as_separators() -> None:
    data = b"First paragraph.\n   \t\nSecond paragraph."

    document = PlainTextProcessor().process(
        filename="a.txt", mime_type="text/plain", data=data
    )

    assert _paragraphs(document) == ["First paragraph.", "Second paragraph."]


def test_plain_text_detects_headings_not_isolated_by_blank_lines() -> None:
    data = b"# Chapter One\nOpening line.\n### Deep Section\nMore text.\n"

    document = PlainTextProcessor().process(
        filename="a.md", mime_type="text/markdown", data=data
    )

    assert document.chapters[0].title == "Chapter One"
    assert [s.title for s in document.chapters[0].sections] == [None, "Deep Section"]
    assert _paragraphs(document) == ["Opening line.", "More text."]


def test_plain_text_keeps_hash_inside_titles() -> None:
    document = PlainTextProcessor().process(
        filename="a.md", mime_type="text/markdown", data=b"# Learn C#\n\nBody."
    )

    assert document.chapters[0].title == "Learn C#"


def test_plain_text_form_feed_separates_paragraphs() -> None:
    document = PlainTextProcessor().process(
        filename="a.txt", mime_type="text/plain", data=b"Page one.\fPage two."
    )

    assert _paragraphs(document) == ["Page one.", "Page two."]


# --- PDF -----------------------------------------------------------------------
def test_pdf_extracts_reflowed_paragraphs_and_metadata() -> None:
    data = make_pdf(
        [
            [
                "The quick brown fox jumps over the lazy dog and keeps",
                "running far away.",
                "A second para-",
                "graph starts here and it continues on",
                "12",
            ],
            ["to the next page without a break at all in it.", "13"],
        ],
        title="A Fine PDF",
        author="Jane Writer",
    )

    document = PdfProcessor().process(
        filename="book.pdf", mime_type="application/pdf", data=data
    )

    assert _paragraphs(document) == [
        "The quick brown fox jumps over the lazy dog and keeps running far away.",
        "A second paragraph starts here and it continues on to the next page "
        "without a break at all in it.",
    ]
    assert document.metadata.title == "A Fine PDF"
    assert document.metadata.author == "Jane Writer"
    assert document.metadata.page_count == 2
    _assert_offsets_consistent(document)


def test_pdf_without_text_is_reported_as_empty() -> None:
    data = make_pdf([[], []])

    with pytest.raises(ProcessingError) as exc:
        PdfProcessor().process(filename="scan.pdf", mime_type="", data=data)

    assert exc.value.code is ProcessingErrorCode.EMPTY_DOCUMENT
    assert "scanned" in exc.value.message


def test_damaged_pdf_is_reported_as_malformed() -> None:
    with pytest.raises(ProcessingError) as exc:
        PdfProcessor().process(
            filename="bad.pdf", mime_type="application/pdf", data=b"not a pdf"
        )

    assert exc.value.code is ProcessingErrorCode.MALFORMED_FILE


def test_reflow_keeps_hyphenated_compounds_before_capitals() -> None:
    assert reflow_pages(["Anglo-\nSaxon history."]) == ["Anglo-Saxon history."]


def test_reflow_drops_page_number_headers_and_footers() -> None:
    pages = ["Page 3 of 10\nBody text that stays.\n3"]

    assert reflow_pages(pages) == ["Body text that stays."]


# --- EPUB ----------------------------------------------------------------------
def test_epub_follows_spine_and_structure() -> None:
    data = make_epub(
        [
            "<h1>The Beginning</h1><p>First &amp; foremost.</p>"
            "<h2>A Section</h2><p>Line one<br/>line two</p>",
            "<div><p>Untitled chapter text.</p></div><script>var x = 1;</script>",
        ],
        title="Spine Book",
        author="Ada Author",
        language="en",
    )

    document = EpubProcessor().process(
        filename="book.epub", mime_type="application/epub+zip", data=data
    )

    assert [c.title for c in document.chapters] == ["The Beginning", None]
    assert [s.title for s in document.chapters[0].sections] == [None, "A Section"]
    # The nav document (table of contents) is not part of the reading text.
    assert _paragraphs(document) == [
        "First & foremost.",
        "Line one\nline two",
        "Untitled chapter text.",
    ]
    assert document.metadata.title == "Spine Book"
    assert document.metadata.author == "Ada Author"
    assert document.metadata.language == "en"
    _assert_offsets_consistent(document)


def test_epub_skips_dangling_spine_entries() -> None:
    data = make_epub(
        ["<p>Real content.</p>"],
        extra_manifest=(
            '<item id="gone" href="missing.xhtml" '
            'media-type="application/xhtml+xml"/>'
        ),
        extra_spine='<itemref idref="gone"/>',
    )

    document = EpubProcessor().process(filename="b.epub", mime_type="", data=data)

    assert _paragraphs(document) == ["Real content."]


def test_drm_protected_epub_is_unsupported() -> None:
    data = make_epub(["<p>Secret.</p>"], encrypted=True)

    with pytest.raises(ProcessingError) as exc:
        EpubProcessor().process(filename="drm.epub", mime_type="", data=data)

    assert exc.value.code is ProcessingErrorCode.UNSUPPORTED_FORMAT


@pytest.mark.parametrize(
    "data",
    [
        b"not a zip file",
        # A zip archive without the EPUB container document.
        _zip({"hello.txt": "hi"}),
    ],
)
def test_invalid_epub_is_reported_as_malformed(data: bytes) -> None:
    with pytest.raises(ProcessingError) as exc:
        EpubProcessor().process(filename="bad.epub", mime_type="", data=data)

    assert exc.value.code is ProcessingErrorCode.MALFORMED_FILE


def test_epub_member_larger_than_limit_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "app.modules.processing.processors.epub._MAX_DOCUMENT_BYTES", 10
    )
    data = make_epub(["<p>This chapter is longer than ten bytes.</p>"])

    with pytest.raises(ProcessingError) as exc:
        EpubProcessor().process(filename="big.epub", mime_type="", data=data)

    assert exc.value.code is ProcessingErrorCode.TOO_LARGE


# --- registry ------------------------------------------------------------------
@pytest.mark.parametrize(
    ("mime_type", "filename", "expected"),
    [
        ("application/epub+zip", "x", "epub"),
        ("application/octet-stream", "novel.EPUB", "epub"),
        ("application/pdf", "x", "pdf"),
        ("", "paper.pdf", "pdf"),
        ("text/plain; charset=utf-8", "x", "plain_text"),
        ("", "notes.md", "plain_text"),
    ],
)
def test_registry_routes_formats_to_processors(
    mime_type: str, filename: str, expected: str
) -> None:
    registry = ProcessorRegistry(
        [EpubProcessor(), PdfProcessor(), PlainTextProcessor()]
    )

    processor = registry.select(mime_type=mime_type, filename=filename)

    assert processor is not None
    assert processor.name == expected


def test_registry_returns_none_for_unknown_formats() -> None:
    registry = ProcessorRegistry(
        [EpubProcessor(), PdfProcessor(), PlainTextProcessor()]
    )

    assert registry.select(mime_type="application/zip", filename="a.zip") is None
