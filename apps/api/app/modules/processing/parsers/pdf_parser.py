"""PyMuPDF-backed PDF parser.

Pipeline: ``PDF bytes -> pdf_blocks (PyMuPDF) -> pdf_heuristics -> Document
Model``. The parser knows nothing about HTTP, the database, the reader, the
Explanation Engine, or the Learning Intelligence Engine.

Two invariants shape the implementation:

* **Reading order first.** Blocks are consumed in visual reading order and every
  readable element contributes to the canonical text in that order, so the
  reading flow is correct even where structural detection is uncertain.
* **Deterministic identity.** Element IDs come from :class:`StableIdFactory`
  using structural paths, so reprocessing an unchanged PDF yields identical IDs.
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass, field

from app.modules.processing.document import DocumentMetadata
from app.modules.processing.document_model import (
    Caption,
    Chapter,
    CodeBlock,
    Document,
    DocumentElement,
    DocumentList,
    ElementType,
    Footnote,
    Formula,
    Hyperlink,
    Image,
    InlineContent,
    InlineType,
    ListItem,
    Metadata,
    Paragraph,
    Quote,
    Section,
    Sentence,
    SourceLocation,
    StableIdFactory,
    Table,
    TableCell,
    TableRow,
)
from app.modules.processing.parsers.base import (
    ParserCapability,
    ParseRequest,
    ParserError,
    ParserErrorCode,
    ParseResult,
    ParserIssue,
    ParserMetadata,
    ParserProgress,
    ParseStage,
    ParseStatistics,
    ProgressCallback,
)
from app.modules.processing.parsers.pdf_blocks import (
    ImageBlock,
    LinkBlock,
    PdfContent,
    Rect,
    TableBlock,
    TextBlock,
    extract_pdf,
)
from app.modules.processing.parsers.pdf_heuristics import (
    BlockKind,
    classify,
    flow_text,
    footnote_reference,
    in_page_margin,
    is_caption,
    is_heading,
    is_page_folio,
    list_items,
    measure,
    repetition_key,
)
from app.modules.processing.sentence_splitter import split_sentences

_NAME = "pymupdf"
_PDF_MIME_TYPES = frozenset({"application/pdf", "application/x-pdf"})
_PDF_SUFFIXES = frozenset({".pdf"})
_SEPARATOR = "\n\n"
_WORDS_PER_MINUTE = 200
_CELL_SEPARATOR = " | "
# Running-header detection only applies to documents long enough for repetition
# to be meaningful, and needs several identical occurrences.
_RUNNING_MIN_PAGES = 8
_RUNNING_MIN_REPEATS = 4
_FURNITURE_MAX_CHARS = 80


class _TextStream:
    """Builds the canonical reading text and hands out the span of each part."""

    def __init__(self) -> None:
        self._parts: list[str] = []
        self._length = 0

    def add(self, text: str) -> tuple[int, int]:
        start = self._length + (len(_SEPARATOR) if self._parts else 0)
        self._parts.append(text)
        self._length = start + len(text)
        return start, self._length

    @property
    def text(self) -> str:
        return _SEPARATOR.join(self._parts)


@dataclass(slots=True)
class _SectionBuilder:
    """Accumulates one section's children and the span they cover."""

    id: str
    index: int
    title: str | None
    page_number: int
    #: Every element below this section, direct children and descendants alike.
    elements: list[DocumentElement] = field(default_factory=list)
    #: Direct-child count, kept separate so sibling order stays contiguous.
    child_count: int = 0
    start: int | None = None
    end: int | None = None

    def claim(self) -> int:
        """Reserve the next direct-child order index."""
        order = self.child_count
        self.child_count += 1
        return order

    def cover(self, start: int, end: int) -> None:
        self.start = start if self.start is None else min(self.start, start)
        self.end = end if self.end is None else max(self.end, end)


@dataclass(slots=True)
class _ChapterBuilder:
    """Accumulates one chapter's sections and the span they cover."""

    id: str
    index: int
    title: str | None
    page_number: int
    sections: list[_SectionBuilder] = field(default_factory=list)
    start: int | None = None
    end: int | None = None

    def cover(self, start: int, end: int) -> None:
        self.start = start if self.start is None else min(self.start, start)
        self.end = end if self.end is None else max(self.end, end)

    def span(self) -> tuple[int, int] | None:
        """The span covering this chapter's heading and all of its content."""
        starts = [s.start for s in self.sections if s.start is not None]
        ends = [s.end for s in self.sections if s.end is not None]
        if self.start is not None:
            starts.append(self.start)
        if self.end is not None:
            ends.append(self.end)
        return (min(starts), max(ends)) if starts and ends else None


