"""Unit tests for the processor and dispatcher (no database)."""

from __future__ import annotations

import pytest

from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.processors.base import ProcessingError
from app.modules.processing.processors.pdf import PdfProcessor
from app.modules.processing.processors.plain_text import PlainTextProcessor
from app.modules.processing.registry import ProcessorRegistry

_MARKDOWN = (
    "# Chapter One\n\n"
    "Hello world. Second sentence!\n\n"
    "## Section A\n\n"
    "Another paragraph here.\n"
)


def _text_pdf(text: str = "PDF reading works.") -> bytes:
    """Build a tiny valid one-page PDF without a fixture dependency."""
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    stream = f"BT /F1 18 Tf 72 720 Td ({escaped}) Tj ET".encode("ascii")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
        ),
        b"<< /Length "
        + str(len(stream)).encode("ascii")
        + b" >>\nstream\n"
        + stream
        + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    pdf = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, body in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf.extend(f"{number} 0 obj\n".encode("ascii"))
        pdf.extend(body)
        pdf.extend(b"\nendobj\n")
    xref = len(pdf)
    pdf.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    pdf.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        pdf.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    pdf.extend(
        (
            f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref}\n%%EOF\n"
        ).encode("ascii")
    )
    return bytes(pdf)


def test_registry_selects_text_processor() -> None:
    registry = ProcessorRegistry([PlainTextProcessor()])

    assert registry.select(mime_type="text/plain", filename="a.txt") is not None
    assert registry.select(mime_type="application/pdf", filename="a.pdf") is None


def test_pdf_processor_extracts_readable_text_and_page_count() -> None:
    processor = PdfProcessor()

    assert processor.supports(mime_type="application/pdf", filename="book.bin")
    assert processor.supports(mime_type="application/octet-stream", filename="book.pdf")

    document = processor.process(
        filename="book.pdf",
        mime_type="application/pdf",
        data=_text_pdf(),
    )

    assert document.metadata.page_count == 1
    assert document.metadata.word_count == 3
    assert document.text == "PDF reading works."


def test_plain_text_builds_structure() -> None:
    processor = PlainTextProcessor()

    doc = processor.process(
        filename="book.md", mime_type="text/markdown", data=_MARKDOWN.encode()
    )

    assert len(doc.chapters) == 1
    chapter = doc.chapters[0]
    assert chapter.title == "Chapter One"
    # Default section + the "Section A" section.
    assert len(chapter.sections) == 2
    assert chapter.sections[1].title == "Section A"

    paragraphs = [p for s in chapter.sections for p in s.paragraphs]
    assert [p.text for p in paragraphs] == [
        "Hello world. Second sentence!",
        "Another paragraph here.",
    ]
    # First paragraph split into two sentences.
    assert len(paragraphs[0].sentences) == 2
    assert doc.text == "Hello world. Second sentence!\n\nAnother paragraph here."


def test_plain_text_offsets_are_consistent() -> None:
    processor = PlainTextProcessor()

    doc = processor.process(
        filename="book.txt", mime_type="text/plain", data=_MARKDOWN.encode()
    )

    for chapter in doc.chapters:
        for section in chapter.sections:
            for paragraph in section.paragraphs:
                # The stored text matches the canonical text at its offsets.
                assert (
                    doc.text[paragraph.start_offset : paragraph.end_offset]
                    == paragraph.text
                )


def test_plain_text_metadata() -> None:
    processor = PlainTextProcessor()

    doc = processor.process(
        filename="book.txt", mime_type="text/plain", data=_MARKDOWN.encode()
    )

    assert doc.metadata.title == "Chapter One"
    assert doc.metadata.word_count == 7
    assert doc.metadata.character_count == len(doc.text)
    assert doc.metadata.estimated_reading_minutes == 1
    assert doc.metadata.author is None


def test_empty_document_raises() -> None:
    processor = PlainTextProcessor()

    with pytest.raises(ProcessingError) as exc:
        processor.process(
            filename="empty.txt", mime_type="text/plain", data=b"   \n\n   "
        )

    assert exc.value.code is ProcessingErrorCode.EMPTY_DOCUMENT
