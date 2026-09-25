"""Builds the Document Model from a processor's structured output.

This is the bridge the parser framework uses today: existing deterministic text
extraction produces a :class:`StructuredDocument`, and this module lifts it into
the format-independent Document Model that every future parser will emit
directly. It adds no format knowledge and performs no parsing.
"""

from __future__ import annotations

from app.modules.processing.document import StructuredDocument
from app.modules.processing.document_model import (
    Chapter,
    Document,
    DocumentElement,
    ElementType,
    InlineContent,
    InlineType,
    Metadata,
    Paragraph,
    Section,
    Sentence,
    SourceLocation,
    StableIdFactory,
)


def _span(start: int, end: int) -> dict[str, int]:
    """Canonical-text span kept as traceability metadata, not as hierarchy."""
    return {"start_offset": start, "end_offset": end}


def build_document_model(
    document: StructuredDocument,
    *,
    source_reference: str,
) -> Document:
    """Return a validated Document Model with deterministic, stable IDs."""
    ids = StableIdFactory(source_reference)
    document_id = ids.document_id
    elements: list[DocumentElement] = []
    order = 0

    for chapter_index, chapter in enumerate(document.chapters):
        chapter_path: tuple[int, ...] = (chapter_index,)
        chapter_id = ids.element_id(ElementType.CHAPTER, chapter_path)
        elements.append(
            Chapter(
                id=chapter_id,
                parent_id=document_id,
                order_index=order,
                title=chapter.title,
                attributes=_span(chapter.start_offset, chapter.end_offset),
            )
        )
        order += 1

        for section_index, section in enumerate(chapter.sections):
            section_path = (*chapter_path, section_index)
            section_id = ids.element_id(ElementType.SECTION, section_path)
            elements.append(
                Section(
                    id=section_id,
                    parent_id=chapter_id,
                    order_index=section_index,
                    title=section.title,
                    attributes=_span(section.start_offset, section.end_offset),
                )
            )

            for para_index, paragraph in enumerate(section.paragraphs):
                para_path = (*section_path, para_index)
                para_id = ids.element_id(ElementType.PARAGRAPH, para_path)
                elements.append(
                    Paragraph(
                        id=para_id,
                        parent_id=section_id,
                        order_index=para_index,
                        attributes=_span(paragraph.start_offset, paragraph.end_offset),
                    )
                )

                for sent_index, sentence in enumerate(paragraph.sentences):
                    sent_path = (*para_path, sent_index)
                    text = document.text[sentence.start_offset : sentence.end_offset]
                    elements.append(
                        Sentence(
                            id=ids.element_id(ElementType.SENTENCE, sent_path),
                            parent_id=para_id,
                            order_index=sent_index,
                            content=(
                                (InlineContent(inline_type=InlineType.TEXT, text=text),)
                                if text
                                else ()
                            ),
                            attributes=_span(
                                sentence.start_offset, sentence.end_offset
                            ),
                        )
                    )

    metadata_values: dict[str, str | int | None] = {
        "title": document.metadata.title,
        "author": document.metadata.author,
        "language": document.metadata.language,
        "page_count": document.metadata.page_count,
        "word_count": document.metadata.word_count,
        "character_count": document.metadata.character_count,
        "estimated_reading_minutes": document.metadata.estimated_reading_minutes,
    }
    for key, value in metadata_values.items():
        if value is None:
            continue
        elements.append(
            Metadata(
                id=ids.element_id(ElementType.METADATA, (key,)),
                parent_id=document_id,
                order_index=order,
                key=key,
                value=value,
            )
        )
        order += 1

    return Document(
        id=document_id,
        parent_id=None,
        order_index=0,
        elements=tuple(elements),
        source=SourceLocation(original_reference=source_reference),
    )