def _span(start: int, end: int) -> dict[str, int]:
    return {"start_offset": start, "end_offset": end}


def _source(
    page_number: int,
    bbox: Rect | None = None,
    reference: str | None = None,
) -> SourceLocation:
    """Source metadata: page, geometry, and PDF reference — never hierarchy."""
    box = None
    if bbox is not None:
        box = {
            "x": bbox[0],
            "y": bbox[1],
            "width": max(bbox[2] - bbox[0], 0.0),
            "height": max(bbox[3] - bbox[1], 0.0),
            "coordinate_space": "pdf_points",
        }
    return SourceLocation(
        page_number=page_number,
        bounding_box=box,
        original_reference=reference or f"pdf:page={page_number}",
    )


def _text_runs(text: str) -> tuple[InlineContent, ...]:
    return (InlineContent(inline_type=InlineType.TEXT, text=text),) if text else ()


class _DocumentAssembler:
    """Turns ordered PDF blocks into a validated Document Model."""

    def __init__(self, content: PdfContent, *, source_reference: str) -> None:
        self._content = content
        self._source_reference = source_reference
        self._ids = StableIdFactory(source_reference)
        self._document_id = self._ids.document_id
        self._stream = _TextStream()
        self._chapters: list[_ChapterBuilder] = []
        self._issues: list[ParserIssue] = []

    # --- containers ----------------------------------------------------------
    def _new_chapter(self, title: str | None, page_number: int) -> _ChapterBuilder:
        index = len(self._chapters)
        chapter = _ChapterBuilder(
            id=self._ids.element_id(ElementType.CHAPTER, (index,)),
            index=index,
            title=title,
            page_number=page_number,
        )
        self._chapters.append(chapter)
        return chapter

    def _new_section(
        self,
        chapter: _ChapterBuilder,
        title: str | None,
        page_number: int,
    ) -> _SectionBuilder:
        index = len(chapter.sections)
        section = _SectionBuilder(
            id=self._ids.element_id(ElementType.SECTION, (chapter.index, index)),
            index=index,
            title=title,
            page_number=page_number,
        )
        chapter.sections.append(section)
        return section

    def _current_section(self, page_number: int) -> _SectionBuilder:
        """The section content belongs to, creating implicit containers.

        A PDF may begin with body text before any detectable heading, so an
        untitled chapter and section are created on demand. Structure is never
        required for content to be preserved in reading order.
        """
        if not self._chapters:
            self._new_chapter(None, page_number)
        chapter = self._chapters[-1]
        if not chapter.sections:
            self._new_section(chapter, None, page_number)
        return chapter.sections[-1]

    def _element_id(
        self,
        element_type: ElementType,
        section: _SectionBuilder,
        order: int,
    ) -> str:
        chapter = self._chapters[-1]
        return self._ids.element_id(
            element_type,
            (chapter.index, section.index, order),
        )

    def _child_id(
        self,
        element_type: ElementType,
        section: _SectionBuilder,
        parent_order: int,
        *path: int,
    ) -> str:
        chapter = self._chapters[-1]
        return self._ids.element_id(
            element_type,
            (chapter.index, section.index, parent_order, *path),
        )

    # --- content -------------------------------------------------------------
    def _add_paragraph(self, block: TextBlock, text: str) -> None:
        section = self._current_section(block.page_number)
        order = section.claim()
        start, end = self._stream.add(text)
        section.cover(start, end)
        paragraph_id = self._element_id(ElementType.PARAGRAPH, section, order)
        paragraph = Paragraph(
            id=paragraph_id,
            parent_id=section.id,
            order_index=order,
            source=_source(block.page_number, block.bbox),
            attributes=_span(start, end),
        )
        section.elements.append(paragraph)
        for index, (sentence_start, sentence_end) in enumerate(split_sentences(text)):
            section.elements.append(
                Sentence(
                    id=self._child_id(ElementType.SENTENCE, section, order, index),
                    parent_id=paragraph_id,
                    order_index=index,
                    content=_text_runs(text[sentence_start:sentence_end]),
                    source=_source(block.page_number, block.bbox),
                    attributes=_span(start + sentence_start, start + sentence_end),
                )
            )

    def _add_simple(
        self,
        block: TextBlock,
        text: str,
        kind: BlockKind,
    ) -> None:
        """Add a single-span element whose text joins the reading flow."""
        section = self._current_section(block.page_number)
        order = section.claim()
        start, end = self._stream.add(text)
        section.cover(start, end)
        source = _source(block.page_number, block.bbox)
        attributes = _span(start, end)
        element: DocumentElement

        if kind is BlockKind.CODE:
            element = CodeBlock(
                id=self._element_id(ElementType.CODE_BLOCK, section, order),
                parent_id=section.id,
                order_index=order,
                code=text,
                language=None,
                source=source,
                attributes=attributes,
            )
        elif kind is BlockKind.QUOTE:
            element = Quote(
                id=self._element_id(ElementType.QUOTE, section, order),
                parent_id=section.id,
                order_index=order,
                content=_text_runs(text),
                source=source,
                attributes=attributes,
            )
        elif kind is BlockKind.FORMULA:
            element = Formula(
                id=self._element_id(ElementType.FORMULA, section, order),
                parent_id=section.id,
                order_index=order,
                original_representation=text,
                representation_format="pdf_text",
                source=source,
                attributes=attributes,
            )
        else:
            reference = footnote_reference(text)
            element = Footnote(
                id=self._element_id(ElementType.FOOTNOTE, section, order),
                parent_id=section.id,
                order_index=order,
                reference_id=reference or f"p{block.page_number}-{order}",
                label=reference,
                content=_text_runs(text),
                source=source,
                attributes=attributes,
            )
        section.elements.append(element)

    def _add_list(self, block: TextBlock) -> None:
        items = list_items(block)
        if not items:
            return
        section = self._current_section(block.page_number)
        order = section.claim()
        source = _source(block.page_number, block.bbox)
        list_id = self._element_id(ElementType.LIST, section, order)
        ordered = any(character.isdigit() for character in items[0][:3])
        container = DocumentList(
            id=list_id,
            parent_id=section.id,
            order_index=order,
            ordered=ordered,
            source=source,
        )
        section.elements.append(container)
        for index, item in enumerate(items):
            start, end = self._stream.add(item)
            section.cover(start, end)
            section.elements.append(
                ListItem(
                    id=self._child_id(ElementType.LIST_ITEM, section, order, index),
                    parent_id=list_id,
                    order_index=index,
                    content=_text_runs(item),
                    source=source,
                    attributes=_span(start, end),
                )
            )

    def _add_image(self, block: ImageBlock, caption: TextBlock | None) -> None:
        section = self._current_section(block.page_number)
        order = section.claim()
        image_id = self._element_id(ElementType.IMAGE, section, order)
        caption_id = (
            self._child_id(ElementType.CAPTION, section, order, 0)
            if caption is not None
            else None
        )
        section.elements.append(
            Image(
                id=image_id,
                parent_id=section.id,
                order_index=order,
                image_identifier=block.identifier,
                caption_id=caption_id,
                media_type=block.media_type,
                width=float(block.width),
                height=float(block.height),
                source=_source(block.page_number, block.bbox, block.reference),
                # Byte size is recorded; bytes themselves are never retained.
                attributes={"byte_size": block.byte_size},
            )
        )
        if caption is None or caption_id is None:
            return
        text = flow_text(caption)
        start, end = self._stream.add(text)
        section.cover(start, end)
        section.elements.append(
            Caption(
                id=caption_id,
                parent_id=image_id,
                order_index=0,
                describes_id=image_id,
                content=_text_runs(text),
                source=_source(caption.page_number, caption.bbox),
                attributes=_span(start, end),
            )
        )

    def _add_table(self, block: TableBlock) -> None:
        section = self._current_section(block.page_number)
        order = section.claim()
        source = _source(block.page_number, block.bbox)
        table_id = self._element_id(ElementType.TABLE, section, order)
        table_start: int | None = None
        table_end = 0
        rows: list[DocumentElement] = []

        for row_index, row in enumerate(block.rows):
            # Each row joins the reading flow as one line, so table content stays
            # readable while cells keep their own spans and structure.
            line = _CELL_SEPARATOR.join(row)
            line_start, line_end = self._stream.add(line)
            table_start = line_start if table_start is None else table_start
            table_end = line_end
            row_id = self._child_id(ElementType.TABLE_ROW, section, order, row_index)
            rows.append(
                TableRow(
                    id=row_id,
                    parent_id=table_id,
                    order_index=row_index,
                    source=source,
                    attributes=_span(line_start, line_end),
                )
            )
            cursor = line_start
            for cell_index, cell in enumerate(row):
                cell_start = cursor
                cell_end = cell_start + len(cell)
                cursor = cell_end + len(_CELL_SEPARATOR)
                rows.append(
                    TableCell(
                        id=self._child_id(
                            ElementType.TABLE_CELL,
                            section,
                            order,
                            row_index,
                            cell_index,
                        ),
                        parent_id=row_id,
                        order_index=cell_index,
                        content=_text_runs(cell),
                        is_header=row_index == 0,
                        source=source,
                        attributes=_span(cell_start, cell_end),
                    )
                )

        if table_start is None:
            return
        section.cover(table_start, table_end)
        section.elements.append(
            Table(
                id=table_id,
                parent_id=section.id,
                order_index=order,
                source=source,
                attributes=_span(table_start, table_end),
            )
        )
        section.elements.extend(rows)

    def _add_link(self, link: LinkBlock) -> None:
        """Hyperlinks are structural annotations, not reading-flow text.

        Their label already appears inside the surrounding paragraph, so they
        carry no span — recording one would duplicate document characters.
        """
        section = self._current_section(link.page_number)
        order = section.claim()
        section.elements.append(
            Hyperlink(
                id=self._element_id(ElementType.HYPERLINK, section, order),
                parent_id=section.id,
                order_index=order,
                target=link.uri,
                content=_text_runs(link.text),
                source=_source(link.page_number, link.bbox),
            )
        )

    # --- assembly ------------------------------------------------------------
    def build(self) -> tuple[Document, str, tuple[ParserIssue, ...]]:
        """Walk the blocks in reading order and assemble the document."""
        blocks = list(self._content.blocks)
        body_size = self._content.body_font_size or 0.0
        page_left = self._page_left(blocks)
        running = self._running_text(blocks, body_size, page_left)
        chapter_size = self._chapter_size(blocks, body_size, page_left, running)
        index = 0

        while index < len(blocks):
            block = blocks[index]
            index += 1

            if isinstance(block, ImageBlock):
                caption, consumed = self._lookahead_caption(blocks, index)
                self._add_image(block, caption)
                index += consumed
                continue
            if isinstance(block, TableBlock):
                self._add_table(block)
                continue

            text = flow_text(block)
            if not text or repetition_key(text) in running:
                continue
            style = measure(
                block,
                body_size=body_size or style_fallback(block),
                page_left=page_left.get(block.page_number, block.bbox[0]),
            )
            # A bare page number in the margin is furniture, not reading content.
            if in_page_margin(style) and is_page_folio(text):
                continue
            kind = classify(block, style, text, chapter_size=chapter_size)

            if kind is BlockKind.CHAPTER_HEADING:
                chapter = self._new_chapter(text, block.page_number)
                # Heading text stays in the reading flow as well as becoming a
                # title, so the reader never loses a heading from the page.
                chapter.cover(*self._stream.add(text))
                self._new_section(chapter, None, block.page_number)
            elif kind is BlockKind.SECTION_HEADING:
                if not self._chapters:
                    self._new_chapter(None, block.page_number)
                section = self._new_section(self._chapters[-1], text, block.page_number)
                section.cover(*self._stream.add(text))
            elif kind is BlockKind.LIST:
                self._add_list(block)
            elif kind in (
                BlockKind.CODE,
                BlockKind.QUOTE,
                BlockKind.FORMULA,
                BlockKind.FOOTNOTE,
            ):
                self._add_simple(block, text, kind)
            else:
                # Captions without an image, and everything ambiguous, stay
                # paragraphs so the reading flow is never dropped.
                self._add_paragraph(block, text)

        for link in self._content.links:
            self._add_link(link)

        return self._finalize()

    @staticmethod
    def _page_left(
        blocks: list[TextBlock | ImageBlock | TableBlock],
    ) -> dict[int, float]:
        """Left text margin per page, used to measure indentation."""
        margins: dict[int, float] = {}
        for block in blocks:
            if not isinstance(block, TextBlock):
                continue
            current = margins.get(block.page_number)
            if current is None or block.bbox[0] < current:
                margins[block.page_number] = block.bbox[0]
        return margins

    def _running_text(
        self,
        blocks: list[TextBlock | ImageBlock | TableBlock],
        body_size: float,
        page_left: dict[int, float],
    ) -> frozenset[str]:
        """Repeated page furniture, which is layout rather than content.

        Running heads, footers and vertical side tabs ("PART VI") repeat the same
        short line on many pages. Position alone cannot identify them — side tabs
        sit mid-page on the outer edge — so repetition is the signal: a short line
        whose exact text recurs across several pages is furniture. Keeping it
        would repeat the same words hundreds of times in the reading flow and
        promote every page to a chapter.
        """
        page_count = self._content.metadata.page_count
        if page_count < _RUNNING_MIN_PAGES:
            return frozenset()

        pages_by_key: dict[str, set[int]] = {}
        for block in blocks:
            if not isinstance(block, TextBlock):
                continue
            text = flow_text(block)
            if not text or len(text) > _FURNITURE_MAX_CHARS:
                continue
            key = repetition_key(text)
            if key:
                pages_by_key.setdefault(key, set()).add(block.page_number)

        # A running head repeats identically across a run of pages; a per-chapter
        # head may only cover part of the book, so the threshold is absolute.
        repeated = {
            key
            for key, pages in pages_by_key.items()
            if len(pages) >= _RUNNING_MIN_REPEATS
        }
        if repeated:
            self._issues.append(
                ParserIssue(
                    code="repeated_furniture_removed",
                    message=(
                        f"{len(repeated)} repeated layout lines (running heads, "
                        "footers, side tabs) were excluded from the reading flow."
                    ),
                )
            )
        return frozenset(repeated)

    @staticmethod
    def _chapter_size(
        blocks: list[TextBlock | ImageBlock | TableBlock],
        body_size: float,
        page_left: dict[int, float],
        running: frozenset[str],
    ) -> float | None:
        """The largest heading font size in the document, if it has headings.

        Heading tiers are a property of the document, not of a single block, so
        the top tier is measured once and reused for every chapter decision.
        """
        largest: float | None = None
        for block in blocks:
            if not isinstance(block, TextBlock):
                continue
            text = flow_text(block)
            if not text or repetition_key(text) in running:
                continue
            style = measure(
                block,
                body_size=body_size or style_fallback(block),
                page_left=page_left.get(block.page_number, block.bbox[0]),
            )
            if is_heading(text, style) and (
                largest is None or style.max_size > largest
            ):
                largest = style.max_size
        return largest

    @staticmethod
    def _lookahead_caption(
        blocks: list[TextBlock | ImageBlock | TableBlock],
        index: int,
    ) -> tuple[TextBlock | None, int]:
        """Claim the next block as a caption when it reads like one."""
        if index >= len(blocks):
            return None, 0
        candidate = blocks[index]
        if isinstance(candidate, TextBlock) and is_caption(flow_text(candidate)):
            return candidate, 1
        return None, 0

    def _finalize(self) -> tuple[Document, str, tuple[ParserIssue, ...]]:
        text = self._stream.text
        elements: list[DocumentElement] = []
        order = 0

        for chapter in self._chapters:
            # Drop only containers that carry neither content nor a title, so an
            # implicit wrapper never appears in the document for nothing.
            sections = [
                section
                for section in chapter.sections
                if section.elements or section.title is not None
            ]
            if not sections and chapter.title is None:
                continue
            chapter_span = chapter.span()
            chapter_attributes = (
                _span(*chapter_span) if chapter_span is not None else {}
            )
            elements.append(
                Chapter(
                    id=chapter.id,
                    parent_id=self._document_id,
                    order_index=order,
                    title=chapter.title,
                    source=_source(chapter.page_number),
                    attributes=chapter_attributes,
                )
            )
            order += 1
            for section_order, section in enumerate(sections):
                section_attributes = (
                    _span(section.start, section.end)
                    if section.start is not None and section.end is not None
                    else {}
                )
                elements.append(
                    Section(
                        id=section.id,
                        parent_id=chapter.id,
                        order_index=section_order,
                        title=section.title,
                        source=_source(section.page_number),
                        attributes=section_attributes,
                    )
                )
                elements.extend(section.elements)

        for key, value in self._document_metadata_values().items():
            elements.append(
                Metadata(
                    id=self._ids.element_id(ElementType.METADATA, (key,)),
                    parent_id=self._document_id,
                    order_index=order,
                    key=key,
                    value=value,
                )
            )
            order += 1

        document = Document(
            id=self._document_id,
            parent_id=None,
            order_index=0,
            elements=tuple(elements),
            source=SourceLocation(original_reference=self._source_reference),
        )
        return document, text, tuple(self._issues)

    def _document_metadata_values(self) -> dict[str, str | int]:
        metadata = self._content.metadata
        values: dict[str, str | int] = {"page_count": metadata.page_count}
        if metadata.title:
            values["title"] = metadata.title
        if metadata.author:
            values["author"] = metadata.author
        return values


