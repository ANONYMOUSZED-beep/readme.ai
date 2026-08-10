# Requirements Document

## Introduction

**Guiding principle: the Reader is the product. Everything else exists to support
the Reader.**

The parser, Document Model, persistence layer, Explanation Engine, and Learning
Intelligence Engine all serve one experience: a person reading a book and
understanding it better than they would alone. Sprint 6.5 changes what the Reader
consumes — typed document elements instead of one flat canonical string — without
changing what reading feels like.

Two rules constrain every requirement below. **Reading comes first:** no
structural improvement may cost reading fluency, and where structure is uncertain
reading flow wins. **ReadMe.ai is not a document viewer, a ChatPDF, or a
summarizer:** structured rendering exists to make text readable and explainable,
not to display files.

In scope: element delivery to the Reader, native rendering of the element
vocabulary, `DocumentPaginationSource`, selection resolution across all readable
element types, and preservation of progress, bookmarks, and explanations.

Out of scope: rich image rendering, real table layout, hyperlink navigation,
Reader UI redesign, pagination redesign, parser changes, Explanation Engine
architecture, LIE changes, OCR, AI, RAG, and summarization.

## Glossary

- **Canonical text**: the single character stream stored once per document; all
  offsets index into it.
- **Canonical offset**: a Unicode scalar position in the canonical text. The
  anchor space already used by reading progress, bookmarks, and explanations.
- **Readable element**: an element contributing text to the canonical stream —
  paragraph, sentence, code block, quote, list item, footnote, formula, caption,
  table row, table cell.
- **Structural element**: an element contributing no text of its own — chapter,
  section, list container, table container, image, hyperlink.
- **Reading window**: the pages currently measured by the Sprint 6.1 incremental
  paginator.
- **Reference book**: the existing 911-page SQL reference PDF (~2.1M characters,
  ~51,500 elements) used as the large-book benchmark.
- **Placeholder**: a provisional, bounded rendering that marks an element's
  presence and position without rich presentation.

## Requirements

### Requirement 1: Format-agnostic reading

**User Story:** As a reader, I want every processed book to read the same way, so
that I never have to think about which file it came from.

#### Acceptance Criteria

1. The Reader SHALL consume only Document Model elements and canonical offsets.
2. The Reader SHALL NOT branch on file format, MIME type, file extension, or
   parser name in any code path.
3. WHEN two books have equivalent structure but were produced by different
   parsers THEN the Reader SHALL render them identically, element for element.
4. The Reader SHALL NOT display parser or format identity anywhere in the reading
   surface.
5. WHEN a future parser is added THEN the Reader SHALL require no change to
   render every element type that parser produces.
6. WHEN the Reader encounters an unrecognised element type THEN it SHALL render
   that element's text using its span, and SHALL NOT crash, blank the page, or
   interrupt reading flow.

### Requirement 2: Element rendering behavior

**User Story:** As a reader, I want the book's structure to be visible and
legible, so that headings, code, quotes, and lists read as what they are instead
of collapsing into undifferentiated text.

#### Acceptance Criteria

1. The Reader SHALL render all elements in canonical reading order, and SHALL NOT
   reorder, group, or filter elements for visual effect.
2. WHEN a chapter has a title THEN the Reader SHALL render it as the most
   prominent heading at its canonical position; WHEN a chapter has no title THEN
   the Reader SHALL render nothing visible and SHALL NOT introduce a gap or
   artifact.
3. The Reader SHALL NOT force a page break at a chapter boundary in this sprint.
4. WHEN a section has a title THEN the Reader SHALL render it as a secondary
   heading, visually subordinate to a chapter and distinct from body text; WHEN a
   section has no title THEN the Reader SHALL render nothing visible.
5. The Reader SHALL render paragraphs as flowing body text using the reader's
   current font size, line height, and theme, visually unchanged from the current
   canonical-text rendering.
6. The Reader SHALL render code blocks in a monospaced font, preserving original
   line breaks and leading whitespace exactly, visually set apart from body text.
7. The Reader SHALL NOT re-indent, reformat, tokenize, or syntax-highlight code.
8. WHEN a code line exceeds the page width THEN the Reader SHALL keep it readable
   without breaking pagination.
9. The Reader SHALL render quotes visually distinct from body text using body
   typography, and SHALL render attribution when present.
10. The Reader SHALL render a list as a grouped block of its items preserving
    order and ordered/unordered nature, and the list container SHALL contribute
    no text.
11. The Reader SHALL render each list item with a marker — a bullet for unordered
    lists, a sequential number for ordered lists — with wrapping, selectable text.
