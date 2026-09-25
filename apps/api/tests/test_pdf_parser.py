"""Tests for the PyMuPDF PDF parser.

Sample PDFs are generated with PyMuPDF itself so the suite has no binary
fixtures and every input is reproducible: a simple text PDF, an image-heavy PDF,
a technical page with a monospaced code block, a large multi-page book, plus
encrypted, malformed and empty inputs.
"""

from __future__ import annotations

import pymupdf
import pytest

from app.modules.processing.document_model import (
    Chapter,
    CodeBlock,
    Document,
    ElementType,
    Image,
    Paragraph,
    Section,
)
from app.modules.processing.enums import ProcessingErrorCode
from app.modules.processing.parsers import (
    DocumentParser,
    ParserCapability,
    ParseRequest,
    ParserError,
    ParserErrorCode,
    ParserProgress,
    ParserRegistry,
    ParseStage,
    PyMuPdfParser,
)
from app.modules.processing.parsers.pdf_heuristics import BlockKind

_BODY = 11.0
_HEADING = 20.0
_SECTION = 14.0


def _request(data: bytes, filename: str = "book.pdf") -> ParseRequest:
    return ParseRequest(
        filename=filename,
        mime_type="application/pdf",
        data=data,
        source_reference=f"books/{filename}",
    )


def _parse(data: bytes, filename: str = "book.pdf") -> object:
    return PyMuPdfParser().parse(_request(data, filename))


def _png(width: int = 120, height: int = 90, shade: int = 200) -> bytes:
    """A small opaque PNG, generated without extra dependencies."""
    pixmap = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, width, height))
    pixmap.set_rect(pixmap.irect, (shade, 60, 90))
    return bytes(pixmap.tobytes("png"))


def _simple_pdf() -> bytes:
    """Chapter heading, section heading, and two body paragraphs."""
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 90), "Chapter One", fontsize=_HEADING, fontname="Helvetica")
    page.insert_text((72, 140), "Foundations", fontsize=_SECTION, fontname="Helvetica")
    page.insert_text(
        (72, 190),
        "Reading comes first. Structure serves reading.",
        fontsize=_BODY,
        fontname="Helvetica",
    )
    page.insert_text(
        (72, 230),
        "A second paragraph continues the argument here.",
        fontsize=_BODY,
        fontname="Helvetica",
    )
    data = document.tobytes()
    document.close()
    return bytes(data)


def _image_pdf(count: int = 2) -> bytes:
    """Images with captions beneath them, plus a paragraph."""
    document = pymupdf.open()
    page = document.new_page()
    payload = _png()
    top = 80.0
    for index in range(count):
        rect = pymupdf.Rect(72, top, 272, top + 150)
        page.insert_image(rect, stream=payload)
        page.insert_text(
            (72, top + 170),
            f"Figure {index + 1}. A generated illustration.",
            fontsize=9.0,
            fontname="Helvetica",
        )
        top += 220
    page.insert_text(
        (72, top + 20),
        "The figures above are decorative and are never analysed.",
        fontsize=_BODY,
        fontname="Helvetica",
    )
    data = document.tobytes()
    document.close()
    return bytes(data)


def _technical_pdf() -> bytes:
    """A monospaced code block, a bullet list, and body prose."""
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text(
        (72, 90), "Prompt Engineering", fontsize=_HEADING, fontname="Helvetica"
    )
    page.insert_text(
        (72, 130),
        "The example below shows a minimal call.",
        fontsize=_BODY,
        fontname="Helvetica",
    )
    writer = pymupdf.TextWriter(page.rect)
    writer.append(
        (72, 170),
        "def explain(word):",
        font=pymupdf.Font("cour"),
        fontsize=_BODY,
    )
    writer.append(
        (72, 186),
        "    return model.ask(word)",
        font=pymupdf.Font("cour"),
        fontsize=_BODY,
    )
    writer.write_text(page)
    page.insert_text(
        (72, 240), "\u2022 First guideline", fontsize=_BODY, fontname="Helvetica"
    )
    page.insert_text(
        (72, 256), "\u2022 Second guideline", fontsize=_BODY, fontname="Helvetica"
    )
    data = document.tobytes()
    document.close()
    return bytes(data)