def style_fallback(block: TextBlock) -> float:
    """Body size for documents where no dominant size could be measured."""
    return max((line.size for line in block.lines), default=1.0) or 1.0


class PyMuPdfParser:
    """Parses PDF documents into the Document Model using PyMuPDF."""

    @property
    def metadata(self) -> ParserMetadata:
        return ParserMetadata(
            name=_NAME,
            version="1.0.0",
            display_name="PDF (PyMuPDF)",
            capabilities=frozenset(
                {
                    ParserCapability.TEXT,
                    ParserCapability.METADATA,
                    ParserCapability.IMAGES,
                    ParserCapability.TABLES,
                    ParserCapability.HYPERLINKS,
                    ParserCapability.CODE_BLOCKS,
                    ParserCapability.FOOTNOTES,
                    ParserCapability.FORMULAS,
                    ParserCapability.PAGE_COORDINATES,
                }
            ),
            supported_mime_types=frozenset(_PDF_MIME_TYPES),
            supported_extensions=frozenset(_PDF_SUFFIXES),
            # Above the generic text-extraction fallback for the same files.
            priority=20,
        )

    def supports(self, *, mime_type: str, filename: str) -> bool:
        normalized = (mime_type or "").split(";", 1)[0].strip().lower()
        if normalized in _PDF_MIME_TYPES:
            return True
        dot = filename.rfind(".")
        return (filename[dot:].lower() if dot != -1 else "") in _PDF_SUFFIXES

    def parse(
        self,
        request: ParseRequest,
        on_progress: ProgressCallback | None = None,
    ) -> ParseResult:
        started = time.perf_counter()

        def report(
            stage: ParseStage,
            completed: int,
            total: int | None,
            detail: str | None = None,
        ) -> None:
            if on_progress is not None:
                on_progress(
                    ParserProgress(
                        stage=stage,
                        completed_units=completed,
                        total_units=total,
                        detail=detail,
                    )
                )

        report(ParseStage.STARTED, 0, None, _NAME)
        content = extract_pdf(
            request.data,
            on_page=lambda number, total: report(
                ParseStage.READING, number, total, f"page {number}/{total}"
            ),
        )

        report(ParseStage.STRUCTURING, content.metadata.page_count, None)
        document, text, issues = _DocumentAssembler(
            content, source_reference=request.identity
        ).build()

        if not text.strip():
            raise ParserError(
                ParserErrorCode.EMPTY_DOCUMENT,
                (
                    "The PDF contains no extractable text. It may be a scanned "
                    "document, which requires OCR."
                ),
                parser_name=_NAME,
            )

        report(ParseStage.FINALIZING, content.metadata.page_count, None)
        metadata = self._document_metadata(content, text, document)
        duration_ms = (time.perf_counter() - started) * 1000
        report(ParseStage.COMPLETED, content.metadata.page_count, None)

        return ParseResult(
            document=document,
            canonical_text=text,
            metadata=metadata,
            statistics=ParseStatistics.from_document(document, duration_ms=duration_ms),
            parser_name=_NAME,
            warnings=tuple(content.issues) + issues,
        )

    @staticmethod
    def _document_metadata(
        content: PdfContent,
        text: str,
        document: Document,
    ) -> DocumentMetadata:
        """Document metadata, preferring the PDF's own title over a heading."""
        heading = next(
            (
                element.title
                for element in document.elements
                if isinstance(element, Chapter) and element.title
            ),
            None,
        )
        word_count = len(text.split())
        return DocumentMetadata(
            title=content.metadata.title or heading,
            author=content.metadata.author,
            language=content.metadata.language,
            page_count=content.metadata.page_count,
            word_count=word_count,
            character_count=len(text),
            estimated_reading_minutes=(
                math.ceil(word_count / _WORDS_PER_MINUTE) if word_count else None
            ),
        )