12. The Reader SHALL render hyperlinks as tappable, visually distinct text.
13. WHEN a hyperlink is tapped THEN the Reader SHALL show a visible
    acknowledgement of the target, and SHALL NOT navigate away, open a browser,
    or block reading.
14. The Reader SHALL render a formula's preserved original representation as
    set-apart text, and SHALL NOT interpret, evaluate, typeset, or convert it.
15. The Reader SHALL render images and tables as placeholders per Requirement 5.
16. The Reader SHALL render captions as small, de-emphasized text directly beneath
    the image or table they describe; WHEN a caption's target is missing THEN the
    Reader SHALL render the caption as ordinary body text.
17. The Reader SHALL render footnotes as small, de-emphasized text at their
    canonical position, showing marker or label when present.
18. Every rendered element SHALL be visually attributable to its type, such that a
    reader can distinguish body text, heading, code, quote, list item, footnote,
    and caption without inspecting data.

### Requirement 3: Reading progress preserved exactly

**User Story:** As a reader, I want to reopen a book and land exactly where I
stopped, so that migrating the Reader internals costs me nothing.

#### Acceptance Criteria

1. The system SHALL persist and restore reading position as a canonical scalar
   offset, and SHALL NOT replace or alter that persisted anchor format.
2. WHEN element IDs are carried alongside a position THEN they SHALL be additive
   and SHALL NOT be required to resolve that position.
3. WHEN a position or bookmark was saved before this sprint THEN it SHALL resolve
   to the same reading location afterwards for the same processed document,
   without migration.
4. WHEN a book is opened THEN the Reader SHALL restore the saved position and
   display the page containing that offset.
5. WHEN saved progress resolves asynchronously after the first page has already
   been measured THEN the Reader SHALL realign the reading window to the restored
   offset.
6. The Reader SHALL compute progress percentage from the current canonical offset
   against the canonical character count, consistent with the visible position.
7. WHEN a bookmark is created THEN the system SHALL store the current canonical
   offset and a label derived from the surrounding readable text, for every
   readable element type and not only paragraphs.
8. WHEN a bookmark is opened THEN the Reader SHALL display the page containing its
   offset and SHALL persist the new position.
9. The system SHALL preserve existing reading-time accumulation,
   persist-on-dispose, and persist-on-page-turn behavior.
10. WHEN font size, line height, text scale, or viewport changes THEN the Reader
    SHALL preserve the canonical offset and remain on the same content after
    re-pagination.
11. The Reader SHALL derive page numbering and estimated total pages from measured
    pagination, and SHALL NOT use source page numbers for progress or hierarchy.

### Requirement 4: Selection and explanation everywhere

**User Story:** As a reader, I want to select anything I am reading and ask what it
means, so that the Explanation Engine works everywhere my eyes go.

#### Acceptance Criteria

1. The Reader SHALL report every selection as a canonical `[start, end)` scalar
   range addressing the characters the reader visually selected.
2. The Reader SHALL resolve word, sentence, and multi-paragraph selections in
   paragraphs exactly as it does today, as the regression baseline.
3. WHEN a selection is made inside a code block THEN the system SHALL resolve the
   correct canonical range and SHALL preserve whitespace and line breaks in the
   submitted text.
4. WHEN a selection is made inside a quote THEN it SHALL resolve within that
   quote's span and SHALL NOT bleed into neighbouring elements.
5. WHEN a selection is made inside a list item THEN it SHALL resolve within that
   item's span; WHEN a selection spans multiple list items THEN it SHALL resolve
   to a contiguous canonical range covering them.
6. WHEN a selection is made inside a formula THEN its original characters SHALL be
   submitted unmodified.
7. WHEN a selection is made inside a caption, footnote, or table cell THEN it
   SHALL resolve and return an explanation.
8. WHEN a selection resolves inside any readable element type THEN the system
   SHALL return a successful explanation and SHALL NOT return an
   outside-book-content error.
9. WHEN the whole-passage explain action is invoked THEN the system SHALL submit
   the readable element containing the current position, whatever its type.
10. The Reader SHALL NOT classify selections as word, sentence, or paragraph;
    classification SHALL remain backend-driven from stored structure.
11. Structural elements with no text of their own SHALL NOT produce selectable
    empty ranges.

### Requirement 5: Image and table placeholders

**User Story:** As a reader, I want to know that a figure or table exists at this
point in the book, so that the reading flow makes sense before rich rendering
arrives.

#### Acceptance Criteria

1. The Reader SHALL render an image as a bounded placeholder occupying a modest,
   fixed share of the page.
2. The image placeholder SHALL display an image affordance, the source page number
   when available, dimensions when available, and an abbreviated form of the
   stable image identifier.