def _large_pdf(pages: int = 60) -> bytes:
    """A multi-page book with per-page headings and body text."""
    document = pymupdf.open()
    for number in range(1, pages + 1):
        page = document.new_page()
        page.insert_text(
            (72, 90),
            f"Chapter {number}",
            fontsize=_HEADING,
            fontname="Helvetica",
        )
        for line in range(6):
            page.insert_text(
                (72, 140 + line * 26),
                f"Page {number} paragraph {line}. It carries readable prose.",
                fontsize=_BODY,
                fontname="Helvetica",
            )
    data = document.tobytes()
    document.close()
    return bytes(data)


def _encrypted_pdf() -> bytes:
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 90), "Secret content.", fontsize=_BODY)
    data = document.tobytes(
        encryption=pymupdf.PDF_ENCRYPT_AES_256,
        owner_pw="owner-secret",
        user_pw="user-secret",
    )
    document.close()
    return bytes(data)


def _blank_pdf() -> bytes:
    document = pymupdf.open()
    document.new_page()
    data = document.tobytes()
    document.close()
    return bytes(data)


# --- registration & capabilities -------------------------------------------
def test_parser_is_registered_and_wins_pdf_selection() -> None:
    from app.modules.processing.dependencies import get_parser_registry

    registry = ParserRegistry(list(get_parser_registry().available()))

    selected = registry.select(mime_type="application/pdf", filename="book.pdf")

    assert selected is not None
    assert selected.metadata.name == "pymupdf"
    assert isinstance(selected, DocumentParser)
    # The plain-text fallback still exists beneath it.
    assert registry.get("pdf") is not None


def test_parser_reports_rich_capabilities() -> None:
    metadata = PyMuPdfParser().metadata

    assert metadata.supports_all(
        [
            ParserCapability.TEXT,
            ParserCapability.IMAGES,
            ParserCapability.TABLES,
            ParserCapability.HYPERLINKS,
            ParserCapability.CODE_BLOCKS,
            ParserCapability.PAGE_COORDINATES,
        ]
    )
    assert metadata.priority > 0
    assert ".pdf" in metadata.supported_extensions


def test_parser_supports_pdf_by_mime_type_and_extension() -> None:
    parser = PyMuPdfParser()

    assert parser.supports(mime_type="application/pdf", filename="x.bin")
    assert parser.supports(mime_type="application/octet-stream", filename="x.pdf")
    assert not parser.supports(mime_type="text/plain", filename="x.txt")


# --- metadata & structure ---------------------------------------------------
def test_metadata_is_extracted() -> None:
    result = _parse(_simple_pdf())

    assert result.metadata.page_count == 1
    assert result.metadata.word_count > 0
    assert result.metadata.character_count == len(result.canonical_text)
    assert result.metadata.estimated_reading_minutes == 1
    # No PDF /Title, so the detected chapter heading is used.
    assert result.metadata.title == "Chapter One"


def test_headings_become_chapters_and_sections() -> None:
    result = _parse(_simple_pdf())
    document = result.document
    assert isinstance(document, Document)

    chapters = [e for e in document.elements if isinstance(e, Chapter)]
    sections = [e for e in document.elements if isinstance(e, Section)]

    assert [chapter.title for chapter in chapters] == ["Chapter One"]
    assert "Foundations" in [section.title for section in sections]


