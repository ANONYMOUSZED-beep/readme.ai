# Internal Document Model

Every processed book is represented as a structured document. This is the
single representation all current and future features address — never raw files
or page numbers.

## Hierarchy

```
ProcessedBook            (document: status + metadata, one per book)
└── Chapter              (order, anchor, title?, offsets)
    └── Section          (order, anchor, title?, offsets)
        └── Paragraph    (order, anchor, offsets, TEXT)
            └── Sentence (order, anchor, offsets)
```

## Where text lives (no duplication)

The document's **canonical text** is the body paragraphs joined by blank lines.
Text is stored exactly once, on `Paragraph.text`. Every other element —
sentences, sections, chapters — stores only `start_offset`/`end_offset`
(character positions into the canonical text). Sentence and chapter text are
*derived* by slicing, never stored twice.

The reader reconstructs the readable text by selecting paragraphs ordered by
their global `order_index` — a single indexed query, efficient for large books.

## Stable anchors

Each element has a deterministic `anchor`, stable across reprocessing of
identical structure:

| Element | Anchor example |
| --- | --- |
| Chapter | `ch1` |
| Section | `ch1-sec2` |
| Paragraph | `ch1-sec2-p3` |
| Sentence | `ch1-sec2-p3-s1` |

Future bookmarks, notes, highlights, AI explanations, and cross-book citations
reference content by these anchors (plus character offsets for sub-sentence
spans), so they remain valid regardless of font size, device, or layout.

## Metadata

Extracted into `ProcessedBook` where available; unsupported fields are `null`:
title, author, language, page_count, word_count, character_count,
estimated_reading_minutes.

## Persistence notes

- Each structural row carries a denormalised `processed_book_id` for efficient
  scoped reads and FK-cascade cleanup.
- The plain-text processor derives structure deterministically: `#`/`##` heading
  lines become chapter/section titles; blank-line blocks become paragraphs;
  terminal punctuation splits sentences.