3. WHEN an image has a caption THEN the Reader SHALL render that caption directly
   beneath the placeholder.
4. The Reader SHALL NOT request, decode, cache, or display image bytes.
5. The Reader SHALL render a table as a bounded placeholder that identifies itself
   as a table, reports its row count, and keeps the table's textual content
   readable in canonical order.
6. The Reader SHALL NOT invent column widths, borders, alignment, or grid layout,
   and SHALL follow stored row and cell order.
7. Placeholders SHALL participate in pagination like any other element, and SHALL
   NOT overflow a page, be clipped without indication, or cause an empty page.
8. Placeholders SHALL be visually marked as provisional.

### Requirement 6: Performance with very large books

**User Story:** As a reader of a 900-page reference book, I want the book to open
immediately and turn pages smoothly, so that structure costs me nothing.

#### Acceptance Criteria

1. The Reader SHALL NOT load a large book's complete element set into memory or
   into widgets, and SHALL consume elements windowed around the reading position.
2. The Reader SHALL keep pagination incremental and lazy, measuring only the
   current page plus the existing look-ahead, and SHALL NOT paginate the whole
   document.
3. The Reader SHALL NOT run pagination or element preparation inside `build()`.
4. WHEN content resolves THEN the Reader SHALL present the first readable page
   promptly, showing a lightweight loading state until then and never a frozen UI.
5. WHEN reading the reference book THEN page turning SHALL remain smooth with no
   dropped frames attributable to element loading, mapping, or measurement.
6. WHEN a widget rebuild occurs without a layout or typography change THEN the
   Reader SHALL NOT re-fetch, re-map, or re-measure already prepared content.
7. The system SHALL retrieve element data for a reading window without scanning
   the whole document server-side, with a bounded response size.
8. WHEN reading the reference book THEN peak memory SHALL remain within the same
   order of magnitude as the current canonical-text reader, and SHALL NOT be
   proportional to total element count.
9. The team SHALL record benchmarks for a small TXT book, a medium PDF book, and
   the reference book, covering time to first readable page, page-turn
   responsiveness, and peak memory.

### Requirement 7: Backward compatibility

**User Story:** As an existing user, I want the books already in my library to keep
working, so that nothing I uploaded is stranded.

#### Acceptance Criteria

1. WHEN a book was processed before this sprint THEN it SHALL remain readable
   without reprocessing or migration.
2. The system SHALL retain `StringPaginationSource` and SHALL use it when only
   canonical text is available.
3. The system SHALL add `DocumentPaginationSource` alongside `StringPaginationSource`
   and SHALL NOT remove or replace the latter.
4. The Reader SHALL depend only on the `PaginationSource` abstraction, with no
   conditional logic distinguishing implementations beyond selecting one at
   construction.
5. WHEN both sources address identical text THEN they SHALL produce identical
   canonical offsets, so a position saved under one resolves correctly under the
   other.
6. TXT and PDF books SHALL be indistinguishable in reading behavior: same
   gestures, progress semantics, selection semantics, and settings.
7. WHEN a book's structure is unavailable or unreadable THEN the Reader SHALL
   degrade to canonical-text reading rather than failing to open.
8. The system SHALL preserve existing unsupported-format and processing-failure
   states.

### Requirement 8: No regressions

**User Story:** As the product owner, I want this migration to be provably
non-destructive, so that a Reader internals change cannot quietly cost us
features.

#### Acceptance Criteria

1. The Reader UI, page-turn interaction, reader settings, bookmarks sheet, and
   explanation sheet SHALL be behaviorally unchanged.
2. The parser, Document Model, persistence schema, Explanation Engine
   architecture, and LIE SHALL remain unmodified; adapting the Reader's
   integration seam is permitted, redesigning those components is not.
3. The existing backend and Flutter test suites SHALL pass, except where a changed
   assertion documents an intended behavior change.
4. Every requirement above SHALL be covered by at least one automated test with an
   unambiguous pass/fail condition, except benchmark figures, which SHALL be
   measured and recorded.

### Requirement 9: Selection seam widening

**User Story:** As a reader, I want explanations to work in code, lists, and quotes,
so that the parts of a technical book I most need explained are not excluded.

#### Acceptance Criteria

1. The system SHALL resolve selection context from all readable element types, not
   from paragraphs alone.
2. The system SHALL implement this widening inside the persistence layer that
   serves the Explanation Engine, and SHALL NOT modify the Explanation Engine's
   architecture, prompts, strategies, or classification rules.
3. WHEN the selection context is widened THEN existing paragraph-selection
   classification results SHALL remain unchanged.