def test_paragraphs_and_sentences_are_extracted_with_spans() -> None:
    result = _parse(_simple_pdf())
    text = result.canonical_text
    paragraphs = [e for e in result.document.elements if isinstance(e, Paragraph)]

    assert len(paragraphs) == 2
    for paragraph in paragraphs:
        start = paragraph.attributes["start_offset"]
        end = paragraph.attributes["end_offset"]
        # Every span addresses the canonical text exactly.
        assert text[start:end].strip() == text[start:end]
        assert text[start:end]
    sentences = [
        element
        for element in result.document.elements
        if element.element_type == ElementType.SENTENCE
    ]
    assert len(sentences) >= 3
    for sentence in sentences:
        run = sentence.content[0]
        span = text[
            sentence.attributes["start_offset"] : sentence.attributes["end_offset"]
        ]
        assert run.text == span


def test_reading_order_follows_the_page_layout() -> None:
    result = _parse(_simple_pdf())
    text = result.canonical_text

    assert text.index("Chapter One") < text.index("Foundations")
    assert text.index("Foundations") < text.index("Reading comes first.")
    assert text.index("Reading comes first.") < text.index("A second paragraph")


# --- rich content -----------------------------------------------------------
def test_images_are_extracted_with_position_and_captions() -> None:
    result = _parse(_image_pdf())
    images = [e for e in result.document.elements if isinstance(e, Image)]

    assert len(images) == 2
    for image in images:
        assert image.image_identifier.startswith("sha256:")
        assert image.source.page_number == 1
        assert image.source.bounding_box is not None
        assert image.source.bounding_box.width > 0
        assert image.source.original_reference is not None
        assert "xref=" in image.source.original_reference
        assert image.width > 0 and image.height > 0
        assert image.attributes["byte_size"] > 0

    captions = [
        element
        for element in result.document.elements
        if element.element_type == ElementType.CAPTION
    ]
    assert len(captions) == 2
    assert images[0].caption_id == captions[0].id
    assert captions[0].content[0].text is not None
    assert captions[0].content[0].text.startswith("Figure 1")


def test_identical_images_share_one_identifier() -> None:
    result = _parse(_image_pdf())
    images = [e for e in result.document.elements if isinstance(e, Image)]

    # The same embedded XObject is hashed once and reused.
    assert images[0].image_identifier == images[1].image_identifier


def test_monospaced_block_becomes_a_code_block() -> None:
    result = _parse(_technical_pdf())
    code = [e for e in result.document.elements if isinstance(e, CodeBlock)]

    assert code
    assert "def explain" in code[0].code
    assert code[0].source.page_number == 1


def test_bulleted_block_becomes_a_list() -> None:
    result = _parse(_technical_pdf())
    lists = [
        element
        for element in result.document.elements
        if element.element_type == ElementType.LIST
    ]
    items = [
        element
        for element in result.document.elements
        if element.element_type == ElementType.LIST_ITEM
    ]

    assert lists
    assert len(items) >= 2
    assert all(item.attributes.get("start_offset") is not None for item in items)


def test_statistics_describe_the_parse() -> None:
    result = _parse(_technical_pdf())
    statistics = result.statistics

    assert statistics.chapters >= 1
    assert statistics.paragraphs >= 1
    assert statistics.code_blocks >= 1
    assert statistics.duration_ms >= 0


# --- determinism & scale ----------------------------------------------------
def test_stable_ids_are_identical_across_reprocessing() -> None:
    data = _simple_pdf()

    first = _parse(data)
    second = _parse(data)

    assert first.document == second.document
    assert first.canonical_text == second.canonical_text


def test_stable_ids_differ_per_source_reference() -> None:
    data = _simple_pdf()
    parser = PyMuPdfParser()

    first = parser.parse(_request(data, "a.pdf"))
    second = parser.parse(_request(data, "b.pdf"))

    assert first.document.id != second.document.id


def test_large_book_is_parsed_with_correct_page_order() -> None:
    result = _parse(_large_pdf())

    assert result.metadata.page_count == 60
    assert result.statistics.chapters == 60
    assert result.statistics.paragraphs >= 300
    text = result.canonical_text
    assert text.index("Page 1 paragraph 0") < text.index("Page 60 paragraph 0")


def test_progress_is_reported_per_page() -> None:
    updates: list[ParserProgress] = []

    PyMuPdfParser().parse(_request(_large_pdf(5)), updates.append)

    stages = [update.stage for update in updates]
    reading = [update for update in updates if update.stage is ParseStage.READING]
    assert stages[0] is ParseStage.STARTED
    assert stages[-1] is ParseStage.COMPLETED
    assert len(reading) == 5
    assert reading[-1].fraction == 1.0


# --- error handling ---------------------------------------------------------
def test_encrypted_pdf_is_reported_structurally() -> None:
    with pytest.raises(ParserError) as exc:
        _parse(_encrypted_pdf())

    assert exc.value.code is ParserErrorCode.ENCRYPTED_DOCUMENT
    assert exc.value.processing_code is ProcessingErrorCode.MALFORMED_FILE
    assert exc.value.parser_name == "pymupdf"


def test_malformed_pdf_is_reported_structurally() -> None:
    with pytest.raises(ParserError) as exc:
        _parse(b"%PDF-1.4 this is not really a pdf")

    assert exc.value.code is ParserErrorCode.CORRUPTED_DOCUMENT


def test_empty_input_is_reported_structurally() -> None:
    with pytest.raises(ParserError) as exc:
        _parse(b"")

    assert exc.value.code is ParserErrorCode.EMPTY_DOCUMENT


def test_pdf_without_text_is_reported_as_empty() -> None:
    with pytest.raises(ParserError) as exc:
        _parse(_blank_pdf())

    assert exc.value.code is ParserErrorCode.EMPTY_DOCUMENT
    assert "OCR" in exc.value.message


def test_scanned_pages_are_reported_as_warnings_not_failures() -> None:
    document = pymupdf.open()
    document.new_page()
    page = document.new_page()
    page.insert_text((72, 90), "Only this page has text.", fontsize=_BODY)
    data = bytes(document.tobytes())
    document.close()

    result = _parse(data)

    assert result.canonical_text
    assert any(issue.code == "page_without_content" for issue in result.warnings)


# --- heuristics -------------------------------------------------------------
def test_block_kinds_cover_the_documented_categories() -> None:
    # The classifier vocabulary is fixed; new kinds must be added deliberately.
    assert {kind.value for kind in BlockKind} == {
        "chapter_heading",
        "section_heading",
        "paragraph",
        "code",
        "quote",
        "list",
        "footnote",
        "formula",
        "caption",
    }


def test_repeated_page_furniture_is_excluded_from_the_reading_flow() -> None:
    document = pymupdf.open()
    for number in range(1, 13):
        page = document.new_page()
        # A running head and a folio repeat on every page; body text does not.
        page.insert_text((72, 40), "SQL The Complete Reference", fontsize=9.0)
        page.insert_text((520, 770), str(number), fontsize=9.0)
        page.insert_text(
            (72, 200),
            f"Body paragraph {number} carries the actual prose.",
            fontsize=_BODY,
        )
    data = bytes(document.tobytes())
    document.close()

    result = _parse(data)

    assert "SQL The Complete Reference" not in result.canonical_text
    assert "Body paragraph 7" in result.canonical_text
    assert result.statistics.paragraphs == 12
    assert any(issue.code == "repeated_furniture_removed" for issue in result.warnings)


def test_table_detection_budget_is_reported_when_exhausted() -> None:
    from app.modules.processing.parsers.pdf_blocks import extract_pdf

    document = pymupdf.open()
    for _ in range(3):
        page = document.new_page()
        page.draw_rect(pymupdf.Rect(72, 100, 400, 200))
        page.draw_line(pymupdf.Point(72, 150), pymupdf.Point(400, 150))
        page.insert_text((80, 120), "Header | Value", fontsize=_BODY)
    data = bytes(document.tobytes())
    document.close()

    # A zero budget disables detection entirely; content is still extracted.
    content = extract_pdf(data, table_budget_seconds=0.0)

    assert content.blocks
    assert not [block for block in content.blocks if hasattr(block, "rows")]
